# OpenCode iOS 推送通知调研

更新：2026-07-24

## 结论

可以不改每一台 OpenCode server 的源码，但不能只改 iOS client 就获得及时、可靠的后台通知。

iOS app 在前台时，现有代码已经能从 `/global/event` 判断 `question.asked` 和 `permission.asked`，也已经把它们归类为 needs attention。进入后台后，app 会主动断开 SSE 和 SSH tunnel；即使不主动断开，iOS 也会很快挂起普通网络连接。因此 app 不在前台时，必须有另一个常驻进程继续监听 server，再通过 APNs 唤醒或通知手机。

建议采用一个独立的 notification bridge，而不是修改 OpenCode server：

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

这样“不改 server”成立，代价是增加一个很小的旁路服务。若要求连这个常驻服务也不存在，则只能做不及时、不可保证的后台轮询，不适合作为正式推送能力。

## 当前客户端已经具备一半能力

第一，现有 `SSEClient` 已连接 `GET /global/event`，不需要 OpenCode 新增通知 endpoint（`OpenCodeClient/OpenCodeClient/Services/SSEClient.swift:51-137`）。

第二，客户端已经识别需要人处理的两个核心事件：`permission.asked` 和 `question.asked`（`OpenCodeClient/OpenCodeClient/AppState+SSE.swift:125-138`）。`AppState` 也已经按 session 汇总 attention 数量（`OpenCodeClient/OpenCodeClient/AppState.swift:487-503`）。

第三，server 现有 REST API 能在断线重连后补拉 pending permission 和 question，所以 bridge 或客户端不必完全依赖瞬时 SSE 事件（`OpenCodeClient/OpenCodeClient/Services/APIClient.swift:386-423`）。

第四，通知点击后的导航基础已经存在。app 已支持 `opencode://session/<session_id>` deep link（`OpenCodeClient/Info.plist:5-15`）。

真正缺失的是后台 delivery。app 进入后台时明确断开 SSE 和 SSH tunnel（`OpenCodeClient/OpenCodeClient/ContentView.swift:738-746`），Xcode 工程目前也没有 `aps-environment` entitlement 或 Remote notifications background mode。

## 为什么纯 client 方案不成立

### 本地通知只能覆盖 app 仍在运行时收到的事件

如果 app 在前台收到 `question.asked`，它当然可以立即安排一条本地通知。但用户真正需要通知的场景恰恰是 app 已经离开前台；此时没有 SSE 事件到达，也就没有触发本地通知的机会。

### 后台轮询可以做 fallback，不能承担实时通知

`BGAppRefreshTask` 可以偶尔唤醒 app，让它调用现有 `/permission`、`/question` 和 `/session/status`。但执行时间由系统决定，可能延迟或跳过，Apple 只提供短暂运行窗口。它适合恢复 badge 或兜底同步，不适合“AI 现在停下来等你”的及时触达。[Apple：Choosing Background Strategies](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app)

对当前产品还有第二层问题：SSH host 需要 app 先建立 tunnel，而当前后台路径会主动关闭 tunnel。即使系统偶尔给一次后台运行机会，也不适合依赖临时 SSH 握手、全量轮询多台 host，再发本地通知。

### Live Activity 不是 APNs 的替代品

Live Activity 适合显示一个已知长任务的进度，但 app 挂起后若要从远端更新，仍然需要 ActivityKit push。它也不适合承载 permission/question 这种离散、高优先级请求。第一版应先做普通 push；需要长任务进度时再单独评估 Live Activity。

### 不应借用 PushKit 或伪装后台模式

PushKit 面向 VoIP 等特定用途。用它维持普通 OpenCode 事件连接既不符合平台语义，也有审核风险。音频、定位等后台模式同样不适用于此功能。

## 推荐架构：server 零源码改动，增加旁路 bridge

notification bridge 做四件事：

1. 保存 iOS 安装实例的 APNs device token，以及它订阅的 host/session 范围。
2. 对每个已配置 host 保持现有 `/global/event` SSE；断线后使用 `/permission`、`/question` 和 `/session/status` 对账。
3. 用一套集中规则去重并判断哪些事件需要通知。
4. 调 APNs 发送可见通知，payload 只携带不可泄密的 host profile ID、session ID 和事件类型；通知正文避免包含 prompt、文件路径或 server credential。

