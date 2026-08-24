# OpenCode iOS Client — Product Requirements Document

> Version 0.4 · Working Draft · Jul 2026

## 1. 产品定位

OpenCode iOS Client 是面向 OpenCode 服务端的原生 iOS 远程控制应用。它并非独立的 AI 编程工具，而是运行在 Mac/Server 上的 OpenCode 实例在**移动端的延伸**——方便用户在沙发上、通勤途中等远离电脑的场景下，发送指令、监控 AI 工作进度、浏览代码变更以及切换模型。

核心设计原则：**轻量、快速、以阅读和交互为主**。所有繁重的配置（如 Provider 密钥、MCP 服务、workspace 设置）均在电脑端完成，iOS 端仅负责必要的交互与内容消费。

比起技术架构，该 App 更核心的目标是解决人机交互闭环：**如何让 AI 将关键决策充分呈现给人类审查，并在必要时支持通过语音快速介入纠偏**——我们将这种模式定义为 **Steer（统领）**。在该模式下，AI 负责执行与探索，人类负责判断与方向把控。App 的价值不仅在于“看一眼 AI 在做什么”的状态监控，更在于充当轻量的**决策审查与方向控制终端**——用户每次打开 App，主要是阅读 Markdown 报告、查看内嵌的截图与产物，并通过语音下达新的方向性指令。它的本质是统领工具，而非单纯的内容浏览工具。

围绕 Steer 范式，App 将核心聚焦在三个交互载体上：**Markdown 对话窗口**（AI 向人类汇报进展与展示产物的主要途径）、**文件卡片预览**（用于快速查看 AI 的修改内容，以文档而非代码为主）以及**语音输入**（方便用户在脱离键盘时高效下达方向性指令）。代码语法高亮并非核心优先级——因为用户审查的重点在于 AI 做出决策的依据与结果，而非代码本身的排版美感。

### 1.1 它不是什么

该 App 明确不做以下事情：在手机端编辑代码、在手机端运行 OpenCode server，或替代完整的 Web UI。它的核心场景在于：在 AI 执行任务的任意时刻，用户随时拿出手机阅读刚生成的 Markdown 分析报告或代码改动；一旦发现方向有偏差，即可立即通过语音指令调整路线。

### 1.2 核心交互范式

#### Steer 范式

App 围绕“统领”的认知闭环设计交互流程：

1. **Surface**——AI 通过 Markdown 窗口向人类呈现其决策过程、参考代码、执行命令、分析思路与最终结论。内容采用自然语言 Markdown 表达，并支持嵌入部署结果截图、图表、UI diff 等可视化产物，而非单纯堆砌代码。这是 AI 与人类之间最主要的信息通道。
2. **Review**——人类通过阅读 Markdown 来评估结论合理性与整体方向。大部分产出为文档、分析或调研内容，天然适合 Markdown 呈现；必要时也可查看代码 diff 确认细节。人类在这一环节的核心职责是决策判断，而非编写代码。
3. **Steer**——若发现执行方向偏离预期，用户可通过语音快速下达纠偏指令（例如“停，不要用继承，换成组合模式”），或切换模型/Agent 重新开始。指令采用自然语言输入，无需繁琐打字。

整个闭环在两端均为异步运行：AI 在电脑端执行，人类在手机端审查，两端无需保持实时同步——这也是移动端相比桌面端的独特优势。但也因此带来了一个实际痛点：当 AI 暂停等待人类决策时（例如触发 `question` tool），用户在离开 App 时无法收到通知，容易造成双方等待。该问题的根本解法不在 UX 交互层，而在 iOS 系统工程层面——需要引入 push notification 或 Live Activity 实现主动提醒。

#### Markdown 作为交互窗口

Markdown 是该 App 中 AI 与人类交互的**核心信息媒介**。该 App 并非“顺便支持 Markdown”的代码编辑器，而是将 Markdown 阅读与审查体验做到极致的统领终端。具体设计体现为：

- **不强调代码语法高亮**，优先保证 Markdown 渲染质量（如清晰的标题层级、列表、链接、代码块以及图片嵌入）。用户的核心诉求是审查 AI 的思考逻辑与交付产物，而非代码的外观样式。
- **完善的图片嵌入支持**：AI 可将部署结果截图、生成图表、UI 对比图直接嵌入 Markdown 报告中。App 配套了专门的 Skill 体系引导 AI 运用这些能力，并确保相对路径图片在 Files 预览与 Chat 渲染中表现一致。
- **内容形态不局限于编程**：AI 的产出既包含代码 diff，也涵盖调研文章、分析报告与系统设计文档。Markdown 天然能良好承载各类内容形态。

#### 文件卡片预览（非代码编辑器）

文件浏览的核心定位在于**快速确认 AI 的改动**，而非“在手机上写代码”。在绝大多数场景下，用户直接通过 Chat 窗口中的 tool/patch 卡片跳转查看文件预览——Files Tab 属于兜底入口，并非主要工作流。例如在 Chat 中看到 `edit_file` 卡片时，点击卡片上的文件路径即可直接调起预览，无需切到 Files Tab 逐层翻找目录树。

文档 diff 的审查权重远高于代码 diff：目前 AI 已具备较好的编码能力，人类审查的重点主要在于文档维度的逻辑与架构决策。

该 App 明确不做以下事情：在手机端编辑代码、在手机端运行 OpenCode server，或替代完整的 Web UI。它的价值在于“随时拿出手机查看 AI 当前进展，必要时快速介入调整方向”这一核心场景。

## 2. 目标用户与使用场景

目标用户为日常使用 OpenCode 的开发者（初期以作者本人为主）。需要明确的关键认知是：重度用户打开 App 并非为了“扫一眼状态”——每次打开都是深度交互：阅读 Markdown 报告、通过语音与 AI 对话、在各 Session 间频繁切换以追踪不同任务。App 的核心价值在于让用户在远离电脑时，依然保持对 AI 工作全流程的判断力与控制力，而非单纯充当 status checker。

**场景 A — 远程监控与审阅**：在电脑端发起了一项耗时较长的重构任务后离开工位。拿出手机时，用户不仅能查看 AI 处理了多少文件，更能直接阅读 AI 最新生成的 Markdown 分析报告——报告中会阐述各项修改的原因并附带架构图截图。用户的核心操作包括：深入阅读报告、点开文件卡片核对具体改动、确认整体方向无误。

**场景 B — 快速纠偏（语音驱动）**：在手机上发现 AI 的实现思路偏离了预期，正在采用错误方案编写功能。此时可通过语音输入迅速下达指令：“停，不要用继承，改用组合模式”，随后收起手机。语音输入在该场景下的关键价值在于规避手机端打字的不便，将方向调控的交互摩擦降至最低。

**场景 C — 模型 A/B 测试**：需要对比不同模型（如 GPT-5.3 Codex / DeepSeek / Opus / GLM）在同一任务下的表现。用户可在手机端一键切换至另一模型，发送相同指令以观察差异。该场景通常还会配合 Fork Session 使用——从同一对话节点分叉出不同模型的尝试分支。

**场景 D — 文档审查**：AI 完成一轮修改后，用户在手机端浏览 Markdown 文档的 diff，以 Preview 模式为主查看变更内容，确认文档改动合理后再让 AI 执行下一步。代码审查则作为辅助——目前 AI 已具备编写高质量代码的能力，人类审查的重心主要在文档层面的逻辑与架构决策。产出内容也不限于编程，可能涵盖调研报告、系统设计文档、部署结果展示等，这些内容天然以 Markdown 形式呈现。

### 2.0 重度用户的时间分布

深入理解重度用户的时间分配，对把握产品演进方向至关重要：

- **约 60% 的时间用于阅读 Markdown**——包括 AI 输出的分析报告、调研文章、设计文档以及带有嵌入截图的部署结果，对应“审”的环节。
- **约 25% 的时间用于与 AI 对话**——通过语音下达新指令、纠正执行方向或追问细节，对应“领”的环节。
- **约 10% 的时间用于在 Session 间切换**——追踪不同项目、不同方向的进展，判断哪些任务需要介入，对应“多线统领”。
- **约 5% 的时间用于 Files Tab**——该入口本质上是兜底通道，绝大多数文件访问均由 Chat 窗口中的 tool/patch 卡片直接跳转完成。

