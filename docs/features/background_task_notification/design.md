# Background Subagent 任务通知渲染设计草案

## 结论

后台 subagent 完成时，服务端向父会话注入一条 **synthetic user message**，内容是 `<task id=... state="completed">` XML 信封，内含 summary 与结果正文。iOS 客户端目前没有解码 TextPart 的 `synthetic` 字段，这类消息被渲染成蓝色用户气泡里的原始 XML，是最刺眼的渲染破绽之一。

这个 UI element 应该是一张 **TaskNotificationCard**——消息流里的"subagent 任务回执"卡片：首屏是状态图标 + 状态标签 + 任务标题，结果正文在卡内用 markdown 渲染，展开后可一键打开 subagent 会话审计全过程。它不是用户气泡（系统注入，不是用户说的话），也不是 tool card（tool card 表示"一次调用"，这张卡表示"一个异步工作交付了结果"）。

识别用双门：part 带 `synthetic: true` **且**文本可解析为 `<task>` 信封 → 渲染卡片；解析失败安全回退现状。

范围严格限定 task 回执。服务端其他 synthetic 注入点（plan mode 指令、compaction 续跑、MCP resource 等）明确 out of scope，不触碰用户气泡的渲染逻辑；它们列在附录，仅作观察记录。

## 成功标准

1. 后台任务完成后，会话里出现状态清晰的回执卡片（绿色完成 / 红色失败），首屏看到任务名与状态，不泄漏任何原始 XML。
2. tap 卡片展开，可读完整 subagent 结果 markdown（含 workspace 链接解析与图片）；超长结果有既有 12k 预览保护。
3. 展开后 tap 按钮可打开 subagent 会话，复用既有 selectSession 路径。
4. 解析失败或旧版本服务端（payload 无 `synthetic` 字段）时，行为安全回退到现状：不吞内容、不崩。

## 数据通路（证据）

### 服务端生成方式

`opencode-official/packages/opencode/src/tool/task.ts`：

- `renderOutput()` 生成固定 XML 信封：
  ```
  <task id="{childSessionID}" state="completed|error|running">
  <summary>Background task completed: {description}</summary>   # error 时为 failed
  <task_result> 或 <task_error>
  {subagent 最后一条 text part 的 markdown}
  </task_result>
  </task>
  ```
- 后台任务完成/失败时，`injectBackgroundResult` 通过 `ops.prompt` 向**父会话**注入一条 user 消息，text part 带 `synthetic: true`。
- 启动后台任务时，父消息里的 `task` tool part 携带 `state.metadata = { parentSessionId, sessionId, model, background: true, jobId }`，output 是 `state="running"` 的信封（本设计不处理，见附录）。
- `TextPart.synthetic` 在 V1 API schema 中是 optional boolean（`packages/schema/src/v1/session.ts:108`）。

live 验证（2026-09-27，本机 4096 server，`GET /session/:id/message`）：

- 回执是 **user-role** 消息，单个 text part
- part payload 实际带 `synthetic: true`
- 正文为完整 `<task>` 信封；该 part 无 `time` 字段

### 客户端现状

- `Models/Message.swift` 的 `Part` 结构没有解码 `synthetic`。
- `MessageRowView.userMessageView` 把所有 user 消息的 text part 渲染进蓝色用户气泡（`DesignColors.Brand.primary` 填充 + 左侧 4pt 竖条）；XML 文本经 `hasMarkdownSyntax` 判定后走 MarkdownUI，按原始 HTML 样文本展示。
- `task` tool part 落在 "N tool calls" 折叠行里，output 是 "Background task started..." 样板文本（本设计不处理）。

## 变更清单

### 1. 模型层：解码 `synthetic`

`Part` 增加：

```swift
let synthetic: Bool?
```

`decodeIfPresent` 语义，缺省视为 `false`；`Part.isSyntheticText` 便利属性（`type == "text" && synthetic == true`）。服务端不带该字段时行为与现状完全一致。

