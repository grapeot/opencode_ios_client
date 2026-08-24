# OpenCode iOS 推送通知调研

更新：2026-07-24

## 结论

我们可以在不修改每台 OpenCode Server 源码的前提下实现通知，但单纯依靠改造 iOS 客户端本身，无法达成及时且可靠的后台消息推送。

当 iOS App 处于前台运行时，现有代码已经能够实时消费 `/global/event` 事件流，精准识别 `question.asked` 与 `permission.asked` 事件，并将其归类为需要人工介入的 Needs Attention 状态。然而一旦 App 退到后台，系统会主动断开 SSE 长连接与 SSH 隧道；即使不主动断开，iOS 系统底层也会在短时间内将常规网络连接挂起。因此，若要在 App 脱离前台时依然能够触达用户，必须引入一个常驻的对端服务继续监听服务端事件流，并通过苹果官方的 APNs 通道唤醒或推送通知到手机。

综合考虑，建议引入一个独立的 Notification Bridge 旁路服务，而非侵入修改 OpenCode Server 的核心代码：

```text
多台 OpenCode server
        │ 现有 SSE / REST，不改协议
        ▼
常驻 notification bridge
        │ 判断 question / permission / done / error
        ▼
       APNs
        ▼
OpenCode iOS，点击通知打开对应 session
```

采用这种架构，既达成了“服务端零改动”的目标，代价仅仅是引入了一个极轻量的常驻旁路服务。如果要求连这一旁路服务也不允许部署，则系统只能退化为受系统调度制约、无法保证及时性的后台间歇轮询，无法作为正式交付的实时推送方案。

## 当前客户端已经具备一半能力

第一，客户端既有的 `SSEClient` 已经稳定连接至 `GET /global/event` 端点，无需 OpenCode 服务端专门开发新的通知接口（代码参见 `OpenCodeClient/OpenCodeClient/Services/SSEClient.swift:51-137`）。

第二，客户端在业务层已经具备识别两类核心人工阻塞事件的能力：`permission.asked` 与 `question.asked`（代码参见 `OpenCodeClient/OpenCodeClient/AppState+SSE.swift:125-138`），且 `AppState` 内部已按 Session 维度完成 Attention 待办计数的聚合统计（代码参见 `OpenCodeClient/OpenCodeClient/AppState.swift:487-503`）。

第三，服务端现有的 REST API 体系支持在连接重连后对账拉取挂起的 Pending Permission 与 Question 数据，因此 Bridge 服务或客户端无需过度依赖脆弱的瞬时 SSE 事件流（代码参见 `OpenCodeClient/OpenCodeClient/Services/APIClient.swift:386-423`）。

第四，通知点击唤醒后的路由与导航基础已经完备。客户端已原生支持 `opencode://session/<session_id>` 深度链接跳转（配置参见 `OpenCodeClient/Info.plist:5-15`）。

当前真正缺失的环节是后台交付能力（Background Delivery）。App 在退到后台时会主动断开 SSE 与 SSH 隧道连接（代码参见 `OpenCodeClient/OpenCodeClient/ContentView.swift:738-746`），且当前的 Xcode 工程尚未配置 `aps-environment` Entitlement 签名，亦未开启 Remote Notifications 后台模式支持。

## 为什么纯 client 方案不成立

### 本地通知只能覆盖 app 仍在运行时收到的事件

如果 App 在前台运行期间收到了 `question.asked` 事件，客户端自然可以即时安排一条本地通知（Local Notification）。但用户真正依赖推送的核心场景恰恰在于 App 已经切到后台或手机处于锁屏状态；在此时段内根本没有网络事件能够触达手机，客户端自然没有任何触发本地通知的时机。

### 后台轮询可以做 fallback，不能承担实时通知

iOS 的 `BGAppRefreshTask` 机制虽然可以在后台由系统间歇唤醒 App，以便调用 `/permission`、`/question` 和 `/session/status` 接口，但其触发时机完全由系统策略黑盒决定，极易产生延迟甚至被直接跳过，且苹果仅提供极其短暂的运行窗口。该机制适合用于校准 Badge 角标或作为兜底对账，完全无法承担“AI 停下来正在等待用户确认”的即时触达需求（参考 [Apple：Choosing Background Strategies](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app)）。

此外，在当前产品架构下还存在第二层阻碍：通过 SSH 连接的主机需要由 App 主动协商建立隧道，而现有后台策略在切后台时会主动关闭隧道。即使系统偶尔赋予了一次后台唤醒机会，让 App 在后台临时完成 SSH 握手、对多台主机执行全量轮询再触发本地通知，在工程上也极不稳定且容易超时失败。

