# OpenCode iOS Client — Product Requirements Document

> Version 0.3 · Working Draft · Mar 2026

## 1. 产品定位

OpenCode iOS Client 是一个面向 OpenCode 服务端的原生 iOS 远程控制应用。它不是一个独立的 AI 编程工具，而是运行在 Mac/Server 上的 OpenCode 实例的**移动端延伸**——让用户可以在沙发上、通勤中或任何远离电脑的场景下，发送指令、监控 AI 工作进度、浏览代码变更、切换模型。

核心设计原则：**轻量、快速、只读为主、交互为辅**。所有繁重的配置（Provider 密钥、MCP 服务、workspace 设置）都在电脑端完成，iOS 端只做必要的交互和消费。

### 1.1 它不是什么

这个 App 不试图做以下事情：在手机上编辑代码、在手机上运行 OpenCode server、替代完整的 Web UI。它的价值在于"随时掏出手机看一眼 AI 干到哪了，必要时踢它一脚让它换个方向"这种场景。

## 2. 目标用户与使用场景

目标用户是日常使用 OpenCode 的开发者（初期就是作者自己），典型场景包括：

**场景 A — 远程监控**：在电脑上启动了一个耗时的重构任务，离开工位去倒咖啡。掏出手机，看到 AI 正在处理第 3 个文件，已经修改了 12 个文件，一切正常。

**场景 B — 快速纠偏**：手机上看到 AI 走偏了，正在用错误的方法实现某个功能。快速发一条消息："停，不要用继承，改用组合模式"，然后放回口袋。

**场景 C — 模型 A/B 测试**：想比较不同模型（如 GPT-5.3 Codex / Spark / Opus / GLM5）对同一个任务的表现。在手机上一键切到另一个模型，发送相同的指令，观察差异。

**场景 D — 文档审查**：AI 完成了一轮修改，在手机上浏览 Markdown 文档的 diff，以 Preview 模式为主查看变更，确认文档改动合理后让 AI 继续下一步。代码审查为辅——AI 能力已足够写出好代码，主要需要的是文档审查。

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
| GLM-5 | `zai-coding-plan` | `glm-5` |
| Opus 4.6 | `anthropic` | `claude-opus-4-6` |
| Sonnet 4.6 | `anthropic` | `claude-sonnet-4-6` |
| GPT-5.4 | `openai` | `gpt-5.4` |
| GPT-5.3 Codex | `openai` | `gpt-5.3-codex` |

**Agent 选择器**：下拉列表，内容从 `GET /agent` API 动态获取。过滤 `hidden != true` 的 agents 后显示。每个选项显示 agent 名称（如 `Sisyphus`），description 可作为 tooltip 或 subtitle。

**iPhone 显示策略**：iPhone 上使用短名（`Opus` / `Sonnet` / `GPT` / `GLM`）以适配窄宽；iPad 上显示全称。

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

#### 4.2.4 输入框

底部固定输入框，支持多行文本。右侧为发送按钮和麦克风按钮。Session 操作（新建、重命名、列表、Compact）在 Chat 顶部 toolbar，不在输入框左侧。

**草稿持久化（Draft Persistence）**：未发送的输入内容按 sessionID 保存（本地持久化），切换到其他 session 再切回时仍可恢复；发送成功后清空草稿。

**语音输入（Speech Recognition）**：输入框右侧麦克风按钮。点击开始录音，再次点击停止并调用 AI Builder `/v1/audio/transcriptions` 转写，将文本追加到输入框。Token 和 Base URL 在 Settings → Speech Recognition 配置，存 Keychain，不提交到 git。

**消息队列**：当 session 处于 busy 状态时，用户发送的消息进入队列。OpenCode Server 的 `POST /session/:id/prompt_async` 在服务端已支持队列——busy 时会将消息入队，当前运行结束后自动处理。iOS 端调用 `prompt_async` 即可，无需本地维护队列。若未来 API 变更，可退化为本地队列维护。

**Enter 行为调研结论**：OpenCode Web 客户端在空输入时按 Enter 会调用 abort 终止当前运行；有内容时按 Enter 发送消息（通过 prompt，消息由服务端队列处理）。无「智能 steer」机制，仅终止或排队。iOS 端可提供手动 abort 按钮，无需实现额外 steer。

