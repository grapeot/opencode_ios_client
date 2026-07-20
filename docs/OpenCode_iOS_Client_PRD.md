# OpenCode iOS Client — Product Requirements Document

> Version 0.4 · Working Draft · Jul 2026

## 1. 产品定位

OpenCode iOS Client 是一个面向 OpenCode 服务端的原生 iOS 远程控制应用。它不是一个独立的 AI 编程工具，而是运行在 Mac/Server 上的 OpenCode 实例的**移动端延伸**——让用户可以在沙发上、通勤中或任何远离电脑的场景下，发送指令、监控 AI 工作进度、浏览代码变更、切换模型。

核心设计原则：**轻量、快速、以阅读和交互为主**。所有繁重的配置（Provider 密钥、MCP 服务、workspace 设置）都在电脑端完成，iOS 端只做必要的交互和消费。

但比技术架构更根本的，是这个 App 要解决的核心交互问题：**如何让 AI 把它做出的最关键决策浮出水面，供人类审查，并在必要时通过语音快速介入纠正**——我们把这个模式叫做 **Steer（统领）**。AI 负责执行和探索，人类负责判断和方向。App 的价值不只是在"看一眼 AI 在干嘛"的监控，更在于它是一个轻量的**决策审查与方向控制终端**——用户每次打开都在阅读 Markdown 报告、查看嵌入的截图和产物、通过语音下达新的方向性指令。它不是浏览工具，是统领工具。

围绕 Steer 这个范式，App 把重心放在了三个交互载体上：**Markdown 对话窗口**（AI 向人类汇报和展示产物的主要途径）、**文件卡片预览**（快速查看 AI 修改了什么，以文档而非代码为主）、**语音输入**（用户在远离键盘时仍能高效下达方向性指令）。代码语法高亮不是优先级——因为用户要审的不是代码本身，而是 AI 做决策的理由和结果。

### 1.1 它不是什么

这个 App 不试图做以下事情：在手机上编辑代码、在手机上运行 OpenCode server、替代完整的 Web UI。它的价值在于"AI 在干活的任何时刻掏出手机，阅读它刚刚完成的 Markdown 分析报告或者代码改动，觉得方向不对就立刻通过语音让它换一条路"这种场景。

### 1.2 核心交互范式

#### Steer 范式

App 围绕"统领"的认知闭环来设计交互：

1. **Surface**——AI 通过 Markdown 窗口向人类展示它正在做的决策、读到的代码、跑过的命令、分析和结论。文本是自然语言 Markdown，可以嵌入截图（如部署结果、图表、UI diff），而不是纯代码。这是 AI 与人之间的主要信息通道。
2. **Review**——人类阅读 Markdown，审查看法对不对、方向偏不偏。大多数内容是文档、分析、调研，天然适合 Markdown 呈现；偶尔需要看代码 diff 确认细节。人类在这个环节是在做判断，不是在写代码。
3. **Steer**——发现方向偏了，通过语音快速下达纠偏指令（"停，不要用继承，换成组合模式"），或者切换模型/Agent 重新开始。指令以自然语言下达，不需要打字。

这个循环在两端都是异步的：AI 在电脑上跑，人类在手机上审。两边的节奏不需要同步——这是移动端相对于桌面端的独特优势。但也因此引入了一个真实痛点：当 AI 停下来等人类决定时（如 `question` tool），人类目前收不到任何通知，双方都在空转。这个问题的解决方案不在 UX 设计层面，而在 iOS 工程层面——需要 push notification 或 Live Activity。

#### Markdown 作为交互窗口

Markdown 是这个 App 里 AI 与人类交互的**主要信息媒介**。这不是一个"顺便支持 Markdown"的代码编辑器，而是一个把 Markdown 阅览体验做到极致的统领终端。具体体现：

- **不强调代码语法高亮**，强调 Markdown 渲染质量（标题层级、列表、链接、代码块、图片嵌入）。用户要审的是 AI 的思考过程和产出物，不是代码的美学。
- **完善的图片嵌入支持**：AI 可以截取部署结果的截图、生成图表、拍摄 UI 对比图，嵌入 Markdown 报告中。App 有专门的 Skill 体系教 AI 如何使用这些能力。相对路径图片在 Files 预览和 Chat 渲染中行为一致。
- **内容形态不限于编程**：AI 产出的可以是代码 diff，也可以是调研文章、分析报告、系统设计文档。Markdown 天然兼容所有这些形态。

#### 文件卡片预览（非代码编辑器）

文件浏览的核心不是"在手机上写代码"，而是**快速确认 AI 的改动**。用户绝大部分情况下通过 Chat 窗口中的 tool/patch 卡片直接跳转到文件预览来看改动——Files Tab 是一个兜底入口，不是主工作流。当用户在 Chat 里看到 `edit_file` 卡片，点一下卡片上的文件路径就进入预览，不需要切到 Files Tab 去翻目录树。

文档 diff 的重要性远高于代码 diff：AI 能力已足够写出好代码，人类需要审查的主要是文档层面的逻辑和架构决策。

这个 App 不试图做以下事情：在手机上编辑代码、在手机上运行 OpenCode server、替代完整的 Web UI。它的价值在于"随时掏出手机看一眼 AI 干到哪了，必要时踢它一脚让它换个方向"这种场景。

## 2. 目标用户与使用场景

目标用户是日常使用 OpenCode 的开发者（初期就是作者自己）。需要理解的关键一点是：重度用户打开 App 并不是为了"瞄一眼状态"——每次打开都是重量级交互：阅读 Markdown 报告、通过语音与 AI 对话、在 Session 之间频繁切换来追踪不同任务。App 的价值在于让用户在离开电脑时保持对 AI 工作的判断力和控制力，不是一个 status checker。

**场景 A — 远程监控与审阅**：在电脑上启动了一个耗时的重构任务，离开工位。掏出手机，不仅看 AI 处理了多少文件，更是阅读 AI 刚生成的 Markdown 分析报告——它在解释每个改动的理由，附带架构图截图。用户的实质操作是：仔细阅读报告、点开文件卡片看具体改动、确认方向正确。

**场景 B — 快速纠偏（语音驱动）**：手机上看到 AI 走偏了，正在用错误的方法实现某个功能。通过语音输入快速下达指令："停，不要用继承，改用组合模式"，然后放回口袋。语音输入在这个场景下的核心价值是避免手机打字的不便，让方向控制尽可能低摩擦。

**场景 C — 模型 A/B 测试**：想比较不同模型（如 GPT-5.3 Codex / DeepSeek / Opus / GLM）对同一个任务的表现。在手机上一键切到另一个模型，发送相同的指令，观察差异。这种场景也涉及 Fork Session——从同一个对话节点分叉出不同模型的尝试。

**场景 D — 文档审查**：AI 完成了一轮修改，在手机上浏览 Markdown 文档的 diff，以 Preview 模式为主查看变更，确认文档改动合理后让 AI 继续下一步。代码审查为辅——AI 能力已足够写出好代码，人类需要审查的主要是文档层面的逻辑和架构决策。内容不限于编程：AI 产出的可能是调研报告、系统设计文档、部署结果展示，这些天然是 Markdown 形态。

### 2.0 重度用户的时间分布

理解重度用户实际花时间的地方，对于把握产品方向至关重要：

- **约 60% 的时间在阅读 Markdown**——AI 的分析报告、调研文章、设计文档、带有嵌入式截图的部署结果。这是"审"的环节。
- **约 25% 的时间在与 AI 对话**——通过语音下达新指令、纠正方向、追问细节。这是"领"的环节。
- **约 10% 的时间在 Session 间切换**——追踪不同项目、不同方向的进展，判断哪个需要介入。这是"多线统领"。
- **约 5% 的时间在 Files Tab**——它本质上是一个兜底入口，绝大部分文件访问都是通过 Chat 窗口中的 tool/patch 卡片跳转完成的。

基于这个时间分布，产品优化的优先级应该是：Markdown 渲染质量 > 语音输入流畅度 > Session 辨识度 > 文件树功能。

### 2.1 分发方式

为了降低试用门槛，产品同时支持两种分发路径：

- **TestFlight**：面向大多数用户，直接安装即可，不要求 Apple Developer account
- **源码构建**：面向需要本地改代码、调试或自定义签名的开发者

README 负责承载最新安装入口，PRD 只保留产品层面的分发策略。

## 3. 技术架构

### 3.1 整体架构

```
┌──────────────┐         HTTP REST + SSE         ┌──────────────────┐
│              │ ◄──────────────────────────────► │                  │
│  iOS Client  │    局域网 / Tailscale / etc.     │  OpenCode Server │
│  (SwiftUI)   │                                  │  (Mac/Linux)     │
│              │                                  │                  │
└──────────────┘                                  └──────────────────┘
     纯展示 + 指令发送                              文件系统 + AI 计算
```

