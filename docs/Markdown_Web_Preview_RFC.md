# RFC: Markdown Web Preview 技术方案

> 技术方案征求意见稿 · 工作草案 · 2026-06

## 元数据

| 字段 | 值 |
|---|---|
| 标题 | Markdown Web Preview 技术方案 |
| 状态 | 工作草案 |
| PRD 引用 | [Markdown_Web_Preview_PRD.md](Markdown_Web_Preview_PRD.md) |
| 目标项目 | OpenCode iOS Client |
| 范围 | Files Markdown 预览 |

## 1. 摘要

本 RFC 提出在 OpenCode iOS Client 中新增 WebView-based Markdown preview。核心方案是：iOS 端 bundle 一个本地 HTML/JS/CSS 渲染 shell，用 `WKWebView` 加载；Swift 将 Markdown 原文、base path、主题和配置通过安全消息传入；WebView 内的 JavaScript 使用 Markdown renderer 转 HTML，经过 sanitizer 后注入页面。

这条路线的目的不是让 iOS client 浏览互联网，而是补足原生 MarkdownUI 对 HTML-in-Markdown、CSS 卡片、内联 SVG 和复杂 visual layout 的支持缺口。

## 2. 背景与现状

当前 Files 预览和 Chat 消息都使用 `MarkdownUI.Markdown`：

1. Files：`MarkdownPreviewView` 内调用 `Markdown(displayText, imageBaseURL: ...)` 并挂 `WorkspaceMarkdownImageProvider`。
2. Chat：`ResolvedMarkdownView` 内调用 `Markdown(resolvedText ?? text)` 并挂同类 image provider。

上游 MarkdownUI 对 HTML 的处理是明确的：HTML block 和 inline HTML 作为 verbatim text 渲染，不执行 HTML/CSS。源码证据包括 `testVerbatimHTML` 和 `.htmlBlock -> ParagraphView(content:)`。

因此，支持 HTML-in-MD 不是给 MarkdownUI 打开一个开关，而是需要另一条渲染路径。

## 3. 设计目标

1. 在 Files 中为 Markdown 文件提供 Web Preview。
2. 支持 HTML-in-MD 的安全子集、局部 CSS、内联 SVG、GFM 表格和现有 Markdown 图片。
3. 与现有 workspace 相对图片解析语义保持一致。
4. 保留 Native Preview / Markdown source 回退路径。
5. 不从网络加载 renderer JS；所有 renderer asset 固定在 app bundle。
6. 不执行 Markdown 中的任意脚本。

## 4. 非目标

1. 不替换 Chat 中 Markdown 消息渲染，也不为 Chat 中 AI 回复提供 Web Preview 展开。
2. 第一版不实现 Mermaid。
3. 第一版不实现完整 `.html` 文件浏览器。
4. 第一版不支持任意外部资源加载。
5. 第一版不实现 server-side Markdown rendering。

## 5. 方案总览

```text
Markdown file content
        │
        ▼
Swift FileContentView
        │ passes markdown + context
        ▼
MarkdownWebPreviewView (WKWebView)
        │ loads bundled preview.html
        ▼
preview.html + bundled JS/CSS
        │ markdown renderer + sanitizer
        ▼
sanitized HTML in WebView
```

### 5.1 为什么先选客户端 WebView 渲染

与 server-side render 相比，客户端 WebView 渲染的优势是实现闭环短：不需要改 OpenCode server，不需要新增 API，先在 iOS client 内验证体验。所有 JS/CSS asset 随 app bundle 固定版本，行为可控。

server-side render 仍然是未来可选路线，尤其适合生成可分享、可缓存、跨客户端一致的 HTML artifact。但 MVP 的痛点是 iOS 预览能力，所以先做客户端 WebView renderer。

## 6. 组件设计

### 6.1 `MarkdownWebPreviewView`

职责：

1. 持有 `WKWebView`。
2. 加载 app bundle 内的 `preview.html`。
3. 在页面 ready 后传入 Markdown payload。
4. 监听 JS 回传的链接点击、图片点击、渲染错误。
5. 跟随 app color scheme 更新主题。

输入：

```swift
struct MarkdownWebPreviewInput {
    let markdown: String
    let markdownFilePath: String?
    let workspaceDirectory: String?
    let baseURL: URL?
    let colorScheme: ColorScheme
}
```

