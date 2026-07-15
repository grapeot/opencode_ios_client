# RFC-002: OpenCode iOS Client 技术方案

> Request for Comments · Working Draft · Mar 2026

## 元数据

| 字段 | 值 |
|------|------|
| **RFC 编号** | RFC-002 |
| **标题** | OpenCode iOS Client 技术方案 |
| **状态** | Working Draft |
| **创建日期** | 2026-03 |
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
- 支持局域网直连、Tailscale MagicDNS 与 SSH tunnel 远程访问；公网（非 Tailscale）要求 HTTPS 或 SSH 转发。Tailscale（`*.ts.net`）豁免 ATS 例外，允许 HTTP；Settings 中 Tailscale + HTTP 时协议显示灰色，其他 WAN + HTTP 显示红色，info 图标悬停说明中英双语

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

- **Views**：SwiftUI 视图，按 Chat / Files / Settings / Split View 模块划分
- **State**：`@Observable` 管理连接、Session、消息、文件等
- **Controllers / Services / Stores / Models / Utils**：事件控制、网络层、状态存储、数据模型与工具层解耦组织

### 2. 技术选型

| 层面 | 选择 | 理由 |
|------|------|------|
| UI | SwiftUI | 原生、声明式，与 iOS 17+ 适配最好 |
| 状态 | Observation (@Observable) | 替代 ObservableObject，减少样板代码 |
| 网络 | URLSession | 原生，无需 Alamofire；SSE 用 `URLSession` 的 `Delegate` 或 `AsyncSequence` |
| SSH 库 | Citadel | 基于 Apple SwiftNIO SSH 封装，支持 Swift 5.10+，API 友好 |
| Markdown | MarkdownUI + 自定义图片 provider / resolver | 支持代码块、链接、列表，以及 workspace 内相对图片 |
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
4. **活跃维护**：44 个 release，支持 SSH direct-tcpip 端口转发
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

