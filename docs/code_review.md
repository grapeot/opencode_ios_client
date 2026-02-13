# OpenCode iOS Client - Code Review (2026-02-13)

## Scope

- 目标：只看明显问题，不做细枝末节。
- 关注：架构可维护性、显著性能风险、显著安全风险。
- 结论：当前代码可用，但有 2 个高优先级问题（1 安全、1 性能/架构交叉），建议先处理。

## Executive Summary

- **P0 安全**：SSH 隧道当前使用 `hostKeyValidator: .acceptAnything()`，等于关闭主机身份校验，存在 MITM 风险。见 `OpenCodeClient/OpenCodeClient/Services/SSHTunnelManager.swift:130`。
- **P1 性能/稳定性**：busy 时采用高频轮询 + 全量消息拉取，长会话下网络与 CPU 压力明显，发热风险高。见 `OpenCodeClient/OpenCodeClient/AppState.swift:834`、`OpenCodeClient/OpenCodeClient/AppState.swift:840`。
- **P1 架构**：`AppState` 职责过重（状态、网络编排、SSE 解析、活动文案、草稿持久化等混在一起），后续功能迭代成本会持续上升。见 `OpenCodeClient/OpenCodeClient/AppState.swift`（文件整体）。

## Findings

### 1) Security

#### 1.1 SSH Host Key Trust Model 缺失（P0）

- 现状：SSH 连接直接接受任意 host key。
- 证据：`OpenCodeClient/OpenCodeClient/Services/SSHTunnelManager.swift:130`
- 风险：首次连接和公网环境中，无法识别中间人攻击。
- 建议：改为 TOFU（首次确认并持久化 fingerprint）或手动 pin fingerprint。

#### 1.2 Basic Auth + HTTP（LAN）默认可用（P2）

- 现状：API 层支持 Basic Auth；地址可为 `http://`（LAN 允许）。
- 证据：`OpenCodeClient/OpenCodeClient/Services/APIClient.swift:59`、`OpenCodeClient/OpenCodeClient/AppState.swift:69`
- 风险：同网段被动抓包即可看到凭证。
- 建议：保留 LAN 例外，但 UI 上增加更强警示与“一键改 https”引导；文档明确“公网必须 https，LAN 也建议 https”。

### 2) Performance / Heat

#### 2.1 Busy 轮询策略偏重（P1）

- 现状：busy 场景每 2 秒轮询一次，最多 90 次，并每轮调用 `loadMessages()`。
- 证据：`OpenCodeClient/OpenCodeClient/AppState.swift:834`、`OpenCodeClient/OpenCodeClient/AppState.swift:858`
- 风险：会话长、消息多时，反复全量解码 + UI 重组，容易带来电量与温度压力。
- 建议：
  - 优先用 SSE 驱动；轮询退化为指数退避（2s/4s/8s）。
  - 增量拉取（基于最后 messageID/time）替代全量拉取。
  - busy->idle 后立即停止所有兜底轮询（已部分做到，可再收紧）。

#### 2.2 列表锚点仍做全量字符串拼接（P2）

- 现状：`scrollAnchor` 每次都遍历所有消息和 streaming map 生成大字符串。
- 证据：`OpenCodeClient/OpenCodeClient/Views/Chat/ChatTabView.swift:525`
- 影响：长会话会增加主线程 diff 与字符串分配负担。
- 建议：改为轻量版本号（如 `messageVersion` / `streamVersion` 计数器），避免遍历拼接。

### 3) Architecture / Maintainability

#### 3.1 AppState 仍是“超级协调器”（P1）

- 现状：虽然已有 Store 拆分，但 AppState 仍承担大量协议细节与生命周期编排。
- 证据：`OpenCodeClient/OpenCodeClient/AppState.swift`（SSE 处理、轮询、活动文案、权限兜底、模型记忆等均在同一类）。
- 影响：
  - 新功能容易相互耦合（例如 activity、polling、session status 交错）。
  - 单测难写，回归风险上升。
- 建议：按职责继续拆分为 `SessionRuntimeCoordinator`、`ActivityTracker`、`PermissionController` 三块，并通过协议注入到 AppState。

#### 3.2 Activity Row 完整性风险点（P2）

- 现状：completed 行在无 `time.completed` 时会退回到 assistant `time.created` 估算结束时间。
- 证据：`OpenCodeClient/OpenCodeClient/Views/Chat/ChatTabView.swift:138`、`OpenCodeClient/OpenCodeClient/Views/Chat/ChatTabView.swift:146`
- 风险：极端事件顺序下时长可能偏小或不稳定。
- 建议：优先以服务端 completed 时间为准；无 completed 时显示 “--:--” 或 `incomplete`，避免伪精确时长。

### 4) Test Coverage

#### 4.1 关键路径自动化不足（P2）

- 现状：已有模型/解析/SSH config 测试，但缺 activity row turn 计算与轮询策略回归测试。
- 证据：`OpenCodeClient/OpenCodeClientTests/OpenCodeClientTests.swift`
- 建议：
  - 抽离 turn activity 计算函数并单测（多 turn、retry、缺 completed）。
  - 给 polling 加 “上限/退避/停止条件” 的纯逻辑测试。

## Priority Backlog

1. **P0**：SSH host key 校验落地（TOFU/pin）。
2. **P1**：轮询降频 + 增量消息同步，降低发热与流量。
3. **P1**：继续拆分 AppState（先拆 ActivityTracker 与 PermissionController）。
4. **P2**：activity row 对缺 completed 的展示策略改为非伪精确。
5. **P2**：补 activity/polling 关键单测。

## Final Verdict

- 代码整体方向正确，近期 UX 修复有效。
- 真正需要尽快处理的是：**SSH 主机身份校验** 与 **busy 轮询负载**。
- 这两项处理完，远程使用的安全性和手机温度/续航会明显更稳。