基于上述时间分布，产品体验优化的优先级定义为：Markdown 渲染质量 > 语音输入流畅度 > Session 辨识度 > 文件树功能。

### 2.1 分发方式

为降低用户的试用门槛，产品同时提供两种分发路径：

- **TestFlight**：面向绝大多数用户，安装即可使用，无需 Apple Developer account
- **源码构建**：面向需要本地修改代码、调试或自定义签名的开发者

README 负责提供最新的安装入口，PRD 仅保留产品维度的分发策略。

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

iOS 端设计为纯粹的 API 消费者，不承担任何本地 AI 推理、文件系统访问或 shell 执行逻辑。所有数据均通过 OpenCode 的 HTTP API 获取，实时状态则通过 SSE（Server-Sent Events）推送。

### 3.2 技术选型

| 层面 | 选择 | 理由 |
|------|------|------|
| UI 框架 | SwiftUI | 原生体验、流畅动画、充分利用 iOS 系统特性 |
| 网络层 | URLSession + 原生 SSE | 无需引入第三方 HTTP 库，SSE 协议实现轻量直接 |
| 状态管理 | Swift Observation (@Observable) | iOS 17+ 原生方案，与 SwiftUI 配合最为简洁 |
| 代码高亮 | 暂不实现 | 当前仅保留等宽字体与行号 |
| Markdown 渲染 | MarkdownUI + 自定义图片解析 | 满足文档预览、代码块展示，并支持 repo 内相对路径图片解析 |
| Diff 渲染 | 自建组件 (基于服务端返回的 before/after) | 服务端已完成 diff 计算，客户端仅需渲染；文档 diff 需高亮 changes |
| 最低版本 | iOS 17.0 | 全面采用 Observation 框架，不再兼容 iOS 16 |
| 持久化 | UserDefaults + Keychain | 仅需存储连接配置与模型预设，无需引入本地数据库 |

### 3.3 与 OpenCode Server 的通信

客户端与服务端的通信基于两条通道：

**REST API** — 承载所有主动操作（如发送消息、获取文件列表、修改配置等）。请求的基础路径由用户在 Settings 中配置的 `http://<ip>:<port>` 决定。

**SSE (Server-Sent Events)** — 承载实时事件推送。客户端连接至 `GET /global/event` 端点接收全量事件，数据格式为 `{ directory, payload: { type, properties } }`。

SSE 连接的生命周期管理是客户端的核心技术点之一：
- App 进入前台时建立或恢复 SSE 连接
- App 进入后台时断开 SSE 连接（避免在 iOS 后台维持长连接）
- 从后台切回前台时，先通过 REST API 拉取最新状态完成全量同步，随后重新建立 SSE 连接

### 3.4 认证

OpenCode Server 支持可选的 Basic Auth（由服务端环境变量 `OPENCODE_SERVER_PASSWORD` 控制）。iOS 端在 Settings 中提供用户名与密码配置项，并安全存储于 Keychain 中。客户端在发起的每个 REST 请求与 SSE 连接中均附带 Basic Auth header。

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
- **左栏**：Workspace（包含文件树与 Sessions 列表）
- **中栏**：Preview（展示文件内容与 Markdown 预览，支持手动刷新）
- **右栏**：Chat（包含消息流与输入框，交互逻辑与 iPhone 保持一致）
- **宽度比例**：Workspace ≈ 1/6；Preview ≈ 5/12；Chat ≈ 5/12（Preview 与 Chat 保持等宽）
- **可拖动**：支持用户拖动分割线调整三栏宽度，默认采用上述初始比例
- **Settings**：作为独立按钮置于第一行 toolbar（与 Session 操作、模型切换并列），点击后以 sheet 或 navigation push 形式展示
- **优势**：在大屏设备上 Chat 与 Preview 并排呈现，查看文件预览无需弹出浮层；同时 Workspace 与 Sessions 常驻左侧，不干扰主要阅读流

### 4.2 Chat Tab（主交互界面）

作为 App 的核心交互界面，Chat Tab 顶部包含模型与 Agent 选择器，中间为消息流，底部为输入控制区（Composer）。

#### 4.2.1 模型与 Agent 选择器

位于 Chat 页面顶部的右侧 toolbar 区域。采用**下拉列表**（Menu + Picker）形式，取代原有的 chip 横向滚动条。

**模型选择器**：下拉列表，包含以下固定选项：

| 显示名称 | providerID | modelID |
|----------|------------|---------|
| GLM-5.1 | `zai-coding-plan` | `glm-5.1` |
| GPT-5.4 | `openai` | `gpt-5.4` |
| GPT-5.3 Codex | `openai` | `gpt-5.3-codex` |
| DeepSeek | `deepseek` | `deepseek-v4-pro` |

**Agent 选择器**：下拉列表，选项由 `GET /agent` API 动态获取，客户端过滤掉 `hidden != true` 的 agent 后进行展示。每个选项展示 agent 名称（如 `Sisyphus`），description 可作为 tooltip 或 subtitle 辅助展示。

**iPhone 显示策略**：在窄屏的 iPhone 上使用短名称（`DeepSeek` / `GPT` / `GLM`）以保证紧凑布局；iPad 等大屏设备上展示全称。

**技术实现**：
- 切换模型或 Agent 仅改变本地状态，无需向服务端发起 API 调用
- 发送消息时在 `POST /session/:id/prompt_async` 的请求 body 中附带：
  - `model: { providerID, modelID }` 字段
  - `agent: string` 字段（对应 agent 名称）
- 模型与 Agent 的选择状态按 Session 独立记忆，切换 Session 时自动还原对应配置

#### 4.2.1.1 Context Usage（上下文占用）指示器

在 Chat 顶部右侧（Agent 选择器与 Settings 齿轮图标之间）展示一个**环形进度条**，用于表示当前 session 最近一次生成时的上下文窗口占用比例。

- **数据来源**：由 `GET /session/:id/message` 返回的 assistant message 中 `info.tokens.total`（以及 input/output/reasoning/cache 细分指标），结合 `GET /config/providers` 中对应 `providerID/modelID` 的 `limit.context` 共同计算。
- **Provider Config 加载**：`GET /config/providers` 的请求结果在本地缓存；若尚未加载或数据为空，点击环形进度时自动触发加载并显示 loading 状态；加载失败时在弹出的 sheet 中展示具体错误信息，而非仅提示 “Provider config not loaded”。
- **无数据时**：展示灰色空环（不显示数值），点击仍可呼出详情 sheet，内容显示 "No usage data"。
- **颜色策略**：占用率 < 70% 显示正常色；70-90% 显示警告色；> 90% 显示危险色（防止用户在 iOS 端盲目发送导致 token 超限截断）。
- **点击交互**：点击环形进度条弹出详情 sheet（iPhone 与 iPad 均支持），展示以下详细信息：
  - Session（title/id，支持复制）
  - provider/model
  - context limit
  - total tokens + usage %
  - input/output/reasoning/cache read/cache write
  - total cost（若服务端返回了 message cost 则展示；若缺失则隐藏）

注：初期不展示 raw messages；关于 context breakdown（即 system/user/assistant/tool 各自占比），待服务端明确暴露对应字段或具备稳定推导方案后再行支持。

- **AI 响应期间可见性**：无论当前处于何种状态（idle / busy / streaming），context ring 均保持常驻显示，不被 spinner 或其他临时控件替换。busy 状态统一由输入栏右侧的红色停止按钮表达，toolbar 不再额外注入 `ProgressView`。

#### 4.2.2 消息流

采用垂直滚动的消息列表，样式设计参考 OpenCode Web 客户端：**不采用左右对话气泡**，所有消息统一呈流式排布，人类消息用灰色背景与 AI 消息区分，保持整体紧凑的阅读节奏。

