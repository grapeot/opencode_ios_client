# yage 修复工作记录

记录我们在自有 fork 上对 opencode-official + oh-my-openagent (OMO) 上做的本地修复，以及定位过程。`adhoc_jobs/opencode_ios_client/opencode-official` 是 opencode 官方仓库的本地 checkout，跟踪 origin/dev；`/private/tmp/oh-my-openagent/` 是 OMO 3.17.13 的源码 checkout。

## 2026-05-04 同 sessionID 多 generation fiber 并发 race

### 症状

升级 OMO 3.17.x 之后，user 在 web UI 跟 main session 对话时，频繁出现"两到三个 thinking 同时进行、内容相似但不一致、context window 消耗加速、compaction 也常常并发跑"的现象。

数据库层面的硬证据来自 prod db (`~/.local/share/opencode/opencode.db`) 上 session `ses_20ac172c1ffe4DAFzQzpgSw0mx` 的某次 user message：单条 user message 下挂了 22 条 assistant message，全部共享同一个 parentID，时间序列里至少出现 6 条 `finish=stop` 的兄弟 assistant，且各自的 input token 用量不递增，前两条间隔 270ms 各自独立调了完全相同的 `background_output(task_id=bg_xxx)`。multi-step generation loop 在正常情况下中间步是 `tool-calls`、最后一步 `stop`、之后 break 退出；这种"同 parent 多 stop"的形态只能由多个独立 generation fiber 在同一 sessionID 上并行写入解释。

### 根因

opencode 服务端 `SessionRunState.defaultLayer` 提供的 sessionID 级互斥锁，并非进程内全局唯一。

`SessionRunState.defaultLayer` 在四个位置被重新 `Layer.provide`：

1. `packages/opencode/src/effect/app-runtime.ts`
2. `packages/opencode/src/server/routes/instance/httpapi/server.ts`
3. `packages/opencode/src/session/prompt.ts`（被 `SessionPrompt.defaultLayer` 提供）
4. `packages/opencode/src/session/revert.ts`（被 `SessionRevert.defaultLayer` 提供）

每次 `Layer.provide(SessionRunState.defaultLayer)` 都会重新 build 该 layer，触发其内部 `InstanceState.make(...)` 跑一遍 `Effect.gen`，从而创建一份独立的 `runners: Map<SessionID, Runner>`。同一进程同一 directory 下同时存在多个 `runners` Map，每个都各自从空开始。

并发场景下：
- 请求 A 走 layer 实例 1 的 `SessionRunState`，`runners_v1.get(sessionID)` 拿不到 → `Runner.make` → 启 fiber_A 跑 `runLoop`。
- 请求 B 走 layer 实例 2 的 `SessionRunState`，`runners_v2.get(sessionID)` 也拿不到 → 又 `Runner.make` → 启 fiber_B。
- 两个 fiber 都在同一个 `sessionID` 上跑 `runLoop`，各自从 db 重读 messages、各自走 step++、各自往 `parts` 表里写 tool call、各自跑 LLM。`SynchronizedRef` 形同虚设，因为它保护的是单个 `Runner` 实例的 state，而 `Runner` 实例本身有两个。

之所以日常用户对话很少踩中这个 race，是因为正常对话天然串行（用户发一条 → 等回完 → 再发下一条），第二次 prompt 进来时第一次早就 idle 了。OMO 3.17.x 的 background-task 通知、`unstable-agent-babysitter`、`todo-continuation-enforcer`、`compaction-context-injector/recovery` 等 7 处 hook 会在已有 fiber 还没退出时主动 `client.session.promptAsync(...)`，把这个本来就坏的锁暴露得最频繁。

### 定位过程关键节点