### 6.2 `preview.html`

本地 HTML shell，包含：

1. `<div id="content"></div>`。
2. 基础 CSS 主题。
3. 本地 JS dependencies。
4. `window.renderMarkdown(payload)` 入口。
5. link/image click event bridge。

### 6.3 JS dependencies

候选：

1. `markdown-it`：成熟、插件生态好、支持 HTML passthrough 配置。
2. `DOMPurify`：对渲染后的 HTML 做 sanitizer。
3. 可选后续：`highlight.js`、`mermaid`。

第一版建议：`markdown-it` + `DOMPurify` + 自定义 CSS。Mermaid 暂不启用。

### 6.4 Swift 与 WebView 通信

推荐：Swift 在 WebView 加载完成后用 `evaluateJavaScript` 调用 `window.renderMarkdown(payload)`，payload 必须 JSON encode，不拼接原始 Markdown 字符串。

示意：

```swift
let payload = PreviewPayload(
    markdown: markdown,
    basePath: markdownFilePath,
    theme: colorScheme == .dark ? "dark" : "light"
)
let json = try jsonEncoder.encode(payload)
let js = "window.renderMarkdown(\(String(data: json, encoding: .utf8)!))"
webView.evaluateJavaScript(js)
```

更稳的后续方案是 `WKScriptMessageHandler` + initial bootstrap script，但第一版 `evaluateJavaScript` 足够验证。

### 6.5 图片路径解析

第一版推荐 Swift 预处理 Markdown 中的相对图片路径，复用现有 `MarkdownImageResolver` 的语义，把相对路径改写成 WebView 可访问的受控 URL 或 data URI。

可选实现路径：

1. 直接复用 `MarkdownImageResolver.resolveImages(...)`，把 workspace 内图片转成 `data:` URI。优点是 WebView 无需额外 file scheme；缺点是大图会增大 HTML/Markdown payload。
2. 新增自定义 URL scheme，例如 `opencode-file://<encoded-path>`，由 `WKURLSchemeHandler` 返回图片数据。优点是适合大图；缺点是实现更复杂。
3. 使用现有 server file endpoint。优点是避免 data URI；缺点是 auth、base URL、离线和 endpoint 语义更复杂。

MVP 建议先走 data URI，因为项目已经有 Markdown 图片 resolver 经验，且第一版主要验证视觉渲染。

### 6.6 链接处理

WebView navigation policy：

1. `http/https` 外链：拦截后交给系统 Safari 或确认弹窗。
2. workspace 相对链接：解析后调用 app 内 `onOpenResolvedPath` 或 Files 跳转。
3. fragment anchor：允许 WebView 内滚动。
4. 其他 scheme：默认拦截。

## 7. 安全模型

### 7.1 信任边界

Markdown 内容来自 workspace 和 AI 输出，不能等同于可信网页。WebView 必须以最小权限运行。

### 7.2 WKWebView 配置

建议：

1. 使用 non-persistent `WKWebsiteDataStore`，避免持久 cookie/localStorage。
2. 禁止 arbitrary navigation。
3. 不启用 file URL 对整个 workspace 的宽访问。
4. 通过 message handler 明确暴露有限接口。
5. JS library 从 app bundle 加载，不从 CDN 加载。

### 7.3 Sanitizer 策略

DOMPurify 配置第一版允许：

- 基础文本标签：`p`, `strong`, `em`, `code`, `pre`, `blockquote`, `ul`, `ol`, `li`, `table`, `thead`, `tbody`, `tr`, `th`, `td`, `details`, `summary`
- 安全布局标签：`div`, `span`
- 图片和 SVG：`img`, `svg`, `path`, `rect`, `text`, `line`, `polyline`, `polygon`, `circle`, `ellipse`, `g`, `defs`, `marker`, `style` 是否允许需谨慎评估
- 属性白名单：`class`, `href`, `src`, `alt`, `title`, `width`, `height`, `viewBox`, 必要 SVG 属性

必须移除：

- `script`, `iframe`, `object`, `embed`, `form`, `input`
- `on*` 事件属性
- `javascript:` URL
- 未授权外部资源

