# SSE Event Data Path 设计（SSE 作为消息状态的数据通路）

Status: implementation ready (step 2 investigation done, all file:line based on master `3c603dc` and opencode-official `71927c2d05`, ready to start)

## 1. Bottom Line

iOS 客户端目前是"用 SSE 当门铃，真话全靠 REST 说"：每个消息相关的 SSE 事件都把 payload 里的完整数据扔掉，转而触发一次全量 REST 拉取（`loadMessages` + `loadSessionDiff`），而且这些 `await` 在同一个串行事件循环内排队。一个 N=3 step、每 step M=2 tool 的普通 turn，静态算出来是 **42 对 REST（84 次拉取）串行阻塞事件循环**（公式 `N×(8+3M)`，源码逐行验证，见「客户端现状盘点」末尾）。感知结果是：tool 正在执行时 UI 要等 REST 快照回来才动。

服务端把数据塞在事件的 payload 里（native OpenCode server + 源码 + live 实测双重验证）：`message.part.updated` 有完整 part（tool 的 `state.status/input/output/time`），`message.updated` 有完整 message info，`message.part.delta` 有流式文本增量，`server.heartbeat` 每 10s 一帧。

设计三件套：

1. SSE作为数据通路：事件payload直接upsert到MessageStore，零RTT，事件到即渲染。payload完整性门禁：字段不全（如dsh shim的瘦part形状）回退现行REST路径，行为与今天一致。
2. REST降级为对账：per-event REST归零，只在bootstrap（重连）、turn结束（session.status -> idle）、手动刷新/切换、看门狗触发时拉。每turn REST从42对降到1-2对。
3. 心跳看门狗：server.heartbeat是/global/event上保证存在的10s帧（long tool期间也发，源码验证）。客户端5s周期检查静默时长，>20s（错过2个心跳）触发一次对账。替代轮询的静默死亡恢复；无心跳的兼容host上退化为20s低频对账，不劣化。

* **明确不做**：2s busy polling（用户痛点，不引入）、发送时乐观 busy（亚秒 cosmetic，不做）、tile 视觉升级（P2 另开）、服务端改动（零）。

## 2. 用户可见问题与根因

观察：Android 可见运行中的 tool + 计时器；iOS tool 运行时 UI 无更新，结束后一次性呈现。

根因链（均有文件行号，master）：

1. **SSE 当门铃用**：`message.part.updated` handler (`AppState+SSE.swift:132-155`) 调用 `messageStore.applyMessagePartUpdate` (`MessageStore.swift:154-169`)，后者只做 `recordPartType` 打点，**不碰 payload**，直接返回 `.finalized` → `await loadMessages() + await loadSessionDiff()` (:149-155)。part 的完整对象被解析出来直接丢弃。
2. **串行事件循环 + 队头阻塞**：`connectSSE` (`AppState+SSE.swift:9-39`) 的 `for try await` 循环里 `await handleSSEEvent(event)` (:28)，消息事件 handler 内部又 `await` REST 往返——一个慢 REST 卡死后续所有事件。
3. **无静默死亡恢复**：backoff 重连（`min(30, 2^attempt)`，2s→4s→8s→16s→30s 封顶，:33-36；重连成功后跑 `bootstrapSyncCurrentSession` :26）只处理「连接断了」。连接活着但没帧（代理缓冲丢帧）时，UI 永久停在最后状态。（注：iOS 现在**没有**busy polling，也没有其他恢复路径。）

4. **UI 层缺口**（与数据通路独立）：**当前 UI 尚不足以把 tool 的 running 状态体现出来**——tool 卡位于折叠的 `ToolCallsRowView`（`MessageRowView.swift:754-796`），行内没有 per-tool 的 running 视觉（无 header spinner、无明确 running 标注）；composer 状态行文案依赖 `session.status` 的 `status.message` 与 ActivityTracker 推导（`ActivityTracker.swift:74-97`），质量取决于服务端措辞。所以数据通路是「用户能看到 tool 在跑」的**必要非充分条件**：本 feature 解决数据及时，running 状态的视觉呈现要由 P2 tile feature（5.7）补齐。P2 落地前，改后的体验 = composer 行及时出现（busy）+ 折叠 tool 行状态及时更新，行内仍无显式 running 指示。

* Android 对照（见 Android 侧 plan）：同样的门铃架构 + 400ms debounce + 2s busy polling + in-memory 流式文本。本设计把数据源换成 payload 本身，用看门狗替代 polling；Android 侧同设计移植并移除 polling。

## 3. 服务端事件契约（native OpenCode server）

源码：`opencode-official`（upstream dev `7945de2089` + 1 个私有 commit `71927c2d05`；私有 patch 仅改动 run-state 的 runner 作用域与两个 schema 定义，**不影响下列任何契约**）。live 实测时间线：来自 `session_status_bar` feature 的探针（`tmp/status_bar_probe.py`，4096 live server，2026-09-30；该 feature 的文档在 opencode_ios_client 主 checkout，未进本分支——时间线已内联在下文，自足）。

### SSE 端点

