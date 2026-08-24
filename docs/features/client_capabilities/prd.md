# iOS 客户端能力 PRD

## 结论

OpenCode iOS 允许将 Car Mode 下受限的结构化动作（structured action）派发至当前 iPhone 本地执行，并将执行结果传回原始 Car Session。V0 阶段仅开放 `health_quantification.export_all` 能力：当 AI 发现服务端存储的健康数据缺失或过期时，向 iPhone 发起调用以打开 Health Quantification；数据导出完成后自动跳回 OpenCode，并无缝继续此前的分析任务。

该能力的核心价值在于消除用户在不同 App 之间手动来回切换的繁琐操作，而非将 iPhone 演进为通用的远程工具执行环境。OpenCode Server、常规 Chat 流程、底层 HealthKit 数据采集以及健康分析协议均保持原样。

## 用户流程

```text
用户在 Car Mode 请求健康分析
→ AI 先用服务器工具检查数据 freshness
→ 数据缺失或过期时返回 typed Health export action
→ OpenCode iOS 首次显示本地授权
→ Health Quantification 执行 Export All
→ callback 唤起 OpenCode
→ OpenCode 向原 Car session 发送规范化结果
→ AI 重新读取服务器数据并完成分析
```

首次弹出授权弹窗时，提供“取消”、“仅允许一次”与“始终允许”三个选项。永久授权项按稳定的 capability 名称持久化存储，用户可在 Settings → Client Capabilities 界面随时撤销。模型返回的自然语言 reason 仅用于向用户解释本次调用的意图，不参与权限规则的匹配。

## 产品边界

- V0 阶段仅对 Car Mode 和 `health_quantification.export_all` 开放。
- 模型无权指定 launch URL、callback URL、Session ID、Host Profile 或过期时间。
- OpenCode 本身不直接读取 HealthKit；数据采集、系统权限申请、进度展示与错误提示仍由 Health Quantification 独立负责。
- callback 仅回传执行状态、导出条数、失败类别以及固定错误码，绝不携带具体的健康明细数据或自由文本。
- continuation 阶段必须重新从 Health Quantification 服务端拉取数据；收到 callback 成功响应并不能直接等同于服务端数据已处于最新状态。
- 明确不支持常规 Chat、快捷指令（Shortcut）、系统分享面板（Share Sheet）、任意自定义 URL 唤起、服务端 remote-tool 协议、后台消息 Broker 以及多设备协同路由。

## 成功标准

- 用户只需表达一次健康分析意图，首次触发时最多完成一次本地授权确认，无需手动点击 Export All 或重新发起提问。
- 在 Health App 未安装、callback 过期、重复回调、网络断开或切换 Host 等异常场景下，系统均能防御性兜底，绝不会将结果错投至其他 Session。
- 全局同一时刻最多维护一条 Health export 的 Pending 或 Outbox 记录；收到重复 action 时不会拉起二次导出。
- 永久授权支持手动撤销，选择取消或仅允许一次的操作不会产生持久化配置。
- 保证 Maps action 与既有的 `opencode://session/<id>` 深度链接行为完全无回归。

正式 URL、存储规范与 continuation 协议参见 [`protocol.md`](protocol.md)，具体架构实现取舍参见 [`rfc.md`](rfc.md)。
