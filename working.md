# Working Notes - OpenCode iOS Client

## Recent Changes

### Image Preview in Tool Calls & Files Tab (2026-03-12)

当 AI tool call（read/patch 等）操作图像文件时，客户端把 base64/二进制内容当纯文本渲染，用户看到一大段不可读字符。期望行为是识别图像文件并展示可交互的图像预览（缩放、平移、分享）。

**问题根因：**

两个维度同时存在缺陷。

第一，FileContentView 的 `loadContent()` 判断优先级有误。代码先检查 `fc.text`（server 返回 `type: "text"` 时为 non-nil），再检查 `type == "binary"` + `isImage`。OpenCode server 对图像文件大概率返回 `type: "text"` 而非 `"binary"`，导致 base64 内容走到文本渲染路径，显示乱码。

第二，ToolPartView 的内联 output 展示完全不做文件类型判断。`part.toolOutput` 无论内容是什么，一律以 monospaced caption 文本渲染。当 `read` tool 读取图像文件，output 是 base64 字符串，直接渲染成一大段无意义文字。

**设计方案：**

1. 提取共享图像检测工具：将 `imageExtensions` 和 `isImageFile(path:)` 从 FileContentView 提取为模块级共享工具（`ImageFileDetector` 或简单的 static 函数），供 FileContentView 和 ToolPartView 共用。

2. 修复 FileContentView.loadContent() 的判断优先级：当 `isImage == true` 时，无论 server 返回 `type` 是 `"text"` 还是 `"binary"`，都优先尝试将 `fc.content` 做 base64 解码。只有解码失败时才 fallback 到错误提示。

3. 增强 ToolPartView 的 output 渲染：在 output 区域增加分支判断。当 `part` 关联的文件路径（来自 `state.pathFromInput`、`metadata.path`、或 `filePathsForNavigation`）指向图像文件时：
   - 尝试将 `part.toolOutput` 做 base64 解码为 UIImage
   - 解码成功：渲染为内联缩略图（高度上限约 200pt，aspectRatio fit），点击展开全屏 sheet
   - 解码失败：渲染占位卡片（图标 + "Image file" 文案 + Open 按钮），引导用户点击打开完整预览
   - 两种情况下都保留已有的 "Open File" 导航按钮

4. 全屏图像 Sheet：点击内联缩略图后 present 一个 `.sheet`，内部复用已有的 `ImageView`（zoom/pan/drag 手势），toolbar 加 ShareLink 和 Reset 按钮。

**改动文件清单：**

- `Views/FileContentView.swift` — 修复 loadContent() 优先级；将 imageExtensions 提取为模块级 static
- `Views/Chat/ToolPartView.swift` — 增加图像检测 + 内联图像预览 + 全屏 sheet
- `OpenCodeClientTests/OpenCodeClientTests.swift` — 新增图像检测和 base64 解码的单元测试

**验证：**

- `xcodebuild -scheme "OpenCodeClient" -project "OpenCodeClient/OpenCodeClient.xcodeproj" -destination 'generic/platform=iOS Simulator' build`
- `xcodebuild test -scheme "OpenCodeClient" -project "OpenCodeClient/OpenCodeClient.xcodeproj" -destination 'platform=iOS Simulator,id=302F88CA-C2D3-4DC0-8E12-B3ED82D5A3C8' -only-testing:OpenCodeClientTests`

**Follow-up polish:**

首版实现跑通后，实际手测又发现三个体验问题。

第一，`ImageView` 初始状态仍然等价于原始像素 100%，不是用户预期的 fit-to-screen。第二，右上角 reset/fullscreen 风格按钮语义不清，而且点击后对当前交互模型帮助不大。第三，share sheet 里只有 `Save to Files`，没有 `Save to Photos`，导致 PNG 等图像文件不能直接进入系统相册。

这轮跟进做了两类修正。

1. 重写 `ImageView` 的缩放基线：`scale == 1.0` 现在表示 fit-to-screen，而不是 native size。新增双击切换行为：在 fit 状态下双击放大到 native scale（小图至少 2x），放大后双击回到 fit；pinch 和 drag 行为保留；移除了内部 reset toolbar 按钮。

2. 在 `Info.plist` 增加 `NSPhotoLibraryAddUsageDescription`。这是 iOS 显示 `Save to Photos` action 的前提，没有这个 privacy key，share sheet 会直接隐藏保存到相册入口。

**Follow-up 改动文件：**

- `OpenCodeClient/OpenCodeClient/Views/FileContentView.swift` — 重写 `ImageView` 的 fit/zoom/double-tap 交互模型，移除内部 reset 按钮
- `OpenCodeClient/Info.plist` — 新增 `NSPhotoLibraryAddUsageDescription`，恢复 `Save to Photos`

**Follow-up 验证：**