额外操作（通过 Chat 顶部 toolbar 按钮，从左到右依次为）：
- Session 列表、重命名、Compact、新建 Session（按此顺序排列）
- Compact Session（调用 `POST /session/:id/summarize`，压缩历史以降低 token 超限风险）（🔲 暂未实现）
- 中止当前运行（调用 `POST /session/:id/abort`）

#### 4.2.5 Session 管理

从 Chat Tab 顶部左侧的按钮进入 Session 列表（slide-over 或 navigation push）。**列出 workspace 下所有已有 Session**，是重要的功能验证手段：可验证连接是否正确、API 解析是否正常、消息/状态能否正确展示。

在 iPhone 上，除顶部 `Session 列表` 按钮外，还支持从屏幕左边缘向右滑入的手势来打开同一个 Session List。这个手势的目标不是提供新的导航分支，而是复用现有列表入口，降低单手操作时点按左上角按钮的成本。

列表显示所有 Session，按时间倒序。每个条目显示：标题、更新时间、`summary.files`（该 session diff 涉及文件数）和状态（idle/busy/retry）。支持新建 Session、切换 Session，也支持删除 Session。

视觉与交互：列表文本默认使用中性色（灰）以避免 iOS 默认的“链接蓝”。当前活跃 Session 使用轻量背景色高亮，并在右侧显示选中标记。

#### 4.2.6 Fork Session（会话分叉）

用户可以从任意消息处 fork 当前对话，创建一个新 session，包含该消息之前的全部历史。典型场景：AI 回复不满意，想从某个节点重新开始；或者想从同一个起点尝试不同的提问方向。

**交互方式**：每条用户消息底部的模型标签（如 `anthropic/claude-opus-4-6`）旁边显示一个 "..." 按钮。点击后弹出菜单，包含 "Fork from here" 选项。点击后调用 `POST /session/{id}/fork`，服务端创建新 session 并复制指定消息之前的全部消息历史，客户端自动切换到新创建的 session。

**API**：`POST /session/{sessionID}/fork`，body 为 `{ "messageID": "..." }`（可选）。返回新的 `Session` 对象。

**实现说明**：使用 SwiftUI `Menu`（tap 触发）而非 `.contextMenu`（需长按），确保可发现性。Fork 后的 session 标题自动变为 "{原标题} (fork #N)"。

### 4.3 Files Tab（文件浏览与 Diff）

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

### 4.4 Settings Tab

#### 4.4.1 Server Connection

- Server Address：文本输入框，格式 `ip:port` 或 `http(s)://host:port`，默认 `127.0.0.1:4096`
- Username：可选，默认 `opencode`
- Password：可选，存入 Keychain
- 连接状态指示：显示 Connected / Disconnected / Connecting
- 协议 (Scheme) 展示：当使用 HTTP 且未启用 SSH tunnel 时，显示协议（HTTP/HTTPS）与 info 图标。Tailscale MagicDNS（`*.ts.net`）允许 HTTP，协议与图标显示灰色；其他 WAN 要求 HTTPS，协议与图标显示红色。info 悬停说明中英双语：Tailscale 不要求 HTTPS，其他广域网仍要求 HTTPS。
- "Test Connection" 按钮：调用 `GET /global/health` 验证连接

#### 4.4.2 SSH Tunnel（远程访问）

用于在非局域网环境下通过 SSH 隧道访问家里的 OpenCode Server。网络拓扑：

```
iOS App → 公网 VPS (SSH) → VPS:18080 → 家里 OpenCode (127.0.0.1:4096)
```

前提条件：
- 家里机器需要先建立反向隧道到 VPS：`ssh -R 127.0.0.1:18080:127.0.0.1:4096 user@vps`
- 用户需要在 VPS 上配置公钥认证

**配置项**：

| 字段 | 说明 | 默认值 |
|------|------|--------|
| Enable SSH Tunnel | 开关 | Off |
| VPS Host | VPS 地址 | - |
| SSH Port | SSH 端口 | 22 |
| Username | SSH 用户名 | - |
| VPS Port | VPS 上转发的端口 | 18080 |

**密钥管理**：

