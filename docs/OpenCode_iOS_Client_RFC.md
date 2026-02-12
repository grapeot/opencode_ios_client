# RFC-001: OpenCode iOS Client 技术方案

> Request for Comments · Draft · Feb 2026

## 元数据

| 字段 | 值 |
|------|------|
| **RFC 编号** | RFC-001 |
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
- 初期仅支持局域网直连，后续可扩展至 Tailscale 等

---

## 方案

### 1. 整体架构

```
┌─────────────────────────────────────────────────────────────────┐
│                        iOS Client (SwiftUI)                       │
├─────────────────────────────────────────────────────────────────┤
│  Views                 │  State                   │  Services     │
│  ─────────             │  ─────────               │  ─────────    │
│  ChatTab               │  AppState (@Observable)   │  APIClient    │
│  FilesTab              │  SessionState             │  SSEClient    │
│  SettingsTab           │  MessageState            │  AuthService  │
│  MessageRow, DiffView  │  ConnectionState         │               │
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
| Markdown | MarkdownUI | 优先使用原生能力；MarkdownUI 支持代码块、链接、列表 |
| Diff | 自建 View（优先 iOS 原生能力） | 基于 `before`/`after` 做 unified diff 渲染，行级高亮 |
| 持久化 | UserDefaults + Keychain | 连接信息、模型预设；密码存 Keychain |

### 3. 网络层设计

#### 3.1 REST API

- 使用 `URLSession` 封装 `APIClient`
- 统一 Base URL：`http://<ip>:<port>`，默认 `192.168.180.128:4096`，来自 Settings
- 所有请求附加 Basic Auth header（若配置）
- 推荐使用 `POST /session/:id/prompt_async` 发送消息，busy 时由服务端排队

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

### 4. 状态管理

```swift
@Observable
final class AppState {
    var serverURL: String
    var isConnected: Bool
    var sessions: [Session]
    var currentSessionID: String?
    var sessionStatuses: [String: SessionStatus]
    var messages: [Message]
    var parts: [String: [Part]]
    var selectedModelIndex: Int
    // ...
}
```

- 单一 `AppState` 持有全局状态
- SSE 事件根据 `type` 分发，更新对应字段
- View 通过 `@Environment` 或直接注入访问

### 5. 消息与文档 UI

#### 5.1 消息流

- **布局**：OpenCode 风格，无左右气泡；人类消息灰色背景，AI 消息白/透明
- **Part 渲染**：text (Markdown)、reasoning (折叠)、tool (卡片)、patch (跳转 Files)
- **流式**：`message.part.updated` 带 `delta` 时追加到对应 Part，实现打字机效果
- **主题**：跟随 `@Environment(\.colorScheme)`，Light/Dark

#### 5.2 文档审查

- **Markdown 展示**：Preview 为主，可切换 Markdown 源码
- **Diff 高亮**：优先在 Preview 内高亮 changes；若实现困难，则在 Markdown 内高亮
- **入口**：Files Tab → Session Changes → 选文件 → diff 视图

### 6. 权限与输入

- **Session 列表**：列出 workspace 下所有已有 Session，作为连接与解析的验证手段
- **权限**：`permission.asked` 时展示卡片，用户手动批准/拒绝，调用 `POST /session/:id/permissions/:permissionID`
- **输入**：支持多行，发送用 `prompt_async`；busy 时消息由服务端排队
- **Abort**：提供按钮调用 `POST /session/:id/abort`

### 7. 文件与 Diff

- **文件树**：`GET /file?path=` 递归展示；`GET /file/status` 获取 git 状态做颜色标记
- **内容**：`GET /file/content?path=`；文本文件语法高亮，二进制显示类型提示
- **Session Diff**：`GET /session/:id/diff` 获取变更列表，点击进入 unified diff 视图

---

## 实现规划

| Phase | 范围 | 预计周期 |
|-------|------|----------|
| 1 | Server 连接、SSE、Session、消息发送、流式渲染 | 2–3 周 |
| 2 | Part 渲染、权限手动批准、主题、`prompt_async` | 2 周 |
| 3 | 文件树、Markdown 预览、文档 Diff、高亮 | 2–3 周 |
| 4 | iPad 适配、mDNS、Widget 等 | 暂不实现 |

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
