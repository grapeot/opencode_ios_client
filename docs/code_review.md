# Code Review

本文档记录一次面向「准备继续迭代」的整体 Code Review，重点覆盖：

- 明显的架构不足
- 设计方面的缺陷（产品/交互/可维护性/可观测性）

Review 范围以 iOS 端为主（`OpenCodeClient/`），以及与 OpenCode server API/SSE 的契合度。

## 1. 明显的架构不足

### 1.1 `AppState` 过于“上帝对象”

`OpenCodeClient/OpenCodeClient/AppState.swift` 同时承担：

- 连接配置（URL/用户名密码）
- REST 调用（通过 `APIClient`）
- SSE 生命周期管理（连接/断开/事件分发）
- Session / Message / Diff / FileTree / Todo 的状态与缓存
- 发送后的轮询策略

问题：

- 单文件/单类型职责过多，后续加功能时容易“牵一发动全身”
- 难以单测：大部分逻辑绑定在 `@MainActor` + 实网调用 + 定时轮询上
- 事件处理和 UI 状态更新耦合，未来做 streaming/delta 合并会更难

建议：

- 拆出更细的 domain store：`SessionStore` / `MessageStore` / `FileStore` / `TodoStore`
- SSE 事件先在一个非 UI 的 reducer 层做「解析/过滤/归并」，再更新 store
- 将轮询与重试策略从 state 中抽成 `SyncCoordinator`

更详细的落地规划（建议按 3 个小阶段做，每阶段都能独立合并并有 test）：

1. **把 side-effect 抽出 AppState（不动 UI 绑定）**
   - 新建 `Services/OpenCodeService`（或 `OpenCodeAPI`）封装：health/sessions/messages/files/todos/abort/summarize…
   - `AppState` 只持有一个 service 实例，并把所有 `apiClient.*` 访问迁移到 service
   - 好处：把“怎么发请求/怎么组 URL/怎么处理错误”集中，AppState 只做流程
   - **细化**：先列出 `APIClient` 当前所有对外方法，逐一迁移到 `OpenCodeService`；`OpenCodeService` 持有 `APIClient` 实例；`AppState` 调用 `service.health()` 等，不再直接 `apiClient.health()`

2. **把 SSE 与 polling 策略抽成 coordinator（可 mock）**
   - 新建 `SyncCoordinator`：负责 connect/reconnect/backoff、message.updated 后的刷新策略、发送后的 fallback polling
   - `SyncCoordinator` 向外暴露 `AsyncStream<DomainEvent>`（例如 `.messagesChanged(sessionID)`、`.permissionAsked(...)`）
   - `AppState` 只做订阅 + 调用 service 拉取 + 写入 stores
   - **细化**：`connectSSE()`、`disconnectSSE()`、`startPollingAfterSend()` 逻辑迁入 `SyncCoordinator`；`AppState` 在 `refresh()` 时创建 coordinator、订阅 event、调用 `loadMessages()` 等

3. **引入 reducer/handler（提升可测性）**
   - 新建 `SSEEventReducer`：输入 `SSEEvent` + `currentSessionID` → 输出 `DomainEvent`（或 `[]`）
   - 这层可以纯函数化，单测覆盖：session 过滤、delta 合并触发条件、todo 更新等
   - 最终结果：`AppState` 变薄，测试重点转移到 reducer/service/coordinator
   - **细化**：`handleSSEEvent` 内 switch 逻辑先迁到 `SSEEventReducer.reduce(event, currentSessionID) -> [DomainEvent]`；`AppState` 只消费 `DomainEvent` 并更新 stores

补充观察（当前代码状态）：

- 已做了第一步“拆数据不拆行为”：新增 `Stores/SessionStore.swift`、`Stores/MessageStore.swift`、`Stores/FileStore.swift`、`Stores/TodoStore.swift`，但 `AppState.swift` 仍然承载了几乎全部 side-effect（API/SSE/polling）与业务流程
- 这能降低 UI diff/合并冲突，但对「可测试性」「演进成本」的帮助有限；后续如果要引入 streaming merge、离线缓存、或更复杂的同步策略，建议继续把“流程/策略”拆出去

### 1.2 SSE 解析与重连策略偏“最小可用”，鲁棒性不足

