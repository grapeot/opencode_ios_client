# RFC-001: OpenCode iOS Client 技术方案

> Request for Comments · Draft · Feb 2026

## 元数据

| 字段 | 值 |
|------|------|
| **RFC 编号** | RFC-002 |
| **标题** | OpenCode iOS Client 技术方案 |
| **状态** | Draft |
| **创建日期** | 2026-02 |
| **PRD 引用** | [OpenCode_iOS_Client_PRD.md](OpenCode_iOS_Client_PRD.md) |
| **API 参考** | [OpenCode_Web_API.md](OpenCode_Web_API.md) |

---

## 摘要

本 RFC 提出 OpenCode iOS Client 的技术实现方案，服务于 PRD 定义的产品目标。核心是：在 iOS 17+ 上构建一个轻量、以 SwiftUI 为主的原生客户端，通过 HTTP REST + SSE 与 OpenCode Server 通信，实现远程监控、消息发送、文档审查等能力。本文档聚焦技术选型、架构设计与关键实现细节，供实现前评审与共识。

---

## 背景

### 问题

开发者使用 OpenCode 时，常需在电脑前等待 AI 完成耗时任务，或离开工位后无法及时了解进度、无法快速纠偏。现有 Web 客户端需在浏览器中使用，移动端体验不佳；TUI 绑定在终端，无法在手机上使用。

### 目标

提供原生 iOS 客户端，让用户可在手机/平板上：
- 监控 AI 工作进度
- 发送消息、切换模型
- 以文档审查为主查看 Markdown diff
- 必要时中止或排队新指令

### 约束

- 最低 iOS 17（使用 Observation 框架）
- 不引入本地 AI 推理、文件系统或 shell 能力
- 支持局域网直连与 SSH tunnel 远程访问；公网场景要求 HTTPS 或 SSH 转发

---

## 方案

### 1. 整体架构

```
┌─────────────────────────────────────────────────────────────────┐
│                        iOS Client (SwiftUI)                       │
├─────────────────────────────────────────────────────────────────┤
│  Views                 │  State                   │  Services     │
│  ─────────             │  ─────────               │  ─────────    │
│  ChatTab (Views/Chat/) │  AppState (@Observable)   │  APIClient    │
│  FilesTab              │  SessionStore, etc.      │  SSEClient    │
│  SettingsTab           │  (单一 AppState 持有)     │               │
│  MessageRow, DiffView  │                          │               │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ URLSession (REST + SSE)
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     OpenCode Server (Mac/Linux)                   │
│  GET /global/event  │  POST /session/:id/prompt_async  │  ...    │
└─────────────────────────────────────────────────────────────────┘
```

- **Views**：SwiftUI 视图，按 Tab 与功能模块划分
- **State**：`@Observable` 管理连接、Session、消息、文件等
- **Services**：网络层、认证、SSE 解析，与 UI 解耦

### 2. 技术选型

| 层面 | 选择 | 理由 |
|------|------|------|
| UI | SwiftUI | 原生、声明式，与 iOS 17+ 适配最好 |
| 状态 | Observation (@Observable) | 替代 ObservableObject，减少样板代码 |
| 网络 | URLSession | 原生，无需 Alamofire；SSE 用 `URLSession` 的 `Delegate` 或 `AsyncSequence` |
| SSH 库 | Citadel | 基于 Apple SwiftNIO SSH 封装，支持 Swift 5.10+，API 友好 |
| Markdown | MarkdownUI | 支持代码块、链接、列表 |
| Diff | 自建 View（优先 iOS 原生能力） | 基于 `before`/`after` 做 unified diff 渲染，行级高亮 |
| 持久化 | UserDefaults + Keychain | 连接信息、模型预设；密码存 Keychain |

#### 2.1 SSH 库选型：Citadel

用于实现 SSH 隧道远程访问功能。