### 2. 解析层：`TaskNotificationParser`

纯函数，与 `ToolCardClassifier` 同风格（可单测、无 View 依赖）：

```swift
struct TaskNotification {
    let sessionID: String        // <task id>
    let state: TaskState         // completed | error | running
    let summary: String?
    let resultText: String       // <task_result>/<task_error> 内文
    var isFailed: Bool { state == .error }
}

enum TaskNotificationParser {
    static func parse(_ text: String) -> TaskNotification?
}
```

解析规则：定位最外层 `<task ...>` 开标签（开头允许前导空白）与 `</task>` 收尾，`id` / `state` 从开标签属性取；正文取 `<task_result>` 或 `<task_error>` 区间内文。全程用 range 定位而非全局 regex，保证结果正文里出现嵌套尖括号（如 subagent 自己输出的 XML 片段）时不误切。任一步缺失返回 `nil`。

### 3. 渲染层：`TaskNotificationCardView`

放在 `Views/Chat/`。`MessageRowView` 对 user 消息的处理改为：

- 非 synthetic text part → 照常进用户气泡（渲染逻辑零改动）；
- synthetic text part 且 `TaskNotificationParser` 解析成功 → `TaskNotificationCardView`；
- 其余情况（含 synthetic 但解析失败、非 synthetic）→ 现状渲染，安全回退。

`copyableText(for:)` 同步调整：解析成功的回执消息复制结果正文而非 XML；用户气泡的复制内容不受影响（本设计不改用户气泡逻辑）。

## UI 规范（TaskNotificationCard）

### 视觉

- 卡片底面：`DesignColors.Neutral.text.opacity(DesignColors.surfaceFill(for:))`，与 ToolPartView 一致；圆角 `DesignCorners.medium`，内边距 `DesignSpacing.cardPadding`。
- 头部行（首屏信息，不可折叠）：
  - 状态图标：completed → `checkmark.seal.fill` + `DesignColors.Semantic.success`；error → `xmark.seal.fill` + `DesignColors.Semantic.error`。
  - 状态标签：L10n 本地化（`taskNotificationCompleted` / `taskNotificationFailed`），从 `state` 生成，**不**把 summary 里的英文前缀 "Background task completed:" 原样展示；前缀剥离后剩下的 description 作任务标题。
  - 任务标题：一行截断。
  - 右侧：展开 chevron（DisclosureGroup 自带，tint brand primary）。
- 展开内容：`resultText` 走既有 `markdownText` 路径（workspace 链接解析、图片解析、`textSelection(.enabled)`），超长由 `LargeMessagePreview`（>12k 截断 + 提示）保护；空结果显示占位 caption "No output"。
- 默认展开状态：结果 ≤ 500 字符时展开，否则折叠——主 agent 随后的消息通常携带消化后的结论，卡片正文是参考材料。实现时以常量固定，可调。
- `accessibilityIdentifier("task-notification-card")`；跳转按钮 `accessibilityIdentifier("task-notification-open-session")`；UI 测试按这两个锚定。

### 交互

- **主动作 = 展开/折叠**：tap 整卡（头部 + 内容区）切换展开状态，与 ToolPartView / ThinkingCard 一致。不把"tap 跳转"作主动作：读结果是高频意图且展开可逆、零成本；跳转切换当前会话上下文，是低频审计动作。高频动作绑主手势。
- **跳转 = 展开区内的带标签按钮**：展开内容底部一个按钮，文案 "打开子代理会话"（L10n `taskNotificationOpenSession`），brand primary 色、`DesignTypography.micro`。按钮命中区域优先于卡片 toggle 手势（SwiftUI Button 在可点容器内天然优先，与 ToolPartView label 内文件打开按钮同机制）。
- **折叠态不设跳转入口**：跳转需先展开再 tap 按钮，两次 tap。低频动作可接受；头部保持安静（不放无标签 icon 按钮），维持首屏信息密度。
- **跳转行为**：`selectSession(subagentSessionID)` + 必要时切换 project directory（session_finder "Continue in This Session" 同款路径）；目标会话已删除时走既有错误路径（`state.sendError`），卡片本身不受影响。
- 消息行操作菜单：synthetic 回执消息不显示 Edit-from-here（不是用户轮次），Fork 保留。