### Live Activity 不是 APNs 的替代品

实时活动（Live Activity）非常适合用于呈现已知长任务的持续进度，但 App 进入挂起状态后若要从远端更新灵动岛或锁屏小组件，底层依然必须依赖 ActivityKit Push 推送通道。同时，它并不适合承载 Permission 或 Question 这类离散、偶发且优先级极高的人工决策请求。首期方案应聚焦于打通标准的 Remote Push；后续若有长任务进度展示需求，再单独评估引入 Live Activity。

### 不应借用 PushKit 或伪装后台模式

PushKit 属于苹果专为 VoIP 通话等强实时场景设立的通道。借用该机制维持普通的 OpenCode 事件流不仅违背了平台规范，在 App Store 审核中也存在极高的下架风险。同理，伪装音频播放或后台定位等模式同样不适用于本业务，不可作为技术方案。

## 推荐架构：server 零源码改动，增加旁路 bridge

Notification Bridge 核心承担四项职责：

1. 统一维护 iOS 客户端安装实例上报的 APNs Device Token，以及该实例订阅的 Host 与 Session 作用域。
2. 面向各个已配置的 OpenCode Host 保持长连监听既有的 `/global/event` SSE 事件；发生断线后，调用 `/permission`、`/question` 与 `/session/status` 接口完成状态对账。
3. 借助集中式的过滤与去重规则，精准判定哪些关键事件需要触发推送。
4. 调用 APNs 接口下发用户可见的通知消息，推送 Payload 仅携带无敏感信息的 Host Profile ID、Session ID 与事件枚举，通知正文中严格避免出现用户 Prompt、源码路径或服务端认证凭证。