每条消息包含：

**用户消息**：灰色背景卡片，展示文本内容，并在底部以小字注明所选用的模型。

**AI 消息**：白色或透明背景，支持按 Part 类型分别渲染：
- `text` — 完整的 Markdown 渲染（支持代码块、链接、列表等格式）
- `reasoning` — 折叠面板，标题显示 "Thinking..."，点击即可展开查看详细思考与推理过程
- `tool` — 工具调用卡片，展示工具名称与当前执行状态（pending → running → completed/error）。在 **running 状态下默认展开**并显示加载指示（spinner）；在 **completed 状态下默认收起**，用户可点击展开查看元数据详情（如文件路径、命令输出等）
- `tool`（todowrite）— 渲染为 Task List（todo）卡片：展示条目清单与完成进度（completed/total）；todo 的完整数据可从 tool 输入/metadata 获取，并通过 SSE `todo.updated` 事件实时更新。**仅在各 tool 卡片内部就地展示，不在 Chat 顶部常驻（方案 B）**
- `step-start` / `step-finish` — 渲染为步骤分割线，展示 token 用量与调用成本
- `patch` — 文件变更摘要卡片，列出修改的文件列表，点击可直接跳转至 Files Tab 的文件树并打开对应文件预览
- `tool`（write/edit/apply_patch/read_file 等）— 若当前 part 包含文件路径（如 metadata.path、state.input.path、files 数组或 patchText 解析出的路径），点击卡片可弹出「在 File Tree 中打开」操作项，直接调起文件预览；若目标为图像文件且 tool output 支持解码，则直接内联显示缩略图并支持点击放大

**大屏布局（iPad / Vision Pro）补充**：为充分利用横向屏幕空间，`tool` / `patch` / permission 卡片支持采用**三列网格**横向排列（空间不足时自动换行）；但 `text`（最终回复）仍保持整行通栏展示，以确保长文本的阅读连贯性。

**流式更新（Think Streaming）**：行为逻辑与官方 Web 客户端保持一致。当 SSE 推送 `message.part.updated` 且包含 `delta` 字段时，客户端对对应的 text 或 reasoning Part 执行增量追加，呈现打字机效果；若事件中不含 delta，则执行全量 reload。定位具体 Part 时使用 `messageID` + `partID` 复合标识。**注**：目前服务端 API 尚不支持 Tool output 的实时行级流式传输（如逐行输出终端内容），output 数据仅在 completed 状态时一次性返回。

**自动滚动规则**：仅当用户当前视图停留在消息流底部附近时，新到达的 streaming 文本、tool 卡片、permission card、question card 或 activity row 才会驱动视图继续自动下滚；若用户已向上滑动翻阅历史记录，则自动暂停滚动跟随，防止打断阅读。

**历史消息分页加载**：为缩短弱网环境（如 SSH tunnel 或广域网连接）下的首屏加载耗时，默认仅拉取最近 **3 轮对话**（共 6 条 message：user 与 assistant 各 3 条）。聊天视图顶部提供“下拉加载更多历史消息”交互，用户每次下拉将向上追加拉取 3 轮历史记录。

**Activity Row 一致性规则**：实际运行态的判定优先级高于 `session.status=idle` 可能出现的瞬时抖动。只要客户端仍存在处于 running 或 pending 状态的 tool，或正在接收 streaming 增量，Activity Row 必须维持 running 状态；仅在确认本轮 assistant 全部完成后，才切换至 completed。

**Session 状态指示器**：消息流顶部实时展示当前 session 的运行状态（idle / busy / error），状态数据来源于 `session.status` SSE 事件。处于 busy 状态时展示进度动画。

#### 4.2.3 权限通知

在 OpenCode 的正常执行流程中极少主动申请权限，一旦触发 `permission.asked` 事件，通常说明存在异常情况。因此客户端采用**手动批准**模式：

- 实时监听 SSE 的 `permission.asked` 事件
- 在消息流中就地插入权限请求卡片，明确展示待批准的操作内容（如“执行 `rm -rf node_modules`”）
- 用户需手动点击「批准」或「拒绝」，客户端调用 `POST /session/:id/permissions/:permissionID` 提交决策
- 客户端不提供任何形式的自动批准选项

#### 4.2.3.1 Question 卡片

当服务端通过 `question` tool 主动向用户发起提问时，Chat 消息流中直接插入 question card，避免 session 陷入无响应等待。

- 监听 SSE 事件：`question.asked`、`question.replied`、`question.rejected`
- 初始化与重连时，通过 `GET /question` 拉取当前 session 的 pending questions
- 支持用户选择单选/多选预设选项，或在输入框中输入自定义文本
- 提交回答调用 `POST /question/{requestID}/reply`
- 拒绝提问调用 `POST /question/{requestID}/reject`

#### 4.2.4 Composer：voice rail + text review field

底部固定 composer 采用上下两行结构：上方为 voice rail，下方为 text review field。Session 相关操作（新建、重命名、列表、Compact）统一置于 Chat 顶部 toolbar，不侵入 composer 区域。

该结构直接服务于 Steer 产品定位：用户在移动端的核心习惯并非冗长的键盘打字，而是在阅读 AI 输出后，通过语音快速追加方向性指示。语音是主要输入模态，文本框则承担转写结果审阅、轻量微调以及打字兜底职责。因此 composer 没有将麦克风作为文本框内的次级按钮，而是将 voice rail 提升至第一行作为首要交互面板。

**草稿持久化（Draft Persistence）**：未发送的输入内容按 sessionID 在本地持久化保存；切换至其他 session 后再返回，草稿内容完整恢复；消息成功发送后清空本地草稿。

**Voice rail（Speech Recognition）**：voice rail 位于文本框上方，由左侧 transport 控制按钮、中央 waveform/status 显示区以及右侧轻量恢复操作区组成。点击 transport 开始录音时，系统创建 VoiceFlowKit realtime session，并通过 `AVAudioEngine` 采集 PCM16 mono 24kHz 音频流。录音过程中，中央 waveform 直接消费 `VoiceFlowMicrophone.audioLevel` 提供的 0..1 范围平滑麦克风音量（smoothed mic level），为用户提供直观的声音采集反馈。再次点击 transport 属于正常结束音频采集并进入转写阶段，与中止 agent 运行（agent abort）概念相互独立。

VoiceFlowKit 在向远端发送 live PCM 数据的同时，将相同的 PCM 音频流同步追加写入本地临时 `.pcm` 文件；若 heartbeat 检测或 live send 发现 WebSocket 连接中断，Kit 不会终止当前录音，而是自动重建 session 并从本地缓存重放完整的 PCM 数据，追齐当前录音进度后恢复实时传输。用户停止录音时，系统等待重传恢复完成后发送 `commit` / `stop` 指令，随后将最终识别出的 transcript 追加至下方的 text review field。

若转写过程出现等待超时或卡顿，voice rail 将展示 processing waveform 并提供明确的恢复入口（如 `Stop transcription wait`）。该操作调用 `abortPreservingAudio()` 终止当前的 WebSocket 与 finalize 等待流程，同时完整保留已录制的 PCM 音频；随后 rail 进入 preserved-audio 状态，左侧 transport 按钮转换为 `Retry this segment` 图标，调用 `transcribe(preservedAudio:)` 重新对该段音频发起识别；右侧动作转换为 `Discard audio`，用于放弃当前保留音频并重置回正常输入状态。这里的 retry 是对已保存音频文件的重新转写，不属于追加录音，也无需用户重新口述。若重试仍告失败，系统依然保留该段音频，用户可选择继续 retry 或点击 discard 退出恢复流程。

**Text review field**：下方文本框支持多行编辑，用于承接语音转写结果、人工修改微调以及纯键盘输入。录音过程中 placeholder 提示“转写会出现在这里”，避免与上方 voice rail 及 status row 中已显示的 Listening 状态产生视觉重复。当语音转写或 preserved-audio 重试流式返回 partial transcript 时，文本框自动滚至末尾，方便用户实时查看转写内容的渐进生成；而普通的手动键入与草稿恢复则不触发强制滚动。发送按钮固定于文本框右侧；即便当前 session 处于 busy 状态该按钮依然可用，因为服务端的 `prompt_async` 接口自带排队机制。

