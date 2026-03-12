# Working Notes - OpenCode iOS Client

## Recent Changes

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
