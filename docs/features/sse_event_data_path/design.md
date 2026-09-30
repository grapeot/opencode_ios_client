# SSE Event Data Path 设计（SSE 作为消息状态的数据通路）

Status: draft — step 1 落盘（当前理解 + 设计方向），step 2 调研后大幅扩充再实现；无代码改动

## Bottom Line

iOS 客户端现在的架构是「SSE 只当门铃」：每一条消息相关的 SSE 事件（`message.updated` / `message.part.updated`）不携带可信数据，只触发一次全量 REST 拉取（`loadMessages` + `loadSessionDiff`），REST 快照才是唯一数据源。事件循环是串行的：`for await` 循环里 `await` 这一次 REST 往返，事件在队列里排队。结果是 tool 正在执行时，UI 往往要等 REST 快照回来才动，感知上就是「tool 结束了才有反应」。

服务端其实把数据放在事件 payload 里了（native OpenCode server，源码已验证）：

- `message.part.updated`：`properties.part` 是**完整 part 对象**（tool part 含 `state.status/input/output/time.start/end`；text part 含累计 `text`），`properties.time` 带时间戳。
- `message.updated`：`properties.info` 是完整 message info（含 `time.completed`）。
- `message.part.delta`：`properties {sessionID, messageID, partID, field: "text", delta}`，流式文本增量（text 与 reasoning 都用 `field: "text"`）。
- `server.heartbeat`：每 10s 一帧，用于探活。

设计：让 SSE 成为数据通路——事件直接原地 upsert 到本地消息状态（零 RTT，事件到达即渲染）；REST 降级为对账（重连 bootstrap、turn 结束、手动刷新、心跳看门狗触发）；新增心跳看门狗（静默 > 20s 触发一次对账，不是轮询）。明确不做：2s busy polling（Android 有，用户反馈差，不引入）、发送时乐观 busy（cosmetic，不关键）、tile 展示改造（P2，另开 feature）。

预期收益：tool running 状态在事件到达时（毫秒级）即可见；每 turn 的 REST 拉取从「每 step 每事件一对」降到「每 turn 1–2 次」，同时满足鸭哥的硬约束「取数动作不能放大」（见 `docs/features/session_status_bar/design.md` 背景节——message list 是重量级负载，不能频繁抓）。

## 用户可见问题与根因

现象：Android 上能看到正在跑的 tool 名称和已运行时长（composer 行 + 计时）；iOS 上 tool 执行期间界面无更新，直到 tool 完成（REST 快照回来）才一次性出现结果。

根因链（iOS）：

1. **SSE 只当门铃**：`AppState+SSE.swift:132-155` 收到 `message.part.updated` 后调 `messageStore.applyMessagePartUpdate`，而 `MessageStore.swift:154-169` 无论 part 处于什么状态（pending/running/completed）一律返回 `.finalized` → 触发 `loadMessages()` 全量 REST 拉取。事件 payload 里的完整 part 数据被丢弃。
2. **串行事件循环，队头阻塞**：`AppState+SSE.swift:27-30` 的 `for try await` 循环在处理每个事件时 `await` REST 往返。一个慢 REST（弱网/大 session）会卡住后面所有事件。turn 中每 step 有 N 个 part 事件 → N 次串行 REST。
3. **无静默死亡恢复路径**：SSE 连接如果「活着但没数据」（如代理缓冲丢帧），现有 backoff 重连（1s→30s）不会触发（连接没断），UI 就永远停在最后状态。Android 靠 2s busy polling 掩盖了这一点，但那是用户痛点，iOS 不能照抄。

Android 为什么好（对照）：同一「门铃」架构，但 (a) 事件处理非阻塞，400ms debounce 后才 REST；(b) 文本 delta 存内存（`streamingPartTexts`）即时渲染；(c) 发送时乐观置 busy（composer 行秒出）；(d) 2s busy polling 兜底。前三个都不依赖 per-event REST 的及时性。本设计把 (a) 升级为「payload 即数据」，用 (d) 的心跳看门狗替代轮询，(c) 按鸭哥判断不做。

## 服务端事件契约（native OpenCode server，源码验证于 origin/dev）

以下全部在 `opencode-official/packages/opencode/` 源码中验证（worktree 内自带该目录）。