**Agent interrupt**：agent 的运行状态通过 composer 附近的低权重状态行进行提示（例如 `Agent running`）。`Interrupt agent` 作为低频中断操作收纳在 `⋯` 更多菜单中，触发时调用 `POST /session/:id/abort`；设计上不采用顶部红色醒目 banner，亦不与语音转写的恢复操作共用 stop 图标，以便用户清晰区分三种不同维度的状态：语音采集、转写等待以及 agent 运行。相关的 Token 与 Base URL 在 Settings → Speech Recognition 中进行配置，保存在 Keychain 中，不提交至 git。

**消息队列**：当 session 处于 busy 状态时，用户发送的新消息直接进入队列。OpenCode Server 的 `POST /session/:id/prompt_async` 在服务端已内建队列机制——busy 期间接收的消息会自动排队，待当前任务执行完成后依次处理。iOS 端直接调用 `prompt_async` 即可，无需在本地自行维护队列逻辑。若未来服务端 API 发生调整，可退化为本地队列管理。

**Enter 行为调研结论**：经调研，OpenCode Web 客户端在输入框为空时按 Enter 会调用 abort 终止当前运行；输入框有内容时按 Enter 则通过 prompt 发送消息（由服务端队列承接排队）。系统本身并不存在所谓的“智能 steer”机制，仅为简单的终止或排队。因此 iOS 端可提供明确的手动 abort 按钮，无需额外设计复杂的 steer 判定。

额外操作（通过 Chat 顶部 toolbar 按钮调起，从左至右依次为）：
- Session 列表、重命名、Compact、新建 Session（严格按此顺序排列）
- Compact Session（调用 `POST /session/:id/summarize`，用于压缩历史上下文以降低 token 超限风险）（🔲 暂未实现）

#### 4.2.5 Session 管理

用户可从 Chat Tab 顶部左侧按钮进入 Session 列表（支持 slide-over 或 navigation push 两种呈现方式）。该页面**列出当前 workspace 下的全部 Session**，也是核心的功能验证通道：可用于验证网络连接、API 数据解析以及消息与状态渲染的正确性。

在 iPhone 上，除了点击顶部 `Session 列表` 按钮外，还支持从屏幕左侧边缘向右滑动手势直接呼出 Session List。该手势并非新建导航分支，而是复用现有的列表入口，以降低单手握持操作时点击左上角按钮的成本。

Session List 定位为当前工作集的管理控制台，而非单纯的历史归档列表。默认展示 Active sessions，并按更新时间倒序排列；Archived sessions 则作为列表内独立的折叠分区存在，用户无需进入 Settings 即可随时找回。无论是 iPhone 上的 Session sheet 还是 iPad / Vision Pro 上的左侧 sidebar，均统一采用 Active 与 Archived 双分区结构，两分区均支持独立展开与折叠。当前版本暂不提供 session search，避免本地基于 title 的过滤被用户误理解为全量历史搜索。

列表中每个条目包含：Session 标题、更新时间、`summary.files`（该 session 改动所涉及的文件数量）以及当前状态（idle/busy/retry）。针对 Active session 支持新建、切换、归档与删除；针对 Archived session 支持切换查看、恢复与删除。Archive / Restore / Delete 操作统一通过 swipe action 触发，按钮样式沿用现有规范：SF Symbol 图标居上、文本居下。Delete 操作固定位于 trailing swipe，采用红色破坏性样式；Archive / Restore 则固定位于 leading swipe，采用克制的电蓝色或中性色。所有 swipe action 均禁用 full swipe（全滑动直接触发），防止日常误触。Delete 操作不再弹出二次确认对话框——用户完成“滑动 + 点击按钮”的操作链路已具备充分明确的主观意图。

Archive 行为机制：点击 Archive 后，该 session 立即从 Active 分区移至 Archived 分区，不再占用主列表的视觉空间。若被归档的 session 存在子 session，客户端必须递归归档整个 subtree，且归档顺序为“先子后父”，防止父 session 隐藏后子 session 短暂跃升为 Active 根节点。Restore 行为机制：点击 Restore 后，session 重新移回 Active 分区；恢复 subtree 时顺序相反，即“先父后子”，避免子 session 在父节点仍处于归档状态时发生游离。若用户直接在 archived session 中继续发送消息，客户端应先自动恢复该 session 再执行发送，确保重新激活的任务回到当前工作集中。Pin 功能在当前阶段暂不实现。

视觉与交互规范：列表文字默认采用中性灰色，避免触发 iOS 默认的链接蓝色。当前活跃的 Session 采用浅色背景高亮，并在左侧边缘内嵌一条 3pt 宽度的电蓝色 accent 色条（与用户消息、操作卡片统一采用相同的“左侧色条”视觉语言；色条与圆角选中背景融合并完全裁切在圆角区域内，不外溢，亦不与展开 chevron 或缩进层级产生冲突）。选中状态不再展示额外的 checkmark，避免用户将其误判为任务完成状态或多选模式。Archived rows 仍支持点击查看历史，但在视觉层级上弱于 Active rows：标题与时间采用对比度更低的中性色，且不渲染选中 accent 色条，避免形成当前正在活跃处理的视觉心理预期。

#### 4.2.6 Fork Session（会话分叉）

用户可从任意历史消息节点对当前对话执行 fork，生成一个包含该节点之前全部历史记录的全新 session。典型适用场景包括：对 AI 当前回复不满意，希望从特定节点推倒重来；或希望从同一前置条件出发探索不同的提示词方向。

**交互方式**：在每条用户消息底部的模型标签（如 `anthropic/claude-opus-4-6`）旁提供 "..." 更多按钮。点击后弹出菜单，选择 "Fork from here" 选项即可调用 `POST /session/{id}/fork`。服务端创建新 session 并复制选定消息之前的所有历史记录，客户端随后自动切换至新创建的 session 视图。

**API**：调用 `POST /session/{sessionID}/fork`，请求 body 为 `{ "messageID": "..." }`（可选）。接口返回全新的 `Session` 对象。

**实现说明**：采用 SwiftUI 的 `Menu` 组件（点击触发）而非 `.contextMenu`（依赖长按），以提升功能的可发现性。分叉后生成的 session 标题将自动命名为 "{原标题} (fork #N)"。

#### 4.2.7 Session Deep Link（跨入口定位会话）

客户端提供标准统一的只读导航链接协议：

```text
opencode://session/<session_id>
```

该链接可由 Chat 中的 Agent Markdown 输出生成，也可来自 Apple Notes、邮件、网页或其他外部 App。用户点击链接后，客户端在当前连接的 Host 上校验目标 session 是否存在；校验通过后依次切换 project、session 并进入 Chat 页面；若校验失败则维持当前 session 不变，并在界面上提示全局错误信息。若 App 尚未启动或正处于网络重连过程中，系统先暂存导航请求，待当前 Host 恢复可用后再行解析。

Session 的全局检索依然由 Agent 与 workspace 的 semantic-search 能力承接，客户端本地不新增搜索独立页、embedding 索引或 archive 读取功能。Agent 在给出 3-5 个带有原文依据的候选结果后，将明确的操作渲染为 `[在 OpenCode 中打开](opencode://session/<session_id>)`；仅当 metadata 明确标记为 OpenCode 且包含合法 session ID 时，方可生成对应的 action link。

V1 版本的作用域严格限定在当前已配置的 Host 之内。链接本身不携带设备本地的 Host Profile UUID、server URL、认证凭证、query 参数或绝对文件路径，客户端亦不会自动轮询或跨 Host 切换。对于处于 OpenCode 软归档状态的 session，只要当前 server 依然可读即可正常打开；但仅保存在离线 SQLite 或本地 Markdown archive 中的远古历史记录不在自动恢复范围内。

