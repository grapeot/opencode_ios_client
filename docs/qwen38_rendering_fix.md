# qwen38 渲染问题排查与修复工作记录

记录 OpenCode iOS 客户端在 qwen-3.8-27b（qwen38 preset）下输出出现大量多余回车、以及 <think> / </think> 思考标签泄漏到正文的排查、根因与修复。

## 结论先行

**这是 iOS 客户端的渲染 bug，不是 OpenCode server 或模型的问题。**

同一份 server 返回的数据，Web 端和 Android 端都渲染正常（无多余回车、无 think 标签泄漏），只有 iOS 把 text part 里的前导 / 尾随换行、纯换行 part、以及泄漏进 text part 的 think 标签原样显示出来。修复方向是让 iOS 客户端像 Web / Android 一样，对 text part 做归一化：trim、跳过纯空白 part、剥离泄漏的 think 标签。

## 症状

- 用户在 iOS app 里用 qwen38（`RadixArk/Qwen3.8-27B-NVFP4`，SGLang 端点 `http://none.tail63c3c5.ts.net:8002/v1`）对话时，回复里出现大量空行 / 多余回车，偶见字面 <think> / </think> 标签。
- 其他模型、以及 Web / Android 端用 qwen38 都没有这个现象。
- 用户最初怀疑是 iOS 客户端 bug，要求先排查、不动代码。

## 排查过程

### 1. 数据层：确认 server 返回的 text part 确实带这些 artifact

对 `~/.local/share/opencode/opencode.db` 的 `message` / `part` 表做跨模型统计（排除当前排查 session 自身，避免自我污染）：

| 指标 | qwen38 | 其他模型 |
|---|---|---|
| text part 以 `\n` 开头 | 99% | 0% |
| text part 以 `\n` 结尾 | 92% | ~0% |
| 纯换行（无实际内容）的 text part | 65% | ~0% |
| 含 `\n\n\n` 的 text part | 24% | 极少 |
| 平均每条 text 换行数 | 12.15 | 2.5–3.2 |

再通过 live API（`GET /session/:id/message`，Basic auth `opencode:restart_Web@`；credential 在 workspace `.env` 的 `OPENCODE_PASSWORD`）拉取真实消息确认：qwen38 的 thinking 内容有时被整体塞进 **text part** 而不是 reasoning part，text part 里带字面 <think> / </think> 标签（SGLang 流式在 reasoning / content 边界切错位置）。当前 session（`ses_fcfbd043bffe417xHHYrV0gw37`）里有 45 个 text part 含 think 标签。

server 只是原样存储、原样返回模型输出，不做归一化——归一化在客户端做。

### 2. 对照：Web / Android 如何把同一份数据渲染正常

- **Web**（`opencode-official/packages/session-ui`）：
  - `message-part-text.ts:2` 对 part text 做 `.trim()`；
  - `message-part.tsx:717`、`session-turn.tsx:108,311` 用 `part.text?.trim()` 判断，纯空白 text part 直接不渲染。
  - 即 Web 显式做了 trim + 跳过空 text part。
- **Android**（`opencode_android_client/.../ChatMessageContent.kt`）：text part 交给 CommonMark 系 `Markdown` 渲染器（`com.mikepenz.markdown`），空白被折叠、空段落不产生可见空行，所以不出现“一堆回车”。

两端都证明了：这份数据本身可以被正确渲染，问题出在 iOS 的渲染层。

### 3. 定位 iOS 渲染缺陷（`MessageRowView.swift`）

- `buildAssistantBlocks(parts:)`：`isReasoning` part 跳过（走 thinking block 渲染），`isText` part 走 `markdownText`。
- `markdownText` → `shouldRenderMarkdown` / `hasMarkdownSyntax`：对纯空白文本（trimmed 为空）返回 false，落到原生 `Text(text)`。
- 原生 `Text` 把每个 `\n` 渲染成可见空行 → 用户看到“一堆回车”。
- text part 里泄漏的 <think> / </think> 标签按字面文本渲染出来。

## 根因

iOS 客户端没有像 Web / Android 那样对 text part 做归一化，具体两个缺陷：