服务端同时挂 `/event`（instance 级，按 directory 过滤）、`/global/event`（全局无过滤）、`/api/event`（V2 面，256 容量 dropping 队列）。**iOS 订阅 `/global/event`**（`SSEClient.swift:57-58` 硬编码；`APIConstants.sseEndpoint` 是死常量）。

- `/event`、`/global/event`：每 ~10s 一发 `server.heartbeat`（handler 里独立的 `Stream.tick("10 seconds")`，`handlers/event.ts:63-66`、`handlers/global.ts:35-38`；**不依赖任何 session/instance 状态**，idle/长 tool 照样发）；新建连接的第一帧 `server.connected`（`properties: {}`）；无界队列不丢帧；同 session 的事件 FIFO 保序（单进程串行 notify + 同 session 来自同一个 runLoop fiber）。
- `/api/event`：心跳是 15s 的 SSE 注释帧（不是 `server.heartbeat` 事件）；对 v1 live 事件（`session.status`/`message.part.delta`）编码会失败（schema 编码探针实测），纯 `cli serve` 进程只挂这个端点。**iOS 客户端不订阅这个端点，与本设计无关**；若主机只有 `/api/event`（纯 cli serve），现状客户端已经连不上，不在范围。
- dsh shim host：iOS 多个 host 可以连 shim（现状可用 ⇒ shim 提供可用的 `/global/event`）；shim 有没有发 `server.heartbeat` **未验证**——看门狗在无心跳 host 上退化成 20s 低频对账（见 5.6），不劣化。

### 事件表（客户端相关，payload 形状已验证）

| 事件 | properties | 关键事实 |
|---|---|---|
| `session.status` | `{sessionID, status: {type: busy\|idle\|retry, ...}}` | 一个 turn 内 busy 约 `2N+1` 帧（循环头 + 每 step process 头，`prompt.ts:1089`、`processor.ts:653`）；**idle 只在整个 turn 结束发一次**（Runner.onIdle，`run-state.ts:48-51`），step 间隙不交替 ⇒ `busy→idle` 可当 turn 结束信号 |
| `message.updated` | `{sessionID, info: <完整 message info>}` | 每 step 新 assistant message 是新 `msg_` id（`prompt.ts:1190-1201`）：step 开始一帧 + step 结束一帧（`processor.ts:470`，此时无 `time.completed`）。turn 级 final completion 帧是否存在未验证（live 待测，不影响设计——对账兜底） |
| `message.part.updated` | `{sessionID, part: <完整 part>}`（`updatePart` 发布，`session.ts:637`，`structuredClone` 全量） | tool 状态机：`tool-input-start` 建 pending → `tool-call`（参数完成）转 running 写 `time.start` → `tool-result` 转 completed 写 `time.end`（`processor.ts:216-253, 331-351, 160-184`）。每 step 固定 6 帧 + 每 tool 3 帧（step-start/reasoning×2/text×2/step-finish；tool pending/running/completed） |
| `message.part.delta` | `{sessionID, messageID, partID, field: "text", delta}` | 仅 text（`processor.ts:513-524`）与 reasoning（`:294-306`）两处 emit，field 恒为 `"text"`；**start（空 text 的 part.updated）→ delta* → end（完整 text 的 part.updated）顺序有保证**；delta 是 live 非 durable 事件；end 帧是幂等收敛帧（丢 delta 可用 end 帧兜底，但无显式丢帧信号） |
| `message.part.removed` | **只有 `{sessionID, messageID, partID}`，无 part 对象** | 触发点：revert 清理（`revert.ts:101-124`，prompt/shell/summarize 前）+ `DELETE` message/part 两个 HTTP 端点。edit 不发 removed |
| `message.removed` | `{sessionID, messageID}` | 同上 |
| `session.updated` | `{sessionID, info: <完整 session 含累计 tokens/cost>}` | 每 step 完成 `Session.touch()`；现状 iOS 已本地 upsert，不触发 REST |
| `server.connected` / `server.heartbeat` | `properties: {}` | `/global/event` 上是普通 data 帧；现状 iOS handler 只处理 connected（`AppState+SSE.swift:55-56`），heartbeat 落 `default: break`（:193）丢弃 |
| subagent | — | 子 session 事件带**子 sessionID**，与父事件同一 bus（客户端按 sessionID 分流）；父 session 的 task part 事件带父 sessionID，执行期间停 `running` 且 `state.metadata.sessionId` 已指向子 session（`task.ts:185-195`）。现状 iOS 只处理 currentSessionID 事件——保持 |

live 时间线（session_status_bar 已验证事实，引用不重复跑探针）：

```text
t+0.0s  session.status=busy
t+1.2s  message.part.updated tool=bash status=pending→running→completed（三帧独立推送）
t+1.3s  step-finish part 带 tokens；session.updated 推送累计
t+2.5s  session.updated；session.status=idle
```

## 4. 客户端现状盘点（iOS，master `3c603dc`，全部 file:line 已复核）