Deep link 属于低权限的纯导航动作，不充当指令执行通道。它不支持直接发送 prompt、批准权限请求、调用 tool、删除或归档 session，且在 Markdown 渲染完成后绝不自动触发跳转。V1 版本暂不支持 message 级别的定位参数；在 Chat 具备稳定可靠的精准滚动与高亮定位能力之前，所有附带 query、fragment 或多余 path 路径的链接均按非法链接拒绝处理。

### 4.3 Files Tab（文件浏览与 Diff）

> Files Tab 在产品定位上属于**兜底入口**，并非主工作流。用户绝大多数文件查看行为均通过 Chat 窗口中的 tool/patch 卡片点击直接完成——在 Chat 消息流中看到 `edit_file` 或 `patch` 卡片时，点击文件路径即可直接调起预览。Files Tab 的存在价值在于满足全局排查诉求：当用户需要宏观浏览全部受修改文件，或需要检索未在 Chat 卡片中提及的文件时，提供可靠的访问通道。因此它不需要追求过于繁复的界面细节，但必须保证基础能力的绝对稳定。

#### 4.3.1 文件树

在 iPhone 上以全屏展示，在 iPad 上作为左侧栏呈现。数据来源于 `GET /file?path=<path>`。

文件树支持以递归树形结构展开与收起目录层级。每个树节点展示文件/目录名称及对应类型图标。存在 git 变更的文件附带明确的颜色标记（绿色代表新增、黄色代表修改、红色代表删除），数据来源于 `GET /file/status`。

顶部配备搜索框，支持通过文件名进行模糊搜索（调用 `GET /find/file?query=...`）。

#### 4.3.2 文件内容查看

点击文件树节点后进入文件内容详情页。数据来源于 `GET /file/content?path=...`。

- **iPhone**：在 Files Tab 导航栈内 push 至内容详情页
- **iPad 三栏**：点击文件后在中栏 Preview 内联呈现；在 Chat 中点击 tool/patch 中的文件路径同样直接刷新 Preview 区域（不弹出独立 sheet）

针对纯文本文件：提供基于等宽字体的代码查看器，展示行号并支持横向滚动。当前版本不做语法高亮，优先确保渲染稳定性与文本可读性。

针对 Markdown 文件：支持在 Preview（富文本预览）与 Markdown source（原始源码）之间无缝切换。Preview 模式基于 MarkdownUI 渲染，针对超长文本行与超大体积文件会自动回退至原始文本模式，防止界面卡顿。

针对 Markdown 内部包含的图片引用，客户端需完整支持 **repo 内部的相对路径解析**，特别是类似 `![x](../assets/foo.png)` 的常见报告引用写法。图片加载不能单纯依赖 MarkdownUI 默认的网络图片加载器，而应由客户端结合当前 markdown 文件所在路径与 workspace 根目录，将其解析为合规的本地文件请求并渲染上屏。该能力在 Files 中直接打开的 `.md` 文件与 Chat 中展示的 AI 报告内保持一致表现。

针对图片文件：支持 base64 解码并内联预览，默认初始比例为 fit-to-screen（整屏适配）；支持手势 pinch 缩放、drag 拖动、double-tap 双击放大，并集成系统级 share sheet。在系统相册权限允许的情况下，share sheet 应支持 `Save to Photos` 操作。

#### 4.3.3 Diff 查看与文档预览

**核心定位**：以**文档审查**为第一优先级。Markdown 渲染、文档 diff 与 Preview 预览属于核心必备能力。

**Markdown 展示规范**：
- 优先采用 **Preview 模式**：用户以富文本 Preview 为主阅读文档；若实现复杂度过高，可提供 Preview / Markdown 切换开关
- **Changes 高亮**：需在 diff 中清晰高亮具体变更。若在 Preview 模式下实现富文本行内高亮存在难度，可在 Markdown 源码界面对 changes 进行高亮标示，用户可在 Preview 模式下对照查看
- 最低支持版本为 iOS 17，无历史系统兼容负担

**两种入口形态**：

**Session Diff**：当前暂不在 iOS 客户端直接展示（因服务端 diff API 在特定边界场景下可能返回空数组）。

**单文件 Diff**：在文件树中点击带有变更标记的文件时，若该文件存在未提交的变更（uncommitted changes），内容详情页将自动切换至 diff 模式展示。

Diff 渲染遵循统一的 unified diff 格式（类似 GitHub 风格）：绿色背景代表新增行，红色背景代表删除行。服务端向客户端返回完整的 `before` 与 `after` 文件内容，由客户端在本地执行 diff 比对与高亮渲染。考虑到手机屏幕宽度受限，默认仅提供 unified 模式，不提供 side-by-side 双栏对照。

#### 4.3.5 Markdown Web Preview（HTML 卡片 / SVG 增强阅读）

打开 `.md` 文档时，默认展示具备丰富视觉结构的排版效果：各类 HTML 状态卡片、内联 SVG 图表以及深色模式阅读均能正常呈现，工具栏支持一键切回纯文本 Native 视图或 Markdown 源码。底层技术细节详见 RFC §7.5。

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

详情与来源 — 决策过程见 [`WORKING.md`](WORKING.md)；完整子项目 PRD / RFC 保留在磁盘 `docs/archive/2026-06_markdown_web_preview_prd.md` / `2026-06_markdown_web_preview_rfc.md`，已从 git 跟踪移除。

### 4.4 Settings Tab

#### 4.4.1 Host Profiles（多 OpenCode 环境）

Settings 顶部不再将 Server Address 与 SSH Tunnel 作为扁平的全局配置项，而是以当前活跃的 `Host` 统一呈现。此处的 Host 代表一个独立的 OpenCode 运行环境，既可以是直连的 LAN / Tailscale / HTTPS server，也可以是通过 SSH gateway 代理访问的隔离 OpenCode 容器。Tailscale、VPN 与局域网对 App 均为透明网络，统归为 Direct transport。

**设计目标**：确保用户在 5 秒内明确当前连接的 OpenCode 环境及其底层传输通道（Direct 或 SSH Tunnel），并能便捷切换到其他 host，避免误触修改底层网络配置。

**Host 列表管理**：

- Settings 顶部展示 Current Host 摘要卡片：包含 profile 名称、transport 类型、地址摘要、实时连接状态与 Test 测试按钮。
- Current Host 卡片内置轻量级连接诊断。连接建立期间展示所处阶段；连接失败时呈现具备明确操作指引的排查文案，而非抛出未经处理的原生 Swift error。
- 点击卡片进入 Hosts 管理页面，完整列出所有已配置的 profiles；当前激活的 profile 在左侧使用 accent 色条与 checkmark 进行高亮标识。
- 列表每行展示 profile 名称、transport 摘要以及最近连接状态（如 `example.com:8006 -> :19001`、`Direct HTTPS + Basic Auth`、`Last used yesterday`）。若该 host 尚无成功连接记录，则明确标注 `Never connected`，禁止将 epoch 时间戳格式化为无意义的长相对时间。
- 点击任意列表行进入 Host Detail 详情页。切换 host 属于详情页内的显式 `Use This Host` 主动作，避免用户因单纯查看配置信息而发生误切换。
- 提供 Add Host、Host Detail、Edit、Duplicate 以及 Delete 操作。在删除当前处于激活状态的 host 前，必须强制用户先切换至其他 host 或进行二次弹窗确认。
- Device Public Key 作为设备维度的通用凭证置于 Hosts 页面底部；该公钥仅供 SSH Tunnel 类型的 host 使用，Direct 类型的 host 无需该项。

**Host Detail（详情页面）**：

- 展示 profile 名称、transport 类型、连接地址摘要、实时连接诊断信息以及最近一次连接尝试时间。
- Direct profile 展示 OpenCode URL 以及是否配置了 Basic Auth username。
- SSH Tunnel profile 展示 Gateway Host、SSH Port、SSH Username、Assigned Remote Port、本地映射的 OpenCode URL `127.0.0.1:4096` 以及已信任的 host fingerprint（若存在）。
- 若当前查看的并非活跃 host，页面提供 `Use This Host` 主操作；同时详情页配备 `Test Connection`、`Edit` 与 `Copy Host Config JSON` 快捷功能。
- SSH Tunnel profile 详情页提供 `Copy This Device Public Key` 入口。私钥部分严格保存在本机的 Keychain 中，不支持任何形式的导出。

