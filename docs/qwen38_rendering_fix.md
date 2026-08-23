# qwen38 渲染问题排查与修复工作记录

记录 OpenCode iOS 客户端在 qwen-3.8-27b（qwen38 preset）下输出出现大量多余回车、以及偶见 `<think> / </think>` 思考标签泄漏到正文的排查、根因与修复。

## 结论先行

**主 bug 在 iOS 客户端渲染层，不在 OpenCode server。**

同一份 server 返回的数据，Web 端和 Android 端都渲染正常（无多余回车、无 think 标签泄漏），只有 iOS 把 text part 里的前导 / 尾随换行、纯换行 part、以及泄漏进 text part 的 think 标签原样显示出来。修复方向是让 iOS 客户端像 Web / Android 一样，对 text part 做归一化：trim、跳过纯空白 part、删除泄漏进 text part 的 thinking 内容。

两个边界说明（独立评审后修正）：

- 换行本身是 qwen38 / SGLang 的输出形态，server 原样存储、原样返回——不是 server "有 bug"，而是 iOS 缺了 Web / Android 已有的归一化。
- think 标签泄漏**不是** qwen38 的系统性问题：干净的 qwen38 session（`ses_fcfbff756ffe`，219 条 text part）里 0 条 think 标签。当前 session 里的 think 标签大多来自本次排查"讨论"这些标签本身，外加少量 `<think> / </think>` 切分尾巴。

## 症状

- 用户在 iOS app 里用 qwen38（`RadixArk/Qwen3.8-27B-NVFP4`，SGLang 端点 `http://none.tail63c3c5.ts.net:8002/v1`）对话时，回复里出现大量空行 / 多余回车，偶见字面 `<think> / </think>` 标签。
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

再用 live API（`GET /session/:id/message`，Basic auth `opencode:restart_Web@`；credential 在 workspace `.env` 的 `OPENCODE_PASSWORD`）复核：当前 session（`ses_fcfbd043bffe417xHHYrV0gw37`，活跃中、计数为移动目标）评审时点有 58 条 text part 含 think 标签；但对照干净 qwen38 session（`ses_fcfbff756ffe`：219 条 text、161 条纯空白、**0 条 think**）可知，当前 session 的 think 标签大多来自本次排查讨论标签本身，加少量 `<think> / </think>` 切分尾巴（SGLang 流式在 reasoning / content 边界切错位置）。所以 think 标签泄漏是 **session 特有 + 少量切分尾巴**，不是 qwen38 的系统性输出问题。

server 只是原样存储、原样返回模型输出，不做归一化——归一化是客户端的职责。

### 2. 对照：Web / Android 如何把同一份数据渲染正常

- **Web**（`opencode-official/packages/session-ui`）：
  - `message-part-text.ts:2` 对 part text 做 `.trim()`；
  - `message-part.tsx:717`、`session-turn.tsx:108,311` 用 `part.text?.trim()` 判断，纯空白 text part 直接不渲染；
  - `markdown-cache.tsx` 的 DOMPurify 不把 `think` 列入保留标签，未知标签会被剥离。
  - 即 Web 显式做了 trim + 跳过空 text part + 剥未知标签。
- **Android**（`opencode_android_client/.../ChatMessageContent.kt`）：text part 交给 CommonMark 系 `Markdown` 渲染器（`com.mikepenz.markdown`，`:436` 分派、`:776` 渲染），空白被折叠、空段落不产生可见空行，所以不出现“一堆回车”。

两端都证明：这份数据本身可以被正确渲染，问题出在 iOS 的渲染层。

### 3. 定位 iOS 渲染缺陷（`MessageRowView.swift`）

- `buildAssistantBlocks(parts:)`：`isReasoning` part 跳过（走 thinking block 渲染），`isText` part 走 `markdownText`。
- `markdownText` → `shouldRenderMarkdown` / `hasMarkdownSyntax`：对纯空白文本（trimmed 为空）返回 false，落到原生 `Text(text)`。
- 原生 `Text` 把每个 `\n` 渲染成可见空行 → 用户看到“一堆回车”。
- text part 里泄漏的 `<think> / </think>` 标签按字面文本渲染出来。

### 4. SGLang reasoning parser 交叉验证（2026-08-23，SGLang 源码 `none:~/co/llm_serving`）