| 位置 | 现状 |
|---|---|
| `AppState+SSE.swift:9-39` | `connectSSE`：重连循环 + backoff（2s 起步 30s 封顶）+ 重连后 `bootstrapSyncCurrentSession`；串行 `for try await` + `await handleSSEEvent` |
| `AppState+SSE.swift:57-76` | `session.status` handler：busy/idle/retry 只更新 `sessionStatuses` + `updateSessionActivity`，**不触发 REST**（有单测断言 `messagesCallCount == 0`） |
| `AppState+SSE.swift:107-118` | `message.updated` → `await loadMessages() + await loadSessionDiff()` |
| `AppState+SSE.swift:119-131` | `message.part.delta` → 仅 `recordVisibleToken`（throughput），不更新文本 |
| `AppState+SSE.swift:132-155` | `message.part.updated` → `applyMessagePartUpdate`（恒 `.finalized`）→ `await loadMessages() + await loadSessionDiff()` |
| `AppState+SSE.swift:193` | `default: break`（`server.heartbeat` 在此被丢弃） |
| `AppState+SSE.swift:393-395` | `applySSEEventForTesting`：薄直通 `handleSSEEvent`（测试入口） |
| `MessageStore.swift:9-17` | `@Observable final class MessageStore`：`messages: [MessageWithParts]`（只有整体替换路径）、`partsByMessage: [String: [Part]]`（**app 侧只写不读**，只有测试读） |
| `MessageStore.swift:11-14, 154-169` | `MessagePartUpdateOutcome { .ignored, .finalized }`；`applyMessagePartUpdate` 只做 `recordPartType` 打点 |
| `MessageStore.swift:21` | `pendingOptimisticMessageIDs`（optimistic user row 对账是纯 id membership） |
| `Models/Message.swift:254-264` | `MessageWithParts { info: Message, parts: [Part] }`，非 Equatable 非 Identifiable；`Part` 是 Identifiable by `id` |
| `AppState+Messages.swift:22-90` | `loadMessages`：`GET /session/{id}/message?limit=20` + stale guard + optimistic 合并（id membership，keep-latest = 服务端版本覆盖 temp parts）+ `partsByMessage` 重建 + busy 时 `refreshSessionActivityText`（2.5s debounce） |
| `AppState+Messages.swift:152, 209-211` | optimistic user row：确定性 `msg_<uuid>`（`makeServerID`，commit c9c0be8 的对账基础）随 prompt 发给服务端 |
| `AppState+Messages.swift:213-269` | `appendOptimisticUserMessage`：temp text part id `temp-part-<messageID>` + temp file parts |
| `AppState+Messages.swift:119-135` | `loadSessionDiff`：`GET /session/{id}/diff` |
| `AppState.swift:878-888` | `shouldProcessMessageEvent`（事件入口 guard，无 sessionID 放行）/ `shouldApplySessionScopedResult`（REST 结果 stale guard）。`message.part.updated/delta` 走内联 `sessionID == currentSessionID`（SSE:124,134）+ `applyMessagePartUpdate` 内再一层 |
| `SSEClient.swift:52-137` | 订阅 `baseURL + /global/event`；逐字节行解析，`:` 注释帧丢弃，`data:` 帧 JSON 解码为 `SSEEvent{directory, payload{type, properties}}`；heartbeat/connected 是普通 data 帧（解析层无特殊处理） |
| `ChatTabView.swift:563-588` | 消息列表非 lazy（ScrollView+VStack+ForEach），identity = 组 id（`assistant-<joined msg ids>`）；单 part 变化现状只能经 `messages` 整体替换传播 |
| `SessionFlowTests.swift:1339-1697` | SSE 单测全在 `AppStateFlowTests`；harness = `makeSSEEvent(JSON)` + `applySSEEventForTesting`；**REST 计数断言已存在**（`MockAPIClient.messagesCallCount`/`sessionDiffCallCount`，TestDoubles.swift:98/116） |

每 turn REST 静态计数（per-event 触发点逐行核对）：

```
每 turn loadMessages 对 ≈ N × ( 2(message.updated) + 6(step-start + reasoning×2 + text×2 + step-finish) + 3M )
                        = N × (8 + 3M)   （loadMessages 与 loadSessionDiff 各这么多，全部串行 await）
例：N=3, M=2 → 42 对（84 次拉取）。dsh shim host 更糟：tool input 流式期每 chunk 一帧 part.updated，各 +1 对。
```

## 5. 设计

### 5.1 事件 → apply 规格

| 事件 | 现状 | 改后 |
|---|---|---|
| `message.part.updated` | 全量 REST | 解码 `properties.part` → `MessageStore.upsertPart`（原地，零 RTT）；**门禁不通过 → 回退现行 REST**（见 5.2）。保留 `recordVisibleToken`/`recordStepFinish`/`recordPartType` 打点 |
| `message.updated` | 全量 REST | 解码 `properties.info` → `MessageStore.upsertMessageInfo`（按 id upsert，保留本地 parts）；保留 `recordStepStart`；user message 确认 → `untrackPendingOptimisticMessage` |
| `message.part.delta` | 仅 throughput | 按 partID 追加本地 part.text（in-memory 流式）；throughput 保留 |
| `message.part.removed` | `default: break` | 按 `{sessionID, messageID, partID}` 删 part |
| `message.removed` | `default: break` | 按 `{sessionID, messageID}` 删行 |
| `session.status` | 本地状态更新，无 REST | 保持；**`idle` 额外触发一次对账**（`loadMessages` + `loadSessionDiff`，新行为） |
| `session.updated` / `permission.*` / `question.*` / `todo.updated` / `session.error` | 轻事件 | 保持不动 |
| `server.connected` | bootstrap poll | 保持不动 |
| `server.heartbeat` | `default: break` 丢弃 | 显式 case，无动作（时间戳在 `handleSSEEvent` 入口统一刷，见 5.6） |

