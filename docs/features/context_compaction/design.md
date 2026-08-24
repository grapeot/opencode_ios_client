# OpenCode iOS Manual Context Compaction Design

Status: proposal only, no implementation

## Bottom Line

`/compact` 是一个纯客户端指令，而非发送给模型的 Prompt。Web 端在输入框（composer）中识别到该指令后，会调用会话压缩相关的 API，而绝不会将指令字面文本作为普通用户消息提交。

iOS 客户端目前尚未建立对等的指令解析层。`sendMessage` 会将输入框中的所有文本无差别转发至 `/session/:id/prompt_async`，因此输入 `/compact` 会直接将该字符串发送给模型。这是当前客户端实现的预期行为，并非服务端缺陷。

建议的产品交互形态为统一抽象为一个会话级 Action，并提供两个触发入口：

1. 在 Session 的操作菜单（`...`）和上下文使用量（context-usage）UI 中提供直观的 `Compact Context` 操作项。
2. 在输入框中为键盘用户提供 `/compact` 斜杠指令（slash-command）快捷方式。

两个入口底层均调用同一个强类型的客户端 Action，且均不生成普通的用户文本消息。

## Current Mechanism

### Web Client

Web 端注册了一个内置指令，其定义包含：

- command ID：`session.compact`
- slash trigger：`compact`
- action：调用 `client.session.summarize(...)`

当用户在斜杠命令选择器中选中该内置指令时，输入框会清空指令文本并调用指令注册表分发。自定义斜杠指令则走另一套逻辑，保持为可编辑的 Prompt 文本。

相关源码参考：

- `opencode-official/packages/app/src/pages/session/use-session-commands.tsx`
- `opencode-official/packages/app/src/components/prompt-input.tsx`

这解释了之前观察到的 Tab 键交互行为：Tab 键用于选中本地自动补全候选，选中后触发 `session.compact` 的分发，而非模型端对 `/compact` 的语义理解。

### Current iOS Client

iOS 客户端目前的执行路径为：

```text
composer text
  -> AppState.sendMessage(...)
  -> APIClient.promptAsync(...)
  -> POST /session/:id/prompt_async
  -> normal user message
```

目前缺少内置指令注册表及发送前的拦截层。虽然 `Part.type` 可以将未知的 Part 类型解码为字符串，但 iOS 端尚未针对 Compaction 设计专用的状态机流转与完成态 UI 呈现。

相关源码参考：

- `OpenCodeClient/OpenCodeClient/AppState+Messages.swift`
- `OpenCodeClient/OpenCodeClient/Services/APIClient.swift`
- `OpenCodeClient/OpenCodeClient/Models/Message.swift`

## Backend Contract

OpenCode 服务端目前存在两代 API 规范，在设计时不应混为一谈。

### Legacy API Used By The Current Web Client

```http
POST /session/:sessionID/summarize
Content-Type: application/json

{
  "providerID": "openai",
  "modelID": "gpt-5.6-sol",
  "auto": false
}
```

接口处理逻辑：

1. 清理当前处于激活态的 Revert 状态。
2. 从最近的历史消息中推导当前处于活跃态的 Agent。
3. 构造并追加一条包含 `compaction` part 的合成用户消息（synthetic user message）。
4. 使用当前选中的模型执行正常的会话推理循环。
5. 针对较早的历史会话生成结构化摘要，若此前已有摘要则可选择性合并。
6. 后续的会话轮次将基于该压缩后的表示继续推进。

该操作会真实消耗一次模型调用额度，而非简单的本地字符串截断算法。

### V2 API Direction

V2 版本的公开设计规范定义如下：

```http
POST /api/session/:sessionID/compact
Content-Type: application/json

{}
```

当前的 V2 文档将其描述为异步准入（asynchronous admission）机制：服务端接收压缩请求后，在安全的会话轮次边界执行压缩，并通过 Session 事件流推送执行进度与完成通知。可选的 Request ID 支持幂等重试。