| 事件 | properties | 触发时机 | 数据完整性 |
|---|---|---|---|
| `session.status` | `{sessionID, status: {type: "busy"\|"idle"\|"retry", ...}}` | turn 开始 `prompt.ts:1088`；每个 loop 迭代、每次 `llm.stream` 前 `processor.ts:653`；turn 结束 onIdle（`run-state.ts`，从 status map 移除 → 事件 status=idle） | `GET /session/status` 只返回 busy/retry，idle 不在 map 里——客户端以「收到 idle 事件」为准，不能以 REST 轮询判 idle |
| `message.updated` | `{sessionID, info: <完整 message info>}` | step 结束（`finish: "tool-calls"`，此时无 `time.completed`）；清理完成（带 `time.completed`） | 完整 |
| `message.part.updated` | `{sessionID, messageID, part: <完整 part>, time}` | `updatePart` 时（`session.ts:629-643`，`structuredClone(part)` 全量推送） | 完整。tool part 状态机 `pending→running→completed/error`，`state.time.start/end` 齐备；text part 先推 start（空 text）后推 end（完整 text） |
| `message.part.delta` | `{sessionID, messageID, partID, field: "text", delta: string}` | 流式 token 到达（`processor.ts`，text 与 reasoning 均 `field: "text"`） | 增量，需按 partID 聚合 |
| `message.part.removed` / `message.removed` | 含被删 ID | 删除/revert 相关路径 | step 2 验证完整 payload |
| `session.updated` | `{sessionID, info: <完整 session，含累计 tokens/cost>}` | 每 step 完成 `Session.touch()` | 完整（`session_status_bar` 已 live 验证，见下） |
| `server.connected` / `server.heartbeat` | `{type: ...}` | 连接建立；每 10s（`handlers/global.ts:32-35`） | 探活帧，iOS 现状 `default: break` 直接丢弃 |
| 其他（`permission.*` / `question.*` / `todo.updated` / `session.error` 等） | — | — | iOS 现状已按轻事件即时处理，保持 |

subagent 边界：task 工具在子 session 运行，子 session 的事件走同一 event bus，`sessionID` 不同。iOS 现状只处理 `sessionID == currentSessionID` 的事件；本设计保持该边界不变（是否记录 subagent 活动到 activity text 是 step 2 决策项）。

**live 实测证据**（引 `docs/features/session_status_bar/design.md` 的已验证事实，2026-09-30，探针 `tmp/status_bar_probe.py`，4096 live server）：

```text
t+0.0s  session.status=busy
t+1.2s  message.part.updated tool=bash status=pending→running→completed（同一 part 连续三帧）
t+1.3s  step-finish part 带 tokens；session.updated 推送累计
t+2.5s  session.updated 累计更新；session.status=idle
```

关键结论：tool 的 `running` 状态**以独立事件帧推送**（pending/running/completed 各一帧），客户端只要应用 payload 就能在 tool 开始执行的那一刻渲染 running 态——这正是 Android 有、iOS 没有的视觉差的直接来源。

**多 host 注意（dsh shim 兼容）**：dsh shim 的 `message.part.updated` payload 形状不同（`part` 只有 `{messageID, id, type: "text"}`，增量在顶层 `delta` 字段，无 `state`/`time`/`text`）。iOS 是多 host 的（local / SSH tunnel / shim，见 `session_status_bar` 背景节），所以 in-place apply 必须带 **payload 完整性门禁**（见 5.1）：字段不全时回退现行 REST 拉取路径，行为与今天一致。

## 客户端现状盘点（iOS，文件:行号）

| 位置 | 现状 |
|---|---|
| `AppState+SSE.swift:27-30` | 串行 `for try await` 循环，事件处理内 `await` REST |
| `AppState+SSE.swift:107-118` | `message.updated` → 触发 `loadMessages` 全量拉取 |
| `AppState+SSE.swift:119-131` | `message.part.delta` → 仅喂 throughput（`recordVisibleToken`），不更新文本 |
| `AppState+SSE.swift:132-155` | `message.part.updated` → `applyMessagePartUpdate` → 触发全量拉取 |
| `AppState+SSE.swift:193` | `default: break`（含 `server.heartbeat` 被丢弃） |
| `MessageStore.swift:154-169` | `applyMessagePartUpdate` 恒返回 `.finalized` |
| `AppState+Messages.swift:22-90` | `loadMessages`：全量 REST + 全量替换 + optimistic user row 合并 + stale guard + `refreshSessionActivityText` |
| `AppState+Messages.swift:137-176` | `sendMessage`：无乐观 busy |
| `AppState+Sessions.swift:435-447` | SSE (re)connect bootstrap：`loadMessages` + permissions + status poll |
| `ChatTabView.swift:173-176, 305, 373-378, 387-444, 735-738` | composer 状态行：`isCurrentSessionBusy` / `runningTurnActivity` / `quietComposerStatus` 门控 + 计时 |
| `MessageRowView.swift:105-141, 754-796` | `buildAssistantBlocks`（tool part 无条件渲染）+ `ToolCallsRowView`（折叠行，无 per-tool header spinner） |
| `ToolPartView.swift:31, 191-198, 224-228` | tool part 的 running/completed 视觉 |
| `ActivityTracker.swift:6-72, 74-97` | `updateSessionActivity` / `bestSessionActivityText`；activity text 由 `AppState.swift:435-442` 的 `activityTextForSession` 从消息**实时计算**（不是独立状态源） |
| `SSEClient.swift:52-137` | 帧解析（含 heartbeat 帧，目前被上层丢弃）；backoff 重连 1s→30s |