注：若允许 inline SVG 的 `<style>`，需要确认 DOMPurify 配置和 WebView 行为。MVP 可以先支持 HTML/CSS 卡片和普通 Markdown 图片，inline SVG 作为 fixture 验证项，不把任意 SVG 作为安全承诺。

## 8. UI 设计

### 8.1 Files toolbar

当前 Markdown 文件已有 `Preview` / `Markdown` 切换。新增 Web Preview 后可选两种设计：

方案 A：三态按钮

```text
Native → Web → Markdown → Native
```

方案 B：Menu

```text
Preview Mode
  Native
  Web
  Source
```

推荐方案 B，避免按钮文案在三态间不清楚。

### 8.2 默认模式

~~MVP 默认仍使用 Native Preview。~~ **更新（2026-06-14）：Web Preview 真机验证通过后，默认改为 Web Preview**，用户可手动切回 Native / Source。大文件由 oversize gate 兜底。后续可以检测 Markdown 是否包含 `<style>`、`<div class=...>`、`<svg>`，对纯普通 Markdown 决定是否回退更轻量的 Native。

### 8.3 错误显示

Web Preview 失败时显示：

1. 错误摘要。
2. `Open Native Preview`。
3. `Open Markdown Source`。
4. 可复制 debug 信息。

## 9. 测试计划

测试分四层推进：先用固定 fixture 锁住内容覆盖面，再用 simulator 做视觉验收，然后补 XCTest 覆盖关键交互，最后跑顺序化 build/test 防止工程集成回归。

### 9.1 Fixture 文件

在 `OpenCodeClient/OpenCodeClientUITests/Fixtures/MarkdownWebPreview/` 或同等测试资源目录加入：

1. `plain_markdown.md`
2. `html_cards.md`
3. `inline_svg.md`
4. `relative_images.md`
5. `dark_theme_cards.md`
6. `malicious_script.md`
7. `wide_table.md`
8. `large_markdown.md`
9. `broken_html.md`

同时加入 `images/chart.png` 和 `images/diagram.svg`，用于验证相对路径解析。fixture 内容不要依赖网络，避免测试结果受外部资源影响。

### 9.2 验收点

1. HTML card 在 Web Preview 中显示，在 Native Preview 中可 fallback 为文本。
2. 深色模式下无深底深字。
3. `<script>` 不执行。
4. 相对图片显示。
5. 外部链接不在 WebView 内任意跳转。
6. 切换 Preview mode 不丢内容。
7. 大文件或渲染失败可回到 source。
8. `broken_html.md` 不影响 WebView 容器稳定性，失败时显示错误状态或 sanitizer 后的可读内容。
9. `relative_images.md` 中的图片按 Markdown 文件所在目录解析，不按 workspace 根目录误解析。

### 9.3 UI 测试

第一版先用 simulator screenshot 人工验收；稳定后补 XCTest。UI 测试只覆盖稳定哨兵，不依赖完整 CSS 像素一致性：

1. 打开 fixture markdown。
2. 切换 Web Preview。
3. 检查 WebView 存在。
4. 检查页面 title / sentinel text。
5. 点击外链，确认被拦截。
6. 切回 Native Preview 和 Source，确认内容仍可见。
7. 打开 `malicious_script.md`，确认页面出现安全哨兵文本，但没有执行脚本副作用。

建议给 WebView 根节点、Preview mode menu 和错误状态加稳定 accessibility identifier，避免 UI test 依赖按钮文案或 SwiftUI 层级。

### 9.4 手工视觉验收

每个 milestone 都做一次手工视觉验收，记录截图到临时目录或测试 artifact：

1. iPhone 窄屏浅色模式。
2. iPhone 窄屏深色模式。
3. iPad 或 regular width split preview。
4. HTML card、wide table、relative image、inline SVG 四个 fixture。
5. Web Preview 失败状态和回退按钮。

验收重点不是像素级一致，而是首屏可读、无深底深字、无横向溢出破坏主体阅读、模式切换不丢状态。

### 9.5 构建与测试命令

本项目的 `xcodebuild build` 和 `xcodebuild test` 需要串行运行，避免共享 build database 锁冲突。建议在 `OpenCodeClient/` 目录下执行：