本地 7 月 14 日的检出代码处于过渡期：该路由已存在，但其核心实现仍直接返回 `OperationUnavailableError`。因此 iOS 客户端不应仅因路由声明存在就直接切换至 V2，而应沿用当前已部署服务端的 Legacy 协议，待后续完成能力探测（capability check）或协同升级服务端后再行迁移。

### What Compaction Changes

Compaction 改变的是模型可见的会话历史表示，并不会从底层存储中物理删除原始的持久化消息记录。

概念示意如下：

```text
Durable session history
  = original messages remain available to clients and export

Next model context
  = system context
  + generated checkpoint/summary of older history
  + retained recent turns
  + messages created after compaction
```

该摘要过程是存在信息损耗的（lossy）。尽管原始消息依然完整保留在会话数据库中，但旧会话中的精确细节可能会从后续模型的可见上下文（context）中消失。

自动压缩（Automatic compaction）是针对相同底层机制的另一套独立触发策略。现有 Legacy 配置使用 `compaction.auto`、`compaction.prune` 和 `compaction.reserved`；V2 逐步演进为基于模型感知的裕量（headroom）与保留轮数（retained-tail）配置。手动压缩应支持独立触发，不受自动压缩开关状态的影响。

## Recommended UX

### Primary Entry Point

在 Session 的 `...` 菜单中新增 `Compact Context` 操作项，位置与 `Interrupt Agent`、重命名等会话级操作并列。

在操作行或首次引导 Sheet 中展示简明说明：

> Summarize older conversation to free context space. Full history remains visible, but the agent may lose exact older details.

相比强制用户记住终端式指令，这种方式更具可发现性。

### Context Usage Entry Point

点击现有的 Context 环形进度条可唤起轻量详情面板：

```text
Context used                 78%
Older turns can be summarized to free space.

[Compact Context]
```

当使用量超过产品设定的阈值时，该操作按钮可在视觉上进行强调，但同样允许用户在较低水位下手动触发。单纯打开该详情面板不应自动触发压缩。

### Slash Command Entry Point

当输入框以 `/` 开头时，展示原生指令选择器，包含：

```text
/compact       Compact context
/summarize     Alias for /compact
```

选择任一指令后，可直接立即触发该强类型 Action，或在输入框中替换为待发送的 Action Chip 并由用户点击 Send 发送。直接立即触发与 Web 端行为一致，整体交互设计更轻量。

安全解析规则：

- 仅拦截从选择器中明确选中的内置指令，或用户手动输入、去除首尾空白后完全匹配且未附带附件的 `/compact` 与 `/summarize`。
- 绝不将 `/compact please`、包含在句子中间的 `/compact` 或携带附件的 `/compact` 误识别为压缩操作。
- 若输入文本以保留的内置指令开头但语法不合法，在本地展示语法错误提示，严禁将其静默发送给模型。
- 唤起斜杠选择器之前输入框中已有的草稿内容必须予以妥善保留。

### Progress And Completion

UI 状态应严格限定在 Session 作用域内：

```text
idle -> requesting -> compacting -> completed
                          |
                          -> failed
```

推荐的视觉呈现策略：

- 请求中与压缩中（requesting/compacting）：Context 环形指示器展示平缓的加载动画，菜单中的操作项文案变为 `Compacting Context...`。
- 压缩完成（completed）：在时间线中插入或渐显一条克制的分割标记 `Context compacted`，随后刷新 Context 使用量数据。
- 压缩失败（failed）：展示可重试的错误提示，且不修改或丢弃输入框中的草稿。
- 除非后端明确支持针对 Compaction 的取消协议，否则不展示取消按钮。

针对 Legacy `summarize`，HTTP 响应成功可指示执行完成，随后通过 SSE 消息与 Part 更新刷新会话历史；针对 V2，HTTP 接收仅代表成功准入，客户端必须等待 Compaction 事件通知或会话进入稳定态。

### Busy Session Behavior