现状要点：UI 侧其实已经准备好「tool running 可见」的渲染（`ToolPartView` 有 running 态、composer 行有计时），缺的只是数据及时性——tool part 的 `running` 状态只在 REST 快照里，而 REST 是串行且每事件一次的。

## 设计

### 5.1 SSE 作为数据通路（事件 → apply 规格）

核心：消息相关事件的 payload 直接原地 upsert 到 `MessageStore`，不触发 REST。

| 事件 | 现状 | 改后 |
|---|---|---|
| `message.part.updated` | 全量 REST | 解码 `properties.part` → 按 partID 原地 upsert（所属 message 已知则替换/插入 part；message 未知则插入最小 `MessageWithParts` 壳并标记待对账）；tool 状态变化立即渲染 |
| `message.updated` | 全量 REST | 解码 `properties.info` → 按 messageID 原地 upsert info（保留本地已有 parts） |
| `message.part.delta` | 仅 throughput | 按 partID 追加到本地 part.text（in-memory 流式文本）；throughput 逻辑（`recordVisibleToken`）保留 |
| `message.part.removed` | `default: break` | 删除对应 part |
| `message.removed` | `default: break` | 删除对应 message |
| `session.status` / `session.updated` / `permission.*` / `question.*` / `todo.updated` | 轻事件即时 | 保持；`session.status → idle` 额外触发一次对账（见 5.2） |
| `server.connected` / `server.heartbeat` | `default: break` | 更新 `lastFrameAt`（见 5.3） |

约束与规则：

- **sessionID 门控不变**：只处理 `currentSessionID` 的事件。
- **幂等**：按 ID upsert，天然幂等；事件重复/乱序（part 先于 message 到达）安全。
- **payload 完整性门禁**：part 缺该类型所需字段时（tool part 无 `state`；text part 无 `text` 且无顶层 `delta`）→ 回退现行 REST 拉取路径（与今天行为一致）。这是多 host 兼容的关键：dsh shim 的 payload 是「顶层 delta + 瘦 part」形状，门禁不通过，自动走老路。
- **stale guard**：in-place upsert 同样受 `shouldApplySessionScopedResult` 类守卫约束（session 切换时丢弃过期事件）；具体守卫点 step 2 核对。
- **delta 聚合**：`streamingPartTexts` 式内存缓冲，part 的完整 `message.part.updated`（text end 帧）到达后以完整帧为准、清缓冲（与 Android 现有 `streamingPartTexts` 语义一致）。

### 5.2 REST 降级为对账

`loadMessages`（全量 REST）不再由 per-event 触发，仅在以下时机：

1. SSE (re)connect bootstrap（现状已有，`AppState+Sessions.swift:435-447`）；
2. turn 结束：`session.status → idle` 事件时一次性对账（保证终态干净，含 `time.completed`、最终 tokens）；
3. 手动刷新 / session 切换（现状已有）；
4. 心跳看门狗触发（见 5.3）；
5. `session.error` 恢复（现状已有）。

`loadMessages` 内部逻辑不变（仍是权威对账源，含 optimistic 合并与 stale guard）。预期：每 turn REST 对数从 ~N×2（每 step 每事件一对 message+diff）降到 1–2 次。message list 重量级负载的拉取频率显著下降——这是「取数动作不能放大」硬约束下的**收缩**，不是放大。

### 5.3 心跳看门狗（替代轮询的静默死亡恢复）

