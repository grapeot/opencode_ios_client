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
- 建议：采用 **TOFU**（Trust On First Use）策略作为默认方案。
  - 首次连接时：展示服务器 fingerprint，用户确认后写入本地信任存储。
  - 后续连接时：强制比对 fingerprint；不一致直接阻断并给出明确告警。
  - 提供「重置信任并重新配对」入口，支持服务器重装/换机。
  - 文档与 UI 文案统一用“首次信任、后续强校验”的心智模型。

#### 1.2 Basic Auth + HTTP（LAN）默认可用（P2）

- 现状：API 层支持 Basic Auth；地址可为 `http://`（LAN 允许）。
- 证据：`OpenCodeClient/OpenCodeClient/Services/APIClient.swift:59`、`OpenCodeClient/OpenCodeClient/AppState.swift:69`
- 风险：同网段被动抓包即可看到凭证。
- 建议：保留 LAN 例外，但 UI 上增加更强警示与“一键改 https”引导；文档明确“公网必须 https，LAN 也建议 https”。

### 2) Performance / Heat

#### 2.1 Busy 轮询策略偏重（P1）

- 现状：busy 场景每 2 秒轮询一次，最多 90 次，并每轮调用 `loadMessages()`。
- 证据：`OpenCodeClient/OpenCodeClient/AppState.swift:834`、`OpenCodeClient/OpenCodeClient/AppState.swift:858`
- 背景：目标应调整为 **SSE 主通道 + 首次全量同步一次**，而非持续轮询。
  - App 进入会话/重连后，先做一次全量 `loadMessages()` + `GET /permission`，用于补齐可能错过的事件。
  - 首次同步完成后，常态只依赖 SSE 推送，不再做 2 秒周期轮询。
  - permission 场景可由这次首次全量/权限拉取覆盖，无需额外持续轮询。
- 风险：会话长、消息多时，反复全量解码 + UI 重组，容易带来电量与温度压力。
- 建议：
  - 移除 busy 期间周期轮询；保留“进入会话/重连时仅一次”的全量补偿同步。
  - 保留手动下拉刷新作为用户可控兜底。
  - 若后续实测仍有漏事件，再引入“有条件、低频、短窗口”的增量补偿，而不是常驻轮询。

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
2. **P1**：SSE 主通道化：改为“首次全量同步一次”，移除 busy 常驻轮询。
3. **P1**：继续拆分 AppState（先拆 ActivityTracker 与 PermissionController）。
4. **P2**：activity row 对缺 completed 的展示策略改为非伪精确。
5. **P2**：补 activity/polling 关键单测。

## Iteration Plan（SSE 主通道）

### Iteration 1 - 行为收敛（低风险）

- 进入 session、SSE 重连成功后：执行一次 `loadMessages()` + `refreshPendingPermissions()`。
- 删除/禁用 `startPollingCurrentSession(forBusySession:)` 的周期调度路径。
- 保留用户手动刷新入口，作为显式兜底。

### Iteration 2 - 观测与验证

- 增加轻量日志：记录“首次同步触发点、耗时、消息数量、权限数量”。
- 在真实网络抖动与前后台切换场景回归：确认 permission 卡片与 activity 行不丢。
- 对比改造前后：CPU 时间、网络请求数、设备温升趋势。

### Iteration 3 - 条件化补偿（仅在必要时）

- 仅当监控证实存在漏事件，再增加“短窗口、低频、可停机”的增量补偿。
- 增量同步必须带停止条件，避免再次演化为常驻轮询。

## Refactor Plan（AppState 拆分，Test First）

> 说明：这里的迭代方案专指 AppState 重构执行方案，不是整体 backlog 的执行顺序。

### 目标与原则

- 目标：把 `AppState` 中“运行时编排逻辑”拆到独立组件（如 `SessionRuntimeCoordinator`、`ActivityTracker`、`PermissionController`），同时保持现有 UI 行为不变。
- 原则：每一轮重构都先补测试，再改结构；没有测试护栏不做下一步。

### Iteration A - 建立测试基线（先测后拆）

- 新增 `AppState` 行为级测试（黑盒）：
  - session 切换后消息清理与加载顺序。
  - SSE 到达后的状态合并优先级（SSE 不被旧轮询覆盖）。
  - permission 丢事件时，首次 `GET /permission` 能补齐卡片。
  - activity row 逐 turn 规则（running/completed、时长来源）
- 引入可注入测试替身（API/SSE 协议化），避免依赖真实网络。
- **Gate**：上述关键路径测试全部稳定通过后，才进入组件拆分。

### Iteration B - 拆 PermissionController（低耦合先行）

- 把 permission 相关状态机与补偿同步逻辑从 `AppState` 抽离。
- 保持外部接口不变（`pendingPermissions`、respond flow）。
- 测试新增：
  - permission.asked 各 payload 形态解析一致性。
  - once/always/reject 回写与 UI 状态收敛。
  - 首次补偿同步仅触发一次，不产生重复卡片。
- **Gate**：本轮新增 + 原有回归测试全绿。

### Iteration C - 拆 ActivityTracker（中等耦合）

- 抽离 activity label 推导、2.5s debounce、per-turn 计时计算。
- 测试新增：
  - reasoning/tool/text 映射一致性。
  - debounce 行为（避免标签抖动）。
  - completed 时长优先级（completed > fallback）与边界场景。
- **Gate**：activity 相关 snapshot/行为测试全绿，且无 UI flapping 回归。

### Iteration D - 拆 SessionRuntimeCoordinator（高耦合最后做）

- 负责 SSE 生命周期、首次全量同步、session status 合并策略。
- 测试新增：
  - 前后台切换后重连与首次同步触发点。
  - 重连期间事件顺序错位时的一致性。
  - 无常驻轮询下的最终一致性（手动刷新兜底仍可用）。
- **Gate**：端到端回归（消息流、权限、activity）全部通过。

### Test Plan（覆盖与验收）

- 覆盖目标：
  - 关键状态机/编排逻辑行覆盖率 `>= 80%`。
  - permission/activity/runtime 三块新增代码分支覆盖 `>= 70%`。
- 测试层次：
  - Unit：纯逻辑（映射、去抖、状态转移、时间计算）。
  - Integration：`AppState + fake API/SSE` 的异步事件流。
  - UI 回归：最小关键路径（permission 卡片可见性、activity row 末行保留）。
- 执行门禁：
  - 每轮必须跑 `xcodebuild test ... -parallel-testing-enabled NO`。
  - 失败禁止进入下一轮重构。
  - 每轮在 `docs/WORKING.md` 记录“测试新增点 + 风险结论”。

## Final Verdict

- 代码整体方向正确，近期 UX 修复有效。
- 真正需要尽快处理的是：**SSH 主机身份校验** 与 **busy 轮询负载**。
- 这两项处理完，远程使用的安全性和手机温度/续航会明显更稳。