```bash
xcodebuild build -project OpenCodeClient.xcodeproj -scheme OpenCodeClient -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test -project OpenCodeClient.xcodeproj -scheme OpenCodeClient -destination 'platform=iOS Simulator,name=iPhone 16'
```

如果本机没有 `iPhone 16` simulator，先用 `xcrun simctl list devices available` 找一个可用 iOS simulator，再替换 destination。不要为了验证 Web Preview 去重启或杀掉用户正在使用的 OpenCode server；fixture 测试应优先走本地测试资源。

## 10. 实现计划

### Phase 0：Spike

目标是用最小改动证明 WebView renderer 能在 app 内稳定工作，不先重构现有 MarkdownUI 路径。

1. 新增 `OpenCodeClient/Views/MarkdownWebPreviewView.swift`，内部用 `UIViewRepresentable` 包 `WKWebView`。
2. 新增 bundled resources：`preview.html`、`preview.css`、`preview.js`、`vendor/markdown-it.min.js`、`vendor/purify.min.js`。
3. 在 `preview.html` 暴露 `window.renderMarkdown(payload)`，payload 至少包含 `markdown` 和 `theme`。
4. Swift 侧用 JSON encoder 生成 payload，通过 `evaluateJavaScript` 传给 WebView，不拼接原始 Markdown 字符串。
5. WebView 内先完成 Markdown 渲染、DOMPurify 过滤、基础 CSS、深浅色切换。
6. 用 `html_cards.md` 和 `dark_theme_cards.md` 手工验证，确认 WebView 能显示卡片且没有深色主题问题。

Phase 0 不接入 Files toolbar，不处理相对图片，不做链接跳转。这样可以把 WebView bundling、JS 调用和 sanitizer 三个风险先拆出来验证。

### Phase 1：Files MVP

目标是在 Files 中形成可用闭环：Native Preview、Web Preview、Source 三种模式都能打开，同一份 Markdown 可回退。

1. 在 `FileContentView.swift` 中把 `showPreview: Bool` 改为 `previewMode` enum，例如 `native`, `web`, `source`。
2. 把 toolbar 的二态按钮改成 menu：`Native Preview`、`Web Preview`、`Markdown Source`。
3. `contentView(text:)` 按 mode 分派：native 走现有 `MarkdownPreviewView`，web 走 `MarkdownWebPreviewView`，source 走 `RawTextView`。
4. 保留现有大文件保护：超过 `markdownMaxTotalLength` 或单行过长时，Native Preview 自动回到 source；Web Preview 可先显示确认/警告状态，避免直接塞超大 payload。
5. Web Preview 输入接入 `markdownFilePath` 和 `workspaceDirectory`，但第一版仍可以先把图片转成 data URI。
6. 复用 `MarkdownImageResolver.resolveImages(...)` 生成含 data URI 的 Markdown，再传给 WebView，确保相对图片路径语义与 Native Preview 一致。
7. 加入加载中、渲染失败、回退按钮三个状态，失败时可以一键打开 Native Preview 或 Source。
8. 对 WebView 根节点和 mode menu 加 accessibility identifier，为 UI test 留入口。

Phase 1 的完成标准是：用户从 Files 打开 `.md` 后可以手动切到 Web Preview，HTML card、相对图片、暗色主题、安全过滤四类 fixture 都能通过手工验收。

### Phase 2：安全和 polish

目标是把 MVP 从能看推进到可长期维护，重点处理安全边界、导航行为和测试稳定性。

1. 收紧 DOMPurify allowlist，明确禁止 `script`, `iframe`, `form`, `object`, `embed`, `on*`, `javascript:` URL。
2. 配置 `WKNavigationDelegate`，拦截所有非 fragment navigation。
3. 外部 `http/https` 链接交给系统打开或 app 现有外链策略，不在 WebView 内连续浏览。
4. workspace 相对链接先解析为 path，再走 app 内 Files 打开路径；解析失败时显示不可打开状态。
5. WebView 使用 non-persistent data store，避免持久 cookie/localStorage。
6. 主题变化时重新发送 theme payload 或调用 JS 更新 `data-theme`，不要求重建整个 WebView。
7. 补 UI tests 覆盖 mode 切换、WebView 出现、外链拦截、安全 fixture 和 source fallback。
8. 补轻量 unit tests 覆盖 Markdown 图片路径预处理，尤其是同目录、子目录、`../` 和 workspace absolute path。