APNs 的标准架构本身就要求 app 把 device token 交给 provider，provider 再持有 APNs 连接并发送通知。[Apple：Setting up a remote notification server](https://developer.apple.com/documentation/usernotifications/setting-up-a-remote-notification-server)

### bridge 放在哪里

最省改动的第一版是运行在一台常在线、能访问所有 OpenCode host 的机器上。它可以是独立 daemon、容器或小型云服务，不需要链接进 OpenCode 进程。

如果各 server 只在彼此隔离的私网内可达，则不存在一个中心位置能直接消费全部 SSE。这时仍不必改 server 源码，但每个网络域需要一个轻量 watcher，把归一化后的 attention event 发给中央 APNs gateway。APNs 私钥只放中央 gateway，不散落到每台机器。

这个部署边界比“每台 server 加 push 逻辑”更适合当前多 host 模型：OpenCode 升级不会覆盖通知功能，通知规则也只维护一份。

## 多用户产品应优先采用 OpenCode plugin

中央 bridge 直接访问所有用户 host 只适合单一所有者的私有部署。多用户产品不应收集用户的 OpenCode URL、Basic Auth、SSH key 或私网访问权。更合理的拓扑是让 plugin 在用户自己的 OpenCode 进程内观察事件，只向中央 APNs gateway 发出站 HTTPS：

```text
用户机器：OpenCode + notification plugin
                    │ 只上传最小 attention envelope
                    ▼
              APNs gateway
                    ▼
                 iPhone
```

这条路径不修改 OpenCode core，但用户需要安装 plugin。OpenCode 官方支持从 `~/.config/opencode/plugins/` 自动加载本地 JS/TS plugin，也支持在 `opencode.json` 的 `plugin` 数组中声明 npm package；npm plugin 会在启动时自动安装。[OpenCode Plugins](https://opencode.ai/docs/plugins)

### 当前 plugin API 足够完成通知

OpenCode 的公开 `Hooks.event` 接收类型化 `Event`（`opencode-official/packages/plugin/src/index.ts:222-225`）。官方文档列出的稳定事件正好覆盖第一版：

- `question.asked` / `question.replied` / `question.rejected`
- `permission.asked` / `permission.replied`
- `session.error`
- `session.idle` 或 `session.status`

`serve` 的 server layer 明确装配 `Plugin.node`（`opencode-official/packages/opencode/src/server/routes/instance/httpapi/server.ts:212-225`），所以这不是只在 TUI 中工作的 hook。server plugin 还会收到同进程 SDK client、当前 directory 和 server URL（`opencode-official/packages/plugin/src/index.ts:56-65`）。

当前 event 分发对 plugin 使用 fire-and-forget 调用（`opencode-official/packages/opencode/src/plugin/index.ts:251-257`），推送网络请求不会阻塞 OpenCode session。plugin 自己必须捕获异常并进入本地 outbox，不能让 rejected promise 演变成未处理错误。

### 难度判断

只做“收到 `question.asked` 后 POST 一次 webhook”的 plugin 很简单，核心逻辑只有事件筛选、最小 payload 和签名请求。社区已经有 Pushover、Discord、Slack 等同类 notification plugin，说明这个扩展路径已被实际使用。

生产可用版本是中等工作量，但复杂度主要不在 OpenCode：

| 模块 | 难度 | 主要工作 |
|---|---|---|
| OpenCode plugin | 小 | 事件过滤、隐私裁剪、签名、outbox |
| 用户配对 | 中 | 把某个 host installation 与某台 iOS device 安全绑定 |
| APNs gateway | 中 | device token 生命周期、鉴权、限流、无效 token 清理 |
| 可靠性 | 中 | 本地持久化、重试、去重、解决事件撤销 badge |
| 版本兼容 | 小到中 | 跟踪公开 event 名称和 payload 的版本变化 |

### 维护成本可控的前提

plugin 应保持“薄”：只消费公开 `event` hook，不调用 OpenCode 内部模块，不修改 permission/question 执行流程，也不在 hook 中同步等待 gateway。把通知文案、用户偏好、频率限制和 APNs 逻辑留在 gateway，plugin 只发送版本化的最小 envelope。

建议 envelope 只包含 `schema_version`、plugin/OpenCode version、installation ID、event ID/type、session ID、request ID 和时间戳。默认不上传 question 正文、permission pattern、prompt、目录或文件路径。

需要维护一个很小的兼容矩阵，并至少覆盖当前与前一个 OpenCode release。历史上 OpenCode 确实出现过 v1/v2 event 名称变化，因此不应假设 payload 永远不变；但我们依赖的是官方文档化 API，维护风险明显低于 patch OpenCode core 或解析日志。

### 推荐配对流程

1. iOS app 向 gateway 注册 APNs device token，并生成短期一次性 pairing code。
2. 用户在 host 上运行 plugin package 提供的 setup 命令，输入 pairing code；命令安装/配置 plugin，并在本机保存 installation secret。
3. plugin 只用该 secret 向 gateway 发送签名 attention event。gateway 没有 OpenCode credential，也不能反向访问 host。
4. push payload 携带 installation ID 和 session ID。iOS 用 installation ID 找到本地 Host Profile，再用 Keychain 中已有 credential 打开 session。

因此，“不改 server”更准确的产品含义是：不 fork 或 patch OpenCode，但要求用户安装一个官方 plugin。若连 plugin/companion 都不能安装，则只能推动 OpenCode core 原生增加 webhook；纯 iOS client 无法实现可靠后台推送。

## 第一版通知规则

第一版不应把所有 server event 都推到手机。建议只覆盖：

| 事件 | 默认行为 | 原因 |
|---|---|---|
| `question.asked` | 立即通知 | AI 明确阻塞，等待输入 |
| `permission.asked` | 立即通知 | AI 明确阻塞，等待批准 |
| `session.error` | 通知 | 需要人工恢复或判断 |
| busy/retry → idle | 可配置通知 | 有价值，但高频任务容易制造噪声 |
| message/todo 更新 | 不通知 | 不是 attention，只更新 app 内状态 |

去重键应使用 `host_id + event_type + request_id`。如果 SSE 断线后 REST 对账再次发现同一 pending request，不应重复推送。permission/question 解决后应清除 badge；通知点击使用现有 session deep link，再由 app 实时拉取 request 状态，不能信任通知 payload 中的旧状态。

## 改动范围与难度

### iOS client：中等偏小

需要增加 Push Notifications capability、通知授权 UI、APNs device-token 注册、token 上传、前台展示策略、通知点击路由、badge 清理及测试。现有 deep link 和 attention model 可复用，所以 client 侧不是主要难点。

### OpenCode server：可以为零

bridge 直接消费现有 SSE 和 REST。无需改 OpenCode endpoint、event schema 或每台 server 的业务代码。

### 新增 bridge：中等

工作量主要在多 host 连接管理、credential 安全、SSE 重连/REST 对账、去重和 APNs token 生命周期。单 host demo 很小；生产可用的多 host 版本才是本功能的主体。

## 不建议的方案

| 方案 | 判断 |
|---|---|
| 只在 iOS 加本地通知 | 只能通知前台已收到的事件，没有解决问题 |
| iOS 用 BGTaskScheduler 轮询所有 server | 可作低频 fallback，不及时、不保证执行，SSH host 尤其脆弱 |
| 每台 OpenCode server 直接接 APNs | 能工作，但把 token、私钥和通知规则复制到所有 server，升级与运维成本最高 |
| 修改 OpenCode core 增加 push endpoint | 当前没有必要；已有 SSE/REST 足够作为事件源 |
| Live Activity 取代普通 push | 不成立；远端更新仍需要 push，且 question/permission 更适合普通通知 |

## 建议的验证顺序

第一步先做一个单 host、单设备 spike：bridge 连现有 SSE，只处理 `question.asked`，通过 APNs 发一条带 session deep link 的通知。它验证最关键的闭环，同时完全不改 OpenCode server。

第二步补 `permission.asked`、`session.error`、完成通知、REST 对账和去重，再扩展到多个 direct host。

第三步单独验证 SSH/private host 的网络拓扑。若中央 bridge 无法直连，就部署网络域内 watcher，而不是强迫 iOS 在后台临时建 SSH tunnel。

第一步闭环跑通后，再决定 bridge 是现有常在线 Mac 上的本地 daemon，还是一个集中托管服务。这个决定影响部署与 credential 管理，但不影响 iOS/APNs 协议设计。

## Apple 平台依据

- [Setting up a remote notification server](https://developer.apple.com/documentation/usernotifications/setting-up-a-remote-notification-server)：provider 保存 device token，并向 APNs 发送请求。
- [Sending notification requests to APNs](https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns)：provider 通过 HTTP/2/TLS 向 `/3/device/<token>` 发送 payload。
- [Choosing Background Strategies for Your App](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app)：后台任务由系统调度，remote notification 的后台执行窗口有限且可能限流。
- [Configuring background execution modes](https://developer.apple.com/documentation/xcode/configuring-background-execution-modes)：普通 app 在后台通常处于 suspended；Remote notifications 只是受支持的有限后台入口之一。