通用规则：

- **sessionID 门控不变**：消息级事件只处理 `currentSessionID`（现有 `shouldProcessMessageEvent` / 内联比较位置不动）。
- **幂等**：按 ID upsert，重复/乱序安全（part 先于 message 到达 → 壳行，见 5.3；服务端同 session 事件 FIFO 保序）。
- **stale guard**：事件同步处理（无「发出→返回」窗口），现有内联 `== currentSessionID` 检查即守卫，无需新增。

### 5.2 `MessageStore` upsert 实现规格

新增方法（均在 `MessageStore.swift` 中，`applyMessagePartUpdate` 附近）：

```swift
// 返回 .applied（已原地更新）/ .needsReconcile（门禁不通过，调用方回退 REST）/ .ignored（sessionID 不匹配等）
enum PartUpsertOutcome { case applied, needsReconcile, ignored }

func upsertPart(_ part: Part) -> PartUpsertOutcome // 壳行的 time 用本地时间（5.3）
func upsertMessageInfo(_ info: Message)            // 保留本地 parts；行不存在则建壳行
func removePart(messageID: String, partID: String)
func removeMessageRow(messageID: String)           // 同步清 partsByMessage 对应键
```

handler 侧骨架 —— `message.part.updated` 分支（`AppState+SSE.swift:132-155`）：
现有的 sessionID 门控 + 打点块（:133-148，`recordVisibleToken`/`recordStepFinish`）原样保留；
:149-155 的 `applyMessagePartUpdate` switch 替换为下。注意现状的 switch 在门控块**之外**（`applyMessagePartUpdate` 内部自做 sessionID 检查），新代码显式把 `part.sessionID == currentSessionID` 作为 gate：

```swift
if let partObj = props["part"]?.value as? [String: Any],
   let data = try? JSONSerialization.data(withJSONObject: partObj),
   let part = try? JSONDecoder().decode(Part.self, from: data),
   part.sessionID == currentSessionID {
    switch messageStore.upsertPart(part) {
    case .applied:
        break // 零 REST
    case .needsReconcile:
        await loadMessages()
        await loadSessionDiff() // 门禁回退 = 现行路径
    case .ignored:
        break
    }
} else {
    // part 缺失/解码失败：现状 .finalized 的前置条件是「partObj 有 messageID+id 且 sessionID 匹配」，
    // 解码失败意味着 id 可能缺失，现状行为是 .ignored（不 REST）；这里做 REST 是略收紧的安全方向
    await loadMessages()
    await loadSessionDiff()
}
```

**同步删除** `applyMessagePartUpdate` 方法与 `MessagePartUpdateOutcome` enum (`MessageStore.swift:11-14, 154-169`)。其内部的 `recordPartType` 打点移至 handler 打点块——直接调用现有方法 `messageStore.recordPartType(sessionID:partID:type:)` (`MessageStore.swift:107-112`)，首写优先，delta 的 partType 判断依赖它。

handler 侧骨架——`message.updated` 分支（`AppState+SSE.swift:107-118` 改造）：

```swift
case "message.updated":
    let eventSessionID = props["sessionID"]?.value as? String
    if Self.shouldProcessMessageEvent(eventSessionID: eventSessionID, currentSessionID: currentSessionID) {
        if let infoObj = props["info"]?.value as? [String: Any],
           infoObj["role"] as? String == "assistant",
           let assistantID = infoObj["id"] as? String,
           let sessionID = eventSessionID {
            messageStore.recordStepStart(assistantID, sessionID: sessionID) // 保留
        }
        if let infoObj = props["info"]?.value as? [String: Any],
           let data = try? JSONSerialization.data(withJSONObject: infoObj),
           let info = try? JSONDecoder().decode(Message.self, from: data) {
            messageStore.upsertMessageInfo(info) // 5.2 语义（含 user message untrack）
        } else {
            await loadMessages()
            await loadSessionDiff() // info 缺失/解码失败 = 现行路径
        }
    }
```

* `upsertPart` 语义：

1. **门禁（payload 完整性）**：tool part 必须带可解码的 `state`（`PartStateBridge` 双形态已支持）；text/reasoning part 必须带 `text` 字段。不满足（如 dsh shim 的瘦 part + 顶层 delta）→ 返回 `.needsReconcile`，handler 走现行 `await loadMessages() + await loadSessionDiff()`。门禁让多 host 兼容自动成立：shim 走老路，native server 走数据通路。
2. **行定位**：按 `part.messageID` 找 `messages` 行。
   - 行存在：按 `part.id` 在 `parts` 内 replace-or-insert（替换保持原位置——服务端同一 part id 多次推送是状态更新不是新 part；插入追加末尾）。
   - 行不存在：按 part 类型决定（见 5.3 壳行规则）。