1. **现象不一致**：第一次在 prod db 看到的 session `ses_20b312218ffevzQP9joW0u5mYD` 单条 user 下也挂了 9 条独立 assistant，前两条间隔 270ms 各自调 background_output(`bg_66da62a9`)，input token 不累加，确认是真并发不是 step chain。
2. **第一轮误判**：把 race 归因到 commit `5ba68a28 refactor(httpapi): scope async prompt fiber (#25213)` —— 该 commit 把 `Effect.runFork` 换成 `Effect.forkIn(scope, ...)` 并删掉了显式 `provideService(InstanceRef, ...)`，怀疑 fork 出去的 fiber 失去 per-request InstanceRef binding 导致拿到不同 InstanceState。打了一轮"显式 provide InstanceRef + WorkspaceRef 给 forked fiber"的 fix，部署后发现 race 没消失，db 上同 user 又见 22 条 stop 兄弟。
3. **加 trace 实证**：在 `SessionRunState.runner` 的 reuse/create 分支加 `Effect.logInfo`，并给每份 InstanceState 实例打一个随机 `mapId`。重启 server 后看到 0 reuse / 9 create — 同一 sessionID 第二次 prompt 仍然 create 而不是 reuse，证实 race 不在 fiber binding 层而在 `runners` Map 多实例层。
4. **再加 trace 看 cache**：往 `InstanceStore.load` 加 `cacheSize / cacheHit / cacheKeys` log，看到有同一 directory `/Users/grapeot/co/knowledge_working` 在不同 InstanceStore 实例下被 boot 两次（启动期 AppRuntime 一次，HTTP server 启动一次），并且 `SessionRunState` 在多次 prompt 间出现两个不同 `mapId`。
5. **定位到 Layer 多次 build**：grep `SessionRunState.defaultLayer` 看到四处 `Layer.provide`，确认这是 layer reference 在不同位点被 build 出多个 service 实例的根因。

### 修复

`packages/opencode/src/session/run-state.ts`：把 `runners` Map 提到 module 顶层 `sharedRunners`，所有 `SessionRunState` layer 实例共享同一份 Map。Scope 仍然每个 InstanceState 一份用于 fork run fiber，但 sessionID 锁从 layer 实例数解耦。

```ts
// module top-level
const sharedRunners = new Map<SessionID, Runner.Runner<MessageV2.WithParts>>()

// in layer init
return { runners: sharedRunners, scope, __id }
```

finalizer 不再 `runners.clear()` —— 因为这个 Map 现在是 process-wide，其他 layer 实例可能仍在用。Active runner 在自己 fiber scope close 时被 cancel，正常生命周期不依赖这个 finalizer 来清理。

部署后验证：同 main session 连续 prompt，每次单 fiber 跑、单条 user 下 1 条 user → ≤4 条顺序 assistant（中间 tool-calls，末尾 stop），race 消除。

### 同时保留的诊断 trace（暂留 1-2 天观察用）

未撤掉的本地诊断改动：

- `packages/opencode/src/session/run-state.ts`：`SessionRunState.state init` / `finalize` 打 `mapId` + `sharedRunners.size`；`SessionRunState.runner reuse/create` 打 `sid / mapId / mapSize / stateTag / busy`。
- `packages/opencode/src/project/instance-store.ts`：`InstanceStore.load called` 打 `inputDir / resolvedDir / cacheSize / cacheHit / cacheKeys`。

如果短期内 race 复发，这些 log 能立刻指认是 `SessionRunState.runner` 没 reuse 还是 `InstanceStore.load` cache miss，便于定位。观察期过后可以删除。

### 还附带的另一处 fix（保留）

`packages/opencode/src/server/routes/instance/httpapi/handlers/session.ts`：在 `forkIn` 之前显式 `provideService(InstanceRef, instance)` + `provideService(WorkspaceRef, workspace)` 给 forked fiber。这是上面误判路径里打的 fix，单独看也是合理的（恢复 commit `5ba68a28` 之前的语义，避免 forked async prompt fiber 在某种时序下解析到错误 instance），不会和真正的 fix 冲突，留着不取。

## 2026-05-04 OMO 3.17.13 background_output "Task not found" race（已修）

### 症状