| 库 | 语言 | 维护状态 | Swift 版本 | 推荐度 |
|----|------|----------|------------|--------|
| **Citadel** | Swift (基于 SwiftNIO SSH) | 活跃 (0.12.0, 2026-01) | 5.10+ | ★★★★★ |
| SwiftNIO SSH | Swift (Apple 官方) | 活跃 | 6.0+ | ★★★★ |
| NMSSH | Obj-C wrapper of libssh2 | 活跃 | 5.0+ | ★★★ |

**选择 Citadel 的原因**：

1. **无需升级 Swift 6.0**：支持 Swift 5.10+，避免 Swift 6 的并发安全 breaking changes
2. **高级 API**：基于 Apple 的 SwiftNIO SSH 封装，比直接用 SwiftNIO SSH 简单
3. **功能完整**：支持 Ed25519 密钥认证、DirectTCPIP 端口转发、SFTP
4. **活跃维护**：44 个 release，最近刚加入反向隧道支持
5. **文档齐全**：有 README 示例 + [官方文档](https://swiftpackageindex.com/orlandos-nl/Citadel/0.12.0/documentation/citadel)

**使用示例**：

```swift
import Citadel

let settings = SSHClientSettings(
    host: "your-vps.com",
    port: 22,
    authenticationMethod: .publicKey(username: "user", privateKey: ed25519Key),
    hostKeyValidator: .acceptAnything()
)
let client = try await SSHClient.connect(to: settings)

// 本地端口转发：iOS:4096 -> VPS:18080 -> 家里 OpenCode
let channel = try await client.createDirectTCPIPChannel(
    using: .init(
        targetHost: "127.0.0.1",
        targetPort: 18080,
        originatorAddress: try SocketAddress(ipAddress: "127.0.0.1", port: 4096)
    )
)
```

### 3. 网络层设计

#### 3.1 REST API

- 使用 `URLSession` 封装 `APIClient`
- 统一 Base URL：`http://<ip>:<port>` 或 `https://<host>:<port>`，默认 `127.0.0.1:4096`，来自 Settings
- 所有请求附加 Basic Auth header（若配置）
- 推荐使用 `POST /session/:id/prompt_async` 发送消息，busy 时由服务端排队

#### 3.1.1 消息分页拉取（已实现）

- `GET /session/:id/message` 使用 `limit` 参数分页拉取，默认加载最近 6 条 message（3 轮 user/assistant）
- 用户在 Chat 顶部下拉触发“加载更多历史消息”后，`limit` 每次增加 6 并重新拉取
- 目标是把弱网首屏时延从“全量历史”收敛到“最近可操作上下文”
- 注意：`limit` 统计单位是 **message**，不是 tool 调用次数。一个 assistant message 可包含多个 tool/text/reasoning parts

#### 3.2 SSE 连接

- 连接 `GET /global/event`
- 使用 `URLSession` 的 `dataTask` 或 `URLSession.AsyncBytes` 流式读取
- 解析 `data:` 行，按行或按 `\n\n` 切分事件
- 事件格式：`{ directory, payload: { type, properties } }`

**生命周期**：
- 前台：建立/恢复连接
- 后台：主动断开（iOS 限制）
- 恢复：先 REST 全量拉取 (health, sessions, messages, status)，再重建 SSE

#### 3.3 错误与重连

- 网络错误：展示 Toast，不 crash
- SSE 断开：按指数退避重连，上限 30s
- Server 不可达：Settings 显示 Disconnected，Chat/Files 显示占位提示

#### 3.4 SSE 鲁棒性

- 解析：API 使用单行 `data:`，当前实现已满足
- 请求头：建议添加 `Accept: text/event-stream`、`Cache-Control: no-cache`
- 重连：可选，现有轮询 + 前台恢复已覆盖主要场景

### 3.5 SSH 隧道架构

用于远程访问场景，通过公网 VPS 中转到家里网络。

**网络拓扑**：

```
┌─────────────┐      SSH Tunnel       ┌─────────────┐      反向隧道      ┌─────────────┐
│  iOS App    │ ───────────────────▶  │    VPS      │ ─────────────────▶ │  家里 Mac   │
│ 127.0.0.1   │   DirectTCPIP         │ 127.0.0.1   │    (预先建立)       │ OpenCode    │
│   :4096     │   :4096 → :18080      │   :18080    │                    │   :4096     │
└─────────────┘                       └─────────────┘                    └─────────────┘
```

**数据模型**：

```swift
struct SSHTunnelConfig: Codable {
    var isEnabled: Bool = false
    var host: String = ""           // VPS 地址
    var port: Int = 22              // SSH 端口
    var username: String = ""       // SSH 用户名
    var remotePort: Int = 18080     // VPS 上转发的端口
}

enum SSHConnectionStatus {
    case disconnected
    case connecting
    case connected
    case error(String)
}
```

**密钥管理**：

```swift
enum SSHKeyManager {
    // 生成 Ed25519 密钥对
    static func generateKeyPair() throws -> (privateKey: Data, publicKey: String)
    
    // 私钥存 Keychain
    static func savePrivateKey(_ key: Data)
    static func loadPrivateKey() -> Data?
    
    // 公钥用于显示/复制
    static func getPublicKey() -> String?
    
    // 密钥轮换
    static func rotateKey() throws -> String  // 返回新公钥
}
```

**安全考虑**：

1. **私钥保护**：使用 `kSecAttrAccessibleWhenUnlocked`，只在设备解锁时可访问
2. **公钥传输**：用户手动复制，app 不通过网络传输公钥
3. **TOFU**：首次连接自动信任并保存服务器 fingerprint（按 host:port 绑定），后续 mismatch 直接失败并提示 reset trusted host
4. **超时**：连接超时 30 秒，自动断开并提示

**错误处理**：

| 错误 | 原因 | 用户提示 |
|------|------|----------|
| 密钥未授权 | 公钥未添加到 VPS | "请先添加公钥到服务器的 authorized_keys" |
| 连接超时 | 网络问题或地址错误 | "连接超时，请检查网络和服务器地址" |
| 认证失败 | 私钥不匹配 | "认证失败，请确认公钥已正确添加" |

**SSH UX 补充**：
- 在 Settings 内生成可复制的 reverse tunnel command（用户可直接在电脑端执行）
- 公钥复制入口常驻，不依赖 tunnel enable 状态
- 在 SSH 配置区增加灰字提示：启用 SSH 后仍需到上方 `Server Connection` 点击 `Test Connection`

### 4. 状态管理

```swift
@Observable
final class AppState {
    var serverURL: String
    var isConnected: Bool
    var sessions: [Session]
    var currentSessionID: String?
    var sessionStatuses: [String: SessionStatus]
    var messages: [MessageWithParts]
    var partsByMessage: [String: [Part]]
    var selectedModelIndex: Int
    
    // Agent 选择（2026-02 新增）
    var agents: [AgentInfo]           // 从 GET /agent 获取
    var selectedAgentIndex: Int       // 当前选中的 agent
    
    // SessionStore, MessageStore, FileStore, TodoStore 等
}
```

- 单一 `AppState` 持有全局状态，子 store 委托 session/message/file/todo 等
- SSE 事件根据 `type` 分发，更新对应字段
- View 通过 `@Environment` 或直接注入访问

#### 4.1 Agent 数据模型

```swift
struct AgentInfo: Codable, Identifiable {
    var id: String { name }
    let name: String              // agent 名称，如 "Sisyphus (Ultraworker)"
    let description: String?      // 描述
    let mode: String?             // "primary" 或 "subagent"
    let hidden: Bool?             // 是否隐藏（隐藏的 agent 不在 UI 显示）
}
```

#### 4.2 Agent API

| 方法 | 路径 | 说明 | 响应 |
|------|------|------|------|
| GET | `/agent` | 列出所有 Agent | `AgentInfo[]` |

- App 启动时后台调用此 API 获取 agent 列表
- 过滤 `hidden != true` 的 agents 后显示在 UI
- 默认选择第一个 primary agent（通常是 `Sisyphus`）

#### 4.3 Project 选择（Workspace 过滤）

**背景**：OpenCode Server 支持多项目，`GET /session` 默认返回 server 当前项目的 sessions。Web 端可切换项目，iOS 端需支持按项目过滤，否则只能看到 server 当前项目的 sessions。

**API**：

| 方法 | 路径 | 说明 | 响应 |
|------|------|------|------|
| GET | `/project` | 列出服务器已知的项目 | `Project[]` |
| GET | `/project/current` | 当前项目 | `Project` |
| GET | `/session?directory=<path>&limit=<n>` | 按 worktree 过滤 sessions | `Session[]` |

**数据模型**：

```swift
struct Project: Codable, Identifiable {
    let id: String           // 通常为 git commit hash
    let worktree: String     // 绝对路径，如 /Users/xxx/co/knowledge_working
    let vcs: String?         // "git" 等
    let time: ProjectTime?
}

// 展示名称：worktree 最后一段，如 knowledge_working
func projectDisplayName(_ worktree: String) -> String {
    (worktree as NSString).lastPathComponent
}
```

**状态**：

```swift
var projects: [Project] = []              // 从 GET /project 拉取
var selectedProjectWorktree: String?      // nil = 使用 server 默认（不传 directory）
var customProjectPath: String = ""        // "Custom path" 时用户输入的路径
```

**流程**：
1. 连接成功后调用 `GET /project` 填充 Picker
2. 用户选择：从列表选 → `selectedProjectWorktree = project.worktree`；选 "Custom path" → 展开 TextField，`selectedProjectWorktree = customProjectPath`
3. `loadSessions()` 时：若 `selectedProjectWorktree != nil`，请求 `GET /session?directory=xxx&limit=100`；否则 `GET /session`（无参数）
4. 持久化：`selectedProjectWorktree`、`customProjectPath` 存 UserDefaults

#### 4.3.1 Session 与 Project 不匹配时的防御性处理

**背景**：`POST /session` 不支持传 directory，server 在其 current project 下创建 session。iOS 用 `effectiveProjectDirectory` 过滤列表。当 server current project ≠ 用户所选 project 时，新建的 session 不在 GET 结果中，直接覆盖会导致新 session 消失。详见 [session_disappear_investigation.md](session_disappear_investigation.md)。

**实现**：`loadSessions()` 中，若 `currentSessionID` 不在 server 返回列表，单独 `GET /session/:id` 拉取该 session 并 prepend 到 `sessions`，保证 `currentSession` 仍可解析。404 时不做 merge（session 可能已删除）。

### 5. 消息与文档 UI

#### 5.1 消息流

- **布局**：OpenCode 风格，无左右气泡；人类消息灰色背景，AI 消息白/透明
- **单位语义**：一个 message 可包含多个 part（tool/reasoning/text 等）。tool 调用计入 part，不单独计为 message
- **Part 渲染**：text (Markdown)、reasoning (折叠)、tool (卡片)、patch (跳转 Files)。tool/patch 若含文件路径，点击可「在 File Tree 中打开」预览；其中 `todowrite` tool 需渲染为 Task List（todo）视图，并响应 SSE `todo.updated`。Todo 仅在 tool 卡片内展示，不在 Chat 顶部常驻（方案 B）
- **iPad 大屏密度**：在 `horizontalSizeClass == .regular` 时，tool/patch/permission 卡片可用三列网格横向填充；text part 仍整行显示（避免阅读断裂）
- **流式（Think Streaming）**：`message.part.updated` 带 `delta` 时追加到对应 Part，实现打字机效果；无 delta 时全量 reload。Tool 卡片：running 展开、completed 默认收起
- **Activity Row 收敛**：状态显示采用 "运行证据优先"。若检测到 running/pending tool 或 streaming 增量，即使瞬时收到 `session.status=idle` 也保持 running，避免提前 completed
- **主题**：跟随 `@Environment(\.colorScheme)`，Light/Dark

#### 5.1.1 Chat 文字选择（textSelection）— 设计

**原则**：仅对两类内容启用选择，其余区域禁用，避免手势冲突、缩小可选范围。

| 区域 | 是否可选 | 说明 |
|------|----------|------|
| 用户消息正文 | ✅ | 用户打出去的消息，可复制 |
| AI 最终回复（text part） | ✅ | AI 的 response 文本，可复制 |
| 思考过程（reasoning） | ❌ | 包括 streaming 时的 think |
| 工具调用（tool 卡片） | ❌ | Reason、Command/Input、Output、Path、todo 等 |
| Patch 卡片 | ❌ | 按钮为主，无需选择 |

**实现**：`MessageRowView` 的 `markdownText` 对用户消息和 AI text part 使用 `.textSelection(.enabled)`；`ScrollView` 不设全局 textSelection；`ToolPartView`、`StreamingReasoningView`、`TodoListInlineView` 不启用 textSelection。

#### 5.1.2 Think Streaming 实现

- **Delta 处理**：`handleSSEEvent` 收到 `message.part.updated` 时，若 `properties.delta` 存在，则定位 `messageID`/`partID` 对应 Part，将 delta 追加到 text；否则执行 `loadMessages()` 全量刷新
- **Tool 折叠**：`ToolPartView` 根据 `part.state.status`：`running` 时 `isExpanded = true`，`completed` 时 `isExpanded = false`（默认），用户可手动切换
- **限制**：Tool output 的实时流式（terminal 逐行）当前 API 不支持，见 PRD 调研

#### 5.2 文档审查

- **Markdown 展示**：Preview 为主，可切换 Markdown 源码
- **Diff 高亮**：优先在 Preview 内高亮 changes；若实现困难，则在 Markdown 内高亮
- **入口**：Files Tab → 选文件 → 预览

### 6. 权限与输入

- **Session 列表**：列出 workspace 下所有已有 Session，作为连接与解析的验证手段
- **Session 列表样式**：避免系统默认链接蓝；文本用中性色，当前 Session 用背景高亮
- **权限**：`permission.asked` 时展示卡片，用户手动批准/拒绝，调用 `POST /session/:id/permissions/:permissionID`
- **输入**：支持多行，发送用 `prompt_async`；busy 时消息由服务端排队
- **草稿**：按 sessionID 持久化未发送输入；切换 session 可恢复；发送成功后清空
- **模型选择**：按 sessionID 记忆当前选择的模型；切换 Session 自动恢复（避免全局 model 覆盖）
- **Agent 选择**：按 sessionID 记忆当前选择的 agent（与 model 同理）；发送消息时在 body 中携带 `agent: string` 字段
- **语音输入**：输入框右侧麦克风按钮；录音后调用 AI Builder `POST /v1/audio/transcriptions` 转写，结果追加到输入框；Base URL 与 token 在 Settings → Speech Recognition 配置并存 Keychain
- **Abort**：提供按钮调用 `POST /session/:id/abort`
- **历史加载交互**：Chat 顶部显示“下拉加载更多历史消息”提示；加载中显示“正在加载更多历史消息...”，支持中英文本地化

### 7. 文件与 Diff

- **文件树**：`GET /file?path=` 递归展示；`GET /file/status` 获取 git 状态做颜色标记
- **内容**：`GET /file/content?path=`；文本文件语法高亮，二进制显示类型提示
- **Session Diff**：暂不在 iOS 客户端展示（server 端 diff API 在部分情况下返回空数组）

### 8. iPad / Vision Pro 布局（Phase 3）

- **条件**：`horizontalSizeClass == .regular` 或 `userInterfaceIdiom == .pad` 时启用
- **布局**：无 Tab Bar；三栏（NavigationSplitView）：左栏 Workspace（Files + Sessions），中栏 Preview（文件预览），右栏 Chat（消息流 + 输入框）
- **列宽**：Workspace 约占 1/6；Preview 与 Chat 平分剩余 5/6（各 5/12）
- **可拖动**：三栏宽度支持拖动调整；以上为默认 ideal 宽度
- **文件预览**：iPad 上不使用 sheet。左栏选择文件、或 Chat 中点击 tool/patch 的 file path 时，更新中栏 Preview 预览对应文件
- **刷新**：Preview 中栏右上角提供刷新按钮（重新加载文件内容），用于外部变更后的手动刷新
- **Toolbar**：第一行统一：左（Session 列表、重命名、Compact、新建 Session）+ 右（模型下拉列表、Agent 下拉列表、Context Usage ring、**Settings 按钮**）；Settings 点击以 sheet 打开
- **模型与 Agent 选择器**：原 chip 横向滚动改为下拉列表（Menu + Picker）。模型列表固定（Opus 4.6 / Sonnet 4.6 / GPT-5.3 Codex / GPT-5.2 / Gemini 3.1 Pro / Gemini 3 Flash）；Agent 列表从 `GET /agent` 动态获取（过滤 hidden）
- **模型标签**：iPhone 上使用短名（`Opus` / `Sonnet` / `GPT` / `Gemini`）以适配窄宽；iPad 上显示全称
- **实现**：`@Environment(\.horizontalSizeClass)` 分支：regular 时渲染三栏 split，小屏时渲染 `TabView`；iPad 用 `previewFilePath` 驱动中栏预览，iPhone 保留 `fileToOpenInFilesTab` 走 sheet / tab 跳转

### 9. Context Usage（上下文占用）

- **展示**：Chat 顶部右侧（模型切换条与齿轮之间）显示环形进度（灰色空环表示无数据）。
- **数据**：从最近一次 assistant message 的 `info.tokens`/`info.cost` 读取 token/cost；context limit 从 `GET /config/providers` 中 `limit.context` 获取。
- **交互**：点击 ring 弹 sheet 展示 provider/model、context limit、total tokens、token breakdown（input/output/reasoning/cache read/cache write）与 total cost。

---

## 实现规划

| Phase | 范围 | 预计周期 |
|-------|------|----------|
| 1 | Server 连接、SSE、Session、消息发送、流式渲染 | 2–3 周 |
| 2 | Part 渲染、权限手动批准、主题、`prompt_async` | 2 周 |
| 3 | 文件树、Markdown 预览、文档 Diff、Think Streaming delta、**iPad/Vision Pro 分栏布局** | 2–3 周 |
| 4 | mDNS、Widget 等 | 暂不实现 |

### Code Review 跟进（2026-02）

| 编号 | 状态 | 说明 |
|------|------|------|
| 2.1 | ✅ | UserDefaults + Keychain 持久化凭证 |
| 2.2 | ✅ | Chat 文字选择 — 仅用户消息 + AI text part 可选，见 RFC §5.1.1 |
| 2.3 | ✅ | ChatTabView 拆分至 Views/Chat/*.swift |
| 2.4 | ✅ | Todo 方案 B：仅 tool 卡片内展示 |
| 2.5 | ✅ | 移除 debug print |

---

## 弃用方案

以下方案在讨论中被放弃：

1. **使用 Alamofire**：`URLSession` 足够，新增依赖无必要
2. **后台常驻 SSE**：iOS 会主动断开，且耗电；改为前台建立、后台断开
3. **本地消息队列**：服务端 `prompt_async` 已支持 busy 排队，无需客户端维护
4. **自动批准权限**：OpenCode 极少请求 permission，出现即为异常，改为手动批准

---

## 已决事项

1. **Markdown 库**：使用 MarkdownUI，优先采用 iOS 原生能力
2. **大型 Session**：暂不考虑，不预期 session 超过百条消息
3. **Diff 高亮**：优先使用 iOS 原生能力实现

---

## 附录：与 PRD 的对应关系

| PRD 章节 | 本 RFC 对应 |
|----------|-------------|
| 3. 技术架构 | §1 整体架构、§2 技术选型 |
| 4.2 Chat Tab | §5 消息与文档 UI、§6 权限与输入 |
| 4.3 Files Tab | §7 文件与 Diff |
| 5. 数据流与状态管理 | §4 状态管理、§3 网络层 |
| 11. 实现起步指南 | §实现规划 |