`OpenCodeClient/OpenCodeClient/Services/SSEClient.swift`：

- 仅按单行 `\n` 处理 `data:`，未覆盖 SSE 规范里的多行 data、`event:`、空行分隔、comment keep-alive（":" 开头）等
- 没有指数退避/重连策略（断网/切后台/服务端重启时体验会抖）
- `AsyncThrowingStream` 内部启动的 `Task` 没和 `continuation.onTermination` 绑定，长期看更难控制资源

补充一个更“致命”的点：

- 当前实现按 **byte → UnicodeScalar → Character** 逐字节拼接字符串，这在遇到 UTF-8 多字节字符（中文、emoji、某些标点）时会产生错误字符，从而导致 JSON 解码失败或内容错乱（即使服务端发送是合法 UTF-8）

建议：

- 按 SSE 标准以 event 为单位解析（以空行 `\n\n` 作为 event 结束）
- 增加重连：指数退避 + 最大间隔 + 前台恢复时快速重连
- 建议加 `Accept: text/event-stream`、`Cache-Control: no-cache`

当前实现进展：

- ✅ 已增加 `Accept: text/event-stream`、`Cache-Control: no-cache`
- ✅ 已把解析从“逐字节 Character”改为“按 UTF-8 buffer 解码 + 按 event 切分”，并支持多行 `data:` + keep-alive comment
- ✅ `AsyncThrowingStream` task 已绑定 `continuation.onTermination`
- ✅ `AppState.connectSSE()` 已增加指数退避重连（断线/服务端重启时更稳）

### 1.3 SSE 事件未按 session 过滤导致潜在的跨 session 污染

这个问题的典型形态是：`AppState.handleSSEEvent` 在 `message.updated` / `message.part.updated` 上只要 `currentSessionID != nil` 就触发 `loadMessages()`，但没有检查 event 是否属于当前 session。

问题：

- 多 session 并发时，会频繁拉取“当前 session”但事件可能来自其他 session
- 不必要的网络开销与 UI 抖动

建议：

- 参考 `opencode-official` 的处理方式：基于 event properties 的 `sessionID/messageID` 做过滤
- 如果服务端 event payload 不含 sessionID，需要在 SSE 解析层补齐（或回退到定时 sync）

当前实现进展：

- ✅ `AppState.shouldProcessMessageEvent(...)` + `handleSSEEvent` 已按 `sessionID` 过滤 `message.updated` / `message.part.updated`

### 1.4 “文件/跳转路径”属于跨模块的协议，应该单独建一个统一的规范化层

路径规范化属于跨模块协议，容易在多个地方出现“各自 trim 一下”的实现，最终导致跳转/请求不一致。

建议：

- 抽到 `PathNormalizer` / `FilePath` 类型，统一处理：`a/` `b/` 前缀、`#L..`、`:line:col`、URL 编码等
- 增加对异常 path 的可观测性：当 server 返回 empty content 时记录 request url/path 以及响应摘要

当前实现进展：

- ✅ 已新增 `OpenCodeClient/OpenCodeClient/Utils/PathNormalizer.swift`，并用于 `Part.filePathsForNavigation`
- ✅ 已补齐：percent-encoding decode（含双重编码的常见情况）、`file://` URL 兼容、以及最基本的 `../` 防御性处理
- ✅ 已补齐：对 tool payload 里的“绝对路径”做 workspace 前缀剥离（使 read/write/apply_patch 等路径能正确打开文件预览）
- ✅ 已补齐：把 `.` / `..` segment 过滤成“安全路径”（避免 `src/../x` 这类路径污染 API 请求）
- ✅ 已补齐：empty content 可观测性（`loadFileContent` 发现 text 为空时记录 base/raw/resolved/sessionID）
- ❗仍缺：URL encode/decode 的一致性策略（哪些地方 encode/哪些地方只 normalize）

## 2. 设计方面的缺陷

### 2.1 连接配置与凭证存储缺失（与 RFC/PRD 不一致）

RFC/PRD 提到 UserDefaults + Keychain。

当前实现进展：✅ 已实现