3. **optimistic temp-part 去重**（关键边界）：行是 pending optimistic（id ∈ `pendingOptimisticMessageIDs`）且 incoming part id 不是 `temp-` 前缀 → 先移除该行全部 `temp-` 前缀 part，再插入 incoming part。避免服务端 user part 事件与 optimistic temp part 并排显示。
4. **`partsByMessage` 同步重建**该行（app 侧只写不读，但 `removeMessage`/`appendOptimisticUserMessage` 都维护它，保持一致；测试也读它）。

* 解码：用已有例子（`AppState+SSE.swift:58-61`）把 `properties["part"]?.value` 转 JSON → `JSONSerialization.data(withJSONObject:)` → `JSONDecoder().decode(Part.self)`。失败 → `.needsReconcile`。

`upsertMessageInfo`的含义是：如果消息已存在，则使用新的 `info` 替换它（注意：这里不更新 `parts` 字段，因为 `message.updated` 不包含 `parts` 信息，`parts` 由 `part` 事件和对账提供）；如果消息不存在，则插入一个壳行（`parts` 为空）。对于用户消息且消息处于 `pending optimistic` 状态的情况，则替换 `info` 并执行 `untrackPendingOptimisticMessage(id)`（与 `loadMessages` 中 id 的成员资格语义保持一致，当服务器确认该 id 的消息时，将其添加到 `pending` 集合中，但 `parts` 仍保持临时版本，直到对账完成，详见 5.8 中的已知取舍）。

### 5.3 壳行规则（part 先于 message 到达）

**注意**：正常流程下不会出现 "服务端每 step 先 `message.updated`（step 开始建 assistant message, `prompt.ts:1201`）再发 part 事件" 的情况，且同一个 session 是 FIFO 的。出现这种情况说明要么重连错过了 message.updated，要么消息乱序。规则：

- part 类型 ∈ {`tool`, `reasoning`, `step-finish`, `patch`}（仅 assistant）→ 创建空行：`Message(id: part.messageID, sessionID, role: "assistant", time: 本地时间, 其余字段置 null)`，并追加 part 到末尾。空行需能被后续 `upsertMessageInfo` / `loadMessages` 自然覆盖。
- part 类型 ∈ {`text`, `file`}（用户或助手可能发送）→ **不创建空行，忽略此 part**（等待 `message.updated` 或对账）。宁可暂时不显示，也不要创建角色不明空行。
- `message.part.delta` 的 part 在本地不存在 → 忽略（start 帧保证 part 已存在；重连丢 start 时由 end 帧/对账收敛）。

### 5.4 `message.part.delta` 处理

handler（`AppState+SSE.swift:119-131` 改造）。现有 guard 链是 `sessionID == currentSessionID && field == "text" && delta 非空 && messageID/partID 可解析 && partType(for: partID) == "text"`（末项用 `partTypes` first-write-wins 索引，`MessageStore.swift:39,107-112`，由 part.updated 的 start 帧写入）——**全部保留**，新增的文本追加挂在同一 guard 内：

1. 定位本地 part（partID 在当前 session 行内）→ `part.text += delta`（原地改 `messages`）。part 不存在 → 忽略（5.3）。
2. **reasoning 不进流式**：guard 只放行 text part，reasoning 文本仅经 end 帧（完整 `part.updated`）落本地 part——与现状一致（现状 iOS 的 reasoning 也不从 delta 渲染），不扩大改动面。
3. end 帧（完整 text 的 `part.updated`）到达后 `upsertPart` 整体替换该 part → 自然收敛（delta 拼接与全量帧一致；即便 delta 有丢失也被 end 帧覆盖）。

### 5.5 REST 降级为对账

- 删除 `loadMessages` 和 `loadSessionDiff` 的所有 per-event 触发点，保留的触发时机：

| 时机 | 现状 | 改后 |
|---|---|---|
| SSE (re)connect bootstrap（`bootstrapSyncCurrentSession`） | 有 | 保留 |
| `session.status → idle` | 无（只更新本地状态，单测断言 0 REST） | **新增**：`await loadMessages() + await loadSessionDiff()`（turn 终态对账，含 `time.completed`/tokens；一个 turn 一次） |
| 手动刷新 / session 切换 / loadOlder / revert / edit / abort / recover / refresh | 有 | 保留（非 per-event 的 `loadMessages` 调用点清单见下，全部不动） |
| 看门狗触发 | 无 | 新增（5.6） |
| `session.error` | `await loadMessages`（无 diff） | 保留不动（错误路径保持现状，不扩大改动面） |

* 预期：每 turn REST 从 `N×(8+3M)` 对降到 1（idle 对账）+ 0–1（bootstrap，仅重连时）。message list 重量级负载拉取频率显著下降——满足「取数动作不能放大」硬约束（`session_status_bar/design.md` 背景节），是收缩不是放大。