- 服务端每 10s 发 `server.heartbeat`（`handlers/global.ts:32-35`）；turn 中还有各类业务事件，正常时静默期不会超过 10s。
- 客户端维护 `lastFrameAt`（monotonic clock）：任何 SSE 帧到达（含 heartbeat / connected / 任意事件）即刷新。`SSEClient` 需把 heartbeat 帧作为事件向上抛（现在被 `default: break` 丢弃）。
- 检查机制：轻量定时（如每 5s 一次，仅在 SSE 连接声称存活时）+ 每次事件分发时。若 `now - lastFrameAt > 20s`（= 错过 2 个 heartbeat 周期）→ 触发**一次**对账（`loadMessages` + `loadSessionDiff` + `syncSessionStatusesFromPoll`），然后重置 `lastFrameAt`。
- 与 backoff 重连的关系：重连管「连接断了」，看门狗管「连接活着但没帧」（代理缓冲丢帧等静默死亡）。正常时看门狗零成本；静默死亡时 ≤20s 恢复。
- **不是轮询**：无固定周期拉取，无「busy 期间每 2s 双拉」。busy 且无事件时（长 tool 执行）heartbeat 仍在到达，看门狗不会误触发。

### 5.4 明确不做

- **2s busy polling**：Android 的 `launchBusyPolling`（busy 期间每 2s `loadMessages`）是用户痛点（REST 双拉 + UI 抖动），iOS 不引入；静默死亡由 5.3 覆盖。
- **发送时乐观 busy**：`sendMessage` 后到 `session.status=busy` 事件之间（亚秒级）composer 行缺口的 cosmetic 问题，接受，不做。
- **tile / FileCard 展示改造**（tool running 时的 per-tool header spinner、进度等视觉升级）：P2，另开 feature，本文档只保证数据及时。
- **subagent 事件处理**：保持现状（只处理 currentSessionID）；是否把 subagent 活动计入 activity text 留 step 2 决策。
- **服务端改动**：零。所有数据 native server 已经通过事件推送。

### 5.5 边界与一致性

- **乐观 user row**：`sendMessage` 用确定性 ID（`c9c0be8`）插入 optimistic user row；服务端回推的 user message 事件与 optimistic row 按 ID 去重。upsert 语义需与现有 `loadMessages` 的合并行为一致（细节 step 2 核对，含 `parts` 是否被服务端事件覆盖的边界）。
- **revert**：revert 后客户端本已强制 `loadMessages`（现状行为），保持；对账后本地状态自然收敛。
- **session 切换**：切换时丢弃旧 session 的 in-flight upsert（stale guard）；切换本身触发 bootstrap 对账（现状已有）。
- **大 session**：in-place upsert 只作用于已加载窗口，不扩大内存占用。
- **已知取舍**：若 message 状态被绕过事件总线修改（直接写 DB），本地状态滞后到下次对账。OpenCode server 的所有修改都走 event bus，此情形不存在。
- **compaction**：不删改历史 part，`tail_start_id` 机制不影响消息状态；无需特殊处理（与 `session_status_bar` 已验证事实 6 一致）。

## 与 session_status_bar feature 的关系

两者互补，命名注意区分：那个 feature 的「数据通路」指 session 级计数器（rounds / tool calls / tokens）的**取数来源**；本 feature 的「数据通路」指聊天渲染的消息/part 状态**实时落地**。

- 取数证据共享：本文档引用的 live 实测时间线（busy → tool pending/running/completed → idle）来自该 feature 的已验证事实（`tmp/status_bar_probe.py`，2026-09-30），不重复跑探针。
- hook 点重叠：本 feature 改的正是该 feature 挂钩的 handler（`message.updated` / `message.part.updated` / `loadMessages` 完成 / revert 四处）。**兼容承诺**：四处 hook 的调用点保留，handler 内部各自的计数 bookkeeping 不动；变的只是「不再为取数而 await 全量拉取」。其「每次 loadMessages 后窗口对账」变为「每次对账性 loadMessages 后窗口对账」——语义保留、频率下降；其计数主体是 SSE 增量（ID 去重），不受影响。
- 硬约束一致：「取数动作不能放大」同时约束两个 feature；本 feature 是收缩方向。
- 实现顺序：相互独立。若对方先 merge，本 feature 的 diff 基于其 merge 后的 master；若本 feature 先 merge，对方需适配「per-event 不再触发 loadMessages」（其计数 hook 不受影响）。branch 状态 step 2 再核。

## 测试与验收

单测（沿用现有 `applySSEEventForTesting` 类 harness；具体测试文件与工具函数 step 2 盘点）：