运行中的 SGLang 端点 `none.tail63c3c5.ts.net:8002` 的启动参数（`serve_llm.sh`，进程实测一致）：`--reasoning-parser qwen3 --tool-call-parser qwen3_coder --speculative-algorithm DFLASH --speculative-num-draft-tokens 8`。

`vendor/sglang/python/sglang/srt/parser/reasoning_parser.py` 里 `Qwen3Detector`（:355）继承 `BaseReasoningFormatDetector`（:62），流式状态机是**一次性**的：

- :206-211：`stripped_think_start` 一次性标记，只剥第一个 `<think>`；
- :214-225：遇到的**第一个** `</think>` 永久关闭 reasoning（:220 `_in_reasoning = False`，之后不再回 True）；
- :260-263：退出 reasoning 后所有内容一律按 `normal_text` 原样透传——包括字面的 `<think>` / `</think>`。

OpenAI-compatible 端点（`serving_chat.py` :222-238 构造 `ReasoningParser`，:738 / :1923 输出 `reasoning_content`）把 `reasoning_text` 映射到 `reasoning_content`（OpenCode 存为 reasoning part），`normal_text` 映射到 `content`（OpenCode 存为 text part）。

数据交叉验证（当前 session 189 条 assistant 消息）：

- 189 条消息的 part 序列清一色 `step-start / reasoning / text / step-finish / tool...`——每条消息恰好 1 个 reasoning part + 1 个 text part；
- 189 条 reasoning part 里 0 条含字面 think 标签；62 条 text part（33%）含标签，其中 61 条含至少一个**独立成行**（代码围栏外）的 `</think>`；
- **决定性证据**：含泄漏 text part 的消息，其 reasoning part 在句中截断，text part 恰好从同一句话的后半句接续。例：某条 reasoning part 以 “...thought output uses `” 结尾（句中截断，反引号未闭合），同消息 text part 以 “` tags. In OpenCode, reasoning parts are separated...” 开头——同一句被 SGLang 从中切开。

机制闭环：模型在自己的 thinking 里输出字面 `</think>`（本 session 是排查 think 标签 bug，模型思考中反复讨论 / 复述这些标签），SGLang 状态机把 thinking 里的字面 `</think>` 当成真结束符 → reasoning 提前收尾 → 剩余 thinking + 真 `</think>` 全部泄漏进 content 流 → OpenCode 原样存成 text part → iOS 原样渲染。干净 session（思考中不出现字面 `</think>`）0 泄漏；本 session 33% 泄漏，与“思考中写字面 `</think>` 的概率”直接相关。SGLang 的 tokenizer 层无法区分“模型把标签当文本输出”和“模型结束思考”，歧义只能在客户端归一化层消化——修 iOS 渲染层位置正确。