- App 自动生成 Ed25519 密钥对
- 私钥存储在 iOS Keychain（`kSecAttrAccessibleWhenUnlocked`）
- 公钥在 Settings 中显示，支持一键复制
- 支持密钥轮换（重新生成）

**首次设置流程**：

1. 打开 Settings → SSH Tunnel
2. App 自动生成密钥对
3. 复制公钥，SSH 到 VPS 添加到 `~/.ssh/authorized_keys`
4. 填写 VPS 地址、用户名、SSH 端口、VPS 端口
5. 复制 app 生成的 reverse tunnel command，在电脑上执行
6. 开启 SSH Tunnel 开关
7. Server Address 改为 `127.0.0.1:4096`（通过隧道访问），并在上方点 `Test Connection`

**连接状态**：

- 显示 Connected / Connecting / Disconnected / Error
- 错误时显示具体原因（如"公钥未授权"）

**安全要求**：

- 只支持 key-based 认证，不支持密码认证
- 首次连接采用 TOFU 自动信任并保存服务器 fingerprint，后续严格校验；UI 提供 fingerprint 展示与 reset trusted host

#### 4.4.3 Model Presets

**当前实现**：固定预设列表（GLM-5、Opus 4.6、Sonnet 4.6、GPT-5.4、GPT-5.3 Codex），无导入、无排序。发送消息时在 body 中携带 `model: { providerID, modelID }`。

#### 4.4.3 Project (Workspace)

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

#### 4.4.4 外观

- **主题跟随系统**（Light/Dark/Auto）：根据系统 theme 切换明暗两种格式
#### 4.4.5 About

- 当前 App 版本
- 连接的 OpenCode Server 版本（来自 `GET /global/health` 的 `version` 字段）

## 5. 数据流与状态管理

### 5.1 核心状态模型

```swift
@Observable class AppState {
    // Connection
    var serverURL: String
    var isConnected: Bool
    var serverVersion: String?
    
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

### Phase 4 — 打磨与增强（暂不实现）

| 功能 | 说明 |
|------|------|
| mDNS 自动发现 | 局域网自动发现 OpenCode server |
| 推送通知 | AI 完成任务时通过 APNs 通知（需要 server 端配合或轮询） |
| Widget | iOS Widget 显示当前 session 状态 |
| Haptic 反馈 | 关键操作的触觉反馈 |
| Spotlight 集成 | 搜索最近的 session |

## 9. 已知限制与风险

**网络依赖**：App 完全依赖与 OpenCode Server 的网络连接。如果 Server 不可达（网络不通、Server 未启动），App 无法使用。当前支持局域网直连与 SSH tunnel 远程访问；弱网下通过“最近 3 轮 + 下拉扩展历史”降低首屏延迟。

**SSE 在 iOS 上的行为**：iOS 会在 App 进入后台后积极断开网络连接。需要实现可靠的重连和状态恢复机制。不建议在后台保持 SSE 连接。

**屏幕尺寸**：代码和 diff 在 iPhone 窄屏上的可读性是一个持续挑战。需要仔细设计横向滚动、字号调节等交互。iPad 上的体验会显著更好。

**Server API 稳定性**：OpenCode 的 HTTP API 目前没有正式的版本承诺（没有 `/v1/` 前缀）。Server 更新可能引入 breaking changes。建议 iOS 端对 API 响应做防御性解析，对未知字段忽略而非 crash。

**安全**：初期 App 仅用于本地局域网，安全风险较低。如果后续支持公网访问，需要考虑 TLS、token-based auth 等增强方案。当前的 Basic Auth over HTTP 在局域网环境下可接受，但不适合公网暴露。**ATS 例外**：局域网（私有 IP、localhost、.local）与 Tailscale MagicDNS（`*.ts.net`）允许 HTTP；其他 WAN 强制 HTTPS。Info.plist 中 `NSExceptionDomains` 对 `ts.net` 豁免。

## 10. 已决事项

1. **消息发送 API**：使用 `POST /session/:id/prompt_async`。源码调研确认：sync 与 async 均调用同一 `SessionPrompt.prompt()`，async 仅不 await 响应；消息创建、处理、SSE 推送行为完全一致。iOS 端配合 SSE 获取结果，async 更合适。

2. **大型 Session**：暂不考虑。不预期 session 超过百条消息。

3. **推送通知**：暂不实现。

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