- part upsert：tool `pending→running→completed` 三帧各自产生本地状态变化，**且零 REST 调用**（REST 计数断言）。
- delta 流式：连续 `message.part.delta` 追加到 part.text；完整帧到达后以完整帧为准。
- removed：`message.part.removed` / `message.removed` 正确删除。
- 幂等与乱序：同帧重放不重复；part 先于 message 到达 → 壳 message 被后续 message.updated 补全。
- sessionID 门控：非 currentSessionID 事件被忽略。
- payload 完整性门禁：dsh shim 形状（瘦 part + 顶层 delta）→ 回退 REST 路径（行为回归断言）。
- 看门狗：时间可注入。静默 20s → 触发一次对账；帧到达 → 重置不误触发；触发后 `lastFrameAt` 重置不连发。
- 回归：turn 结束（idle 对账）后的本地终态 == 全量 REST 快照（等价性断言）。

live 验收（临时端口 scratch server，不复用 4096/4097 live server；prompt 用 `bash sleep 6` 类长 tool）：

- 发送后：`session.status=busy` 事件到达 → composer 行出现并开始计时（亚秒级）。
- tool running：tile 可见，activity text 为 `Running commands - <cmd>`，已运行时长持续走秒（事件驱动，不依赖 REST）。
- 静默死亡模拟（掐断 SSE 或代理缓冲）：≤20s 内看门狗触发一次对账，状态恢复。

UI 验收：现有 iOS UI automation 流程（截图核对 composer 行与 tool tile 状态）。

## 风险与回滚

- **状态漂移**（事件丢失/解析失败导致本地与服务端不一致）：缓解 = idle 对账 + bootstrap 对账 + 看门狗对账三道；step 2 增加调试期「本地 vs REST diff 日志」辅助（debug 开关，默认关）。
- **SwiftUI 重渲染**：`MessageWithParts` 是 struct 数组，in-place 更新仍触发 list diff。本 feature 的主要收益是消除 per-event REST 与事件队列阻塞；渲染端收益是次要的。是否需要 per-part observable 级粒度优化 → step 2 评估。
- **回滚**：无数据迁移、无协议/服务端改动。revert 本 feature 的 commit 即回到现状。

## 工作量估计

| 项 | 估计 |
|---|---|
| 数据通路：SSE handler 重写 + MessageStore upsert + 完整性门禁 + 单测 | 1–2 天 |
| 心跳看门狗（SSEClient 帧上报 + AppState 计时 + 单测） | 0.5 天 |
| live 验收 + UI automation | 0.5 天 |

## Step 2 调研待办（扩充本文档前完成）

- [ ] `MessageStore.swift` 全量细读：`messages` / `partsByMessage` 的精确存储形状，upsert 插入点，现有测试工具函数（本文档引用的行号基于 step 1 快速盘点，需复核）。
- [ ] SSE handler 单测套件全量盘点（SessionFlowTests 等）：`applySSEEventForTesting` harness 的形状、如何加「REST 计数断言」。
- [ ] 乐观 user row（确定性 ID `c9c0be8`）与 in-place upsert 的交互细节：服务端 user message 事件到达时 optimistic row 的 parts/info 是否被覆盖、何种覆盖是期望的。
- [ ] `message.part.removed` / `message.removed` 的完整 payload 形状（源码 + 必要时实测）。
- [ ] stale guard（`shouldApplySessionScopedResult`）的精确位置与 in-place upsert 的守卫方式。
- [ ] @Observable 粒度：`MessageStore.messages` 整体观察 vs 细粒度，in-place part 更新的重渲染范围实测；是否引入 per-part observable。
- [ ] `session_status_bar` feature 的实现状态（branch / PR / 是否已 merge），确认 hook 点兼容承诺可落地。
- [ ] 是否处理 subagent 事件的决策（倾向：保持现状，activity text 不含 subagent）。
- [ ] iOS 现有 settings / debug 基础设施：diff 日志的落点与开关方式。
- [ ] 性能基线：现状每 turn REST 次数与 payload 大小实测（临时端口 scratch server，`bash sleep 6` prompt），作为改后对比基准。
- [ ] 看门狗阈值（20s）与检查周期（5s）的取值依据写死还是可配置。
- [ ] Android 侧同设计移植（`opencode_android_client/docs/plan_sse_event_data_path.md`，含移除 `launchBusyPolling`）——两 repo 文档互为引用，Android 侧需额外核对 dsh shim host 的兼容性（其 payload 完整性门禁同样适用）。