**idle 对账的代码位置**：`session.status` handler（`AppState+SSE.swift:57-76`）内、`sessionStatuses[sessionID] = decoded` 之后追加：

```swift
if decoded.type == "idle", sessionID == currentSessionID {
    await loadMessages()
    await loadSessionDiff()
}
```

* 注意门控：现有handler对所有session更新status（无currentSession过滤，`sessionStatuses`是全局map），所以idle对账动作必须显式带`sessionID == currentSessionID`。busy/retry分支不动。

* **非 per-event 的 `loadMessages` 调用点清单**（全部保留；`loadSessionDiff` 同理，列主要项）：

- `AppState+Sessions.swift`：`selectSession` :285, `loadSessions` 恢复 hydrate :174, `forkSession` :364, `deleteSession` :395, `abortSession` :482, `bootstrapSyncCurrentSession` :441
- `AppState.swift`：`refresh()` :900
- `AppState+Messages.swift`：`loadOlderMessagesForCurrentSession` :111, `editFromMessage`/revert :191
- `AppState+SSE.swift`：`recoverFromMissingCurrentSessionIfNeeded` :359, `handleRemoteSessionDeleted` :380, `session.error` handler :191（此路径保留，见上表）

### 5.6 心跳看门狗

- **时间戳**：`handleSSEEvent` 入口统一 `sseLastFrameAt = Date()`（任何帧，包括 heartbeat）。
- **检查**：5s 周期 Task（`connectSSE` 的 stream 启动时 launch，断流/取消时 cancel；AppState 是 `@MainActor`，与事件循环无竞态）：

```swift
func checkSSEWatchdog() {
    guard let last = sseLastFrameAt, currentSessionID != nil else { return }
    guard Date().timeIntervalSince(last) > Self.sseSilenceThreshold else { return } // 20s
    sseLastFrameAt = Date()
    Task { await loadMessages(); await loadSessionDiff(); await syncSessionStatusesFromPoll() }
}
```

- **阈值 20s** = 2 个心跳周期（服务端 10s 硬编码）。最坏恢复时延 25s（20s 阈值 + 5s 检查周期）。常量：`AppState` 的 static let 常量区（`AppState.swift:165-186`）新增 `sseWatchdogCheckInterval: TimeInterval = 5` 与 `sseSilenceThreshold: TimeInterval = 20`。
- **接线（精确落点）**：
  - `AppState` 新成员（存储属性区，`sseTask` 旁，`AppState.swift:667-668` 附近）：`var sseLastFrameAt: Date?`（**internal，不加 `private`**——单测经 `@testable` 直接预置；测试 target 现有模式就是直读 internal 状态，如 `state.messageStore...`）；`private var sseWatchdogTask: Task<Void, Never>?`（测试不触碰）。
  - `connectSSE`（`AppState+SSE.swift:9-39`）：函数入口先 `sseWatchdogTask?.cancel()`；`bootstrapSyncCurrentSession` 调用后（:25-26 与 :26 之间语义上即在 stream 消费前）置 `sseLastFrameAt = Date()` 并 launch watchdog Task：

```swift
sseWatchdogTask = Task { [weak self] in
    while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(Self.sseWatchdogCheckInterval))
        await self?.checkSSEWatchdog()
    }
}
```

- `handleSSEEvent` 入口（`switch` 前）：`sseLastFrameAt = Date()`。
  - `checkSSEWatchdog()`：新增 `@MainActor` internal 方法，放 `AppState+SSE.swift`（上述伪码）；`syncSessionStatusesFromPoll` 已存在（`AppState+Sessions.swift:464-468`），直接复用。
  - AppState 销毁 / `connectSSE` 重入时 cancel watchdog Task（与 `sseTask` 同生命周期，:10-11 的 cancel 模式）。
- **不是轮询**：无固定周期拉取；正常时（heartbeat 10s 一帧 + turn 中业务事件）检查恒 no-op。
- **与 backoff 重连分工**：重连管「连接断了」（重连后 bootstrap 对账已存在）；看门狗管「连接活着但没帧」。两者叠加覆盖静默死亡。
- **无心跳 host 的退化行为**（dsh shim / 假设的兼容 host）：静默期每 20–25s 触发一次对账 = 低频轮询，频率远低于 Android 现状 busy polling（2s），无回归。若日后确认 shim 无心跳且用户在意，可加「连续 K 次无心跳触发后阈值升到 60s」的自适应——本期不做。
- **后台场景**：app 后台时 Task 可能挂起；SSE（URLSession）后台大概率断连 → 重连 bootstrap 已覆盖回补；回前台后第一次 timer tick 或下一帧即收敛。已知取舍，不做专门处理。
- 单元测试路径：`sseLastFrameAt` 与 `checkSSEWatchdog()` 走 internal 暴露（或 `@testable` 直访），测试里把 `sseLastFrameAt` 置为 30s 前 → 调 `checkSSEWatchdog()` → 断言 `messagesCallCount == 1`。

### 5.7 明确不做