- `OpenCodeClient/OpenCodeClient/AppState.swift`：`serverURL/username` 写入 `UserDefaults`；`password` 写入 Keychain（空串会 delete）
- `OpenCodeClient/OpenCodeClient/Utils/KeychainHelper.swift`：最小 Keychain helper
- `OpenCodeClient/OpenCodeClient/Views/SettingsTabView.swift`：Settings UI 直接绑定 `state.serverURL/username/password`

仍可改进：

- Keychain 的 `kSecAttrAccessible` 未显式指定；如果要更严格，可设为 `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` 或根据需求选择
- `serverURL` 当前允许任意 http(s) 地址；若后续支持公网，需要引入 TLS + token-based auth（Basic Auth over HTTP 不适合公网）

### 2.2 Chat 的可选中与交互冲突风险 ✅ 已按限定范围实现

**决策**：仅对「用户消息」和「AI 最终回复（text part）」启用 textSelection；思考过程、工具调用、todo 等均不启用。

- 实现：`MessageRowView` 的 `markdownText` 保留 `.textSelection(.enabled)`；`ScrollView` 移除全局选择；`ToolPartView`、`StreamingReasoningView`、`TodoListInlineView` 不启用

**长按选中调研**：用户反馈长按显示 copy/share 但无法选中文字。可能原因：（1）SwiftUI 的 `.textSelection(.enabled)` 在 iOS 上仅支持「全选」、范围选择仅 macOS 支持；（2）MarkdownUI 的 `Markdown` 内部结构可能影响选择手势；（3）List/ScrollView 内嵌时 iOS 18 曾有 bug（18.1 已修复）。若需更好的选中体验，可考虑 `UITextView` + `UIViewRepresentable` 包装（如 RichText 库），或接受当前「全选 + 复制」能力。

### 2.3 `ChatTabView.swift` 体积过大，可维护性下降 ✅ 已拆分

已拆至 `Views/Chat/`：`ChatTabView.swift`、`MessageRowView.swift`、`ToolPartView.swift`、`PatchPartView.swift`、`PermissionCardView.swift`、`StreamingReasoningView.swift`、`TodoListInlineView.swift`。原 `Views/ChatTabView.swift` 集中定义了大量子 View（消息行、tool 卡片、patch 卡片、权限卡片、todo 卡片）。

问题：

- 小改动经常触发大范围 diff
- 编译增量与 SwiftUI preview 体验会变差

建议：

- 将子视图拆分到 `Views/Chat/` 目录（每个卡片一个文件）
- 将纯格式化/映射逻辑（比如状态 label、颜色等）移到专门的 formatter

### 2.4 Todo 渲染的“重复表达”可能让用户困惑

（当前不是优先项；按方案 B 仅在 tool 卡片内展示，暂不特别强调。）

### 2.5 Observability：大量 `print` 不利于线上定位

`print()` 虽然开发快，但难以分级/过滤，也无法跨模块串联。

建议：

- 引入 `Logger`（os.log）并按 subsystem/category 分类
- 日志里包含：sessionID/messageID/path/request url/statusCode/response length

补充观察：

- 当前代码整体已经很少 `print()`，但也缺少“可定位错误”的结构化日志（尤其是 file content 空内容、SSE decode failure、HTTP 4xx/5xx body 摘要）

## 3. 其他明显问题（本次全 repo review 新发现）

### 3.1 SSE UTF-8 处理方式会损坏非 ASCII 内容（影响 streaming 与 tool 输出）

见 1.2 补充点：按 byte 拼 Character 不等于按 UTF-8 解码字符串。只要 payload 里出现中文/emoji，client 侧就可能出现：

- JSON 解码失败（event 丢失，进而 UI 不刷新）
- 文本内容乱码（reasoning/tool 输出显示异常）

建议：

- 以 `Data` buffer 累积 bytes，使用 `String(decoding:buffer,as:UTF8.self)` 或 `String(data:...,encoding:.utf8)` 解码
- 按 SSE 标准用空行分隔 event，合并多行 `data:`

当前实现进展：✅ 已完成（见 1.2）

### 3.2 App 的“网络安全边界”需要在文档里说清楚

当前设计默认局域网 HTTP + Basic Auth（可选），并在 `Info.plist` 允许 local networking。

建议：