// 本地端口转发：iOS:4096 -> SSH gateway assigned port -> OpenCode
let channel = try await client.createDirectTCPIPChannel(
    using: .init(
        targetHost: "127.0.0.1",
        targetPort: 19001,
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

#### 3.1.2 Edit from here / message revert（已实现 MVP）

iOS 客户端支持 Web 端同源的 message revert MVP，用于从某条 user message 回到历史位置、把原消息放回 composer，并让用户修改后重新发送。

- 数据模型：`Session` 解码 server 返回的 `revert` 字段，最小字段为 `messageID`、`partID`、`snapshot`、`diff`
- API：`APIClient.revertSession(sessionID:messageID:partID:)` 调用 `POST /session/:id/revert`，body 为 `{ messageID, partID? }`，返回更新后的 `Session`
- UI 入口：`MessageRowView` 的 user message 菜单新增 `Edit from here`；busy session 下禁用，避免和 server 的 `assertNotBusy` 冲突
- 状态编排：`AppState.editFromMessage(messageID:)` 只接受 user message，拼接 text parts 写回 per-session draft，upsert 返回的 session，并刷新 messages / diff / file status
- 消息可见性：`AppState.visibleMessages(_:revertMessageID:)` 按 OpenCode Web 语义隐藏 `message.id >= revert.messageID` 的已回滚消息；临时 optimistic message 保留
- 非目标：MVP 不提供 `unrevert` / restore dock / part-level revert；这些行为留给后续需要时再补

#### 3.1.3 Image attachments（已实现 Phase 1/2）

iOS 图片支持与 OpenCode Web 保持同构：图片作为 prompt 的 `file` part 发送，`url` 使用 `data:<mime>;base64,...`，不新增独立 upload endpoint。

- 发送模型：`APIClient.promptAsync` 支持 mixed parts；文本生成 `type: "text"`，图片生成 `type: "file"`、`mime`、`filename`、`url`
- Composer：`ChatTabView` 使用 `PhotosPicker` 选择图片，最多 4 张；本地转 JPEG data URL，最长边 2048，JPEG quality 0.82，压缩后单图上限 5MB
- 失败恢复：发送失败时恢复文本和附件状态；optimistic user message 同时包含 text part 与 file part
- 渲染模型：`Part` 解码 `mime`、`filename`、`url`、`source`；`MessageRowView` 对 `type == "file"` 渲染图片缩略图或 fallback file card
- 图片预览：历史 image attachment 点击后复用现有 `ImageView` zoom/pan 预览
- 非目标：本轮不做 Files app 文件选择、PDF/text 附件、跨重启附件草稿持久化、server-side upload 或大 payload 分片

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

### 3.5 Host Profiles 与 Transport 抽象

多 host 支持把“连接哪个 OpenCode 环境”和“如何到达这个环境”分开。Host 指一个 OpenCode 环境；transport 指访问路径。Direct 覆盖 LAN、Tailscale / VPN、HTTPS public server。SSH Tunnel 覆盖通过 SSH gateway 和 assigned remote port 访问私有 OpenCode 容器。

**数据模型（设计稿）**：

```swift
struct HostProfile: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var transport: HostTransport
    var serverURL: String
    var basicAuth: BasicAuthConfig?
    var ssh: SSHTunnelConfig?
    var lastUsedAt: Date?
}

enum HostTransport: String, Codable {
    case direct
    case sshTunnel
}

struct BasicAuthConfig: Codable, Equatable {
    var username: String
    var keychainPasswordID: String
}
```

**持久化边界**：

- `HostProfile` 列表存 UserDefaults 或轻量 JSON store；密码只保存 Keychain reference，不进入 JSON。
- SSH private key 默认是 device-level key，由现有 `SSHKeyManager` 管理，多个 SSH profiles 复用同一个 public key。后续如需高安全模式，再增加 per-profile key override。
- TOFU known host 仍按 SSH gateway `host:port` 绑定，而不是按 profile name 绑定。多个 profiles 指向同一 gateway 时共享同一个 trusted host fingerprint。

**切换流程**：

1. 保存当前 profile 的 `lastUsedAt` 和必要 runtime 状态。
2. 停止当前 SSE。
3. 如果当前 profile 使用 SSH，断开当前 SSH tunnel。
4. 应用新 profile 的 `serverURL`、Basic Auth 和 transport config。
5. 清空当前 session selection，并按新 host 重新拉取 health / projects / sessions。
6. 如果新 profile 是 SSH Tunnel，可尝试自动连接 tunnel；失败进入 `.error` 状态但不阻塞 Settings。

**Import Host Config 格式（不含 secret）**：

```json
{
  "version": 1,
  "name": "Yage Private OpenCode",
  "transport": "sshTunnel",
  "serverURL": "127.0.0.1:4096",
  "ssh": {
    "host": "example.com",
    "port": 8006,
    "username": "opencode",
    "remotePort": 19001
  }
}
```

Direct 示例：

```json
{
  "version": 1,
  "name": "Home Mac via Tailscale",
  "transport": "direct",
  "serverURL": "http://macbook.ts.net:4096"
}
```

Import 不包含 private key、provider token、Basic Auth password。SSH import 后仍要求用户复制本设备 public key 给管理员。

**Host Config 导出格式**：

Host Config JSON 从已保存的 `HostProfile` 生成，`HostProfile` 仍是持久化 source of truth。客户端不把原始 import JSON 作为第二份状态保存。导出的 JSON 用于用户和管理员对照配置，但必须排除 secret 和 runtime-only 字段：Basic Auth password、Keychain password ID、SSH private key、`SSHTunnelConfig.isEnabled` 都不能进入导出结果。

**Runtime 连接诊断**：

```swift
struct ConnectionDiagnostic: Codable, Equatable {
    var hostProfileID: UUID?
    var phase: ConnectionPhase
    var message: String
    var recoveryHint: String?
    var timestamp: Date
}

enum ConnectionPhase: String, Codable {
    case idle
    case sshGateway
    case sshAuth
    case localTunnel
    case health
    case bootstrap
    case connected
    case failed
}
```

`ConnectionDiagnostic` 属于 app runtime 状态，不需要长期持久化。切换 host 时重置；`testConnection()` 和 refresh/bootstrap 流程负责更新 phase、message 和 recovery hint。UI 只展示用户可执行文案，不能直接暴露 `APIError error 0`、`NSURLErrorDomain -1004` 这类底层错误字符串。常见映射包括：Basic Auth 401/403 → 检查用户名密码；connection refused / cannot connect → 检查服务器地址、网络或本地 tunnel；SSH tunnel error → 检查 gateway、设备 public key 和 assigned remote port。

**Host Detail 交互契约**：

Hosts list row 的主点击行为是打开 Host Detail，不是直接切换 host。切换 host 必须通过详情页里的 `Use This Host` 显式动作完成。Host Detail 读取当前 `HostProfile` 字段展示 Direct / SSH Tunnel 的完整关键配置，并提供 `Copy Host Config JSON`。SSH Tunnel profile 额外提供 `Copy This Device Public Key`。

### 3.6 SSH 隧道架构

用于远程访问场景，通过 SSH gateway 中转到用户独立的 OpenCode 服务。

**网络拓扑**：

```
┌─────────────┐      SSH Tunnel       ┌─────────────┐      internal      ┌─────────────┐
│  iOS App    │ ───────────────────▶  │  Gateway    │ ─────────────────▶ │  OpenCode   │
│ 127.0.0.1   │   DirectTCPIP         │ 127.0.0.1   │    (预先建立)       │ OpenCode    │
│   :4096     │   :4096 → :19001      │   :19001    │                    │   :4096     │
└─────────────┘                       └─────────────┘                    └─────────────┘
```

**数据模型**：

```swift
struct SSHTunnelConfig: Codable {
    var isEnabled: Bool = false
    var host: String = ""           // SSH gateway 地址
    var port: Int = 8006            // SSH 端口
    var username: String = "opencode" // SSH 用户名
    var remotePort: Int = 19001     // 管理员分配的 remote port
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
- 在 Settings 内显示 setup guide：复制设备公钥给管理员，并填写管理员返回的 assigned remote port
- 公钥复制入口常驻，不依赖 tunnel enable 状态
- SSH Host Profile 的 `Test Connection` 先建立 SSH tunnel，并等本地 `127.0.0.1:4096` listener ready；只有 tunnel ready 后才请求 `/global/health`
- tunnel 建立失败时把 SSH 错误写入 connection error，避免只显示 disconnected

### 3.7 Markdown 图片解析契约

Markdown 文本里出现的图片分两类：

1. **公网 URL**：`https://...`，可交给默认网络图片加载路径
2. **workspace 内相对图片**：如 `../assets/timeline_40d.png`，必须由客户端自己解析

对第二类，RFC 约束如下：

- Files 预览和 Chat 消息渲染都必须支持 repo 内相对图片，不允许出现“文件预览能看见、聊天里看不见”的双重语义
- 相对图片路径解析必须同时考虑 `markdownFilePath` 和 `workspaceDirectory`
- 解析后的最终文件请求必须是 **workspace-relative path**，再交给 `/file/content` API 获取内容
- Chat 场景允许先把图片转换为 `data:` URI 再交给 MarkdownUI；但一旦采用这条路径，渲染端必须显式挂载能处理 `data:` URL 的 image provider
- Files 预览场景若使用 `imageBaseURL`，仍然需要在 image provider 中做 workspace-relative 归一化，避免绝对路径穿透到 API 层

这条契约的目标是：无论同一份 Markdown 报告从 Files 打开，还是由 AI 在 Chat 中直接输出，都应该得到一致的图片结果。

### 4. 状态管理

```swift
@Observable
final class AppState {
    var hostProfiles: [HostProfile]
    var currentHostProfileID: UUID
    var serverURL: String          // 当前 profile 展开后的 runtime URL
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

#### 4.3.1 Session 创建仅限 Server default

**背景**：`POST /session` 不支持传 directory，server 在其 current project（由启动位置或 Web/TUI 最后使用决定）下创建 session。iOS 的 Project 选择器只影响列表过滤，不改变创建目标。若允许在「选了具体 project」时创建，新 session 会落在 server default，不在过滤结果中，导致消失。

**实现**：仅当 `effectiveProjectDirectory == nil`（用户选 Server default）时允许创建。当用户选了具体 project 时，新建按钮置灰，旁加 info 图标，点击显示提示：需用命令行启动 OpenCode 并指定不同的工作目录，然后在此选 Server default 再创建。`canCreateSession` 控制按钮可用性。

#### 4.4 Session Deep Link

**协议**：V1 只接受 `opencode://session/<session_id>`。`OpenCodeDeepLinkParser` 是无副作用纯函数，要求 scheme 和 host 分别为 `opencode`、`session`，path 只有一个 segment，session ID 以 `ses_` 开头且后续仅含 ASCII 字母、数字、下划线或连字符。parser 拒绝 userinfo、port、query、fragment、多层 path、控制字符、Unicode、重复 percent encoding 和过长 ID。未知 scheme 不由 deep-link router 处理。

**实现分层**：

- `Utils/OpenCodeDeepLink.swift` 定义 URI contract 和 parser。
- `AppState+DeepLinks.swift` 持有 `pendingDeepLink`、`deepLinkRouteState`、全局错误和 route generation token。
- `ContentView.onOpenURL` 处理系统 cold/warm launch；`MessageRowView` 的 `OpenURLAction` 先识别 OpenCode link，再回落到既有 HTTP/workspace link resolver。
- `Info.plist` 通过 `CFBundleURLTypes` 注册 `opencode` scheme；Debug 和 Release 共用同一配置。

**解析状态机**：

```text
receive URL
  -> strict parse
  -> store latest pending route
  -> wait while disconnected
  -> GET /session/:id on current Host
  -> apply target directory + upsert session
  -> select session + hydrate Chat + reload Files
```

客户端必须在 `GET /session/:id` 成功前保留原 `currentSessionID` 和 messages。目标 session 不要求已进入当前 100 条列表窗口；验证后先按 `Session.directory` 设置已知 project 或 custom project，再 upsert 并调用现有 session hydration。Session 列表刷新需保留当前已验证 session，Files root/children 请求使用 `effectiveProjectDirectory`。

**生命周期与并发**：cold launch 或 SSH 恢复期间只保存 pending route，连接成功后消费。App 进入后台或切换 Host 时更新 generation token，使旧 Host 的 in-flight 响应失效，同时保留最后一个 pending link 给新连接处理。新链接覆盖旧链接，不建立队列；同一 session 重复点击幂等。404 显示“当前 Host 不可用”，其他网络错误显示通用打开失败，二者均不切换上下文。

**安全边界**：URL 不接受 server、Host Profile、凭证、模型、prompt、tool action 或任意 command。Deep link 只能由用户点击或系统显式唤起，不能因 Markdown 渲染自动执行。V1 不跨 Host 搜索，不恢复离线 archive DB，不支持 `?message=`。

**验证**：unit tests 覆盖 parser 白名单、404/断连、project 切换、列表窗口保留和 route invalidation；fixture XCUITest 覆盖 assistant Markdown 点击与 cold pending route。完整系统验收使用 Simulator `simctl openurl` 和独立临时 server，不触碰 live `4096`。Agent 搜索输出另用 synthetic archive 验证 source、frontmatter session ID、候选去重和证据邻接；真实 Agent acceptance 保持 opt-in，不进入每次 unit test。

### 5. 消息与文档 UI

#### 5.1 消息流

- **布局**：OpenCode 风格，无左右气泡；人类消息灰色背景，AI 消息白/透明
- **单位语义**：一个 message 可包含多个 part（tool/reasoning/text 等）。tool 调用计入 part，不单独计为 message
- **Part 渲染**：text (Markdown)、reasoning (折叠)、tool (卡片)、patch (跳转 Files)。tool/patch 若含文件路径，点击可「在 File Tree 中打开」预览；其中 `todowrite` tool 需渲染为 Task List（todo）视图，并响应 SSE `todo.updated`。Todo 仅在 tool 卡片内展示，不在 Chat 顶部常驻（方案 B）
- **图像类 tool output**：若 tool 结果关联到图像文件，优先渲染内联缩略图而不是 raw base64；点击后进入可缩放的全屏预览
- **iPad 大屏密度**：在 `horizontalSizeClass == .regular` 时，tool/patch/permission 卡片可用三列网格横向填充；text part 仍整行显示（避免阅读断裂）
- **流式（Think Streaming）**：`message.part.updated` 带 `delta` 时追加到对应 Part，实现打字机效果；无 delta 时全量 reload。Tool 卡片：running 展开、completed 默认收起
- **自动滚动**：仅在用户当前位于底部附近时跟随新的 streaming 文本和卡片更新；用户主动向上浏览时停止自动跟随，避免抢走阅读位置
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
- **图片预览**：文件预览与 tool output 统一使用图像分支；初始为 fit-to-screen，支持 pinch、drag、double-tap zoom 和系统 share sheet

### 6. 权限与输入

- **Session 列表**：列出 workspace 下所有已有 Session，作为连接与解析的验证手段
- **Session 列表样式**：避免系统默认链接蓝；文本用中性色，当前 Session 用背景高亮
- **权限**：`permission.asked` 时展示卡片，用户手动批准/拒绝，调用 `POST /session/:id/permissions/:permissionID`
- **Question**：`question.asked` 时展示 question card；启动时通过 `GET /question` 补拉 pending questions；回答与拒绝分别调用 `/question/{id}/reply`、`/question/{id}/reject`
- **Composer**：采用 `voice rail + text review field` 两行结构。voice rail 在上方承载语音 transport、waveform/status、转写等待恢复和 preserved-audio retry；text review field 在下方承载转写文本、人工修正、fallback 打字和固定 send 按钮。语音转写或 preserved-audio retry 流式返回 partial transcript 时，text review field 自动滚到末尾，保持最新文字可见；普通手动输入和草稿恢复不强制滚动。busy 时 send 仍调用 `prompt_async`，消息由服务端排队
- **草稿**：按 sessionID 持久化未发送输入；切换 session 可恢复；发送成功后清空
- **模型选择**：按 sessionID 记忆当前选择的模型；切换 Session 自动恢复（避免全局 model 覆盖）
- **Agent 选择**：按 sessionID 记忆当前选择的 agent（与 model 同理）；发送消息时在 body 中携带 `agent: string` 字段
- **语音输入**：开始录音时创建 VoiceFlowKit realtime session，`AVAudioEngine` 输出 PCM16 mono 24kHz chunk；Kit 内部把每个 chunk 写入临时 `.pcm` cache 并发送到当前 WebSocket。录音期间 voice rail waveform 消费 `VoiceFlowMicrophone.audioLevel` 的真实 0..1 smoothed mic level。heartbeat / send failure 触发 Kit recovery：取消坏 session，创建新 session，从 cache 文件 offset 0 顺序 replay 到当前文件末尾，之后继续 live 发送。停止录音时等待恢复完成，发送 `commit` / `stop`，将 transcript 追加到 text review field。转写等待时显示 processing waveform 和 `Stop transcription wait`，点击后调用 `abortPreservingAudio()` 立即释放 UI 并保留 cache；preserved-audio 状态下左侧 transport 显示 `Retry this segment` 图标按钮，点击后用 `transcribe(preservedAudio:)` 重新识别同一段 PCM，右侧动作显示 `Discard audio` 用于放弃缓存并退出恢复状态。retry 失败后保留 cache，用户可以继续 retry 或 discard。Base URL 与 token 在 Settings → Speech Recognition 配置并存 Keychain
- **Agent abort**：`Interrupt agent` 作为 composer 状态行 `⋯` 菜单项调用 `POST /session/:id/abort`。它是低频 escape hatch，不和语音转写恢复共用 transport slot 或 stop glyph
- **历史加载交互**：Chat 顶部显示“下拉加载更多历史消息”提示；加载中显示“正在加载更多历史消息...”，支持中英文本地化。加载更多通过扩大 `GET /session/:id/message?limit=` 的窗口实现，并记录请求 limit、返回 message 数量和 fallback decoder 丢弃数量，便于排查旧历史消息形态导致的分页无感问题。Message part 的 `files` 字段兼容字符串数组和缺少 diff 计数的对象，避免旧 patch/tool 记录阻断更早历史展示。
- **Session Archive**：Session List 按 Active / Archived 两个分区展示。归档语义复用 `PATCH /session/:id`：Archive 写入正数 archived timestamp，Restore 写入 `-1` 作为 legacy restore sentinel；客户端按 `time.archived > 0` 判断 Archived。客户端不把 archive 当作 delete 的变体。Archive / Restore 成功后使用返回的 `Session` 更新本地列表，并重新计算 Active / Archived 分区。Archive 对 session subtree 递归生效，顺序为 children-first、parent-last，避免父 session 先隐藏后 active children 被临时提升为 root；Restore 顺序为 parent-first、children-after，避免子 session 在父级仍 archived 时临时游离。iPhone sheet 与 iPad sidebar 使用同一组规则：leading swipe 为 Archive/Restore，trailing swipe 为 Delete；所有 swipe action 禁用 full swipe，Delete 不弹确认框。Session list 分页使用显式“Load more sessions”行，而不是底部 `onAppear` 自动加载，避免默认折叠 archived 区域时自动拉取大量不可见历史 session。本轮不提供 session search，避免本地 title filter 被误解为全量历史搜索。

#### 6.1 Fork Session（会话分叉）

用户消息底部 model label 旁的 "..." 菜单提供 "Fork from here" 选项。调用 `POST /session/{id}/fork`（body: `{ "messageID": "..." }`），服务端复制指定消息之前的全部历史到新 session 并返回。客户端收到新 `Session` 后插入列表顶部并切换。

**实现要点**：
- 使用 SwiftUI `Menu`（tap 触发，非 `.contextMenu` 长按），确保按钮可发现性
- `MessageRowView` 新增 `onForkFromMessage: ((String) -> Void)?` 回调，将 `message.info.id` 传递给 `AppState.forkSession(messageID:)`
- `AppState.forkSession()` 遵循 `createSession()` 模式：guard `isConnected` + `currentSessionID`，调 API，insert session，switch，load messages
- Fork 后的 session 标题由服务端生成："{原标题} (fork #N)"

### 7. 文件与 Diff

- **文件树**：`GET /file?path=` 递归展示；`GET /file/status` 获取 git 状态做颜色标记
- **内容**：`GET /file/content?path=`；文本文件显示等宽代码视图与行号；Markdown 使用 Preview / source 切换；图像文件支持交互式预览与系统分享
- **Session Diff**：暂不在 iOS 客户端展示（server 端 diff API 在部分情况下返回空数组）

### 7.5 Markdown Web Preview 架构决策

打开 `.md` 文件能看到卡片、SVG、暗色适配，不只是纯文字。所有渲染发生在 iOS 本地，不联网、不跑作者代码。

<style>
.rfcw-stat{display:inline-block;border-radius:999px;padding:1px 8px;font-size:.78rem;font-weight:650}
.rfcw-stat.ok{background:var(--ok-bg,#d1fae5);color:var(--ok-fg,#065f46)}
.rfcw-stat.block{background:var(--block-bg,#e5e7eb);color:var(--block-fg,#374151)}
</style>

| 用户能体验到的 | 状态 |
|---|---|
| 打开 markdown 文件默认看到 Web Preview，工具栏可切回 Native / 源码 | <span class="rfcw-stat ok">上线</span> |
| `<style>` / `<div class="card">` / 内联 SVG 正常渲染 | <span class="rfcw-stat ok">上线</span> |
| 相对路径的图片能加载 | <span class="rfcw-stat ok">上线</span> |
| 同一个文件在 light / dark 模式都好读，不出现糊掉的卡片 | <span class="rfcw-stat ok">上线</span> |
| 危险 HTML（脚本、表单、外站 iframe）被剥掉不执行 | <span class="rfcw-stat ok">上线</span> |
| 切换文件时内容立刻刷新，不需要手动下拉 | <span class="rfcw-stat ok">上线</span> |
| 超大文件先弹确认，避免卡死 | <span class="rfcw-stat ok">上线</span> |
| 打开独立 `.html` artifact、Mermaid、代码高亮、点图放大 | <span class="rfcw-stat block">下一轮</span> |

<details>
<summary>实现要点（工程读者展开）</summary>

- **渲染路径**：`MarkdownWebPreviewView`（`UIViewRepresentable` 包 `WKWebView`）加载 app bundle 内的 `preview.html`；Swift 通过 `evaluateJavaScript` 调用 `window.renderMarkdown({markdown, theme})`，payload 经 `JSONSerialization`，不字符串拼接 markdown。
- **JS 依赖**：`markdown-it@14.2.0` + `DOMPurify@3.4.10` 固定打进 bundle，零 CDN 调用。Xcode 同步文件夹会拍平子目录，所以 vendor 文件与 `preview.html` 同级，src 不带 `vendor/` 前缀。
- **图片解析**：复用 `MarkdownImageResolver.resolveImages` 把相对图片转 `data:` URI，再交给 WebView — 与 §3.7 Markdown 图片解析契约语义一致。
- **安全模型**：DOMPurify allowlist 禁 `script` / `iframe` / `form` / `object` / `embed` / `on*` 事件属性 / `javascript:` URL；`WKNavigationDelegate` 拦截除 file / fragment 外的所有 navigation；外链交系统 Safari，workspace 相对链接走 `state.fileToOpenInFilesTab`；`WKWebsiteDataStore` 用 non-persistent，无持久 cookie / localStorage。
- **主题适配**：shell 暴露 `--fg` / `--bg` / `--card-bg` / `--border` / `--link` / `--ok-*` / `--bad-*` / `--warn-*` / `--block-*` 等 CSS 变量，light / dark 两套定义。作者样式必须用 `var(--x, fallback)` 形式，不支持主题变量的渲染器（Cursor、GitHub）退回 fallback。Dark 模式 chip 用饱和主色（`--ok-bg=#10b981` 等），避免深底沉进卡片。chip 必须用复合选择器 `.vx-chip.ok`，裸 `.ok` 会被卡片 `color:var(--fg)` 覆盖。
- **切换刷新**：`FileContentView` 在 `.onChange(of: filePath)` 主动 reset content + reload，避免 SwiftUI 复用 view 实例时旧文件残留。

</details>

完整子项目 PRD / RFC 保留在磁盘 `docs/Markdown_Web_Preview_PRD.md` / `Markdown_Web_Preview_RFC.md`，已从 git 跟踪移除；决策过程见 [`WORKING.md`](WORKING.md)。

### 8. iPad / Vision Pro 布局（Phase 3）

- **条件**：`horizontalSizeClass == .regular` 或 `userInterfaceIdiom == .pad` 时启用
- **布局**：无 Tab Bar；三栏（NavigationSplitView）：左栏 Workspace（Files + Sessions），中栏 Preview（文件预览），右栏 Chat（消息流 + 输入框）
- **列宽**：Workspace 约占 1/6；Preview 与 Chat 平分剩余 5/6（各 5/12）
- **可拖动**：三栏宽度支持拖动调整；以上为默认 ideal 宽度
- **文件预览**：iPad 上不使用 sheet。左栏选择文件、或 Chat 中点击 tool/patch 的 file path 时，更新中栏 Preview 预览对应文件
- **刷新**：Preview 中栏右上角提供刷新按钮（重新加载文件内容），用于外部变更后的手动刷新
- **Toolbar**：第一行统一：左（Session 列表、重命名、Compact、新建 Session）+ 右（模型下拉列表、Agent 下拉列表、Context Usage ring、**Settings 按钮**）；Settings 点击以 sheet 打开
- **模型与 Agent 选择器**：原 chip 横向滚动改为下拉列表（Menu + Picker）。模型列表固定（GLM-5.1 / GPT-5.4 / GPT-5.3 Codex / DeepSeek）；Agent 列表从 `GET /agent` 动态获取（过滤 hidden）
- **模型标签**：iPhone 上使用短名（`GLM` / `Opus` / `GPT` / `Gemini`）以适配窄宽；iPad 上显示全称
- **实现**：`@Environment(\.horizontalSizeClass)` 分支：regular 时渲染三栏 split，小屏时渲染 `TabView`；iPad 用 `previewFilePath` 驱动中栏预览，iPhone 保留 `fileToOpenInFilesTab` 走 sheet / tab 跳转

### 9. Context Usage（上下文占用）

- **展示**：Chat 顶部右侧（模型切换条与齿轮之间）显示环形进度（灰色空环表示无数据）。
- **数据**：从最近一次 assistant message 的 `info.tokens`/`info.cost` 读取 token/cost；context limit 从 `GET /config/providers` 中 `limit.context` 获取。
- **交互**：点击 ring 弹 sheet 展示 provider/model、context limit、total tokens、token breakdown（input/output/reasoning/cache read/cache write）与 total cost。
- **常驻可见**：ring 在 idle、busy、streaming 等所有状态下始终显示。`ChatTabView` 不向 `.navigationBarTrailing` 注入 `ProgressView`；busy 状态已由输入栏红色停止按钮传达，toolbar spinner 已移除。

### 10. Car Mode 技术方案（已实现 Foreground Phase）

#### 10.1 组件与平台门控

Car Mode 只在 iPhone 编译路径和运行时 idiom 下显示。`isCarModeEnabled` 持久化于 UserDefaults，默认 `false`；Settings 的开关和 Car Tab 使用同一个条件。iPad、iPad compact window 与 visionOS 均不暴露入口。

主要组件：

- `AppState+CarMode.swift`：session lifecycle、turn state、structured response 和 exactly-once 状态。
- `Models/CarMode.swift`：versioned response envelope 与 JSON Schema。
- `Views/Car/CarModeView.swift`：录音、等待、朗读、确认和失败 UI。
- `CarSpeechOutputService.swift`：Apple TTS 与 AudioSession 切换。
- `CarClientActionDispatcher.swift`：typed Maps action allowlist。
- `APIClient.promptStructured(...)`：同步 `POST /session/:id/message` wrapper。

#### 10.2 Structured Prompt Contract

每轮请求显式携带 `system` 和 `format: json_schema`，固定使用 `build` agent 与 `openai/gpt-5.6-sol-fast`。server 通过 StructuredOutput tool 校验并把结果写入 `assistant.structured`。客户端不从自然语言 text part 推断 action，也不因 structured assistant 的 `finish == tool-calls` 判定失败。

最小 envelope：

```json
{
  "version": 1,
  "status": "completed",
  "speech": "车库门关着，状态刚刚更新。",
  "confirmation": null,
  "clientActions": []
}
```

需要确认时，`status` 为 `needs_confirmation` 并携带稳定 confirmation ID；导航完成时最多返回一个 typed action：

```json
{
  "version": 1,
  "status": "completed",
  "speech": "正在打开前往 Bright Horizons 的导航。",
  "confirmation": null,
  "clientActions": [
    {
      "id": "route-1",
      "type": "open_navigation",
      "destination": "Bright Horizons, Bellevue",
      "waypoints": []
    }
  ]
}
```

Schema 限制 version、status、speech 长度、action 数量和 action type。system prompt 约束 speech 先说结论、不含 Markdown/URL/代码、默认 8-12 秒且不超过 15 秒，并声明只有用户消息可以授权现实世界副作用。

#### 10.3 Session Lifecycle 与归档恢复

Car session key 为 `hostProfileID + effectiveProjectDirectory`，与普通 Chat 的 `currentSessionID` 分离。本地记录：

```text
sessionID
lastHandledAssistantMessageID
pendingConfirmationID
lastUsedAt
```

每个 turn 都调用 `ensureCarSession()`：

1. 无记录时创建 `Car Mode` session 并保存。
2. 有记录时调用 `GET /session/:id`；404 清除记录并创建一次新 session。
3. session 的 `time.archived > 0` 时，调用 `PATCH /session/:id` 写入 `{ "time": { "archived": -1 } }`，用 server 已接受的 legacy restore sentinel 恢复 iOS Active 状态，然后继续使用原 session。
4. 不 fork、不复制历史，也不为 Web global list 修改 server。OpenCode Web 可能要求 `archived === undefined`，因此 `-1` 的跨客户端可见性不属于 Car Mode 保证。

切后台、切 Tab 或打开 Maps 会停止录音、TTS 和当前前台 request，但不清除 session ID。用户显式选择 New Car Session 时才移除当前 context mapping。

#### 10.4 Turn State 与 Exactly-Once

```text
idle
→ recording
→ finalizing
→ waitingReply
→ speaking / awaitingConfirmation / failed
→ idle
```

只有 VoiceFlow final transcript 自动提交。响应必须同时满足目标 session、assistant role、`time.completed != nil`、可解码的 version 1 structured envelope 和非空 speech。客户端用 assistant message ID 去重 TTS/action，用 confirmation ID 关联下一轮。取消活动 turn 时停止 TTS，并 best-effort 调用 `POST /session/:id/abort`。

当前 Foreground Phase 使用同步 endpoint，直接获得最终 assistant；普通 Chat 的异步 `prompt_async → SSE → reload` 不复用这条状态机。后续异步化仍需保留上述 completion predicate 和 exactly-once ID，不得仅凭 `session.status == idle` 触发朗读或 action。

#### 10.5 Audio 与 Client Action

VoiceFlow finalization 完成后先释放录音 AudioSession，再由 TTS service 切换到 `.playback` + `.spokenAudio`。这避免声音残留在 receiver 或 Bluetooth HFP route。录音开始或取消时停止当前朗读。

`open_navigation` 是唯一客户端 action。dispatcher 校验 version/type、destination/waypoints 长度并严格 URL encode，再生成 Apple Maps unified URL。模型不得返回任意 URL。客户端先完成短 TTS，再打开 Maps；文案只能说“正在打开路线”，不能声称导航已经开始或路线已经修改。

#### 10.6 Server Contract 与验证证据

Car Mode 不维护 archive-list server patch。唯一独立 server compatibility 修复是 structured user message `info.format` 的 wire schema，使 `GET /session/:id/message` 能读取持久化 structured turns；该修复位于 nested checkout commit `43a4a0e53`，与 Car session active-list 行为无关。

2026-07-13 live spike 已验证：同步 structured speech 返回有效 object；同一 session 第二轮保留上一轮目的地；tool execution 后仍能以 structured final 结束。它只证明通用 tool → structured 链路，不证明 Smart Home、邮件、iMessage 或 route-duration 已注册、授权或完成真实 E2E。

客户端验证覆盖 unit state flow、structured history fallback、iPhone 实验开关与 Car UI、iPad 入口隐藏，以及 visionOS build。测试固定使用串行 `xcodebuild` 和 `-parallel-testing-enabled NO`。

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
