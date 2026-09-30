# Session Status Bar 设计（session 级状态行）

## 结论

在 composer 上方的常驻状态行（显示 "Thinking" / "Listening..." 的那一行）上，为当前 session 增加三个 session 级别的计数： rounds、 tool calls 和 tokens in total。消息 footer 保持原样（model | t/s），不做改动。

数据上，这三个量从不同的地方取，但客户端不新增任何网络请求：

- **tokens** 和 **cost**：服务端在 session 对象上已经维护了累计 tokens/cost，并通过 session.updated 的 SSE 事件逐 step 推送。此前客户端解析时直接丢弃了这两个字段，本次补上解析即可，服务端零改动。
- **rounds**（等于用户消息个数） 和 **tool calls**（等于 tool part 个数）：服务端没有现成的聚合，用客户端本地维护。持久化「计数 + 已见过的 ID 集合」，增量来自原本就收的 SSE 事件，重启后从聊天界面本来就会拉的 message list 里做 ID 对账。不为此抓取全量历史。

## 背景

状态栏需求：每个 session 有一行一直显示的极简状态，看三件事——进行到第几轮、调了多少次 tool、一共多少 token。

硬约束（鸭哥）： message list 是重量级负载（含全文+tool output），不能为计数去频繁抓历史。计数可本地化，但取数动作不能放大。

另一个现实： iOS client 是多 host 的（local: 4096/4097, SSH tunnel: remote, dsh shim）。服务端改动只能覆盖打过 patch 的 host，所以这次全部在客户端做，对所有 OpenCode compatible host 一致。服务端加计数列（user_messages / tool_calls）作为可选未来升级，不影响本 feature。

## 已验证事实（live server 实测， 2026-09-30）

以下事实用探针脚本（`tmp/status_bar_probe.py`）在 4096 live server 上实测确认：

1. `GET /session` 列表和 `GET /session/:id` 每个 session 对象都包含 `tokens: { input, output, reasoning, cache: { read, write }}` 和 `cost` 字段，并且是 session 级的累计值。
2. 服务端在 core 投影层 (`opencode-official/packages/core/src/session/projector.ts` 的 `applyUsage`) 使用 SQL 原子自增来维护这些列：`step-finish` part 落库时 +，`PartRemoved` / `MessageRemoved` 时 −。
3. 每完成一个 step，`Session.touch()` 把 session 行从 DB 重读并发出 `session.updated` 事件， payload 带完整累计值。实测时间线（1 个 prompt、 1 次 bash tool 调用、 2 个 step）：

```text
t+0.0s  session.status=busy，聚合全 0
t+1.2s  message.part.updated tool=bash status=pending→running→completed
t+1.3s  step-finish part 带 tokens {in:14542 out:34}
        session.updated 推送聚合 {in:14542 out:34}        ← step 1 完成即更新
t+2.5s  step-finish part 带 tokens
        session.updated 推送聚合 {in:20142 out:64 cacheR:8960}
        session.status=idle
终态核对：session 聚合 == 各 message tokens 求和，delta 精确为 0
```

4. 每次 tool 调用都有一个 `type == "tool"` 的 part，`message.part.updated` 事件携带 part（含 partID 和 state.status），新调用的第一个事件 status 为 pending。
5. 每个 `prompt_async` 正好落一条 user message。当前 session 实测有 2 条 user message、 20 条 assistant message、 37 个 tool part。
6. compaction 不删除/改写历史 message/part（仅写 `tail_start_id` 标记下次 LLM 调用从哪条开始带），总结调用自身的 tokens 会计入累计。因此三个量在 compaction 后语义均不变： rounds/tools 是历史累计， tokens 单调不减。
7. 客户端现状：`Session` Swift 模型不解析 `tokens`/`cost`（字段一直丢失）；`Message` 模型完整解析了 `tokens`、 tool part 与 state； SSE handler 已在处理 `session.updated` (upsert) 与 `message.part.updated` (按 partID 跟踪 part type)。