**Add Host 添加流程**：

1. 首选推荐 `Import Host Config` 导入入口。用户可直接粘贴管理员分发的标准 setup JSON 配置，防止手动输入时填错 host、port、username 或 remotePort。
2. 手动创建时需先明确选择 `Direct` 或 `SSH Tunnel` 传输类型。
3. Direct 表单仅需填写 Name、OpenCode URL 以及可选的 Basic Auth 鉴权信息。
4. SSH Tunnel 表单需录入 Name、SSH Gateway Host、SSH Port、SSH Username 以及 Assigned Remote Port。OpenCode URL 字段对用户锁定不可编辑，保存后统一由 App 通过本地 `127.0.0.1:4096` 代理隧道建立连接。
5. SSH Tunnel 表单必须显式提供 `Copy This Device Public Key` 按钮，并附带明确的安全指引：“请将公钥提供给 server 管理员，严禁向外分享 private key”。
6. Test Connection 根据当前配置的 transport 执行链路校验：Direct 模式直接向远端发起 `/global/health` 探活请求；SSH 模式先建立 SSH 隧道，随后向本地 OpenCode 代理端口发起 health 校验。
7. 点击 `Save` 仅代表本地 profile 保存成功；只有通过 `Test Connection` 才代表网络连接校验通过。在 UI 设计上必须将“保存配置”与“连接就绪”明确分离开来。

**切换行为机制**：

- 切换 host 时，系统主动断开当前已建立的 SSH tunnel 与 SSE 长连接，随后加载并应用目标 profile。
- 切换完成后重置当前 session 的选中状态；session 与 project 的状态数据在逻辑上归属于具体的 host 维度，后续版本可扩展支持按 host 记忆上次选中的 project/session。
- 若目标 host 启用了 SSH Tunnel，App 可尝试自动建立隧道连接；若连接失败仅更新当前连接状态，不弹出打断性的阻塞式 alert 弹窗。
- Basic Auth 认证凭据按 profile 独立隔离存储在 Keychain 中；SSH private key 默认在设备维度全局共用同一密钥对。

#### 4.4.2 Direct Transport

Direct 模式适用于 App 能直接与 OpenCode 实例通信的网络场景：如本地局域网、Tailscale / VPN 虚拟专网或公网 HTTPS 服务器。

**配置项清单**：

| 字段 | 说明 | 默认值 |
|------|------|--------|
| Name | profile 名称 | 从 host 推断或用户填写 |
| OpenCode URL | `ip:port` 或 `http(s)://host:port` | - |
| Username | Basic Auth 用户名，可选 | - |
| Password | Basic Auth 密码，可选，存入 Keychain | - |

**协议安全提示**：当 Direct 模式配置为 HTTP 协议且目标地址不属于 localhost、局域网私有网段或 Tailscale MagicDNS（`*.ts.net`）时，界面展示非阻塞的警告提示，建议用户升级为 HTTPS。该提示仅针对 Direct 模式生效；在 SSH Tunnel 模式下，本地回环地址 `http://127.0.0.1:4096` 属于设计预期，不弹出 HTTPS 协议警告。

#### 4.4.3 SSH Tunnel Transport（远程访问）

适用于通过 SSH gateway 访问部署在内网或隔离容器中的托管 OpenCode Server。网络通信拓扑如下：

```
iOS App → SSH Gateway (:8006) → Assigned Remote Port (:19001) → OpenCode (127.0.0.1:4096)
```

前置准备条件：
- 管理员已在服务端完成独立 OpenCode 实例部署并分配了对应的 remote port
- 用户已将 iOS 设备的公钥提供给管理员配置；私钥严格保存在本机 Keychain 中

**配置项清单**：

| 字段 | 说明 | 默认值 |
|------|------|--------|
| Enable SSH Tunnel | 开关 | Off |
| Gateway Host | SSH gateway 地址 | - |
| SSH Port | SSH 端口 | 8006 |
| Username | SSH 用户名 | opencode |
| Assigned Remote Port | 管理员分配的 remote port | 19001 |

**密钥管理规范**：

- App 在首次使用时自动生成 Ed25519 密钥对
- 私钥安全存放在 iOS Keychain（设置访问控制属性为 `kSecAttrAccessibleWhenUnlocked`）
- 公钥展示在 Settings 界面中，支持一键复制到剪贴板
- 提供密钥轮换入口（支持重新生成全新密钥对）

**首次配置流程**：

1. 进入 Settings → SSH Tunnel
2. App 自动生成本地密钥对
3. 复制生成的公钥并发送给 OpenCode host 管理员
4. 管理员在服务端完成授权后，返回 gateway host、SSH 端口、用户名及 assigned remote port 参数
5. 在 App 中逐项录入上述参数，并开启 SSH Tunnel 功能开关
6. 将 Server Address 设置为 `127.0.0.1:4096`（通过本地隧道转发），并点击上方的 `Test Connection` 进行连通性验证

**连接状态展示**：

- 实时显示四种状态：Connected / Connecting / Disconnected / Error。
- SSH Tunnel 的连接诊断需具备链路拆解能力，至少能明确区分 SSH gateway 连通性、SSH auth 鉴权、本地 tunnel 代理通道以及 OpenCode health check 四个阶段。
- 发生异常时给出明确的失败原因与排障建议，例如公钥未授权时提示用户复制当前设备 public key 发送给管理员；Basic Auth 校验失败时提示检查用户名与密码配置。

**安全要求**：

- 仅支持基于公私钥（key-based）的 SSH 认证，不开放密码认证
- 首次连接采用 TOFU（Trust On First Use）策略自动信任并保存服务器的 host fingerprint，后续连接执行严格指纹校验；UI 界面提供 fingerprint 查看与 reset trusted host 重置功能

#### 4.4.4 Model Presets

**当前实现机制**：内置固定预设模型列表（GLM-5.1、GPT-5.4、GPT-5.3 Codex、DeepSeek），暂不支持导入与排序。发送消息时在请求 body 中携带 `model: { providerID, modelID }` 结构。

#### 4.4.5 Project (Workspace)

用于指定当前需要浏览的 OpenCode 项目上下文。OpenCode Server 原生支持多项目管理，每个项目拥有独立的 session 数据集。iOS 客户端通过 `GET /session?directory=<worktree>` 按项目目录筛选对应的 sessions。

**选择已有项目**：
- 调用 `GET /project` 获取服务端已知的所有项目列表
- 使用 Picker 组件呈现项目，选项显示名称默认截取 worktree 路径的末级目录名（如 `knowledge_working`、`agentic_trading`）
- 用户选中的项目持久化存储在 UserDefaults 中

**自定义路径支持**：
- 提供「Custom path」选项，支持用户手动输入任意 worktree 绝对路径
- 适用于服务端存在 session 记录但未被自动收录进 project 列表的边缘目录场景
- 若输入路径有误，接口 `/session?directory=xxx` 将返回 0 个 session，用户可直接感知

**默认项目行为**：若用户未显式选择项目，调用 `GET /session` 时不传 `directory` 参数，此时默认沿用服务端当前打开的项目（与 Web 端逻辑保持一致）。选定具体项目后，客户端调用 `GET /session?directory=xxx&limit=100` 获取对应数据。

**创建 Session 限制**：新建 session 仅在选择 Server default 时允许操作。因服务端的 `POST /session` 接口不支持传入 directory 参数，新创建的 session 始终绑定在 server 当前打开的 project 下。当用户手动指定了具体 project 时，新建按钮将自动置灰并附带 info 提示图标，告知用户需通过命令行启动 OpenCode 并指定不同的工作目录后再行创建。

#### 4.4.6 外观