- **2s busy polling**：不引入。静默死亡由 5.6 覆盖；数据及时性由 5.1 的 payload 直供覆盖。
- **发送时乐观 busy**：`sendMessage` 到 `session.status=busy` 帧之间（亚秒）composer 行缺口，接受。
- **tile / FileCard 视觉升级**：不是纯体验润色，是把 tool running 状态体现出来的**必要补充**（见「UI 层缺口」）：现有折叠 tool 行内没有 per-tool running 指示，composer 行文案依赖服务端 `status.message`。P2 feature 要在行内显式呈现运行中的 tool（tool 名 + 已运行时长）——即 Android 现状已有的体验，也是 iOS 最终要对齐的目标。`ToolPartView` 现有 running 态（`ToolPartView.swift:31, 191-198`）随数据及时落地直接生效，作为 P2 前的过渡形态。
- **subagent 事件处理**：保持现状（只处理 currentSessionID）；父 session 的 task part 状态变化走正常 part 事件通路（父 sessionID），UI 自然可见。
- **`APIConstants.sseEndpoint` 死常量清理**：顺手可做可不做（ConnectionTests 断言它），不阻塞。
- **服务端改动**：零。

### 5.8 边界与一致性

- **幂等/乱序**：upsert 按 ID；壳行被后续事件覆盖；end 帧收敛 delta 拼接。
- **optimistic user row**：服务端回推的 user `message.updated` 覆盖 info + untrack；**parts 层面接受 transient 显示**——服务端可能改写 user 文本（如 analyze-mode 前缀，现有单测 `loadMessagesReplacesOptimisticRowWhenServerConfirmsSameMessageID` 断言服务端文本胜出），in-place 路径下该改写在对账（idle）时才收敛。turn 期间显示原文是 cosmetic 取舍，可接受；若服务端为 user message 发 part 事件，5.2-3 的 temp-part 去重保证不重复显示。
- **revert**：revert 后客户端已强制 `loadMessages`（现状路径保留）；`message.removed`/`part.removed` 事件（revert 清理发）现在直接删本地行/part，比现状（等 REST）更及时。
- **session 切换**：内联 `== currentSessionID` guard 丢弃过期事件；切换触发 bootstrap 对账（现状）。
- **大 session**：upsert 只作用已加载窗口（limit 20 页），不扩内存。
- **绕过事件总线的状态修改**：不存在（server 所有修改走 bus）。
- **compaction**：不删改历史 part（`tail_start_id` 机制，session_status_bar 已验证事实 6），无特殊处理。
- **渲染粒度**：`MessageWithParts` 是 struct 数组、非 lazy 列表，in-place 改 `messages[i].parts[j]` 的 Observation 触发面与整体替换相同（ChatTabView body 级）。**本 feature 的收益是消除 per-event REST 与事件队列阻塞，不是渲染粒度**；per-part observable 是后续优化（数据模型是 struct 数组，做不了增量 observable，需换引用类型，不在此范围）。

## 6. 与 session_status_bar feature 的关系

* **补充说明**：在命名上要注意区分，它的"数据通路"指的是 session 级别的一些计数器（比如 rounds, tool calls, tokens）的来源；这个 feature 的"数据通路"指的是聊天界面消息和 message/part 的状态实时反映出来。

- **它已做**（2026-09-29 观察，主 checkout 未提交）：message.updated 里加了 `statsStore.observeUserMessage`（user role），message.part.updated 里加了 `statsStore.observeToolPart`，都在 await REST 前。
- **兼容承诺**：本 feature 仅移除 per-event 的 `await loadMessages/loadSessionDiff`，`statsStore.observe*` 调用点原样保留（它们都是同步本地 bookkeeping，不依赖 REST）。其对账依赖的「loadMessages 完成后窗口对账」在 idle/bootstrap 对账时仍会发生（频率下降，计数主体是 SSE 增量，不受影响）。
- live 证据共享：本文档引用的事件时间线来自它的已验证事实（探针 `tmp/status_bar_probe.py`）。
- 实现顺序：相互独立。谁先 merge，后者基于其后的 master；branch 状态以实施时实际为准。

## 7. 实现顺序（按步验证）

1. **MessageStore 数据层**：新增 `upsertPart`/`upsertMessageInfo`/`removePart`/`removeMessageRow` + 壳行/optimistic 去重逻辑（5.2/5.3）。纯本地逻辑，不接 SSE。
   - 验证：新增 MessageStore 单测（upsert 替换/插入/壳行/temp 去重/门禁 `.needsReconcile`）。
2. **SSE handler 改造**（`AppState+SSE.swift`）：按 5.1 表逐事件改造；`server.heartbeat` 显式 case；idle 触发对账。
   - 验证：SSE 单测（见测试规格），跑全量 `SessionFlowTests` 回归。
3. **看门狗**：`sseLastFrameAt` + timer + `checkSSEWatchdog`（5.6）。
   - 验证：看门狗单测（时间注入）。
4. **live 验收**（scratch server，见下）+ UI automation 截图。

## 8. 测试规格

**现有测试改写**（`SessionFlowTests.swift`，harness 不变：`makeSSEEvent` + `applySSEEventForTesting` + `MockAPIClient` 计数）：

