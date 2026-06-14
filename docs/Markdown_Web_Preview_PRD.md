# Markdown Web Preview — 产品需求文档

> 工作草案 · 2026-06 · OpenCode iOS Client

## 实施进度速览

<style>
.pv-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:10px;margin:12px 0 18px}
.pv-card{border:1px solid var(--border,#d7dee8);border-radius:12px;padding:12px;background:var(--card-bg,#fff);color:var(--fg,#1a1a1a)}
.pv-card h3{margin:0 0 6px;font-size:1rem;color:var(--fg,#1a1a1a)}
.pv-card p{margin:5px 0;font-size:.9rem;color:var(--fg,#1a1a1a)}
.pv-ok{border-left:5px solid var(--ok-border,#10b981)}
.pv-bad{border-left:5px solid var(--bad-border,#ef4444)}
.pv-warn{border-left:5px solid var(--warn-border,#f59e0b)}
.pv-block{border-left:5px solid var(--block-border,#6b7280)}
.pv-chip{display:inline-block;border-radius:999px;padding:2px 8px;font-size:.78rem;font-weight:650;margin-bottom:6px}
.pv-chip.ok{background:var(--ok-bg,#d1fae5);color:var(--ok-fg,#065f46)}
.pv-chip.warn{background:var(--warn-bg,#fef3c7);color:var(--warn-fg,#92400e)}
.pv-chip.block{background:var(--block-bg,#e5e7eb);color:var(--block-fg,#374151)}
</style>

<div class="pv-grid">
  <div class="pv-card pv-ok"><span class="pv-chip ok">完成</span><h3>Phase 0 — Spike</h3><p>WKWebView + bundled renderer 闭环跑通；HTML 卡片 / 暗色 / 安全过滤 fixture 通过。</p></div>
  <div class="pv-card pv-ok"><span class="pv-chip ok">完成</span><h3>Phase 1 — Files MVP</h3><p>FileContentView 三态 (native/web/source)；data-URI 图片解析；oversize gate；可一键回退。</p></div>
  <div class="pv-card pv-ok"><span class="pv-chip ok">完成</span><h3>Phase 2 — 安全与 polish</h3><p>DOMPurify allowlist 收紧；外链拦截走系统 Safari；workspace 相对链接回 app；non-persistent store。</p></div>
  <div class="pv-card pv-warn"><span class="pv-chip warn">部分</span><h3>主题：明暗双适配</h3><p>shell 暴露 --fg / --card-bg / --ok-* 等变量 + fallback；作者用 var() 即可双模式自适应；chip dark 用饱和主色避免糊掉。</p></div>
  <div class="pv-card pv-block"><span class="pv-chip block">下一轮</span><h3>Phase 3 — Visual 增强</h3><p>.html artifact 浏览、Mermaid、代码高亮、图片点击放大 — 留作下一 PR。</p></div>
</div>

> 纯 Markdown fallback（若 `<style>` 被剥离 / 不支持 CSS 变量）：
> Phase 0/1/2 = 完成；明暗双适配 = shell 提供变量 + fallback，作者用变量写即可；Phase 3 = 下一轮做。

## 1. 背景

OpenCode iOS Client 的核心使用场景已经从“远程看 AI 状态”演化成“在手机上审阅 AI 生成的 Markdown 报告，并及时做方向判断”。现有原生 MarkdownUI 渲染能覆盖标题、列表、表格、代码块和图片，但无法渲染 HTML-in-Markdown、内联 SVG、CSS 卡片、复杂布局和未来可能的 Mermaid/Graphviz 等视觉结构。

这次 visual writing 实验暴露了一个产品级矛盾：AI 现在可以低成本生成更适合人类阅读的视觉结构，但 iOS 端当前的原生 Markdown 渲染器不能承载这些结构。用户在 Cursor/GitHub 这类桌面 Markdown 预览里能看到 HTML/CSS 卡片和内联 SVG，在 OpenCode iOS 里却只能看到普通文本或完全失效的 HTML。

本需求提出一个新能力：**Markdown Web Preview**。它不是替代 Markdown 作为 source of truth，而是给 iOS client 增加一个更强的“预览层”：使用 `WKWebView` 加载本地渲染 shell，把 Markdown 渲染成 HTML 展示。

## 2. 用户问题

用户大多数时候在手机上阅读 AI 产物。手机阅读有三个限制：屏幕窄、注意力碎片化、上下文切换频繁。纯线性 Markdown 容易让用户重新在脑内拼结构，尤其是项目复盘、实验周报、技术调查、方案对比和进度说明。

用户需要的不是“更花的页面”，而是更低认知负担的判断界面：首屏能恢复背景，卡片能标出路径状态，颜色能区分成立/否定/阻塞，图能展示分支和依赖，折叠区能保留审计材料但不干扰第一遍阅读。

当前 iOS client 的缺口是：这些结构在 MarkdownUI 里无法稳定呈现。

## 3. 目标

### 3.1 产品目标

1. 让用户能在 iOS 上稳定阅读 AI 生成的视觉化 Markdown 报告。
2. 保持 Markdown 仍是 source of truth，Web Preview 只是派生渲染视图。
3. 支持 HTML-in-Markdown 的安全子集，包括卡片、局部样式、左右对照、内联 SVG 或图片引用。
4. 支持 repo 内相对图片路径，使 AI 生成的图表、截图和视觉产物能在 Files 预览中稳定显示。
5. 在不破坏现有 MarkdownUI 预览的前提下，提供可回退的 Web Preview 模式。

### 3.2 非目标

1. 不把 iOS client 变成通用网页浏览器。
2. 不执行任意远程 JavaScript。
3. 不默认允许不受控的外部 iframe、表单提交、跨站脚本或任意网络资源加载。
4. 不在第一版实现完整 Mermaid、LaTeX、TikZ、Graphviz 渲染链路。
5. 不要求所有 Markdown 都改写成 HTML；普通 Markdown 继续正常使用。
6. 不支持 Chat 中直接用 Web Preview 阅读 AI 回复；Chat 消息仍走现有 Markdown 渲染路径。

## 4. 目标用户场景

### 场景 A：手机审阅实验周报

AI 生成一个实验总结，包含状态卡、前后对照、证据地图和折叠审计层。用户在手机上打开报告，希望 30-60 秒判断这周做了什么、哪些假设被否定、下周该选哪条路。

成功体验：首屏卡片和颜色正常显示；用户不需要横向滚动宽表，也不需要脑补 Mermaid。

### 场景 B：阅读技术调查报告

AI 调查某个渲染库、API 或部署问题，报告里包含方案矩阵、路径图和源码证据。用户在 iOS 上查看后决定是否投入实现。

成功体验：Web Preview 能显示卡片和 SVG；点击文件路径或 workspace 内链接时仍能回到 app 内 Files 预览。

### 场景 C：打开完整 HTML artifact

AI 生成 `show-me` 风格的独立 HTML 文件。用户在 Files 中点开 `.html`，iOS 端用同一套 WebView 容器打开，而不是把它当代码文本显示。

## 5. 功能需求

### 5.1 文件预览模式

Markdown 文件预览至少提供两种模式：

1. **Native Preview**：现有 MarkdownUI 渲染，稳定、原生、适合普通 Markdown。
2. **Web Preview**：新 WebView 渲染，适合 HTML-in-MD、卡片、内联 SVG、复杂视觉布局。

默认策略：~~第一版保留 Native Preview 默认~~ **更新（2026-06-14）：Web Preview 通过真机验证后，默认模式改为 Web Preview**，用户可手动切回 Native / Source。大文件仍由 oversize gate 保护（超阈值先确认，避免直接塞超大 payload）。

### 5.2 本地 JS 渲染 shell

Web Preview 使用 app bundle 内置的 HTML/JS/CSS shell，不从 CDN 动态加载脚本。Markdown 原文由 Swift 注入 WebView，JS 在 WebView 内渲染为 HTML。

第一版建议内置：

1. Markdown renderer：`markdown-it` 或同类成熟库。
2. Sanitizer：`DOMPurify`。
3. 默认 CSS：适配 iOS 深浅色、窄屏、表格横向滚动、代码块、图片。

Mermaid、代码高亮、数学公式可以留到后续阶段。

### 5.3 安全渲染

默认 Web Preview 是“本地 Markdown renderer”，不是开放网页浏览器。渲染策略：

1. JS 库来自 app bundle 固定版本。
2. Markdown 输入通过安全消息通道传入，不用字符串拼接直接塞进 HTML。
3. 渲染结果经过 sanitizer。
4. 默认阻止任意外部 navigation；外部链接交给系统 Safari 或确认后打开。
5. workspace 内链接和图片走受控路径解析。
6. 默认禁用或移除 `<script>`、`iframe`、`form`、危险事件属性和不必要的外部资源。

### 5.4 图片和相对路径

Web Preview 必须支持 Markdown 中的相对图片路径，例如 `![chart](imgs/chart.png)`。路径语义应与现有 MarkdownUI 图片 provider 一致：相对当前 Markdown 文件所在目录解析，不能依赖 WebView 自己猜路径。

可选实现方式：

1. Swift 预处理 Markdown，把相对图片路径改写成 app/server 可访问的受控 URL。
2. WebView 自定义 URL scheme，由 app 拦截并返回 workspace 文件内容。
3. server 提供 preview asset endpoint，WebView 通过 authenticated URL 读取。

第一版只要在 Files 预览里支持 workspace 相对图片即可。

### 5.5 主题和手机布局

Web Preview 必须适配深浅色主题。核心要求：

1. 普通正文颜色交给主题变量，不硬编码深色文字落到深色背景。
2. 卡片如果指定文字色，必须同时指定背景色。
3. 表格在窄屏上允许横向滚动，但首屏不应依赖宽表。
4. 图片最大宽度为容器宽度，支持点击进入现有图片预览可以后续实现。

### 5.6 降级与回退

Web Preview 失败时，用户应能立即切回 Native Preview 或 Markdown source。失败状态要说明是渲染失败、图片加载失败、还是内容被安全策略过滤。

## 6. 成功标准

第一版完成后，用以下 fixture 验收：

1. 普通 Markdown：标题、列表、表格、代码块、链接正常。
2. HTML-in-MD 卡片：`<style>` + `<div class="card">` 可显示为卡片。
3. 内联 SVG：简单流程图能显示。
4. 相对图片：`imgs/foo.png` 能按 Markdown 文件目录解析。
5. 暗色模式：正文、卡片、代码块不出现深底深字。
6. 安全过滤：内联 `<script>alert(1)</script>` 不执行。
7. 外部链接：点击后不在 WebView 内随意跳转，按 app 规则处理。
8. 回退：同一文件可切回 Native Preview 和 Markdown source。

## 7. 风险

### 7.1 安全风险

WebView 引入 HTML/JS 执行环境，必须避免把本地 workspace 变成任意脚本执行面。第一版应坚持本地 bundle JS + sanitizer + navigation delegate + 受控资源加载。

### 7.2 一致性风险

Native Preview 和 Web Preview 对 Markdown 语法的解释可能不同。需要在 UI 上明确这是两种 preview，不承诺完全一致。长期可通过 fixture tests 收敛常见差异。

### 7.3 性能风险

长 Markdown、大表格、大图片、复杂 SVG 可能让 WebView 卡顿。第一版应有输入大小阈值或加载状态，并保留 Native/Source fallback。

### 7.4 产品复杂度风险

Preview 模式过多会增加用户负担。第一版 UI 应保持简单：`Preview` / `Web` / `Markdown` 三态或二级菜单，不要把渲染选项暴露成配置面板。

## 8. 分阶段计划

工程执行和测试拆分以 [Markdown_Web_Preview_RFC.md](Markdown_Web_Preview_RFC.md) 的“实现计划”“推动执行的任务顺序”和“测试计划”为准。PRD 只定义阶段目标和产品边界。

### Phase 1：Files Web Preview MVP

1. 增加 `MarkdownWebPreviewView`。
2. Bundle `preview.html`、Markdown renderer、DOMPurify、基础 CSS。
3. Files 中 Markdown 文件支持切换 Web Preview。
4. 支持 Markdown 原文注入、基本渲染、相对图片路径改写。
5. 支持深浅色主题和基础安全过滤。

### Phase 2：增强 visual 能力

1. Mermaid server-side 或 WebView-side 渲染评估。
2. 代码高亮。
3. 图片点击预览。
4. 打开独立 `.html` artifact。

## 9. 与 internal writing skill 的关系

这个功能不会改变写作原则。Markdown 仍然是 source of truth；HTML/CSS/JS 是 renderer/view layer。internal writing skill 仍应要求每个 HTML visual 有 Markdown fallback，直到 iOS Web Preview 稳定并经过多渲染器验证。