APNs 标准架构本身即要求客户端将 Device Token 注册给 Provider，再由 Provider 与 APNs 建立双向安全连接完成消息推送（参考 [Apple：Setting up a remote notification server](https://developer.apple.com/documentation/usernotifications/setting-up-a-remote-notification-server)）。

### bridge 放在哪里

在改动最小的初期落地阶段，可将 Bridge 部署在一台常驻开机、且能够直连所有 OpenCode Host 的机器上。它可以作为一个独立的 Daemon 守护进程、Docker 容器或轻量云服务运行，完全无需与 OpenCode 服务端进程代码发生编译期依赖。

如果各台 Server 部署在互相隔离的局域网内部，全局不存在一个能直连全部 SSE 流的中心节点，此时依然无需修改 Server 源码，只需在每个网络域内部署一个轻量级的 Watcher 代理，将清洗归一化后的 Attention 事件统一上报至中央 APNs Gateway。APNs 的推送私钥仅由中央 Gateway 集中托管，无需分发至各边缘节点。

相较于“在每台 Server 内部侵入编写 Push 逻辑”，这种部署边界与当前的多 Host 架构更为契合：OpenCode 官方版本的常规升级不会破坏推送机制，推送过滤规则也得以在单一位置集中演进。

## 多用户产品应优先采用 OpenCode plugin

由中央 Bridge 直接持有所有用户 Host 访问权的做法仅适用于个人私有部署场景。在面向多用户的商业化产品中，绝不应在中心端收集用户的 OpenCode URL、Basic Auth 账密、SSH 私钥或内网穿透凭证。更为合理的拓扑架构是由 Plugin 在用户本地的 OpenCode 进程内部监听事件，仅在触发时通过出站 HTTPS 向中央 APNs Gateway 发送轻量事件摘要：

```text
用户机器：OpenCode + notification plugin
                    │ 只上传最小 attention envelope
                    ▼
              APNs gateway
                    ▼
                 iPhone
```

该方案无需对 OpenCode Core 源码做任何 Patch，仅需用户在宿主机安装一个 Plugin。OpenCode 官方原生支持从 `~/.config/opencode/plugins/` 自动加载本地 JS/TS 编写的 Plugin，亦支持在 `opencode.json` 的 `plugin` 列表中声明 npm 包依赖，并在服务启动时自动拉取安装（参考 [OpenCode Plugins](https://opencode.ai/docs/plugins)）。

### 当前 plugin API 足够完成通知

OpenCode 公开提供的 `Hooks.event` 接口原生支持接收强类型的 `Event` 对象（参见 `opencode-official/packages/plugin/src/index.ts:222-225`）。官方文档中声明的稳定事件已经完全覆盖首期推送所需的核心场景：

- `question.asked` / `question.replied` / `question.rejected`
- `permission.asked` / `permission.replied`
- `session.error`
- `session.idle` 或 `session.status`

服务端的 `serve` 命令层明确挂载了 `Plugin.node`（参见 `opencode-official/packages/opencode/src/server/routes/instance/httpapi/server.ts:212-225`），因此该 Hook 绝非仅在终端 TUI 模式下生效。此外，Server Plugin 还能获取到同进程的 SDK Client 实例、当前 Working Directory 以及 Server URL（参见 `opencode-official/packages/plugin/src/index.ts:56-65`）。

目前 OpenCode 的底层事件分发机制对 Plugin 采用了 Fire-and-forget 的异步调用策略（参见 `opencode-official/packages/opencode/src/plugin/index.ts:251-257`），因此推送网络请求的耗时绝不会阻塞 OpenCode Session 的正常推理与工具执行。Plugin 自身必须严密捕获所有网络异常并落入本地 Outbox 重试，防止未捕获的 Rejected Promise 演变成未处理的进程崩溃。

### 难度判断

若仅实现“收到 `question.asked` 事件后向 Webhook 发起一次 POST 请求”的基础 Plugin，开发量极小，核心代码仅涉及事件过滤、Payload 裁剪与签名请求。社区中已存在针对 Pushover、Discord、Slack 等平台的通知插件，充分印证了该扩展路径的成熟度与可行性。

构建生产可用的完整闭环属于中等工作量，其核心复杂度主要集中在平台侧与网络侧，而非 OpenCode 本身：

| 模块 | 难度 | 主要工作 |
|---|---|---|
| OpenCode plugin | 小 | 事件过滤、隐私裁剪、签名、outbox |
| 用户配对 | 中 | 把某个 host installation 与某台 iOS device 安全绑定 |
| APNs gateway | 中 | device token 生命周期、鉴权、限流、无效 token 清理 |
| 可靠性 | 中 | 本地持久化、重试、去重、解决事件撤销 badge |
| 版本兼容 | 小到中 | 跟踪公开 event 名称和 payload 的版本变化 |

### 维护成本可控的前提

Plugin 自身应保持“轻量与精简”：严格限制在消费公开的 `event` Hook 上，不调用 OpenCode 的内部未公开模块，不侵入修改 Permission 或 Question 的正常流转逻辑，亦不在 Hook 回调内部同步阻塞等待 Gateway 响应。将推送文案组装、用户免打扰偏好、频控限流以及 APNs 交互逻辑全部沉淀在 Gateway 端，Plugin 仅负责投递带版本号的最小 Envelope 载荷。

建议 Envelope 仅包含 `schema_version`、Plugin/OpenCode 版本号、Installation ID、Event ID/Type、Session ID、Request ID 及时间戳等元数据。默认严禁上传 Question 提问正文、Permission 规则匹配项、用户 Prompt 内容或具体的物理文件路径。

在版本管理上，需维护一个轻量的兼容性矩阵，至少覆盖当前最新版与上一代 OpenCode 官方 Release。鉴于 OpenCode 历史上确实发生过 v1/v2 事件名称更迭的情况，设计上不应假定 Payload 格式永久不变；但由于我们依赖的是官方公开的标准化 API，其维护与升级成本显著低于直接维护 Fork 分支或侵入式解析文本日志。

### 推荐配对流程

1. iOS App 向中央 Gateway 上报注册 APNs Device Token，并生成一个短有效期的临时配对码（Pairing Code）。
2. 用户在 Host 终端运行 Plugin 包提供的 Setup 配置命令并输入配对码；命令完成 Plugin 安装与配置，并在本地持久化生成 Installation Secret 密钥。
3. Plugin 后续仅使用该 Secret 签名向 Gateway 发送结构化的 Attention 事件。Gateway 端无需持有用户的 OpenCode 登录凭据，亦不具备反向访问 Host 的网络权限。
4. 推送下发时，Payload 仅携带 Installation ID 与 Session ID。iOS 客户端收到推送后，根据 Installation ID 检索本地的 Host Profile，并复用 Keychain 中保存的既有凭证建立连接并打开对应 Session。

因此，“服务端零改动”在真实产品演进中的严谨表述应为：无需 Fork 或 Patch OpenCode 服务端源码，但要求用户在宿主机安装一个官方标准的 Plugin。如果连 Plugin 或 Companion 伴生进程也完全不允许部署，则只能推动 OpenCode 官方在 Core 层面原生支持 Webhook 能力；单纯依赖 iOS 客户端无法构建出高可用的后台推送体系。

## 第一版通知规则

首期版本切忌将服务端的全部事件无差别推送到手机端，建议严格收敛覆盖范围：

| 事件 | 默认行为 | 原因 |
|---|---|---|
| `question.asked` | 立即通知 | AI 明确阻塞，等待输入 |
| `permission.asked` | 立即通知 | AI 明确阻塞，等待批准 |
| `session.error` | 通知 | 需要人工恢复或判断 |
| busy/retry → idle | 可配置通知 | 有价值，但高频任务容易制造噪声 |
| message/todo 更新 | 不通知 | 不是 attention，只更新 app 内状态 |

去重 Key 建议基于 `host_id + event_type + request_id` 复合生成。当 SSE 连接断开并触发 REST 补偿对账时，若再次扫描到相同的挂起请求，系统能够准确识别并抑制重复推送。当用户处理完 Permission 或 Question 后，客户端应及时清理对应 Badge 角标；点击通知跳转时统一复用现有的 Session 深度链接，并在 App 激活后实时向服务端拉取最新请求状态，严禁直接无条件盲信推送 Payload 中携带的陈旧上下文。

## 改动范围与难度

### iOS client：中等偏小

需在工程中配置 Push Notifications 能力与通知权限申请交互、完成 APNs Device Token 的生成与上报、制定前台通知呈现策略、打通通知点击的会话路由与 Badge 清理逻辑并补齐自动化测试。鉴于现有的 Deep Link 机制与 Attention 状态模型均可直接复用，客户端侧并非主要难点所在。

### OpenCode server：可以为零

通过 Bridge 模式直接消费既有的 SSE 与 REST 端点，完全无需改动 OpenCode 的接口定义、事件 Schema 或各 Server 节点的业务实现。

### 新增 bridge：中等

核心工作量集中在多 Host 的长连接生命周期管理、主机认证凭证的安全存储、SSE 断线重连与 REST 状态对账机制、事件幂等去重以及 APNs Token 的注册与失效维护。跑通单 Host 的验证 Demo 非常轻量，但构建一套高可用、多 Host 隔离的生产级服务才是该模块的主体工程量。

## 不建议的方案

| 方案 | 判断 |
|---|---|
| 只在 iOS 加本地通知 | 只能通知前台已收到的事件，没有解决问题 |
| iOS 用 BGTaskScheduler 轮询所有 server | 可作低频 fallback，不及时、不保证执行，SSH host 尤其脆弱 |
| 每台 OpenCode server 直接接 APNs | 能工作，但把 token、私钥和通知规则复制到所有 server，升级与运维成本最高 |
| 修改 OpenCode core 增加 push endpoint | 当前没有必要；已有 SSE/REST 足够作为事件源 |
| Live Activity 取代普通 push | 不成立；远端更新仍需要 push，且 question/permission 更适合普通通知 |

## 建议的验证顺序

第一步：优先搭建单 Host、单设备的验证原型（Spike）：由 Bridge 监听现有的 SSE 事件流，专门过滤 `question.asked` 事件，并通过 APNs 成功向手机下发一条携带 Session 深度链接的通知。该步骤能以最低成本打通最关键的业务闭环，同时完全无需改动 OpenCode 服务端。

第二步：在此基础上扩充 `permission.asked`、`session.error`、任务完成等事件通知，完善 REST 补偿对账与防重逻辑，并逐步拓展支持多个直连 Host 节点。

第三步：针对 SSH 穿透或处于隔离私网环境的 Host 拓扑进行专项验证。若中央 Bridge 无法直连私网节点，则部署局域网 Watcher 代理，杜绝强迫 iOS 客户端在后台临时建立 SSH 隧道的脆弱方案。

在第一步原型跑通后，即可根据业务场景决定将 Bridge 定位为用户本地常开 Mac 上的守护进程，还是托管于集中式的云服务。该决策仅影响后续的部署拓扑与凭证管理策略，对 iOS 端与 APNs 之间的通信协议设计完全透明。

## Apple 平台依据

- [Setting up a remote notification server](https://developer.apple.com/documentation/usernotifications/setting-up-a-remote-notification-server)：provider 保存 device token，并向 APNs 发送请求。
- [Sending notification requests to APNs](https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns)：provider 通过 HTTP/2/TLS 向 `/3/device/<token>` 发送 payload。
- [Choosing Background Strategies for Your App](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app)：后台任务由系统调度，remote notification 的后台执行窗口有限且可能限流。
- [Configuring background execution modes](https://developer.apple.com/documentation/xcode/configuring-background-execution-modes)：普通 app 在后台通常处于 suspended；Remote notifications 只是受支持的有限后台入口之一。