- 在 `docs/` 明确：仅推荐局域网；公网必须上 TLS + 更安全的鉴权（token/OAuth/mtls 视场景）
- 在 UI（Settings）给出提示：当前连接 scheme（http/https）与风险

当前实现进展：

- ✅ 客户端逻辑：LAN 允许 `http://`，WAN 强制要求 `https://`（否则直接提示错误，不发请求）
- ✅ Settings 展示 scheme + warning（http 显示橙色/红色提示）

### 3.3 默认 server IP/端口与个人环境绑定

`APIClient.defaultServer` 固定为 `192.168.180.128:4096`，并有单测锁定。

影响：

- 对开源用户不友好；也会把个人局域网拓扑写进公开仓库

建议：

- 默认值改为 `127.0.0.1:4096` / `localhost:4096` 或空值（首次引导填写）
- 文档里提供示例，而不是硬编码在代码里

当前实现进展：✅ 已完成

- `APIClient.defaultServer` 改为 `127.0.0.1:4096`
- `AppState.serverURL` 仍存 UserDefaults，用户可在 Settings 修改

### 3.4 Tool 输出的结构化数据展示能力偏弱

目前 `ToolPartView` 的 `Output` 仅支持 string（`PartStateBridge.output`）。但 server 端 tool output 可能是 object/array（例如 read 返回多段、带行号、带路径等）。

建议：

- `PartStateBridge` 对 `output` 支持 string/object/array，object/array 时可 fallback 为 pretty JSON（至少能看）
- 对 read 类 tool：优先展示 file path + 摘要，并提供“打开文件预览”的 CTA（目前已做部分）

## 4. Security Review（准备 push 到 GitHub 前的检查清单）

### 4.1 Secret / Credential 泄漏风险

当前 repo 中未发现明显的真实密钥特征（例如 OpenAI `sk-...`、AWS `AKIA...`、私钥 PEM）。但需要注意：

- `docs/OpenCode_Web_API.md` 中包含示例：`OPENCODE_SERVER_USERNAME=admin OPENCODE_SERVER_PASSWORD=secret`（示例值不是秘密，但容易被误以为真实配置）
- `OpenCodeClient/build_log*.txt` 这类日志文件若上传，会包含本机路径、bundle id、构建环境信息（偏隐私/指纹，不是 credentials，但通常不建议开源仓库保留）

建议：

- 把 `OpenCodeClient/build_log*.txt` 加到 `.gitignore`，或移出 repo
- 文档中的环境变量示例统一用 `YOUR_PASSWORD_HERE` / `CHANGEME` 并强调“示例”

当前实现进展：

- ✅ `OpenCodeClient/build_log*.txt` 已从 git 删除，并加入 `.gitignore`
- ✅ 语音转写 token 通过 Settings 配置并存 Keychain（不写入仓库）

### 4.2 网络通信安全

- 当前客户端支持 Basic Auth，且默认使用 HTTP（局域网）。如果把 server 暴露到公网，Basic Auth over HTTP 会被抓包直接拿到凭证
- iOS 侧 `Info.plist` 允许 local networking（这是为了解决 iOS Local Network 权限与 ATS 的现实问题），但不等于“可以安全上公网”

建议：

- 公网场景必须：HTTPS（TLS）+ 更强鉴权（token）+ 最小权限（只开必要 endpoints）
- 如果继续支持 Basic Auth：至少在 UI 上对 `http://` 做明显提示，避免用户误配公网地址

### 4.3 本地数据存储

- `password` 已存 Keychain（✅）；`serverURL/username` 存 UserDefaults（✅）

建议：

- Keychain 访问级别显式指定（见 2.1）
- 如果后续引入 session/message 缓存落盘，需要额外做：加密、按 workspace 隔离、以及“清除数据”入口

### 4.4 供应链与依赖

- 使用了 `MarkdownUI`（SPM）。如果开源发布，建议锁定依赖版本（`Package.resolved`）并在 README 说明依赖来源

### 4.5 公开仓库的最小暴露面

建议：

- 默认 server 地址不要包含个人局域网 IP（见 3.3）
- 确认没有把 `.opencode/`、本地配置、或 DerivedData/xcuserdata 等上传
- 给 README 加一段“Threat model”：只适用于本地/受信网络；不负责公网暴露造成的风险