OMO 发出 `[ALL BACKGROUND TASKS COMPLETE]` 系统通知给 parent session 后，模型立刻调 `background_output(task_id="bg_xxxxxx")`，**第一次返回 `Task not found`，紧接着用同一个 id 重试一次就能拿到结果**。日常使用里这个 race 出现频率不低；该现象在 race-fix 部署后依然存在，所以跟我们刚修的 server 锁无关，是 OMO 内部时序问题。

之前在 memory (`feedback*` / `reference*`) 里实用 workaround 是"第一次 not found 就立刻 retry 一次"，但 root cause 还没查清。

### 已定位到的代码路径

`/private/tmp/oh-my-openagent/src/tools/background-task/create-background-output.ts:61` 调 `manager.getTask(args.task_id)`，返回 `undefined` 直接返回 `Task not found: <id>`。manager 这边 `tasks: Map<string, BackgroundTask>` 在 `BackgroundManager.addTask`（`features/background-agent/manager.ts:328-337`）时 set，task.id 形如 `bg_<8 hex>`（manager.ts:396）。

唯一删除路径是 `removeTask`（339-341），由 `scheduleTaskRemoval` 在 `setTimeout(..., TASK_CLEANUP_DELAY_MS=10min)` 后调用。所以"通知后立刻 not found"不是被清理太早。

### 还没验证的两个怀疑方向

1. **多 BackgroundManager 实例**：跟刚修的 server side `runners` 多实例同构的可能。如果 OMO plugin 在多 directory / 多 layer 路径下被 init 多份，每份 manager 自己一个 `tasks` Map，发通知的那个 manager 跟接 tool call 的那个 manager 不是同一个。
2. **task.id 在通知和注册之间不一致**：理论上 manager 里 task 还没到 `addTask` 就发通知了；或者 task 被 reissue 了一个新 id 而通知里塞的是旧 id。

下一步：在 `BackgroundManager.addTask` / `getTask` / `notifyParentSession` 三处加 trace（打 manager 实例 id + tasks Map size + 操作的 task id），重启复现一次就能定性。

### 实证

OMO 源码本地 clone 到 `adhoc_jobs/opencode_ios_client/oh-my-openagent`，checkout 3.17.13 tag，`bun install && bun run build`，并把 `~/.config/opencode/opencode.json` 的 plugin 项从 `oh-my-openagent@3.17.13` 改成本地绝对路径，使 opencode plugin loader 直接走 file path 通道（`pluginSource(spec)` 走 `isPathPluginSpec`）。

在 `BackgroundManager` constructor / `addTask` / `getTask` / `removeTask` 里加 trace：每个实例打一个随机 6 字符 `__omoMgrId`，每次操作打 `mgrId` + `taskId` + `tasks Map size` + 当前所有 keys。OMO 自己的 `log()` 通过 `os.tmpdir()` 写到 `/var/folders/.../T/oh-my-opencode.log`（macOS 不是 `/tmp`，需要从 `os.tmpdir()` 拿到具体目录才能 tail）。

第一次复现（Sisyphus orchestrator 让 sub-agent 执行最小 echo）：

```
[03:02:13.836] addTask  mgrId=cmat84  taskId=bg_e6a5c0c1  mapSize=1
[03:02:13.837] getTask  mgrId=cmat84  taskId=bg_e6a5c0c1  hit=yes
[03:02:13.938] getTask  mgrId=cmat84  taskId=bg_e6a5c0c1  hit=yes (×2)
[03:03:14.759] getTask  mgrId=yga2vq  taskId=bg_e6a5c0c1  hit=NO   mapSize=0  keys=[]
```

不同 `mgrId` 之间 `tasks` Map 互不可见——同进程同 directory 下，opencode plugin loader 在 InstanceState bootstrap 路径上对每次 boot 都重新 `import()` 一份 plugin（log 里也直接看到 `service=plugin path=oh-my-openagent@... loading plugin` 出现两次以上），每份 plugin 各自构造一个 BackgroundManager，各自一个 tasks Map。

注册通知用 mgrId=cmat84 上的 task，server 路由后面那次 `background_output(task_id=bg_e6a5c0c1)` 的 tool call 时落到了另一份 plugin 的 tool 闭包，于是查的是 mgrId=yga2vq 的 tasks Map，必然 not found。两次同 id 重试碰巧抢到了原始 mgr 的 tool 注册，所以"重试一次就好"。