## 数据通路

### tokens in total（+ cost，可选显示）

- 基线：`loadSessions` 拉取到的 session 列表自带累计值；切换 session 时 `currentSession?.tokens` 就是基线。
- 实时：当收到 `session.updated` SSE 事件时 upsert session 对象， tokens 随之更新。
- 语义钉死：累计处理量 = 所有 LLM 调用的 usage 之和（每步输入包含当时的全部上下文，长 session 中 input >> output 是正常现象）。不是"对话内容有多少 token"。
- Fallback：若 host 不返回该字段（老版本或兼容层），则回退到对已加载的 message 窗口内 assistant tokens 求和；窗口不完整时该段按近似值显示或隐藏（实现时二选一，默认隐藏宁缺勿假）。

### rounds

- 定义： session 内 user message 总数（鸭哥确认的口径： count of user messages）。
- 基线：首次打开 session 时从已加载的 message 窗口数 user message；若 hasMoreHistory == false（翻到了历史头），计数即精确。
- 实时： SSE message.updated 中 role=user 且 msg ID 不在 seen 集合 → rounds +1， ID 入集合。
- 收敛： UI 自身的翻页（loadOlderMessages）每翻一页都在扩大已加载窗口， seen 集合随之补全，未精确的计数自然收敛。

### tool calls

- 定义： session 内 `type == "tool"` 的 part 总数。注意单位是 part 不是 message：一个 assistant step 可以并行多个 tool part。
- 基线/实时/收敛：同 rounds，单位换成 tool part， ID 用 partID（客户端 MessageStore 已按 partID 跟踪 part type，复用同一基础设施）。

## 本地状态设计

每个 session 持久化一份（跟随 app 现有的 per-session 持久化模式）：

| 字段 | 类型 | 作用 |
|---|---|---|
| `rounds` | Int | user message 计数 |
| `toolCalls` | Int | tool part 计数 |
| `seenUserMessageIDs` | Set\<String\> | 跨重启去重 + 离线对账 |
| `seenToolPartIDs` | Set\<String\> | 同上， part 粒度 |
| `baselineComplete` | Bool | 计数是否覆盖过完整历史 |

规则：

1. 仅对新 ID 增计（seen 集合中已见则跳过），保证同一事件重放/SSE 重连不重复计数。
2. 每次 loadMessages 后窗口对账：仅增未入 seen 的窗口内 ID。对账只增不减。
3. 窗口覆盖全量（hasMoreHistory == false）时按窗口重算并设 baselineComplete = true。
4. revert 后（客户端本身会 revert 后强制 loadMessages）：按重载窗口重算计数， baselineComplete 降级为 false。这是已声明的 edge case，接受瞬态不精确，不做窗口外删除的精确回滚。
5. compaction 无需处理（见已验证事实第 6 条）。
6. 计数是 per-session、 per-device 的；清应用数据后重新 seed，不视为缺陷。

## UI 规格

挂载点在 composer 上方的状态栏（`ChatTabView.quietComposerStatus`）。rounds/tools/tokens 是 session 级数据，天然属于常驻状态栏，不放消息 footer。真机试用发现单行放不下一切（计数 + Thinking + 耗时互相挤占、被截断），所以拆成两行：

- **上行（常驻）**：`⟳ 12 · 🔧 37 · 1.07M tok · 96% cache hit`（刷新环=rounds，扳手锤=tool calls，纯文本 tok 与 cache hit）。有 current session 即显示，tertiary 样式，`lineLimit(1)`。
- **cache hit**：`cache.read / (input + cache.read)`，`input` 为未命中输入（聚合口径已用真实 payload 验证：total = input + output + reasoning + cache.read）。取数与 token 段同构（session 聚合优先、完整窗口回退、无数据隐藏）；input>0 且无 cache 字段 = 真实 0%。图标方案（memorychip/bolt）曾评估，因 memorychip 易被误读为 context window，最终用纯文本。
- **下行（临时）**：原有行为不变——gold 点 + agent 活动（"Thinking"）· 语音状态（"Listening..."）· 耗时 · 中断按钮。
- **消息 footer**：保持原样不变（`model | 通用 t/s | N t/s decoding`），本 feature 不动它。
- 屏幕空间不够时计数段降级为紧凑标签（`12 rd · 37 tl · 1.07M tk`），以真机截图为准。