| 现有用例（行号） | 现断言 | 改后 |
|---|---|---|
| `messagePartUpdatedReloadsCurrentSession`（:1522） | `messagesCallCount == 1` | `== 0` + 本地 part 状态断言（upsert 生效） |
| `messagePartUpdatedWithDeltaStillReloads`（:1541） | `== 1` | 门禁场景化：完整 part → 0 REST + upsert；shim 瘦 part + 顶层 delta → 保持 1 REST（回归断言） |
| `messageUpdatedForCurrentSessionReloads`（:1407） | `== 1` | `== 0` + info upsert 断言 |
| `sessionStatusIdleRecordsIdleForCurrentSession`（:1574） | `messagesCallCount == 0` | `== 1`（idle 对账，新行为） |

* **新增用例**（同文件同 harness）：

- part upsert 三态：tool `pending→running→completed` 三帧各自改变本地 state，全程 0 REST。
- delta 流式：`part.updated`(空 text start) → 3×`message.part.delta` → `part.updated`(完整 end)：中间 `part.text` 逐段增长，end 帧后等于完整文本。
- 壳行：assistant 专属 part（tool）先到未知 messageID → 壳行建立；text part 先到 → 不建。
- 乱序：part 先于 `message.updated` → 壳行被 info 补全。
- 幂等：同帧重放不重复。
- removed：`message.part.removed`（`{sessionID,messageID,partID}`）删 part；`message.removed` 删行。
- optimistic：pending 行的服务端 part（非 temp id）到达 → temp parts 清除、server part 显示；user `message.updated` → untrack。
- 非当前 session 事件全部忽略（0 REST、0 状态变化）。
- 门禁：shim 形状 payload → 回退 REST（`messagesCallCount == 1`）。
- 看门狗：`sseLastFrameAt` 置 30s 前 + `checkSSEWatchdog()` → 1 次对账；fresh 时间戳 → no-op。

## 9. Live 验收

- 环境：临时端口 scratch server（**不复用 4096/4097 live server**）；prompt 用 `bash sleep 6` 类长 tool。
- 验收点：
  1. 发送后 `session.status=busy` 帧到达 → composer 行出现 + 计时（亚秒级，事件驱动）。
  2. tool running 帧到达 → tile 状态即时更新、activity text `Running commands - <cmd>`、时长走秒（事件驱动，不依赖 REST）。注意当前 UI 形态的边界（见 UI 层缺口）：看到的是折叠行状态更新 + composer 行文案，行内显式 running 指示由 P2 tile feature 补齐，验收时不以此为失败项。
  3. 掐断 SSE（或代理模拟静默）→ ≤25s 内看门狗触发一次对账，状态恢复。
  4. REST 计数对照：turn 期间网络面板/日志中 message 拉取次数 = 1（idle 对账），对照现状 42 对（N=3,M=2 公式）。
- UI 验收：现有 iOS UI automation（截图核对 composer 行与 tool tile 状态）。

## 10. 风险与回滚

- **状态漂移**（事件解析失败/丢帧导致本地与服务端不一致）：三道对账（bootstrap/idle/看门狗）+ 门禁回退兜底。调试期加 diff 日志：DEBUG 开关（范式 = `isCarModeEnabled` 三件套，`AppState.swift:182/243/396`，`#if DEBUG` 包一层），对账时比对本地 vs REST 并 `Logger.debug`。
- **iOS 端点假设**：设计依赖 `/global/event` 的 heartbeat 与 FIFO（已源码验证）；shim host 的 heartbeat 未验证，退化行为无回归（5.6）。
- **渲染性能**：in-place 更新不改变触发面（5.8），无新增风险；流式 delta 频率高（每 token 一帧），`messages` 数组每 delta 变一次 → ChatTabView body 重算频率从 0（现状 iOS 不渲染 delta）变为 token 级。**需 live 观察滚动/输入是否卡顿**；若卡，缓解 = delta 追加加 50–100ms 合帧（`lastDeltaAt` 节流，丢失的中间态由 end 帧收敛）——实现时预留该开关位，默认不开。
- **回滚**：无数据迁移、无协议/服务端改动。revert commit 即回现状。

## 11. 工作量估计

| 项 | 估计 |
|---|---|
| MessageStore upsert 层 + 单测 | 0.5 天 |
| SSE handler 改造 + 测试改写/新增 | 1 天 |
| 看门狗 + 单测 | 0.5 天 |
| live 验收 + UI automation | 0.5 天 |

## 12. 遗留开放项（不阻塞开工）

1. **Turn 级的 `final completion` 消息帧**（含 `time.completed`）是否存在——live 待测；不存在也不影响设计（idle 对账会收敛）。
2. **dsh shim host 是否发 `server.heartbeat`**——未验证；退化行为已设计（5.6）。
3. **服务端是否对 user message 的 parts 发 `part.updated` 事件**——未验证；两种情况都被 5.2-3 / 5.8 覆盖。
4. **delta 节流开关是否需要**——live 验收后定（见「10. 风险与回滚」）。