- **主题跟随系统**（Light/Dark/Auto）：依据 iOS 系统的明暗 theme 设置自动切换对应的展示风格
#### 4.4.7 About

- 展示当前 App 版本号
- 展示当前连接的 OpenCode Server 版本（取自 `GET /global/health` 响应中的 `version` 字段）

### 4.5 Car Mode（Experimental）

Car Mode 是专为 iPhone 设计的前台语音交互模式。在不便阅读冗长对话或打字的驾驶场景下，用户仅需单次点击即可完成“口述指令 → 自动提交 → 收听精简结论”的闭环。该功能属于 OpenCode iOS Client 的内建特性，不维护独立的车载 App，亦不属于独立的 CarPlay App。

#### 4.5.1 产品范围

- Car Mode 默认处于关闭状态，仅在 Settings → Experimental Features 中提供显式开启入口。
- 开启该功能后，iPhone 底部的 Tab 切换顺序为 Chat / Files / Car / Settings；关闭后恢复为 Chat / Files / Settings。
- 在 iPad 与 Apple Vision Pro 上不展示 Car Tab 及其配置开关（包括处于 iPad compact window 模式下）。
- 用户点击大尺寸主按钮即启动录音，再次点击即可结束音频采集并自动触发发送，流程完全跳过普通 Chat 模式的 composer 确认环节。
- AI 的回复内容被严格约束为简短、可直接朗读的 structured speech 格式；系统调用 Apple TTS 引擎完成语音播报后自动重置回 idle 待机状态。
- 允许触发的客户端 action 包含 `open_navigation` 与 V0 版本的 `health_quantification.export_all`。其中 Maps 导航由 iOS 本地组装目标 URL；Health 数据导出则通过本地权限校验、受限 App handoff 以及原 session callback 协作完成，产品交互契约详见 [`features/client_capabilities/prd.md`](features/client_capabilities/prd.md)。

Car Mode 并不承诺在系统切换至 Maps 或其他 App 后仍能维持后台持续录音、保活 SSE 连接或继续执行 TTS 朗读。一旦 App 进入后台，立即停止当前的前台交互逻辑，但持久化保留 Car session；待用户重新返回 App 后可继续在原上下文中交互。

#### 4.5.2 独立 Session 与可见性

Car Mode 不复用普通 Chat 当前选中的对话上下文。每个 `(host profile, workspace)` 维度独立维护一个专属、持久化的 Car session，并在本地记录最近处理的 assistant message ID、待确认事项（pending confirmation）以及最后活跃时间戳。

- 首次发起交互时，自动创建标题为 `Car Mode` 的专用 session。
- 后续每次发送前均会校验该 session 是否依然有效；若收到 404 错误则清除旧的本地映射并自动创建全新 session。
- 若用户在普通 Session 列表中手动归档了当前 Car session，客户端在下一次通过 Car 模式发起请求前，会自动向该 session 写入兼容性恢复标记 `time.archived = -1`，随后继续向原 session 提交消息。由于 iOS 客户端是依据 `archived > 0` 来判断归档状态的，因此该 session 将自动重新显现在 iOS 的 Active 列表中。
- 上述恢复逻辑仅确保在 iOS 客户端内的可见性。OpenCode Web 端将 active 严格定义为 `archived === undefined`，因此可能依然无法展示标记为 `-1` 的 session；Car Mode 明确不对服务端引入非标 patch，亦不对原 session 进行 fork 或复制。
- 支持用户手动开启全新的 Car session；但单纯切换 Tab、调起外部 Maps 或短期切出 App 均不得触发自动新建 session。

停车后，用户可随时在普通 Chat 列表中打开 Car session，查看完整的消息记录与工具调用明细。当 structured assistant 响应中不包含 text part 时，Chat 视图会自动将 `assistant.structured.speech` 作为可读的 fallback 内容进行展示。

#### 4.5.3 回复、确认与现实世界动作

每轮交互均会固定附带 Car 专用的 system prompt 与 JSON Schema 约束。AI 的语音回复遵循“结论先行”原则，严禁包含 Markdown 格式、URL 链接、代码块或工具调用的中间流水，单次播报的目标时长控制在 8-12 秒，最长不得超过 15 秒。执行状态严格收敛为三种：`completed`、`needs_confirmation` 与 `failed`。

| 类型 | 示例 | 默认行为 |
|---|---|---|
| Read | 车库门关了吗；开车多久；有什么新邮件 | 直接执行并朗读短结论 |
| Prepare | 摘要邮件；起草消息 | 直接准备，明确尚未发送 |
| Explicit server commit | 打开车库门；把刚才原因发给联系人 | 用户参数明确时执行，随后读回结果 |
| Proposed server commit | Agent 主动建议发送或控制设备 | 返回 `needs_confirmation`，下一轮确认后执行 |
| Client handoff | 导航到明确目的地；同步过期的 Health 数据 | 返回 typed action，由 iOS 打开受限目标 App |
| Ambiguous | 多个联系人、门或目的地 | 最多追问一次，仍不明确则取消 |

必须严格遵循：仅有来自用户消息的显式授权方可触发具有现实世界副作用的操作。在邮件、网页正文、搜索结果以及工具输出中出现的指令只能作为被动数据处理，严禁据此直接授权发送消息、控制智能设备或触发客户端 action。V1 版本严禁开放任意破坏性的 shell 执行、代码提交、线上发布、转账付款或不受限的多步现实世界操作。

Smart Home、邮件、iMessage 以及 route-duration 等具体能力，仍需正式注册为系统级白名单 skills 或 typed tools，并完成真实的 E2E 全链路打通；通用的 `read + bash` 方式仅允许在原型探索（spike）阶段使用，不能作为正式产品的安全权限边界。

#### 4.5.4 状态与失败恢复

主界面保留一个核心的视觉操作按钮，同时直观呈现当前状态、最近识别的 transcript、最近播报的 speech 以及错误提示。完整的状态流转机制如下：

```text
idle → recording → finalizing → waitingReply
     → speaking / awaitingConfirmation / failed → idle
```

仅在最终确认的 final transcript 识别成功后方可自动触发消息发送；partial transcript（中间过渡结果）或识别失败均严禁触发现实世界的任何动作。在 `waitingReply` 等待响应阶段禁止重复提交请求，但允许用户执行取消并向服务端发送 abort 指令。TTS 语音播报与 Maps 导航动作必须基于 completed assistant message ID 执行精确去重。

#### 4.5.5 分期与非目标

前台 Car Mode 的核心链路均已实现并落地：包括实验功能开关、iPhone 专属 UI、独立 session 隔离、VoiceFlow 自动提交、structured reply 解析、Apple TTS 语音播报、typed Maps 导航唤起、Health export callback 回调以及普通 Chat 中的历史记录回退展示。

后续规划主要聚焦于两条演进路线：一是将 Smart Home、邮件、iMessage 与 route-duration 等高频能力正式产品化为稳定的 capability boundary；二是将现有的同步结构化请求全面重构为 `prompt_async + SSE + message reload` 异步模型，以支持更稳健的前后台状态恢复与 exactly-once 幂等动作执行。需要明确的是，即便后续完成了异步恢复机制，亦不代表支持在后台持续进行语音对话。

开发原生的 CarPlay App、在 Maps 前台运行期间实现免按键持续对话、支持任意 URL action 跳转以及开放式的现实世界自动化操作，均明确不属于当前版本的产品范围。

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

数据迁移策略：在第一版实现中，可保留现有的 `serverURL`、Basic Auth 以及 `SSHTunnelManager.config` 等字段作为当前活跃 profile 的展开缓存，但数据持久化的单一事实来源（source of truth）必须统一收敛至 `hostProfiles`。在切换 profile 时，由选中的 profile 将数据写回这些运行时字段，从而避免一次性深层重构危及 APIClient、SSE 以及 SSH tunnel 模块的运行稳定性。

### 5.2 SSE 事件处理

收到 SSE 事件后，根据其 `type` 字段分发至对应业务逻辑进行处理：

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