- `xcodebuild -scheme "OpenCodeClient" -project "OpenCodeClient.xcodeproj" -destination 'generic/platform=iOS Simulator' build`
- `xcodebuild test -scheme "OpenCodeClient" -project "OpenCodeClient.xcodeproj" -destination 'platform=iOS Simulator,id=302F88CA-C2D3-4DC0-8E12-B3ED82D5A3C8' -only-testing:OpenCodeClientTests`


### 语音转写句首空格修复（2026-03-11）

排查后确认，realtime 语音转写里“句首多一个空格”主要不是服务端问题，而是 iOS 客户端在把 partial/final transcript 填回聊天输入框时，无论当前输入框是否为空，都会强行在 transcript 前面补一个空格。

**本次修改：**

- `OpenCodeClient/OpenCodeClient/Views/Chat/ChatTabView.swift` — 新增 `mergedSpeechInput(prefix:transcript:)`，统一处理语音转写结果和现有输入框内容的拼接；当 `prefix` 为空时不再补分隔空格，当 `prefix` 非空时仍保留单个空格分隔
- `OpenCodeClient/OpenCodeClient/Views/Chat/ChatTabView.swift` — partial transcript 和 final transcript 两条路径都改为走同一个 helper，避免行为漂移
- `OpenCodeClient/OpenCodeClientTests/OpenCodeClientTests.swift` — 新增两个测试：一个验证空前缀时不会产生句首空格，一个验证已有草稿时仍会正确插入单个分隔空格

**验证：**

- `xcodebuild test -scheme "OpenCodeClient" -project "OpenCodeClient/OpenCodeClient.xcodeproj" -destination 'platform=iOS Simulator,id=302F88CA-C2D3-4DC0-8E12-B3ED82D5A3C8' -only-testing:OpenCodeClientTests`
- `xcodebuild -scheme "OpenCodeClient" -project "OpenCodeClient/OpenCodeClient.xcodeproj" -destination 'generic/platform=iOS Simulator' build`

### Streaming Auto-Scroll Overshoot Fix (2026-03-11)

Fixed a chat auto-scroll bug where the view could scroll past the real bottom into blank space while an agent was streaming thinking text or tool output. Static inspection plus SwiftUI references pointed to a fragile combination: `ScrollViewReader.scrollTo("bottom")` was firing on every streaming update while the chat content lived inside a `LazyVStack`, so SwiftUI could scroll against an unstable content height and land below the rendered content.

**What changed:**

- `Views/Chat/ChatTabView.swift` — Replaced the chat transcript container from `LazyVStack` to `VStack` so row heights are laid out eagerly during streaming updates
- `Views/Chat/ChatTabView.swift` — Replaced immediate `proxy.scrollTo("bottom")` calls with a cancellable debounced scroll task (`50ms`) to avoid stacking multiple bottom-scroll requests while the layout is still settling
- `Views/Chat/ChatTabView.swift` — Cancel the pending scroll task when the chat view disappears to avoid stale scroll work after navigation

**Validation:**

- `xcodebuild -scheme "OpenCodeClient" -project "OpenCodeClient.xcodeproj" -destination 'generic/platform=iOS Simulator' build`
- `xcodebuild test -scheme "OpenCodeClient" -project "OpenCodeClient.xcodeproj" -destination 'platform=iOS Simulator,id=302F88CA-C2D3-4DC0-8E12-B3ED82D5A3C8' -only-testing:OpenCodeClientTests`

### Question Feature (2026-03-07)

Implemented the Question feature so the iOS client can handle AI-initiated questions from the OpenCode server. Previously, when the server's AI asked questions via the MCP `question` tool, the iOS client had no handler and the session would stall. Now the client displays question cards with selectable options and custom text input, sends replies back to the server, and the session continues.

**What was added:**

- `Models/QuestionModels.swift` — `QuestionOption`, `QuestionInfo`, `QuestionRequest` (Codable, matching server's question API contract)
- `Controllers/QuestionController.swift` — SSE event parsing for `question.asked`, `question.replied`, `question.rejected`
- `Views/Chat/QuestionCardView.swift` — Blue-themed SwiftUI card with radio/checkbox options, multi-question pagination, custom text input, dismiss/submit actions
- `Services/APIClient.swift` — Added `pendingQuestions()`, `replyQuestion()`, `rejectQuestion()` methods
- `Support/L10n.swift` — 10 new localization keys (EN + ZH) for question UI
- `AppState.swift` — `pendingQuestions` state, SSE event handling, refresh on session select/bootstrap, respond/reject methods
- `Views/Chat/ChatTabView.swift` — Renders `QuestionCardView` alongside existing `PermissionCardView`, updates scroll anchor

**Server API contract:**

- `GET /question` — list pending questions
- `POST /question/{requestID}/reply` — send answers (`{ "answers": [["label1"], ["label2"]] }`)
- `POST /question/{requestID}/reject` — dismiss question
- SSE events: `question.asked`, `question.replied`, `question.rejected`

**Tests added:** 12 new tests covering model decoding, controller event parsing, and SSE event structure.