## 边界情况

- **流式截断**：SSE 中途 part 是不完整 XML（无 `</task>`）→ parser 返回 nil → 暂按现状渲染；part 更新为完整后重渲染为卡片。part id 稳定，替换渲染无状态残留。
- **旧服务端**：payload 无 `synthetic` → 解码为 nil → 非 synthetic → 行为与现状一致（用户气泡 + 原始文本），不静默吞内容。
- **用户手动粘贴信封样文本**：无 `synthetic` 标记 → 双门不成立 → 按用户消息正常渲染，不被劫持成卡片。
- **多个后台任务**：每个通知是独立消息 → 独立卡片，天然支持。
- **结果内含嵌套 XML**：range 定位最外层信封（见解析规则），单测覆盖。
- **error 状态**：`<task_error>` 标签 + `state="error"`，红色图标，正文同样 markdown 渲染。
- **summary 缺失**：标题回退显示 task 会话 ID 短形式。

## 实现范围

单一阶段：

1. `Part.synthetic` 解码（`decodeIfPresent`）。
2. `TaskNotificationParser` + 单测。
3. `TaskNotificationCardView`：completed/error 两态、展开/折叠、默认展开阈值、markdown 渲染、跳转按钮。
4. `MessageRowView` 分流 + `copyableText` 修正。
5. L10n keys：`taskNotificationCompleted` / `taskNotificationFailed` / `taskNotificationOpenSession` / `taskNotificationNoOutput`。

明确不做（本阶段）：`task` tool part 的 running 指示与 metadata 解码、用户气泡内其他 synthetic 内容的隐藏或样式化处理。

## 测试计划

- `TaskNotificationParserTests`（unit）：completed / error / running / 无 summary / 截断（无收尾标签）/ 非 task 文本 → nil / 结果内嵌套尖括号 / 空结果 / 前后空白。
- `MessageRowView` 渲染单测：synthetic + 信封消息 → 卡片（a11y id 断言）；同文本无 synthetic → 用户气泡（回退路径）；`copyableText` 对回执消息返回结果正文。
- UI（Tier 4）：tap 卡片展开显示 markdown；展开后 tap 跳转按钮成功切换至 subagent 会话（以子会话 title "…(@general subagent)" 或消息内容断言）。
- 构建与测试按 AGENTS.md 约定串行执行（build → test）。

## 附录：观察到的其他 synthetic 注入点（out of scope）

`packages/opencode/src` 中其余 `synthetic: true` 生成点。本设计不处理；若日后成为渲染缺陷，用同一模式处理（已解码的 `synthetic` 字段 + type-specific 渲染），不另行发明机制。

| 位置 | 内容 | 形态 |
|---|---|---|
| `session/reminders.ts:34/45/64` | plan mode 指令（PROMPT_PLAN / BUILD_SWITCH / PLAN_MODE） | 追加到用户最后一条消息 |
| `session/compaction.ts:541` | "Continue if you have next steps..."（带 `metadata.compaction_continue`） | 独立 synthetic user 消息 |
| `tool/plan.ts:68` | "The plan at X has been approved, execute the plan" | 独立 synthetic user 消息 |
| `session/prompt.ts:447` | "Summarize the task tool output above and continue" | 独立 synthetic user 消息 |
| `session/prompt.ts:485` | "The following tool was executed by the user" + tool part | 样板文本 + tool part |
| `session/prompt.ts:711+` | "Reading MCP resource: X (uri)" / resource 正文 / omitted 提示 | 追加到用户消息 |