iOS 端是纯粹的 API 消费者。不需要任何本地 AI 推理、文件系统访问或 shell 执行能力。所有数据通过 OpenCode 的 HTTP API 获取，实时更新通过 SSE（Server-Sent Events）推送。

### 3.2 技术选型

| 层面 | 选择 | 理由 |
|------|------|------|
| UI 框架 | SwiftUI | 原生体验、流畅动画、iOS 特性利用最充分 |
| 网络层 | URLSession + 原生 SSE | 无需引入第三方 HTTP 库，SSE 协议本身很简单 |
| 状态管理 | Swift Observation (@Observable) | iOS 17+ 原生方案，配合 SwiftUI 最简洁 |
| 代码高亮 | 暂不实现 | 当前仅等宽字体、行号 |
| Markdown 渲染 | MarkdownUI + 自定义图片解析 | 文档预览、支持代码块，并支持 repo 内相对图片 |
| Diff 渲染 | 自建组件 (基于服务端返回的 before/after) | 服务端已经做了 diff 计算，客户端只需渲染；文档 diff 需高亮 changes |
| 最低版本 | iOS 17.0 | 使用 Observation 框架，放弃 iOS 16 |
| 持久化 | UserDefaults + Keychain | 只需存连接信息和模型预设，无需本地数据库 |

### 3.3 与 OpenCode Server 的通信

通信基于两个通道：

**REST API** — 用于所有主动操作（发消息、获取文件列表、切换配置等）。基础路径由用户在 Settings 中配置的 `http://<ip>:<port>` 决定。

**SSE (Server-Sent Events)** — 用于实时更新。连接到 `GET /global/event` 端点，接收所有事件推送。事件格式为 `{ directory, payload: { type, properties } }`。

SSE 连接的生命周期管理是一个关键技术点：
- App 进入前台时建立/恢复 SSE 连接
- App 进入后台时断开 SSE 连接（iOS 不适合维持长连接）
- 从后台恢复时，先通过 REST API 拉取当前状态做一次全量同步，再重新建立 SSE

### 3.4 认证

OpenCode Server 支持可选的 Basic Auth（`OPENCODE_SERVER_PASSWORD`）。iOS 端在 Settings 中提供用户名/密码字段，存入 Keychain。每个 REST 请求和 SSE 连接都带上 Basic Auth header。

## 4. 功能规格

### 4.1 布局结构

#### 4.1.1 iPhone：Tab Bar

iPhone 采用底部 Tab Bar，三个 Tab：

```
┌─────────────────────────────────────┐
│                                     │
│          (Tab Content Area)         │
│                                     │
├───────────┬───────────┬─────────────┤
│   💬 Chat  │  📁 Files  │  ⚙ Settings │
└───────────┴───────────┴─────────────┘
```

#### 4.1.2 iPad / Vision Pro：Split View（无 Tab）

在 iPad 和 Apple Vision Pro 上，**不显示 Tab Bar**，采用三栏布局（Workspace / Preview / Chat）：

```
┌──────────────────────────────────────────────────────────────────────────────────────────────┐
│ [新建] [重命名] [Session 列表]        [GPT] [Spark] [Opus] [GLM] [◔] [⚙]                        │  ← 第一行：Session 操作 + 模型 + Context 使用量 + Settings
├──────────────────────────────┬───────────────────────────────┬───────────────────────────────┤
│                              │                               │                               │
│     🧭 Workspace             │         📄 Preview             │           💬 Chat              │
│     （Files + Sessions）      │         （文件预览）             │           （消息流 + 输入）      │
│                              │                               │                               │
│  文件树（上）                 │  文件内容 / Markdown 预览       │  消息流 + 输入框                │
│  Sessions（下）              │  右上角刷新按钮                 │                               │
│                              │                               │                               │
└──────────────────────────────┴───────────────────────────────┴───────────────────────────────┘
```

**设计要点**：
- **左栏**：Workspace（文件树 + Sessions 列表）
- **中栏**：Preview（文件内容、Markdown 预览，可手动刷新）
- **右栏**：Chat（消息流、输入框、与 iPhone 一致）
- **宽度比例**：Workspace ≈ 1/6；Preview ≈ 5/12；Chat ≈ 5/12（Preview 与 Chat 等宽）
- **可拖动**：用户可拖动分隔条调整三栏宽度；默认值采用上述比例
- **Settings**：作为独立按钮加入第一行 toolbar（与 Session 操作、模型切换并列），点击以 sheet 或 navigation push 打开
- **优势**：大屏上 Chat 与 Preview 并排，文件预览无需弹窗；Workspace 与 Sessions 保持在左侧不干扰阅读

### 4.2 Chat Tab（主交互界面）

这是 App 的核心。顶部是模型与 Agent 选择器，中间是消息流，底部是输入框。

#### 4.2.1 模型与 Agent 选择器

位于 Chat 页面顶部的右侧 toolbar 区域。采用**下拉列表**（Menu + Picker）形式，取代原有的 chip 横向滚动条。

**模型选择器**：下拉列表，包含以下固定选项：

| 显示名称 | providerID | modelID |
|----------|------------|---------|
| GLM-5.1 | `zai-coding-plan` | `glm-5.1` |
| GPT-5.4 | `openai` | `gpt-5.4` |
| GPT-5.3 Codex | `openai` | `gpt-5.3-codex` |
| DeepSeek | `deepseek` | `deepseek-v4-pro` |

**Agent 选择器**：下拉列表，内容从 `GET /agent` API 动态获取。过滤 `hidden != true` 的 agents 后显示。每个选项显示 agent 名称（如 `Sisyphus`），description 可作为 tooltip 或 subtitle。

**iPhone 显示策略**：iPhone 上使用短名（`DeepSeek` / `GPT` / `GLM`）以适配窄宽；iPad 上显示全称。

**技术实现**：
- 切换模型/Agent 不需要调用 API，只是改变本地状态
- 发送消息时在 `POST /session/:id/prompt_async` 的 body 中携带：
  - `model: { providerID, modelID }` 字段
  - `agent: string` 字段（agent 名称）
- 模型和 Agent 选择均按 Session 记忆，切换 Session 时自动恢复

#### 4.2.1.1 Context Usage（上下文占用）指示器

在 Chat 顶部右侧（Agent 选择器与齿轮之间）显示一个**环形进度**，表示当前 session 最近一次生成时的上下文窗口占用情况。

- **数据来源**：`GET /session/:id/message` 返回的 assistant message `info.tokens.total`（以及 input/output/reasoning/cache），并结合 `GET /config/providers` 中该 `providerID/modelID` 的 `limit.context`。
- **Provider Config 加载**：`GET /config/providers` 结果会缓存；若未加载/为空，点击 ring 时应自动触发加载并显示 loading；失败时在 sheet 中展示错误信息，而不是只显示 “Provider config not loaded”。
- **无数据时**：显示灰色空环（不显示数值），点击可打开详情但内容显示 "No usage data"。
- **颜色策略**：< 70% 正常色；70-90% 警告色；> 90% 危险色（避免用户在 iOS 端“盲发”导致 token 超限）。
- **点击交互**：点击环形进度弹出一个 sheet（iPhone/iPad 都可用），展示：
  - Session（title/id，可复制）
  - provider/model
  - context limit
  - total tokens + usage %
  - input/output/reasoning/cache read/cache write
  - total cost（如 server 返回 message cost；若缺失则隐藏）

注：初期不展示 raw messages；context breakdown（system/user/assistant/tool 占比）仅在 server 暴露对应数据或可稳定推导时再做。

- **AI 响应期间可见性**：context ring 在任何状态（idle / busy / streaming）下始终显示，不被 spinner 或其它控件替代。busy 状态由输入栏红色停止按钮传达，toolbar 不再注入额外 `ProgressView`。

#### 4.2.2 消息流

垂直滚动的消息列表，样式参考 OpenCode Web 客户端：**不采用左右气泡**，所有消息统一流式排布，人类消息用灰色背景区分。整体风格类似 OpenCode 的紧凑对话流。

每条消息包含：

**用户消息**：灰色背景，显示文本内容。底部小字标注使用的模型。