1. **纯空白 text part 走原生 `Text`**：`hasMarkdownSyntax` 对 trimmed 为空的文本返回 false，落到原生 `Text`，每个 `\n` 渲染成可见空行。
2. **泄漏的 think 标签按字面渲染**：text part 里的 <think> / </think> 没有剥离，直接显示。

（server 原样返回模型输出、Web / Android 已各自归一化，所以问题只在 iOS 这一层。）

## 修复（分支 `fix/whitespace-text-parts`）

### 第一批：空白 part 过滤 + trim（已完成、已验证）

`MessageRowView.swift`：

- 新增 `isRenderableText(_:)`：纯空白返回 false。
- `buildAssistantBlocks(parts:)` 抽成 static 可测函数；text part 先过 `isRenderableText`，纯空白 part 直接跳过（不再产生空行，也不会打断 tool 卡片合并）。
- `markdownText` 渲染前 trim，去掉前导 / 尾随换行。
- `AssistantBlock` 由 private 改 internal 供测试。

`OpenCodeClientTests.swift`（`MessageRenderingHeuristicTests`）新增 4 个测试：

- `renderableTextRejectsWhitespaceOnlyParts`
- `renderableTextAcceptsContentWithSurroundingWhitespace`
- `assistantBlocksSkipsWhitespaceOnlyTextParts`
- `assistantBlocksMergesToolRunAcrossWhitespaceTextPart`

验证：simulator build 通过；`MessageRenderingHeuristicTests` 11 个测试通过。全量 suite 有 2 个既有 UI 测试失败（`testSettingsShowsThreeSpeechStrategiesAndRealtimePrompt`、`testToolCardsFixtureRendersFileCardsAndMergedToolCalls`），与本次改动无关。

### 第二批：think 标签剥离（待实现）

text part 里泄漏的 <think> / </think> 标签仍会按字面渲染。计划加 `stripReasoningLeak`：

- 剥掉完整的 <think> ... </think> 块；
- 残留的单个 </think>（thinking 尾巴切进了 text）只保留最后一个 </think> 之后的内容（那才是真实 response）；
- 再叠加 trim / 空过滤。

### 第三批：模拟器实证渲染路径（进行中）

- `AppState+Messages.swift` 的 `loadMessages` 加 `render-part` debug log：每条 assistant 消息的每个 text / reasoning part 打 `type`（server 原始类型）、`isReasoning` / `isText`（app 分类）、换行可视化的内容预览（前 160 字符）。
  - 选在 loadMessages 而不是 view：view body 每次 render pass 都会重算（日志会刷屏），loadMessages 每次拉取只跑一次，且是 raw server 数据落地的第一现场。
- 已 build + install 到 booted simulator（iPhone 17 Pro `8625CF87-A59C-474D-9658-DDFFFA707323`，iOS 26.3）。
- 待做：seed 模拟器 credential（UserDefaults `serverURL` / `username` 已写入；Keychain password 待写——simulator 内没有 `security` 二进制，spawn 自定义 binary 也失败，需要换 seed 方式），然后 deep link `opencode://session/ses_fcfbd043bffe417xHHYrV0gw37` 打开目标 session，抓 os_log 确认 think 内容确实按 text part（chat history）渲染、而非 reasoning part（thinking block）。

## 为什么在客户端修

- 同一份 server 数据，Web / Android 都渲染正常，说明数据本身可被正确渲染，问题在 iOS 渲染层，不在 server / 模型。
- 客户端归一化是幂等的：对其他模型（本来没有这些换行 / 标签）无副作用。
- 不动 server、不动模型，影响面最小，且与 Web / Android 行为对齐。

## 关键坐标

- 分支：`fix/whitespace-text-parts`（与 master 同点位，工作区改动分批提交中）
- 目标 session：`ses_fcfbd043bffe417xHHYrV0gw37`
- API：`http://127.0.0.1:4096`，Basic auth `opencode` / `OPENCODE_PASSWORD`（workspace `.env`）
- 模拟器：iPhone 17 Pro `8625CF87-A59C-474D-9658-DDFFFA707323`（iOS 26.3，booted）
- bundle id：`com.grapeot.OpenCodeClient`
- 构建约束：`xcodebuild build` 与 `test` 必须串行（共享 build.db）；全量 test 10–20 分钟，定向用 `-only-testing:OpenCodeClientTests/MessageRenderingHeuristicTests`