### 修复

`src/features/background-agent/manager.ts`：把 BackgroundManager 的五个 task-state Map 全部提到 module 顶层 `SHARED_*`：

```ts
const SHARED_TASKS: Map<string, BackgroundTask> = new Map()
const SHARED_TASKS_BY_PARENT_SESSION: Map<string, Set<string>> = new Map()
const SHARED_NOTIFICATIONS: Map<string, BackgroundTask[]> = new Map()
const SHARED_PENDING_NOTIFICATIONS: Map<string, string[]> = new Map()
const SHARED_PENDING_BY_PARENT: Map<string, Set<string>> = new Map()
```

constructor 里把 `this.tasks = SHARED_TASKS` 等替换原来的 `new Map()`。task.id 是 `bg_<8 hex>` 全进程唯一，sessionID `ses_xxx` 也是全进程唯一，跨实例共享键空间没有冲突。结构上跟前面修 server `runners` Map 的方式同构。

shutdown 路径 `tasks.clear() / ...` 行为保留——shutdown 只在 process exit signal handler（`process-cleanup.ts`）触发，进程要退了清光也无所谓，不存在某个 manager 单独 shutdown 把别人状态清掉的路径。

### 验证

`bun run build` 重打包 OMO；`kill -9` 旧 opencode server，从 `cd /Users/grapeot/co/knowledge_working` cwd 重启 web。

再次跑同样的 background-agent task，关键 trace：

```
[03:05:11] BackgroundManager constructor mgrId=30ty70 dir=/Users/grapeot/co/knowledge_working
[03:05:26] BackgroundManager constructor mgrId=0huwx9 dir=/Users/grapeot/co/knowledge_working
[03:05:36] addTask  mgrId=30ty70  taskId=bg_a8321bf7  mapSize=1
[03:05:36] getTask  mgrId=30ty70  taskId=bg_a8321bf7  hit=yes
[03:05:47] [background-agent] notifyParentSession bg_a8321bf7 ; Task completed via session.idle
[03:05:53] getTask  mgrId=0huwx9  taskId=bg_a8321bf7  hit=YES   keys=["bg_a8321bf7"]
```

两个 BackgroundManager 实例依然存在（plugin 多实例本身没动），但第二个 mgr 现在能查到第一个 mgr add 进去的 task —— 证明 `tasks` Map 已经是 process-wide 共享。这正是用户报错路径里"通知后立刻 not found"的那一刻；fix 后跨 mgr lookup 直接命中。

### 部署

OMO 走的是本地 file path plugin，配置写死在 `~/.config/opencode/opencode.json` 的 `plugin: ["/Users/grapeot/co/.../oh-my-openagent"]`。后续要升级 OMO 上游版本时，需要在本地 git fetch + rebase + 重新 `bun run build`，并保持这五处 SHARED 化的本地修改。可以考虑后续给上游 OMO 提一个 PR，把 tasks/notifications maps 改成 module-level singleton 或者通过显式 `globalThis.__omoBackgroundManagerState__` 兜底。

### 暂留的本地 trace

`__omoMgrId` + `addTask/getTask/removeTask` 的 omo-trace 暂时不删，跟 server 那批 trace 同等地位，留 1-2 天观察期。`/var/folders/.../T/oh-my-opencode.log` 文件已经 170 MB 历史日志，需要的时候 grep `omo-trace` 看本机 race 是否再现。

### 仍存在的更上游问题（未修）

opencode 的 plugin loader 在同进程同 directory 下会 init 多份 plugin instance，这是 SHARED Map 这个修法**绕开**而非**根治**的问题。彻底修法是 opencode 服务端把 plugin init 做成 per-process（而不是 per-InstanceState），让 BackgroundManager 真的只有一份。这等同于前面 server `runners` race 的"方向 B"——侵入面大、风险高，留作后续 task。SHARED Map 已经可以让 OMO 这一侧观察到的 race 消失，先用着。