**AI 消息**：白色/透明背景，包含多种 Part 类型的渲染：
- `text` — Markdown 渲染（支持代码块、链接、列表等）
- `reasoning` — 折叠面板，标题 "Thinking..."，点击展开查看推理过程
- `tool` — 工具调用卡片，显示工具名称和状态（pending → running → completed/error）。**running 时展开**显示进度（spinner），**completed 时默认收起**，可点击展开查看元数据（如文件路径、命令输出）
- `tool`（todowrite）— 渲染为 Task List（todo）卡片：展示条目列表与完成进度（completed/total）；todo 的全量内容可来自 tool 输入/metadata，且会通过 SSE `todo.updated` 事件更新。**仅在各 tool 卡片内展示，不在 Chat 顶部常驻（方案 B）**
- `step-start` / `step-finish` — 渲染为步骤分隔线，显示 token 用量和成本
- `patch` — 文件变更摘要卡片，显示修改的文件列表，点击可跳转到 Files Tab 的 File Tree 中打开该文件预览
- `tool`（write/edit/apply_patch/read_file 等）— 若 part 含文件路径（metadata.path、state.input.path、files 数组、或 patchText 解析），点击可弹出选项「在 File Tree 中打开」，直接打开文件预览；若目标是图像文件且 tool output 可解码，则直接显示内联缩略图并支持展开查看

**大屏布局（iPad / Vision Pro）补充**：为了利用横向空间，`tool` / `patch` / permission 卡片可采用 **三列网格**横向填充（不足自动换行）；但 `text`（最终回答）仍按整行展示，避免阅读断裂。

**流式更新（Think Streaming）**：行为与官方 Web 客户端对齐。SSE 推送 `message.part.updated` 时，若有 `delta` 字段，客户端增量追加到对应 text/reasoning Part，实现打字机效果；若无 delta 则全量 reload。使用 `messageID` + `partID` 定位 Part。**注**：Tool output 的实时流式（如 terminal 输出逐行）当前 API 不支持，output 仅在 completed 时一次性返回。

**自动滚动规则**：只有当用户当前停留在消息流底部附近时，新的 streaming 文本、tool 卡片、permission card、question card 或 activity row 才会继续带着视图往下滚；如果用户已经向上翻看历史内容，则停止自动跟随，避免阅读被打断。

**历史消息分页加载**：为降低长会话在弱网（如 SSH tunnel / WAN）下的首屏等待，默认只拉取最近 **3 轮对话**（6 条 message：user/assistant 各 3 条）。聊天页顶部显示“下拉加载更多历史消息”，用户每次下拉再向上扩展 3 轮并重新拉取。

**Activity Row 一致性规则**：运行态优先级高于 `session.status=idle` 的瞬时抖动。若仍存在 running/pending tool 或 streaming 增量，Activity Row 必须保持 running；仅在确认本轮 assistant 已完成后才进入 completed。

**Session 状态指示器**：消息流顶部显示当前 session 状态（idle / busy / error）。状态来源于 `session.status` SSE 事件。busy 时显示进度动画。

#### 4.2.3 权限通知

OpenCode 绝大多数情况下不会请求 permission，若出现 `permission.asked` 事件，通常说明有异常情况。因此采用**手动批准**模式：

- 监听 SSE 的 `permission.asked` 事件
- 在消息流中插入权限请求卡片，显示待批准的操作（如 "执行 `rm -rf node_modules`"）
- 用户需手动点击「批准」或「拒绝」，调用 `POST /session/:id/permissions/:permissionID` 响应
- 不提供自动批准

#### 4.2.3.1 Question 卡片

当服务端通过 `question` tool 主动向用户发起问题时，Chat 流中插入 question card，而不是让 session 卡死等待。

- 监听 SSE：`question.asked`、`question.replied`、`question.rejected`
- 启动时通过 `GET /question` 拉取当前 session 的 pending questions
- 用户可选择单选/多选选项，也可填写自定义文本
- 回答调用 `POST /question/{requestID}/reply`
- 拒绝调用 `POST /question/{requestID}/reject`

#### 4.2.4 Composer：voice rail + text review field

底部固定 composer 采用两行结构：上方是 voice rail，下方是 text review field。Session 操作（新建、重命名、列表、Compact）在 Chat 顶部 toolbar，不进入 composer。

这条结构来自 Steer 产品定位：用户在手机上最常做的不是长篇打字，而是阅读 AI 输出后用语音快速补一条方向性指令。语音是主输入模态，文本框承担转写审阅、轻量修正和 fallback 打字。composer 因此不把麦克风做成输入框里的附属按钮，而把 voice rail 放在第一行作为主控面。

**草稿持久化（Draft Persistence）**：未发送的输入内容按 sessionID 保存（本地持久化），切换到其他 session 再切回时仍可恢复；发送成功后清空草稿。

**Voice rail（Speech Recognition）**：voice rail 位于文本框上方，由左侧 transport、中央 waveform/status、右侧轻量恢复动作组成。点击 transport 开始录音时创建 VoiceFlowKit realtime session，并用 `AVAudioEngine` 采集 PCM16 mono 24kHz 音频。录音中，中央 waveform 消费 `VoiceFlowMicrophone.audioLevel` 的真实 0..1 smoothed mic level，让用户能看出 App 正在采集声音。再次点击 transport 是正常结束采集并进入转写，不等同于 agent abort。

VoiceFlowKit 一边发送 live PCM，一边把同一份 PCM 追加写入内部临时 `.pcm` 文件；若 heartbeat 或 live send 发现 WebSocket 断开，Kit 不中断录音，而是新建 session 并从本地缓存重放完整 PCM，追上当前录音后继续 live 发送。停止录音时等待恢复完成后发送 `commit` / `stop`，将 transcript 追加到 text review field。

转写等待或卡住时，voice rail 显示 processing waveform 和明确的恢复动作，例如 `Stop transcription wait`。这个动作调用 `abortPreservingAudio()` 关闭 WebSocket/finalize 等待并保留已录 PCM；随后 rail 进入 preserved-audio 状态，左侧 transport 变为 `Retry this segment` 图标按钮，调用 `transcribe(preservedAudio:)` 重新识别同一段音频；右侧轻量动作变为 `Discard audio`，用于放弃这段已保存音频并回到正常输入。retry 是重转同一段已保存音频，不是续录，也不要求用户重新说。retry 失败后保留 preserved audio，用户可以继续 retry，也可以 discard 退出恢复状态。

**Text review field**：下方文本框支持多行文本，承接转写结果、人工修正和 fallback 打字。录音状态下 placeholder 表达“转写会出现在这里”，避免在 voice rail/status row 已显示 Listening 时重复同一状态。语音转写或 preserved-audio retry 流式返回 partial transcript 时，文本框自动滚到末尾，让用户看到最新转写内容逐步出现；普通手动输入和草稿恢复不强制滚动。发送按钮固定在文本框右侧；即使 session busy 也保留，因为 `prompt_async` 支持服务端排队。

**Agent interrupt**：agent 运行状态用 composer 附近的低权重状态行表达，例如 `Agent running`。`Interrupt agent` 是低频逃生口，放在 `⋯` 菜单里调用 `POST /session/:id/abort`，不做成顶部红色 banner，也不和语音转写恢复共用同一个 stop 图标。这样用户能区分三个对象：语音采集、转写等待、agent 运行。Token 和 Base URL 在 Settings → Speech Recognition 配置，存 Keychain，不提交到 git。

**消息队列**：当 session 处于 busy 状态时，用户发送的消息进入队列。OpenCode Server 的 `POST /session/:id/prompt_async` 在服务端已支持队列——busy 时会将消息入队，当前运行结束后自动处理。iOS 端调用 `prompt_async` 即可，无需本地维护队列。若未来 API 变更，可退化为本地队列维护。

**Enter 行为调研结论**：OpenCode Web 客户端在空输入时按 Enter 会调用 abort 终止当前运行；有内容时按 Enter 发送消息（通过 prompt，消息由服务端队列处理）。无「智能 steer」机制，仅终止或排队。iOS 端可提供手动 abort 按钮，无需实现额外 steer。

额外操作（通过 Chat 顶部 toolbar 按钮，从左到右依次为）：
- Session 列表、重命名、Compact、新建 Session（按此顺序排列）
- Compact Session（调用 `POST /session/:id/summarize`，压缩历史以降低 token 超限风险）（🔲 暂未实现）

#### 4.2.5 Session 管理

从 Chat Tab 顶部左侧的按钮进入 Session 列表（slide-over 或 navigation push）。**列出 workspace 下所有已有 Session**，是重要的功能验证手段：可验证连接是否正确、API 解析是否正常、消息/状态能否正确展示。

在 iPhone 上，除顶部 `Session 列表` 按钮外，还支持从屏幕左边缘向右滑入的手势来打开同一个 Session List。这个手势的目标不是提供新的导航分支，而是复用现有列表入口，降低单手操作时点按左上角按钮的成本。