在 Legacy MVP 阶段，当会话处于 Busy 状态时禁用手动压缩。这可以避免与现有的 Prompt 循环发生并发竞态，为用户提供可预期的交互表现。

待 V2 安全边界准入机制部署后，允许在 Busy 状态下触发该操作，并显示文案 `Compact after current step`。由服务端负责对压缩请求与 Prompt 进行排队调度并合并重复请求，无需 iOS 客户端承担该调度职责。

### Confirmation Policy

无需在每次触发时均弹出确认对话框。虽然该操作对模型后续的注意力存在信息损耗，但不会物理删除持久化历史，且官方客户端已将其作为直接指令开放。

提供一次性的教学引导 Sheet 或清晰的操作副标题即已足够。频繁弹出模态确认会严重加重视图交互的摩擦。

## Client Architecture

将指令解析层与 API 传输层严格解耦：

```text
Composer / Session Menu / Context Sheet
                 |
                 v
       AppState.compactCurrentSession()
                 |
                 v
       SessionCompactionClient
          |              |
          v              v
 legacy summarize     V2 compact
```

`AppState.compactCurrentSession()` 负责管理可用性校验、会话级进度状态、错误处理、完成后的状态刷新以及防重复点击抑制；各 UI 入口仅负责触发该方法。

传输适配器层应显式区分 API 代际。应避免在发生任何错误时均盲目进行“先 V2 后 Legacy”的 Fallback 重试，因为超时可能导致首个请求已被服务端受理，进而引发重复的模型调用。具体协议代际的选择应基于服务端返回的版本/能力元数据，或通过 Host Profile 中的固定配置项决定。

## Delivery Slices

### Slice 1: Current Server MVP

- 接入 Legacy `summarize` API 请求。
- 在 AppState 中新增单一的 Compaction Action 与对应状态。
- 在 Session 菜单中新增 `Compact Context` 操作项。
- 在本地精确拦截 `/compact` 与 `/summarize` 指令。
- 在会话处于 Busy 态或尚无用户消息时置灰禁用。
- 成功后自动刷新消息列表与 Context 使用量。
- 补充单元测试，验证指令文本绝不会透传至 `prompt_async`。

该阶段无需改动服务端，属于中小规模的 iOS 功能改造，主要风险在于状态流转与交互细节的正确性，而非后端复杂度。

### Slice 2: Discoverability

- 新增 Context 环形指示器的详情弹出 Sheet。
- 支持斜杠指令的自动补全选择器，替代单纯的发送时精确匹配拦截。
- 新增时间线分割指示器与对应的本地化文案。

### Slice 3: V2 Migration

- 基于显式的能力契约协商自动选择 V2 协议。
- 提交具备幂等保障的 Compact 请求。
- 监听并流转 Admitted、Running、Completed 与 Failed 事件。
- 支持在 Busy 轮次后排队等待执行。
- 仅当所有受支持的主机均具备 V2 能力后，再正式移除 Legacy 传输层。

## Acceptance Criteria

1. 选中 `/compact` 绝不生成普通用户文本消息。
2. 菜单入口、Context 详情面板与斜杠指令均调用同一套 AppState Action。
3. 请求失败时保持会话状态与输入框草稿完好无损。
4. 重复点击无法触发重复的 Compaction 模型调用。
5. 压缩完成后自动刷新消息流与 Context 使用率。
6. 压缩完成后，此前的持久化历史消息依然正常可见。
7. UI 文案明确提示旧会话细节存在摘要损耗。
8. Legacy 与 V2 的完成语义具备独立测试覆盖。
9. 在遇到不确定的超时错误后，客户端不会盲目通过第二代 API 进行二次重试。

## Recommendation

在获得实施授权后，优先推进 Slice 1 的交付。它能在不修改服务端的前提下，彻底修复 iOS 端令人意外的指令透传行为，并提供高可发现性的会话级操作。应将 V2 接口视为后续的协议演进，而非该功能落地的先决条件。