Phase 2 完成后，Web Preview 可以作为实验功能给日常文档阅读使用，但默认仍不替代 Native Preview。

### Phase 3：HTML artifact / visual enhancement

1. Files 中 `.html` 文件支持 WebView 打开。
2. 评估 Mermaid 和代码高亮。

这一步仍然限定在 Files，不扩展到 Chat。`.html` artifact 应使用单独的安全策略，因为它已经是 HTML，不应复用 Markdown sanitizer 的全部假设。

## 11. 推动执行的任务顺序

真正开工时建议按下面顺序建小 PR 或小 commit。每一步都能独立验证，失败时容易回退。

1. **资源接入 PR**：加入 `preview.html/js/css` 和 vendor 文件，确认 bundle path 可加载。
2. **WebView spike PR**：新增 `MarkdownWebPreviewView`，用 hardcoded Markdown 渲染 fixture，不接 Files UI。
3. **Files mode PR**：`FileContentView` 从 bool 改 enum，menu 切换三种模式，Web mode 暂时只渲染原文。
4. **图片解析 PR**：复用 `MarkdownImageResolver`，让 Web Preview 支持相对图片 data URI。
5. **安全 PR**：DOMPurify allowlist、navigation delegate、外链拦截、错误状态。
6. **测试 PR**：加入 fixture、UI tests、unit tests 和手工验收记录。
7. **Polish PR**：深浅色细节、wide table CSS、加载状态、accessibility identifier 文案收敛。

推进时每个 PR 的验收都应包含一次 `xcodebuild build`。涉及 UI test 或导航行为的 PR 再跑 `xcodebuild test`。build 和 test 必须串行执行。

## 12. 开放问题

1. ~~第一版图片路径用 data URI 还是自定义 URL scheme？~~ **已决策（2026-06-14）：data URI**，直接复用现有 `MarkdownImageResolver.resolveImages(...)`，与 Native Preview 路径解析语义完全一致，零新增 Swift 基础设施。大图增大 payload 的代价由 `markdownMaxTotalLength` 同类阈值兜底；自定义 URL scheme 留作大图优化的后续路线。
2. 是否允许 inline SVG 的 `<style>`？需要安全验证。MVP 把 inline SVG 当 fixture 验证项，不作安全承诺。
3. Web Preview 是否应成为包含 HTML 的 Markdown 的默认模式？**已决策：先不默认**，第一版保留 Native 默认，用户手动切 Web。
4. 是否需要 server-side render 作为长期统一方案？可以作为 Phase 4 另开 RFC。

## 12.5 本轮执行决策（2026-06-14）

- **交付范围**：本轮做完 Phase 0 / 1 / 2（spike → Files MVP → 安全与 polish）。Phase 3（`.html` artifact、Mermaid、代码高亮）不在本轮。
- **图片方案**：data URI，复用 `MarkdownImageResolver`（见开放问题 1）。
- **执行编排**：iOS build/集成链是串行的（`build.db` 单锁 + PR 间强依赖），由主 agent 串行推进并自己跑 `xcodebuild` 验证。可并行的三块外包给 sub-agent：
  1. **fixture 生成**：§9.1 的 9 个 `.md` + `images/chart.png`、`images/diagram.svg`，9 个互相独立的生成任务。
  2. **前端 shell 起草**：`preview.html` / `preview.css` / `preview.js` + DOMPurify 配置，一个自包含 web artifact，可在桌面浏览器里先验证渲染/sanitizer 行为，再进 Swift。
  3. **依赖调研**：markdown-it + DOMPurify 的版本选型与 CDN-free bundling 方式。
  「最终交付文本自己写、sub-agent 结果自己验证」：sub-agent 产出的 shell 和 fixture 由主 agent 在真机 simulator build 里验收后才并入。

## 13. 推荐决策

批准 Phase 0/1 spike：在 iOS client 内实现 WebView + bundled JS renderer 的 Files-only MVP。保留现有 MarkdownUI 作为默认和 fallback。不要试图修改 MarkdownUI 支持 HTML，也不要现在迁移 Textual 来解决这个问题。
