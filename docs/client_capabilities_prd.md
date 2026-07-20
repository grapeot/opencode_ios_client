# iOS 客户端能力 PRD

## 结论

OpenCode iOS 可以把 Car Mode 的受限 structured action 交给当前 iPhone 执行，再把结果送回原 Car session。V0 只开放 `health_quantification.export_all`：AI 发现服务器健康数据缺失或过期时，请求 iPhone 打开 Health Quantification；导出完成后自动回到 OpenCode，并继续原始分析。

这个能力减少的是用户手工编排 App 的步骤，不是把 iPhone 变成通用远程工具执行器。OpenCode server、普通 Chat、HealthKit 采集和 Health 数据分析合同均保持不变。

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

首次授权提供取消、仅这次允许、以后自动允许。永久授权按稳定 capability 名保存，可以在 Settings → Client Capabilities 撤销。自然语言 reason 只解释本次用途，不参与授权匹配。

## 产品边界

- V0 只支持 Car Mode 和 `health_quantification.export_all`。
- 模型不能提供 launch URL、callback URL、session ID、Host Profile 或过期时间。
- OpenCode 不读取 HealthKit；Health Quantification 继续拥有采集、权限、进度和错误 UI。
- callback 只返回状态、计数、失败类别和稳定错误码，不返回健康明细或自由文本。
- continuation 必须重新读取 Health Quantification server；callback 成功不是健康数据已经新鲜的可信证明。
- 不支持普通 Chat、Shortcut、Share Sheet、任意 URL、server remote-tool protocol、后台 broker 或多设备路由。

## 成功标准

- 用户只表达一次健康分析目标，首次最多增加一次本地授权，不再手工点击 Export All 或重复描述任务。
- Health App 未安装、callback 过期、重复 callback、断网和 Host 切换均不会把结果发到错误 session。
- 同一时刻最多存在一个 Health export Pending/Outbox；重复 action 不启动第二次导出。
- 永久授权可以撤销，取消和仅这次允许不会持久化。
- Maps action 和 `opencode://session/<id>` 行为不回归。

正式 URL、存储和 continuation 合同见 [`client_capabilities_protocol.md`](client_capabilities_protocol.md)，实现取舍见 [`client_capabilities_rfc.md`](client_capabilities_rfc.md)。