Session List 是当前工作集的管理面板，而不是单纯历史列表。默认显示 Active sessions，按更新时间倒序；Archived sessions 作为同一列表内的独立折叠分区存在，不要求用户进入 Settings 才能找回。iPhone 的 Session sheet 和 iPad / Vision Pro 的左 sidebar 都采用 Active 分区 + Archived 分区，两个分区独立展开/折叠。本轮不提供 session search，避免本地 title filter 被误解为全量历史搜索。

每个条目显示：标题、更新时间、`summary.files`（该 session diff 涉及文件数）和状态（idle/busy/retry）。Active session 支持新建、切换、归档和删除。Archived session 支持切换查看、恢复和删除。Archive / Restore / Delete 都通过 swipe action 暴露，按钮样式沿用当前实现：SF Symbol 图标在上、文字在下。Delete 始终位于 trailing swipe，红色破坏性样式；Archive / Restore 始终位于 leading swipe，使用克制的电蓝/中性色。所有 swipe action 均禁用 full swipe，避免误触。Delete 不再弹确认框；用户已经先滑动再点按钮，意图足够明确。

Archive 行为：点击 Archive 后，session 立即从 Active 分区移入 Archived 分区，当前列表不再占用扫描空间。如果被归档的 session 有子 session，客户端必须递归归档整个 subtree，并且先归档子 session、最后归档父 session，避免父 session 先隐藏后子 session 短暂变成 Active root。Restore 行为：点击 Restore 后，session 回到 Active 分区；恢复 subtree 时顺序相反，先恢复父 session、再恢复子 session，避免子 session 在父级仍 archived 时短暂游离。若用户直接打开 archived session 并继续发送消息，客户端应先恢复该 session，再发送消息，确保“继续工作”的 session 回到当前工作集。Pin 不在本阶段实现。

视觉与交互：列表文本默认使用中性色（灰）以避免 iOS 默认的"链接蓝"。当前活跃 Session 使用轻量背景色高亮，左缘嵌一条 3pt 电蓝 accent 色条（与用户消息、操作卡片同一套"左色条"语言；色条与圆角选中背景合为一体并裁切在圆角内，不外溢、不与展开 chevron/缩进冲突）。选中态不再显示额外 checkmark，避免把当前 session 误读成完成状态或多选状态。Archived rows 仍可点击查看，但视觉层级低于 Active rows：标题和时间使用更弱的中性色，不画选中 accent，避免读起来像当前工作项。

#### 4.2.6 Fork Session（会话分叉）

用户可以从任意消息处 fork 当前对话，创建一个新 session，包含该消息之前的全部历史。典型场景：AI 回复不满意，想从某个节点重新开始；或者想从同一个起点尝试不同的提问方向。

**交互方式**：每条用户消息底部的模型标签（如 `anthropic/claude-opus-4-6`）旁边显示一个 "..." 按钮。点击后弹出菜单，包含 "Fork from here" 选项。点击后调用 `POST /session/{id}/fork`，服务端创建新 session 并复制指定消息之前的全部消息历史，客户端自动切换到新创建的 session。

**API**：`POST /session/{sessionID}/fork`，body 为 `{ "messageID": "..." }`（可选）。返回新的 `Session` 对象。

**实现说明**：使用 SwiftUI `Menu`（tap 触发）而非 `.contextMenu`（需长按），确保可发现性。Fork 后的 session 标题自动变为 "{原标题} (fork #N)"。

#### 4.2.7 Session Deep Link（跨入口定位会话）

客户端支持统一的只读导航链接：

```text
opencode://session/<session_id>
```

链接可以来自 Chat 中的 Agent Markdown，也可以来自 Notes、邮件、网页或其他 App。用户点击后，客户端在当前 Host 上验证目标 session；验证成功才切换 project、session 和 Chat，失败则保留原 session 并显示全局错误。App 未运行或正在恢复连接时先保留导航意图，待当前 Host 可用后再解析。

Session 搜索仍由 Agent 和 workspace semantic-search 完成，不在客户端增加搜索页面、embedding 索引或 archive 读取能力。Agent 返回 3-5 个带原文证据的候选，并把明确动作写为 `[在 OpenCode 中打开](opencode://session/<session_id>)`；只有 metadata 明确标记为 OpenCode 且含合法 session ID 的结果才能生成 action link。

V1 的可用范围是当前配置的 Host。链接不携带设备本地 Host Profile UUID、server URL、凭证、query 或绝对路径，也不自动轮询或切换其他 Host。OpenCode 软归档 session 只要当前 server 仍可读取即可打开；仅存在于离线 SQLite/Markdown archive 的历史不自动恢复。

Deep link 是低权限导航动作，不是命令通道。它不能发送 prompt、批准权限、执行 tool、删除或归档 session，也不能在 Markdown 渲染后自动触发。V1 不支持 message 定位参数；在 Chat 具备可靠 scroll/highlight 前，带 query、fragment 或额外 path 的链接一律拒绝。

### 4.3 Files Tab（文件浏览与 Diff）

> Files Tab 在产品定位上是一个**兜底入口**，不是主工作流。用户绝大部分文件访问都是通过 Chat 窗口中的 tool/patch 卡片点击跳转完成的——在 Chat 流中看到 `edit_file` 或 `patch` 卡片，直接点文件路径就可以预览。Files Tab 的存在是为了：当用户需要全局视角（浏览所有被修改的文件）、或者需要搜索一个没在 Chat 卡片中出现过的文件时，有一个可用的入口。因此它不需要是最精致的 Tab，但它必须可靠。

#### 4.3.1 文件树

左侧（iPad）或全屏（iPhone）显示文件树。数据来源：`GET /file?path=<path>`。

文件树以递归展开/收起的形式呈现目录结构。每个节点显示文件/目录名和图标。有 git 变更的文件带有颜色标记（绿色新增、黄色修改、红色删除），数据来源于 `GET /file/status`。

支持搜索框做文件名模糊搜索（`GET /find/file?query=...`）。

#### 4.3.2 文件内容查看

点击文件后进入内容查看页面。数据来源：`GET /file/content?path=...`。

- **iPhone**：在 Files Tab 内 push 到内容页
- **iPad 三栏**：点击文件后在中栏 Preview 内联预览；Chat 中 tool/patch 点击文件同样更新 Preview（不弹 sheet）

文本文件：等宽字体代码查看器，显示行号，横向可滚动。当前不做语法高亮，以稳定性和可读性优先。

Markdown 文件：支持 Preview / Markdown source 切换。Preview 使用 MarkdownUI，超长行和大文件会自动 fallback 到原始文本，避免渲染卡死。

对于 Markdown 内的图片，客户端需要支持 **repo 内相对图片引用**，尤其是 `![x](../assets/foo.png)` 这类报告写法。图片不能依赖 MarkdownUI 默认网络加载器去猜路径，而应由客户端基于当前 markdown 文件路径和 workspace 目录解析成受控的本地文件请求，再渲染为图片。这条能力同时适用于 Files 中直接打开的 `.md` 文件，以及 Chat 中展示的 AI 生成 Markdown 报告。

图片文件：支持 base64 解码预览，初始状态为 fit-to-screen；支持 pinch、drag、double-tap zoom，以及系统 share sheet。若系统权限允许，share sheet 应支持 `Save to Photos`。

#### 4.3.3 Diff 查看与文档预览

**核心定位**：以**文档审查**为主。Markdown 渲染、文档 diff、Preview 模式是必备能力。

**Markdown 展示**：
- 优先 **Preview 模式**：用户以 Preview 为主查看文档，若实现难度大，可支持 Preview / Markdown 切换
- **Changes 高亮**：需在 diff 中高亮变更。若在 Preview 界面高亮有难度，可在 Markdown 界面高亮 changes，用户在 Preview 中查看
- 最低版本 iOS 17，无兼容顾虑

**两种入口**：

**Session Diff**：暂不在 iOS 客户端展示（server 端 diff API 在部分情况下返回空数组）。

**单文件 Diff**：在文件树中点击有变更标记的文件时，如果该文件有 uncommitted changes，内容查看页面自动切换到 diff 模式。

Diff 渲染采用 unified diff 格式（类似 GitHub），绿色背景表示新增行，红色背景表示删除行。服务端返回完整的 `before` 和 `after` 内容，客户端做 diff 计算和渲染。考虑到手机屏幕宽度，默认只提供 unified 模式，不做 side-by-side。

#### 4.3.5 Markdown Web Preview（HTML 卡片 / SVG 增强阅读）

打开 `.md` 文件时默认看到带视觉结构的预览：状态卡、SVG 图、暗色阅读都正常，工具栏可切回纯文字 Native 或源码。技术细节见 RFC §7.5。