token 的紧凑表示为：<1000 直接显示（`950`）；>=1000 用 K/M/B，值 ≥10 取一位小数、<10 取两位小数、尾部零去掉（`85.2K`、`1.11M`、`2B`）。

注：初版方案把计数放在最后一条 assistant 消息的 footer 上并删除了 decode t/s 段；真机试用后（2026-09-30）改为本方案——footer 完全不动，计数移到常驻状态行。decode t/s 段保留，且 `stepTimings` 增加 UserDefaults 持久化（step 完成时落盘），app 重启后不再丢失。

## 边界与口径

- **subagent（tool/rounds 口径）**： task 工具在子 session 中运行，它的 tool 调用不算进父 session。rounds/tool calls 段保持主 agent 视角，与 message 列表口径相同。
- **subagent（token/cache hit 口径）**：token 总量与 cache hit rate 并入主数字（含全部后代 subagent session）。服务端 session 对象带 `parentID` 链接且父聚合是 self-only（实测父 message 和 == 父聚合，子 session 用量未计入），客户端按 `parentID` 递归求和即可，零新增网络请求（子 session 在项目化 session 列表与 `session.updated` SSE 里都已存在）。主 session 自身部分不可知时整体隐藏；子 session 出分页窗口时少算（接受）。
- **多 host**：本地状态以 sessionID 为键（与 app 内其他 per-session 持久化一致）。session ID 是 `ses_` + 26 位随机值，跨 host 撞 ID 实际不可能；同一 server 的多个 host profile 反而应共享同一份计数。
- **成本**：`cost` 字段一并解析，本期 UI 不显示，留给后续。

## 实现范围（仅 iOS 客户端）

1. **Models/Session.swift**：`Session` 增加可选字段 `tokens: Message.TokenInfo?`、`cost: Double?`（复用现有 `TokenInfo` 的宽容解码，服务端省略 `total` 时自行求和的逻辑已存在）。
2. 新增 **Stores/SessionStatsStore.swift**：上表字段的持久化 + 增量 + 对账 + revert 重置；暴露 `rounds`、`toolCalls`、`totalTokens`（含 fallback 逻辑）给 UI。
3. **AppState+SSE.swift** / **AppState+Messages.swift**：把 `message.updated`（user）、`message.part.updated`（tool）、`loadMessages` 完成、 revert 四个钩子接到 stats store。
4. **Views/Chat/MessageRowView.swift**： token 紧凑格式化函数 `compactTokenCount`（单测覆盖）； footer 本身不动。
5. **Views/Chat/ChatTabView.swift**：`composerStatusText` 前置 session 计数段（rounds/tools/tokens，常驻）。
6. **Stores/MessageStore.swift**：`stepTimings` 持久化——step 完成（有 outputTokens）时写 UserDefaults，启动时加载，session 级清理时同步删除，上限 200 条。
5. 文案：新增 key 进 `L10n`（rounds / tools / tok 及 fallback 隐藏逻辑的注释）。

## 测试与验收

- 单测： token 紧凑格式化（950 / 85200 / 1110000 / 2100000000 等边界）； stats store 增量去重（同 ID 重放不重复计数）；窗口对账补计； revert 重置；`Session` 模型带/不带 `tokens`/`cost` 的解码。
- 集成验收：对着 4097 测试 server 跑 `tmp/status_bar_probe.py` 同款流程，人工确认 footer 三段在 step 完成、 tool 到达时实时更新；重启 app 后计数不丢、不重复。
- UI 验收走现有 iOS UI automation（真机/模拟器截图核对 footer 行数与内容）。