采用“全量状态拉取 + 增量事件订阅”的组合模式，确保即便 SSE 连接在 App 切入后台期间被系统中断，重新回到前台时也不会发生状态丢失或数据不一致。

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

**目标**：成功连接 server、正常发送消息，并能实时接收 AI 的流式响应。

| 功能 | 说明 |
|------|------|
| Server 连接 | 手动输入 IP:Port，Basic Auth |
| SSE 事件流 | 连接、断开、重连、前后台切换 |
| Session 基础 | 列表、创建、切换（删除暂未实现） |
| 消息发送 | 文本输入、发送（使用 `prompt_async`）、查看响应；busy 时消息自动入队 |
| 流式渲染 | text part 的实时打字机效果 |
| 模型切换 | 预设模型列表、发送时指定模型 |

**预估工作量**：2-3 周（基于具备 SwiftUI 开发经验的前提）

### Phase 2 — 完整交互

**目标**：实现对 AI 执行全流程的有效监控与审查能力。

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

**目标**：补齐完整的文件浏览与**文档审查**能力，并针对 iPad 与 Vision Pro 完成大屏三栏布局适配。

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
| **推送通知 / Live Activity** | 当 AI 暂停等待人类决策时（question / permission / 运行完成），通过 APNs 或 Live Activity 主动发起通知，消除人机异步空转。这是完善 Steer 闭环的核心工程能力 |
| **Session 辨识度增强** | 优化活跃与非活跃 Session 的视觉区分度，降低用户在长列表中定位目标会话的认知负担 |
| mDNS 自动发现 | 局域网内自动发现 OpenCode server |
| Widget | 提供 iOS 桌面组件，实时显示当前 session 状态 |
| Haptic 反馈 | 在关键操作节点引入触觉震动反馈 |
| Spotlight 集成 | 支持通过系统 Spotlight 快速检索最近 session |

## 9. 已知限制与风险

**网络依赖**：App 完全依赖与 OpenCode Server 的网络连接。若 Server 不可达（如网络中断或 Server 进程未启动），App 将无法正常工作。目前支持局域网直连与 SSH tunnel 远程访问两种模式；在弱网环境下，通过“拉取最近 3 轮 + 下拉分页加载”策略降低首屏等待耗时。

**SSE 在 iOS 上的行为**：当 App 进入后台时，iOS 系统会积极回收网络资源并断开长连接。因此必须设计健壮的重连机制与前台状态恢复逻辑，且不建议在后台强行维持 SSE 活跃。

**屏幕尺寸**：在 iPhone 的窄屏空间下，代码与 diff 内容的横向排版与可读性面临客观挑战。需要细致优化横向滚动、字体缩放等交互细节。相对而言，iPad 大屏能提供更优的视觉呈现。

**Server API 稳定性**：目前 OpenCode 的 HTTP API 尚未提供严格的版本化承诺（如未引入 `/v1/` 等版本前缀）。后续 Server 版本的演进可能引入 breaking changes。建议 iOS 客户端对 API 响应实施防御性解析策略，遇到未知字段时静默忽略而非直接 crash。

**安全策略**：初期 App 主要应用于受信任的本地局域网环境，整体安全风险可控。若后续开放公网直连访问，需全面引入 TLS 加密与 token-based 鉴权等加固方案。当前采用的 Basic Auth over HTTP 仅适用于局域网环境，不应直接暴露在公网中。**ATS 策略例外**：局域网（私有 IP 段、localhost、.local）与 Tailscale MagicDNS（`*.ts.net`）允许使用 HTTP；其余公网 WAN 请求强制要求 HTTPS。Info.plist 中的 `NSExceptionDomains` 已对 `ts.net` 进行相应豁免配置。

**人机异步空转（Notification 缺失）**：当 AI 因触发 `question` tool、permission 权限申请或等待人类审查而挂起时，若用户已离开 App（iOS 切入后台），目前缺乏主动通知手段。这会导致两端陷入相互等待的“空转”状态——AI 在等待人类指令，而人类并不知晓需要做出决策。该问题的本质属于 iOS 系统的工程能力限制，而非单纯的 UX 交互设计范畴：需要引入 Push Notification（APNs）或 Live Activity 突破后台限制以主动唤醒用户。虽然该功能在 Phase 4 中暂标为“暂不实现”，但应作为高优先级的工程增强项——它直接关乎 Steer 统领范式的闭环效率。

## 10. 已决事项

1. **消息发送 API**：选定使用 `POST /session/:id/prompt_async`。通过服务端源码调研确认：同步（sync）与异步（async）接口底层均调用同一个 `SessionPrompt.prompt()` 逻辑，异步模式仅不阻塞等待最终响应；两者的消息创建、任务处理及 SSE 事件推送行为完全一致。鉴于 iOS 客户端统一配合 SSE 获取实时结果，采用 async 异步模式更为合理。

2. **大型 Session**：暂不作特殊处理。当前设计预期单 session 消息量不会超过百条。

3. **推送通知**：当前阶段暂不实现，但已识别为高优先级工程增强项——当 AI 挂起等待人类决策时（如 question / permission / 执行完成），需依托 APNs 或 Live Activity 绕过 iOS 后台限制主动触达用户，从而消除人机异步等待。

4. **多项目支持**：当前阶段暂不展开实现。

5. **默认 Server**：默认地址采用 `127.0.0.1:4096`。默认不启用身份认证，但客户端需完整实现 Basic Auth 鉴权支持以供按需配置。

## 11. 实现起步指南

### 11.1 项目创建

当前代码仓库已包含可直接打开的完整 Xcode 工程。对于新接入的开发者，推荐采用以下两种起步方式：

1. 通过 README 中提供的 TestFlight 链接直接安装预编译版本进行体验
2. clone 本地仓库后直接打开 `OpenCodeClient/OpenCodeClient.xcodeproj` 进行本地构建与调试

### 11.2 依赖与结构

- **网络层**：采用 `URLSession` 原生实现 REST 请求与 SSE 事件流，无需引入 Alamofire 等第三方网络库
- **状态管理**：采用 iOS 17+ 原生的 `@Observable` 配合 SwiftUI 实现响应式状态绑定
- **Markdown**：集成开源库 [MarkdownUI](https://github.com/gonzalezreal/MarkdownUI)
- **主题**：通过 `@Environment(\.colorScheme)` 监听并跟随系统主题切换
- **SSH Tunnel**：集成 Citadel 库实现 SSH 隧道能力

当前客户端代码采用按职责分层的清晰目录架构：

- `Views/`：包含 Chat、Files、Settings 以及 Split View 等各模块 UI 视图
- `Controllers/`：承载 permission 与 question 等交互事件的逻辑控制器
- `Services/`：封装 API 通信、SSE 事件流、SSH 隧道、语音录音与转写等核心服务
- `Stores/`：管理 Session、Message、File、Todo 等核心业务状态
- `Models/`：定义 Session、Message、Project、Question、ModelPreset 等数据结构
- `Support/`：收纳本地化多语言与通用支持组件
- `Utils/`：提供 Keychain 存储、PathNormalizer 路径处理、LayoutConstants 布局常量等基础工具库

### 11.3 建议的实现顺序

1. **Phase 1**：跑通 Server 连接、SSE 事件流、Session 管理、消息发送与基础流式渲染
2. **Phase 2**：实现完整的消息 Part 渲染、权限手动审批、主题切换以及基于 `prompt_async` 的消息排队机制
3. **Phase 3**：完成文件树、Markdown 预览、文档 Diff 比对以及变更高亮渲染

### 11.4 与 OpenCode Server 的对接

默认 Server 连接地址为 `127.0.0.1:4096`（无认证）。若服务端开启了 `OPENCODE_SERVER_PASSWORD` 等鉴权环境变量，在客户端 Settings 中填入对应的 Username 与 Password 即可。局域网直连场景下可直接配置为服务端的局域网 IP 地址；远程访问场景则可通过 SSH tunnel 代理转发至本地的 `127.0.0.1:4096` 端口。

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