“response 从 code block 开始”观察的数据核验：189 条 text part 里 raw 以 ``` 开头的只有 1 条，模拟第二批剥离后 0 条——说明这主要是 qwen38 的输出风格偏好（爱用代码开头），不是边界 bug；但泄漏的 thinking 尾巴常含代码片段，在 iOS 上确实会造成“回复以代码开头”的观感。

## 根因

iOS 客户端没有像 Web / Android 那样对 text part 做归一化，具体：

1. **纯空白 text part 走原生 `Text`（主因）**：`hasMarkdownSyntax` 对 trimmed 为空的文本返回 false，落到原生 `Text`，每个 `\n` 渲染成可见空行。
2. **泄漏的 thinking 内容按字面渲染（次要、session 特有）**：text part 里泄漏的 thinking 内容与字面 `<think> / </think>` 没有处理，直接显示（SGLang 侧机制见排查过程 §4）。

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

已知缺口（独立评审指出，未修）：

- `copyableText` 只滤 `isEmpty`：`"\n\n\n"` 会留下来再被 `"\n\n"` 拼接，复制 / 划词选择仍是一堆空行。
- `selectionText` / 选择文本 sheet 也没做同样过滤。
- 用户气泡对每个 text part 都加 padding：空 part 变 `EmptyView` 后仍可能留下最多 20pt 空白（助手路径已跳过，用户路径没有）。
- `StreamingReasoningView` 仍是原文 `Text`：reasoning part 目前不含 think 标签，但以后若泄漏会打在思考条上。

### 第二批：剥离泄漏的 thinking 内容（已完成 2026-08-23，方案经 Grok 评审修订）

方案演化：原计划“剥完整块 + 只保留最后一个 `</think>` 之后的内容”→ 独立评审改为 DOMPurify 式“只剥标签、保留 inner text”→ 2026-08-23 与用户讨论后再次修正重点：

**用户关心的不是“字面标签可见”，而是“thinking 内容出现在回复正文里”。** 本来该显示在思考块里的内容泄漏进 text part 后被当成正文展示，才是核心问题。DOMPurify 式“剥标签保内容”会把泄漏的 thinking 内容留在正文里，解决不了核心问题；而“正在讨论这些标签”的正常回复不是用户的 concern。因此方案改为**从 assistant text part 里删除泄漏的 thinking 内容**（不只是剥标签）：

- 抽 `static func normalizedText(_:)`（可单测），只作用于 **assistant text part**；用户消息绝不改动（用户自己讨论标签时必须原样保留——本 session 用户消息里的字面 `</think>` 就是现成例子）：
  1. 逐行识别代码围栏（``` 或 ~~~，行首允许至多 3 个空格；开围栏行可带 info string，闭围栏行必须是纯围栏字符且长度不小于开围栏）；围栏内（含围栏行本身）的标签一律不动——server 侧 parser 对 code fence 零感知，客户端归一化必须自己懂围栏；
  2. 删 thinking 尾巴（主规则，**先执行**）：若有独立成行的 </think>（围栏外），从文本开头切到**最后一个**这样的 closing tag（含）——SGLang 只在 reasoning 期内认第一个 close（`.find()`，任意位置、行内也算），模型 thinking 里的字面 close 让 reasoning 提前结束，其后剩余 thinking + 真 close 全部落在 text part；真 close 恒为 part 里最后一个独立成行的 close，真实 response（若有）在其后；切完为空则该 part 不可渲染；
  3. 删 open 尾巴：若剩余部分还有独立成行的 <think>（流式截断、其后无 close），从该行切到文本末尾；最后 trim 首尾空白。
  4. **顺序决策**（Grok 评审关键发现）：不能先删“完整 open..close 块”再切尾巴——若 thinking 尾巴里夹着字面 open 示例块且其后没有字面 close，“先删块”会把真 close 配对自己的字面 open 一起删掉，前面的泄漏 thinking 会残留正文；先切到最后一个 close 两种情形都正确，代价见“已知取舍”。
- **判别依据**：只有**独立成行**（代码围栏外）的 `<think>` / `</think>` 才被当作边界标记；行内出现的标签（通常带反引号、在讨论句子里）不动。数据核验：当前 session 62 条含标签的 text part 里 61 条至少含一个围栏外独立成行 closing tag；模拟处理后 20 条纯 thinking 尾巴 part 变空。
- `buildAssistantBlocks`：归一化后为空的 text part 跳过（扩展现有纯空白跳过；“纯 thinking 尾巴”part 不再产生空行，也不打断 tool 卡片合并）。
- `markdownText`：assistant part 走 `normalizedText` 后再渲染（user part 维持第一批的 trim）。
- `copyableText`：每 part 先过 `normalizedText`（assistant）/ trim（user），过滤归一化后为空的 part，再用 "\n\n" 拼接——修掉纯空白 part（如 "\n\n\n"）残留再拼接的缺口。
- `selectionText` / 选择 sheet：输入即 `copyableText`，随 copy 构造上修好，函数本身不用改。
- 用户气泡 padding 缺口（任务项 3）：`userMessageView` 的 ForEach 只遍历通过 `isRenderableText` 的 text part，空 part 不再产生 20pt padding 框。
- `StreamingReasoningView`（任务项 4，仅记录）：reasoning part 当前 0/189 含 think 标签（已验证）；若将来泄漏进 reasoning 通道，会显示在思考条上——可接受，思考条本来就是 thinking 内容的展示位；真需要时再复用 `normalizedText`。

待补测试（沿用 `MessageRenderingHeuristicTests` 风格；Swift 里的标签常量用 "\u{3C}think\u{3E}" / "\u{3C}/think\u{3E}" 构造）：

- 完整 thinking 块删除（open 行 + 内容 + close 行 + 真实 response → 只留 response）
- 纯 thinking 尾巴 part → 空字符串
- thinking 尾巴 + 尾部真实 response → 只留 response
- 行内标签（反引号 / 句中）不动
- 代码围栏内标签不动
- 尾巴内含字面 open/close 示例块 → 仍只留最后一个 close 之后内容（顺序回归）
- `copyableText` 归一化（空白 part + thinking 尾巴 part + 真实 part → 无多余空行、无 thinking 内容）
- `copyableText` 不修改用户消息
- `buildAssistantBlocks` 跳过“纯 thinking 尾巴”part 且 tool 合并保持