<style>
.wp-stat{display:inline-block;border-radius:999px;padding:1px 8px;font-size:.78rem;font-weight:650}
.wp-stat.ok{background:var(--ok-bg,#d1fae5);color:var(--ok-fg,#065f46)}
.wp-stat.block{background:var(--block-bg,#e5e7eb);color:var(--block-fg,#374151)}
</style>

| 用户能体验到的 | 状态 |
|---|---|
| 工具栏一键切 Web / Native / 源码，Web 是默认 | <span class="wp-stat ok">上线</span> |
| HTML 状态卡 / 内联 SVG 正常显示 | <span class="wp-stat ok">上线</span> |
| 文档里的相对图片能加载 | <span class="wp-stat ok">上线</span> |
| 同一份文档 light / dark 模式都好读 | <span class="wp-stat ok">上线</span> |
| 切文件立刻刷新内容，大文件先弹确认 | <span class="wp-stat ok">上线</span> |
| `.html` 浏览 / Mermaid / 代码高亮 / 点图放大 | <span class="wp-stat block">下一轮</span> |

详情与来源 — 决策过程见 [`WORKING.md`](WORKING.md)；完整子项目 PRD / RFC 保留在磁盘 `docs/Markdown_Web_Preview_PRD.md` / `Markdown_Web_Preview_RFC.md`，已从 git 跟踪移除。

### 4.4 Settings Tab

#### 4.4.1 Host Profiles（多 OpenCode 环境）

Settings 顶部不再把 Server Address / SSH Tunnel 当成全局配置，而是展示当前 `Host`。这里的 Host 指一个 OpenCode 环境，可以是直连的 LAN / Tailscale / HTTPS server，也可以是通过 SSH gateway 访问的私有 OpenCode 容器。Tailscale、VPN、LAN 对 app 透明，都属于 Direct transport。

**目标**：用户在 5 秒内能知道当前连接的是哪个 OpenCode 环境、它使用 Direct 还是 SSH Tunnel，并能切换到另一个 host 而不误改底层网络字段。

**Host 列表**：

- Settings 顶部显示 Current Host 卡片：名称、transport、地址摘要、连接状态、Test 按钮。
- Current Host 卡片显示轻量连接诊断。连接中显示当前阶段；失败时显示用户能执行的错误文案，而不是 raw Swift error。
- 点击进入 Hosts 管理页，列表展示所有 profiles；当前 profile 使用左侧 accent bar + checkmark 标识。
- 每个 row 显示名称、transport 摘要、最近状态：例如 `example.com:8006 -> :19001`、`Direct HTTPS + Basic Auth`、`Last used yesterday`。没有有效连接历史时显示 `Never connected`，不能把 epoch 渲染成超长相对时间。
- 点 row 打开 Host Detail。切换 host 是详情页里的显式 `Use This Host` 动作，避免用户为了查看配置而误切换。
- 支持 Add Host、Host Detail、Edit、Duplicate、Delete。删除当前 host 前必须先切到其他 host 或显示确认。
- Device Public Key 作为设备级设置显示在 Hosts 页底部；它只用于 SSH Tunnel hosts，Direct hosts 不需要。

**Host Detail**：

- 展示 profile 名称、transport、连接摘要、当前连接诊断和最近一次连接尝试时间。
- Direct profile 展示 OpenCode URL，以及是否配置了 Basic Auth username。
- SSH Tunnel profile 展示 Gateway Host、SSH Port、SSH Username、Assigned Remote Port、本地 OpenCode URL `127.0.0.1:4096` 和 trusted host fingerprint（如果有）。
- 如果不是当前 host，提供 `Use This Host` 主操作；详情页也提供 `Test Connection`、`Edit` 和 `Copy Host Config JSON`。
- SSH Tunnel profile 在详情页提供 `Copy This Device Public Key`。私钥仍只保存在设备 Keychain，不提供导出。

**Add Host 流程**：

1. 入口优先提供 `Import Host Config`。用户可粘贴管理员给的 setup JSON，避免手动填错 host、port、username、remotePort。
2. 手动添加时先选择 `Direct` 或 `SSH Tunnel`。
3. Direct 表单只要求 Name、OpenCode URL、可选 Basic Auth。
4. SSH Tunnel 表单要求 Name、SSH Gateway Host、SSH Port、SSH Username、Assigned Remote Port。OpenCode URL 不让用户编辑，保存后由 app 使用本地 `127.0.0.1:4096` 连接 tunnel。
5. SSH Tunnel 表单必须提供 `Copy This Device Public Key`，并说明“发给 server admin，永远不要分享 private key”。
6. Test Connection 验证当前 transport：Direct 直接请求 `/global/health`；SSH 先建立 tunnel，再请求本地 OpenCode health。
7. `Save` 只表示 profile 已保存；`Test Connection` 才表示连接验证。保存成功和连接成功必须在 UI 上分开表达。

**切换行为**：

- 切换 host 时断开当前 SSH tunnel 和 SSE，再应用新 profile。
- 切换后清空当前 session selection；session/project 状态属于 host 维度，后续可增加 per-host last selected project/session。
- 如果新 host 启用 SSH，可尝试自动建立 tunnel；失败只更新连接状态，不弹出阻塞式 alert。
- Basic Auth credentials 按 profile 存 Keychain；SSH private key 默认仍是设备级同一把 key。

#### 4.4.2 Direct Transport

Direct 用于 app 能直接访问 OpenCode URL 的场景：本地局域网、Tailscale / VPN、HTTPS public server。

**配置项**：

| 字段 | 说明 | 默认值 |
|------|------|--------|
| Name | profile 名称 | 从 host 推断或用户填写 |
| OpenCode URL | `ip:port` 或 `http(s)://host:port` | - |
| Username | Basic Auth 用户名，可选 | - |
| Password | Basic Auth 密码，可选，存入 Keychain | - |

**协议提示**：当 Direct 使用 HTTP 且不是 localhost / LAN / Tailscale MagicDNS（`*.ts.net`）时，显示非阻塞警告，建议 HTTPS。这个提示只属于 Direct；SSH Tunnel 模式下本地 `http://127.0.0.1:4096` 是预期行为，不显示 HTTPS 警告。

#### 4.4.3 SSH Tunnel Transport（远程访问）

用于通过 SSH gateway 访问托管好的 OpenCode Server。网络拓扑：

```
iOS App → SSH Gateway (:8006) → Assigned Remote Port (:19001) → OpenCode (127.0.0.1:4096)
```

前提条件：
- 管理员已经为用户创建独立 OpenCode 服务并分配 remote port
- 用户把 iOS 设备公钥发给管理员；私钥只保存在设备 Keychain 中

**配置项**：

| 字段 | 说明 | 默认值 |
|------|------|--------|
| Enable SSH Tunnel | 开关 | Off |
| Gateway Host | SSH gateway 地址 | - |
| SSH Port | SSH 端口 | 8006 |
| Username | SSH 用户名 | opencode |
| Assigned Remote Port | 管理员分配的 remote port | 19001 |

**密钥管理**：

- App 自动生成 Ed25519 密钥对
- 私钥存储在 iOS Keychain（`kSecAttrAccessibleWhenUnlocked`）
- 公钥在 Settings 中显示，支持一键复制
- 支持密钥轮换（重新生成）

**首次设置流程**：

1. 打开 Settings → SSH Tunnel
2. App 自动生成密钥对
3. 复制公钥并发给 OpenCode host 管理员
4. 管理员完成授权后提供 gateway host、SSH 端口、用户名和 assigned remote port
5. 在 app 中填写这些参数并开启 SSH Tunnel 开关
6. Server Address 改为 `127.0.0.1:4096`（通过隧道访问），并在上方点 `Test Connection`

**连接状态**：

- 显示 Connected / Connecting / Disconnected / Error。
- SSH Tunnel 的连接诊断至少能区分 SSH gateway、SSH auth、本地 tunnel 和 OpenCode health check。
- 错误时显示具体原因和下一步动作，例如公钥未授权时提示复制本设备 public key 给管理员；Basic Auth 被拒绝时提示检查用户名和密码。

**安全要求**：

- 只支持 key-based 认证，不支持密码认证
- 首次连接采用 TOFU 自动信任并保存服务器 fingerprint，后续严格校验；UI 提供 fingerprint 展示与 reset trusted host

#### 4.4.4 Model Presets

**当前实现**：固定预设列表（GLM-5.1、GPT-5.4、GPT-5.3 Codex、DeepSeek），无导入、无排序。发送消息时在 body 中携带 `model: { providerID, modelID }`。

#### 4.4.5 Project (Workspace)

用于指定要查看的 OpenCode 项目。OpenCode Server 支持多项目，每个项目有独立的 session 列表。iOS 客户端通过 `GET /session?directory=<worktree>` 按项目过滤 sessions。

**选择已有项目**：
- 调用 `GET /project` 获取服务器已知的项目列表
- Picker 展示项目，显示名称取 worktree 路径的最后一段（如 `knowledge_working`、`agentic_trading`）
- 选中项持久化到 UserDefaults

**自定义路径**：
- 提供「Custom path」选项，用户可手动输入任意 worktree 路径
- 适用于服务器有 sessions 但未在 project 列表中展示的目录
- 输入错误时 `/session?directory=xxx` 返回 0 个 session，用户可感知

**默认行为**：未选择时调用 `GET /session` 不传 `directory` 参数，使用服务器当前项目（与 Web 端一致）。选择后调用 `GET /session?directory=xxx&limit=100`。

**创建限制**：新建 session 仅在选择 Server default 时可用。`POST /session` 不支持传 directory，新 session 始终落在 server 的 current project。当用户选了具体 project 时，新建按钮置灰，旁加 info 图标，提示需用命令行启动 OpenCode 并指定不同的工作目录后再创建。

#### 4.4.6 外观

- **主题跟随系统**（Light/Dark/Auto）：根据系统 theme 切换明暗两种格式
#### 4.4.7 About

- 当前 App 版本
- 连接的 OpenCode Server 版本（来自 `GET /global/health` 的 `version` 字段）

### 4.5 Car Mode（Experimental）

Car Mode 是 iPhone 上的前台语音交互模式，让用户在不适合阅读长对话或打字时，用一次点击完成“说话 → 自动发送 → 听取短结论”。它属于 OpenCode iOS Client，不维护独立驾驶 App，也不等同于 CarPlay App。

#### 4.5.1 产品范围

- Car Mode 默认关闭，只在 Settings → Experimental Features 中显式开启。
- 开启后，iPhone Tab 顺序为 Chat / Files / Car / Settings；关闭后恢复 Chat / Files / Settings。
- iPad 和 Apple Vision Pro 不显示 Car Tab 或开关，包括 iPad compact window。
- 用户点击大按钮开始录音，再次点击后结束转写并自动发送，不经过普通 Chat composer。
- 回复必须是短、可直接朗读的 structured speech；Apple TTS 朗读后回到 idle。
- 允许的客户端 action 是 `open_navigation` 和 V0 `health_quantification.export_all`。Maps 由 iOS 构造 URL；Health export 经本地授权、受限 App handoff 和原 session callback 完成，产品合同见 [`client_capabilities_prd.md`](client_capabilities_prd.md)。

Car Mode 不承诺切到 Maps 或其他 App 后持续录音、维持 SSE 或继续 TTS。进入后台时停止当前前台交互，但保留 Car session；用户回到 App 后继续同一个上下文。

#### 4.5.2 独立 Session 与可见性

Car Mode 不复用普通 Chat 的当前选择。每个 `(host profile, workspace)` 维护一个独立、持久化的 Car session，并保存最后处理的 assistant message ID、pending confirmation 和最后使用时间。

- 首次发送时创建标题为 `Car Mode` 的 session。
- 后续每次发送前确认 session 仍存在；404 时清除旧映射并创建新 session。
- 若用户从普通 Session 列表归档了当前 Car session，下一次 Car 请求前客户端写入 legacy restore sentinel `time.archived = -1`，然后继续向原 session 发送。iOS 按 `archived > 0` 判断归档，因此该 session 会重新进入 iOS Active 列表。
- 这个恢复行为只保证 iOS 可见性。OpenCode Web 把 active 定义为 `archived === undefined`，可能仍不显示 `-1` session；Car Mode 不为此维护自定义 server patch，也不 fork 或复制 session。
- 用户可以显式开始新的 Car session；切 Tab、打开 Maps 或短期离开 App 不得自动新建 session。

停车后，用户可以从普通 Chat 打开 Car session，查看完整消息和工具记录。structured assistant 没有 text part 时，Chat 显示 `assistant.structured.speech` 作为可读 fallback。

#### 4.5.3 回复、确认与现实世界动作

每轮固定发送 Car system prompt 和 JSON Schema。语音回复先说结论，不含 Markdown、URL、代码或工具过程，目标时长 8-12 秒，最长 15 秒。状态只有 `completed`、`needs_confirmation` 和 `failed`。

| 类型 | 示例 | 默认行为 |
|---|---|---|
| Read | 车库门关了吗；开车多久；有什么新邮件 | 直接执行并朗读短结论 |
| Prepare | 摘要邮件；起草消息 | 直接准备，明确尚未发送 |
| Explicit server commit | 打开车库门；把刚才原因发给联系人 | 用户参数明确时执行，随后读回结果 |
| Proposed server commit | Agent 主动建议发送或控制设备 | 返回 `needs_confirmation`，下一轮确认后执行 |
| Client handoff | 导航到明确目的地；同步过期的 Health 数据 | 返回 typed action，由 iOS 打开受限目标 App |
| Ambiguous | 多个联系人、门或目的地 | 最多追问一次，仍不明确则取消 |

只有用户消息可以授权现实世界副作用。邮件、网页、搜索结果和工具输出中的指令只能作为数据，不能授权发送消息、控制设备或触发客户端 action。V1 不开放任意 destructive shell、代码提交、发布、付款或不受限的多步现实世界动作。

Smart Home、邮件、iMessage 和 route-duration 仍需正式注册为 allowlisted skills 或 typed tools，并完成真实 E2E；通用 `read + bash` 只可用于 spike，不构成产品权限边界。

#### 4.5.4 状态与失败恢复

主界面保留一个视觉主操作，同时明确展示当前状态、最近一次 transcript、最近一次 speech 和错误。状态流为：

```text
idle → recording → finalizing → waitingReply
     → speaking / awaitingConfirmation / failed → idle
```

final transcript 成功后才自动发送；partial transcript 或识别失败不得触发现实世界动作。`waitingReply` 不允许重复提交，但允许取消并调用 server abort。TTS 和 Maps action 必须按 completed assistant message ID 去重。

#### 4.5.5 分期与非目标

Foreground Car Mode 已完成：实验开关、iPhone UI、独立 session、VoiceFlow 自动发送、structured reply、Apple TTS、typed Maps action、Health export callback 和普通 Chat history fallback 已落地。

后续工作集中在两条线：一是把 Smart Home、邮件、iMessage、route-duration 产品化为稳定 capability boundary；二是将同步 structured request 升级为 `prompt_async + SSE + message reload`，支持前后台恢复和 exactly-once action。即使完成异步恢复，也不等于支持后台持续对话。

真正 CarPlay App、Maps 前台持续免触发对话、任意 URL action 和开放式现实世界 automation 均不在当前范围内。

## 5. 数据流与状态管理

### 5.1 核心状态模型

```swift
@Observable class AppState {
    // Host profiles
    var hostProfiles: [HostProfile]
    var currentHostProfileID: UUID
    var currentHostProfile: HostProfile

    // Derived connection state for current host
    var serverURL: String              // derived from currentHostProfile.serverURL
    var isConnected: Bool
    var serverVersion: String?
    var sshTunnelConfig: SSHTunnelConfig? // present only for sshTunnel transport
    var connectionTransport: HostTransport
    
    // Project (workspace filter)
    var projects: [Project]
    var selectedProjectWorktree: String?   // nil = use server current
    var customProjectPath: String         // for "Custom path" option
    
    // Sessions
    var sessions: [Session]
    var currentSessionID: String?
    var sessionStatuses: [String: SessionStatus]  // sessionID → status
    
    // Messages (for current session)
    var messages: [Message]          // ordered by time
    var parts: [String: [Part]]      // messageID → parts
    
    // Models
    var modelPresets: [ModelPreset]   // user-configured
    var selectedModelIndex: Int
    
    // Files
    var fileStatuses: [FileStatus]   // git status
    var sessionDiffs: [FileDiff]     // current session's diffs
    
    // Permissions
    var recentPermissions: [PermissionLog]
}
```

迁移策略：第一版实现可以保留现有 `serverURL` / Basic Auth / `SSHTunnelManager.config` 字段作为 current profile 的展开缓存，但持久化 source of truth 应收敛到 `hostProfiles`。切换 profile 时由 profile 写回这些现有 runtime 字段，避免一次重构影响 APIClient / SSE / SSH tunnel 的稳定性。

### 5.2 SSE 事件处理

收到 SSE 事件后，按 `type` 分发处理：

| 事件 | 处理逻辑 |
|------|----------|
| `session.created` | 追加到 sessions 列表 |
| `session.updated` | 更新对应 session 的属性 |
| `session.status` | 更新 sessionStatuses 字典 |
| `session.diff` | 更新 sessionDiffs（若 SSE 推送；否则由 `GET /session/:id/diff` 拉取） |
| `message.updated` | 更新或插入 message |
| `message.part.updated` | 更新对应 part；如果有 delta，追加到 text part 的文本末尾 |
| `message.part.removed` | 从 parts 中移除 |
| `permission.asked` | 显示权限请求卡片，等待用户手动批准 |
| `file.edited` | 触发 file status 刷新 |
| `session.error` | 显示错误 toast |

### 5.3 连接恢复策略

```
App 进入前台
  ├── 调用 GET /global/health 确认 server 存活
  ├── 调用 GET /session 拉取 session 列表
  ├── 调用 GET /session/:id/message?limit=6 拉取当前 session 最近 3 轮消息
  ├── 调用 GET /session/status 拉取所有 session 状态
  └── 建立 SSE 连接到 GET /global/event
      └── 后续增量更新由 SSE 驱动
```

这种"全量拉取 + 增量订阅"的模式保证了即使 SSE 在后台断开，也不会丢失状态。

## 6. API 依赖清单

以下是 iOS Client 需要调用的 OpenCode API 的完整列表：

### 6.1 必需 API

| 方法 | 路径 | 用途 |
|------|------|------|
| GET | `/global/health` | 连接测试、获取 server 版本 |
| GET | `/global/event` | SSE 事件流 |
| GET | `/session` | Session 列表（支持 `directory`、`limit` 参数按项目过滤） |
| POST | `/session` | 创建 Session |
| GET | `/session/:id` | Session 详情 |
| DELETE | `/session/:id` | 删除 Session |
| GET | `/session/:id/message` | 消息列表（支持 `limit`，默认先拉最近 6 条） |
| POST | `/session/:id/prompt_async` | 发送消息（异步） |
| POST | `/session/:id/abort` | 中止运行 |
| GET | `/session/:id/diff` | Session diff |
| GET | `/session/status` | 所有 Session 状态 |
| POST | `/session/:id/permissions/:pid` | 响应权限请求 |
| GET | `/question` | 拉取 pending questions |
| POST | `/question/:id/reply` | 回答 question |
| POST | `/question/:id/reject` | 拒绝 question |
| GET | `/file?path=...` | 文件列表 |
| GET | `/file/content?path=...` | 文件内容 |
| GET | `/file/status` | 文件 git 状态 |
| GET | `/find/file?query=...` | 文件搜索 |
| GET | `/config/providers` | 可用 Provider 和模型列表 |
| GET | `/agent` | 可用 Agent 列表 |
| GET | `/project` | 项目列表 |
| GET | `/project/current` | 当前项目 |

### 6.2 可选 API（后续增强）

| 方法 | 路径 | 用途 |
|------|------|------|
| POST | `/session/:id/summarize` | Compact session（🔲 暂未实现） |
| POST | `/session/:id/fork` | Fork session |
| GET | `/session/:id/todo` | 查看 AI 的 todo 列表 |
| GET | `/find?pattern=...` | 全文搜索 |
| GET | `/mcp` | MCP 服务状态 |
| GET | `/lsp` | LSP 状态 |
| PATCH | `/config` | 修改配置 |

## 7. UI 线框描述

### 7.1 Chat Tab — iPhone

```
┌─────────────────────────────────┐
│ ☰ Sessions    Session Title   ⋯ │  ← Navigation bar
├─────────────────────────────────┤
│ [Claude Opus] [Sonnet 4.6] [G..│  ← 模型切换条（横向滚动）
├─────────────────────────────────┤
│                                 │
│  ┌───────────────────────────┐  │
│  │ Refactor the auth module  │  │  ← 用户消息
│  │              Claude Opus  │  │
│  └───────────────────────────┘  │
│                                 │
│  ┌───────────────────────────┐  │
│  │ ▸ Thinking... (折叠)      │  │  ← reasoning part
│  │                           │  │
│  │ I'll start by analyzing   │  │  ← text part (streaming)
│  │ the current auth flow...  │  │
│  │                           │  │
│  │ ┌───────────────────────┐ │  │
│  │ │ 🔧 read_file ✓        │ │  │  ← tool part
│  │ │   src/auth/handler.ts │ │  │
│  │ └───────────────────────┘ │  │
│  │                           │  │
│  │ ┌───────────────────────┐ │  │
│  │ │ 🔧 edit_file ⟳        │ │  │  ← tool running
│  │ │   src/auth/handler.ts │ │  │
│  │ └───────────────────────┘ │  │
│  │                           │  │
│  │ ⚠️ Permission required:   │  │  ← 权限请求（需手动批准）
│  │   shell: npm test [Approve]│  │
│  └───────────────────────────┘  │
│                                 │
├─────────────────────────────────┤
│ │ Type a message...    │ ➤ 🎤 │  ← 输入框（发送 + 麦克风）
└─────────────────────────────────┘
```

### 7.2 Files Tab — iPhone

```
┌─────────────────────────────────┐
│         Files                   │
├─────────────────────────────────┤
│ [File Tree]                     │
├─────────────────────────────────┤
│ 🔍 Search files...              │
├─────────────────────────────────┤
│ ▼ src/                          │
│   ▼ auth/                       │
│     ● handler.ts        +12 -5  │  ← modified (黄点)
│     ○ types.ts                  │
│   ▶ api/                        │
│   ▶ utils/                      │
│ ▼ tests/                        │
│   ● auth.test.ts        +45 -0  │  ← new file (绿点)
│ ○ package.json                  │
│ ○ tsconfig.json                 │
└─────────────────────────────────┘
```

点击文件后 push 到文件详情页：

```
┌─────────────────────────────────┐
│ ◀ Files   handler.ts   [Diff]  │
├─────────────────────────────────┤
│  1 │ import { Router } from ... │
│  2 │ import { verify } from ... │
│  3 │                            │
│  4+│ export async function      │  ← 新增行（绿色背景）
│  5+│   authenticateUser(        │
│  6+│   req: Request             │
│  7 │ ) {                        │
│  8-│   const token = req.head.. │  ← 删除行（红色背景）
│  9+│   const token = extractT.. │  ← 新增行
│ 10 │   ...                      │
└─────────────────────────────────┘
```

### 7.3 Settings Tab — iPhone

```
┌─────────────────────────────────┐
│         Settings                │
├─────────────────────────────────┤
│                                 │
│ SERVER CONNECTION               │
│ ┌─────────────────────────────┐ │
│ │ Address   192.168.0.80:4096   │ │
│ │ Username  opencode          │ │
│ │ Password  ••••••••          │ │
│ │ Status    🟢 Connected      │ │
│ │           [Test Connection] │ │
│ └─────────────────────────────┘ │
│                                 │
│ APPEARANCE                      │
│ ┌─────────────────────────────┐ │
│ │ Theme             [Auto   ▾]│ │
│ └─────────────────────────────┘ │
│                                 │
│ SPEECH RECOGNITION              │
│ ┌─────────────────────────────┐ │
│ │ AI Builder Base URL  (space.ai-builders.com/backend) │ │
│ │ AI Builder Token     •••••• │ │
│ │           [Test Connection] │ OK │
│ └─────────────────────────────┘ │
│                                 │
│ ABOUT                           │
│ ┌─────────────────────────────┐ │
│ │ App Version        0.1.0    │ │
│ │ Server Version     1.1.61   │ │
│ └─────────────────────────────┘ │
│                                 │
└─────────────────────────────────┘
```

## 8. 开发分期

### Phase 1 — 最小可用版本（MVP）

**目标**：能连上 server，发消息，看到 AI 的实时响应。

| 功能 | 说明 |
|------|------|
| Server 连接 | 手动输入 IP:Port，Basic Auth |
| SSE 事件流 | 连接、断开、重连、前后台切换 |
| Session 基础 | 列表、创建、切换（删除暂未实现） |
| 消息发送 | 文本输入、发送（使用 `prompt_async`）、查看响应；busy 时消息自动入队 |
| 流式渲染 | text part 的实时打字机效果 |
| 模型切换 | 预设模型列表、发送时指定模型 |

**预估工作量**：2-3 周（假设对 SwiftUI 有基础经验）

### Phase 2 — 完整交互

**目标**：能有效地监控 AI 工作过程并做审查。

| 功能 | 说明 |
|------|------|
| 消息 Part 渲染 | reasoning、tool、step、patch 等所有 Part 类型 |
| 权限手动批准 | 监听 permission.asked，显示请求卡片，用户手动批准 |
| Abort / Compact | 中止运行、压缩 session |
| Markdown 渲染 | AI 消息中的 Markdown 完整渲染 |
| 主题切换 | 跟随系统 Light/Dark |
| 代码块高亮 | 消息中代码块的语法高亮 |
| **Think Streaming** | delta 增量更新（打字机效果）、Tool 完成后默认收起 |

**预估工作量**：2 周

### Phase 3 — 文件浏览、文档审查与 iPad/Vision Pro 布局

**目标**：完整的文件浏览和**文档审查**能力，以及 iPad/Vision Pro 的大屏布局优化。

| 功能 | 说明 |
|------|------|
| 文件树 | 目录展开/收起、git 状态标记 |
| 文件内容 | 行号、等宽字体（语法高亮暂不实现） |
| 文件搜索 | 模糊搜索文件名 |
| Markdown 预览 | Preview 模式为主，支持 Markdown/Preview 切换 |
| 文档 Diff | 高亮 changes（优先 Preview 内高亮，否则 Markdown 内高亮） |
| Session Diff | 当前 session 的变更文件列表和 diff 视图 |
| 单文件 Diff | 文件的 uncommitted changes |
| **Think Streaming** | delta 增量更新（打字机效果） |
| **iPad / Vision Pro 布局** | 无 Tab Bar；三栏：左 Workspace（Files+Sessions）、中 Preview、右 Chat；Settings 作为第一行 toolbar 按钮 |

**预估工作量**：2-3 周

### Phase 4 — 打磨与增强（暂不实现，按优先级排序）

| 功能 | 说明 |
|------|------|
| **推送通知 / Live Activity** | AI 停下来等人类决策时（question / permission / 运行完成）通过 APNs 或 Live Activity 主动通知，消除"人机异步空转"。这是 Steer 闭环的关键工程增强 |
| **Session 辨识度增强** | 活跃/死亡 Session 的视觉区分优化，降低用户在长列表中识别"该切到哪个"的认知成本 |
| mDNS 自动发现 | 局域网自动发现 OpenCode server |
| Widget | iOS Widget 显示当前 session 状态 |
| Haptic 反馈 | 关键操作的触觉反馈 |
| Spotlight 集成 | 搜索最近的 session |

## 9. 已知限制与风险

**网络依赖**：App 完全依赖与 OpenCode Server 的网络连接。如果 Server 不可达（网络不通、Server 未启动），App 无法使用。当前支持局域网直连与 SSH tunnel 远程访问；弱网下通过“最近 3 轮 + 下拉扩展历史”降低首屏延迟。

**SSE 在 iOS 上的行为**：iOS 会在 App 进入后台后积极断开网络连接。需要实现可靠的重连和状态恢复机制。不建议在后台保持 SSE 连接。

**屏幕尺寸**：代码和 diff 在 iPhone 窄屏上的可读性是一个持续挑战。需要仔细设计横向滚动、字号调节等交互。iPad 上的体验会显著更好。

**Server API 稳定性**：OpenCode 的 HTTP API 目前没有正式的版本承诺（没有 `/v1/` 前缀）。Server 更新可能引入 breaking changes。建议 iOS 端对 API 响应做防御性解析，对未知字段忽略而非 crash。

**安全**：初期 App 仅用于本地局域网，安全风险较低。如果后续支持公网访问，需要考虑 TLS、token-based auth 等增强方案。当前的 Basic Auth over HTTP 在局域网环境下可接受，但不适合公网暴露。**ATS 例外**：局域网（私有 IP、localhost、.local）与 Tailscale MagicDNS（`*.ts.net`）允许 HTTP；其他 WAN 强制 HTTPS。Info.plist 中 `NSExceptionDomains` 对 `ts.net` 豁免。

**人机异步空转（Notification 缺失）**：当 AI 因 `question` tool、permission 请求或需要人类审查而暂停等待时，人类如果离开了 App（iOS 进入后台），目前收不到任何通知。这意味着两端都在空转——AI 等着人类的决定，人类不知道需要做决定。这个痛点的实质是 iOS 工程问题，而非 UX 设计问题：需要通过 push notification（APNs）或 Live Activity 来主动触达用户。当前 Phase 4 中已标记为"暂不实现"，但应作为高优先级工程增强项——它影响着整个 Steer 范式的闭环效率。

## 10. 已决事项

1. **消息发送 API**：使用 `POST /session/:id/prompt_async`。源码调研确认：sync 与 async 均调用同一 `SessionPrompt.prompt()`，async 仅不 await 响应；消息创建、处理、SSE 推送行为完全一致。iOS 端配合 SSE 获取结果，async 更合适。

2. **大型 Session**：暂不考虑。不预期 session 超过百条消息。

3. **推送通知**：暂不实现，但已识别为高优先级工程增强项——AI 等待人类决策时（question / permission / 运行完成），需要 APNs 或 Live Activity 突破 iOS 后台限制来主动触达用户，消除人机异步空转。

4. **多项目支持**：暂不实现。

5. **默认 Server**：`127.0.0.1:4096`。默认无认证，但需实现 Basic Auth 支持（可选配置）。

## 11. 实现起步指南

### 11.1 项目创建

当前仓库已经包含可直接打开的 Xcode 工程。对新参与者，更推荐这两种方式：

1. 通过 README 中的 TestFlight 链接直接安装可运行版本
2. clone 仓库后直接打开 `OpenCodeClient/OpenCodeClient.xcodeproj` 本地构建

### 11.2 依赖与结构

- **网络层**：使用 `URLSession` 原生实现 REST + SSE，无需引入 Alamofire 等第三方库
- **状态管理**：`@Observable`（iOS 17+）配合 SwiftUI
- **Markdown**：使用 [MarkdownUI](https://github.com/gonzalezreal/MarkdownUI)
- **主题**：通过 `@Environment(\.colorScheme)` 跟随系统
- **SSH Tunnel**：使用 Citadel

当前代码组织采用按职责分层的目录结构：

- `Views/`：Chat、Files、Settings、Split View 相关 UI
- `Controllers/`：permission / question 等事件控制器
- `Services/`：API、SSE、SSH tunnel、语音转写、录音
- `Stores/`：Session、Message、File、Todo 状态存储
- `Models/`：Session、Message、Project、Question、ModelPreset 等数据模型
- `Support/`：本地化与通用支持代码
- `Utils/`：Keychain、PathNormalizer、LayoutConstants 等工具

### 11.3 建议的实现顺序

1. **Phase 1**：Server 连接、SSE、Session、消息发送与流式渲染
2. **Phase 2**：消息 Part 渲染、权限手动批准、主题切换、消息队列（调用 `prompt_async`）
3. **Phase 3**：文件树、Markdown 预览、文档 Diff、高亮 changes

### 11.4 与 OpenCode Server 的对接

默认 Server 地址：`127.0.0.1:4096`（无认证）。若 Server 启用了 `OPENCODE_SERVER_PASSWORD` 等，在 Settings 中配置 Username/Password 即可。局域网直连时可改为内网地址；远程场景可通过 SSH tunnel 转发到本地 `127.0.0.1:4096`。

---

## 附录 A — OpenCode Server 关键数据结构参考

### Session

```typescript
{
  id: string
  slug: string
  projectID: string
  directory: string
  parentID?: string
  title: string
  version: string
  time: { created: number, updated: number }
  share?: { url: string }
  summary?: { additions: number, deletions: number, files: number }
}
```

### Message (User)

```typescript
{
  id: string, sessionID: string, role: "user",
  model: { providerID: string, modelID: string },
  time: { created: number }
}
```

### Message (Assistant)

```typescript
{
  id: string, sessionID: string, role: "assistant",
  parentID: string,  // links to user message
  providerID: string, modelID: string,
  cost: number,
  tokens: { input: number, output: number, reasoning: number, cache: { read: number, write: number } },
  time: { created: number, completed?: number }
}
```

### Part (核心类型)

```typescript
// Text
{ id, type: "text", text: string }

// Reasoning
{ id, type: "reasoning", text: string }

// Tool call
{ id, type: "tool", callID: string, tool: string, state: "pending"|"running"|"completed"|"error", metadata?: any }

// Step markers
{ id, type: "step-start", snapshot?: string }
{ id, type: "step-finish", reason: string, cost: number, tokens: {...} }

// File change
{ id, type: "patch", hash: string, files: [...] }
```

### FileDiff

```typescript
{
  file: string,       // relative path
  before: string,     // full content before
  after: string,      // full content after
  additions: number,
  deletions: number,
  status?: "added" | "deleted" | "modified"
}
```

### SSE Event

```typescript
{
  directory: string,  // project path, or "global"
  payload: {
    type: string,     // e.g. "message.part.updated"
    properties: any   // event-specific data
  }
}
```