已知取舍（顺序决策的代价）：模型若在普通回复里用**独立成行**的标签引用示例 thinking 块（且不在代码围栏里），从文本开头到该示例 close 的全部内容（含示例前文）会被切掉。用户已明确该 case 不在 concern 范围；代码围栏里的示例不受影响。

另一个残余 case：若 thinking 里的字面 close 是**行内**（非独立成行）且其后没有任何独立成行 close（当前 session 62 条含标签 text part 中仅 1 条如此），text part 里就没有可识别的切分边界，泄漏的 thinking 会原样保留。Web 端同样不具备这个识别能力（表现一致），没有可靠信号可切，接受不修。
### 第三批：模拟器实证渲染路径（暂停，仅本次排查用）

- `AppState+Messages.swift` 的 `loadMessages` 加 `render-part` debug log：每条 assistant 消息的每个 text / reasoning part 打 `type`（server 原始类型）、`isReasoning` / `isText`（app 分类）、换行可视化的内容预览（前 160 字符）。
  - 选在 loadMessages 而不是 view：view body 每次 render pass 都会重算（日志会刷屏），loadMessages 每次拉取只跑一次，且是 raw server 数据落地的第一现场。
- 已 build + install 到 booted simulator（iPhone 17 Pro `8625CF87-A59C-474D-9658-DDFFFA707323`，iOS 26.3）。
- **该 log 不进正式 PR**：正文 preview 是 `privacy: .public`，且只覆盖 `loadMessages`、不覆盖 SSE 流式路径。若长期保留需脱敏 preview 并覆盖 SSE。
- 未做：seed 模拟器 credential（UserDefaults `serverURL` / `username` 已写入；Keychain password 待写——simulator 内没有 `security` 二进制，spawn 自定义 binary 也失败，需要换 seed 方式），然后 deep link `opencode://session/ses_fcfbd043bffe417xHHYrV0gw37` 抓 os_log。

## 独立评审（Grok，2026-08-23）

- 结论：多余空行根因成立（iOS 缺归一化，该修 iOS）；但"think 标签也是系统性 iOS bug"说重了——干净 qwen38 session 里 0 条 think 标签。
- 第一批 fix verdict：正确但不完整（缺口见上）。trim 只去 part 两端空白，不碰中间段落，误伤面很小；Web 的 `.trim()` 行为一致。
- think 标签处理：推荐"只剥标签、保留 inner text"（DOMPurify 式），渲染和 copy 共用 `normalizedText`；不做"截到最后一个 close tag"。
- 证据：live API 206 条消息（assistant text 185 条：99.5% 前导 `\n`、38.9% 纯空白、58 条含 think；reasoning 185 条 0 条 think）；干净 session `ses_fcfbff756ffe` 0 条 think；Web `message-part-text.ts:2` / `message-part.tsx:717` / `markdown-cache.tsx` DOMPurify；Android `ChatMessageContent.kt:436,776`。

## 为什么在客户端修

- 同一份 server 数据，Web / Android 都渲染正常，说明数据本身可被正确渲染，问题在 iOS 渲染层，不在 server / 模型。
- 客户端归一化是幂等的：对其他模型（本来没有这些换行 / 标签）无副作用。
- 不动 server、不动模型，影响面最小，且与 Web / Android 行为对齐。

## 关键坐标

- 分支：`fix/whitespace-text-parts`（`7382991` 空白过滤 + trim；`24f5c36` debug log——不进 PR；`fcef352` 本文档）
- 目标 session：`ses_fcfbd043bffe417xHHYrV0gw37`（活跃，计数为移动目标）
- API：`http://127.0.0.1:4096`，Basic auth `opencode` / `OPENCODE_PASSWORD`（workspace `.env`）
- 模拟器：iPhone 17 Pro `8625CF87-A59C-474D-9658-DDFFFA707323`（iOS 26.3，booted）
- bundle id：`com.grapeot.OpenCodeClient`
- 构建约束：`xcodebuild build` 与 `test` 必须串行（共享 build.db）；全量 test 10–20 分钟，定向用 `-only-testing:OpenCodeClientTests/MessageRenderingHeuristicTests`
