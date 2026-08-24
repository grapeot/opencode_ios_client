# Localization 调研与规划（iOS Client）

最后更新：2026-02-15

## 背景

当前应用是中英文混用状态：核心导航（Chat/Files/Settings）偏英文，但大量按钮、提示、错误文案仍是中文硬编码。你提到的 Settings sheet 里的“关闭”就是这个混用问题的典型表现。

本文件目标不是立刻全量改造，而是给出一条可执行、低风险、可迭代的本地化路径。

## 现状结论

- UI 文案目前主要是 SwiftUI `Text("...")` / `Button("...")` 直接硬编码。
- 项目里尚未建立 `Localizable.strings` / `String Catalog (.xcstrings)` 体系。
- 没有统一 i18n 包装层（例如 `L10n.xxx`），所以文案难做一致性检查。
- 结果是：英文系统下会出现中文按钮，中文系统下也会出现英文提示。

## 复杂度评估

如果目标是“英文系统显示英文、中文系统显示中文”，技术上不难，属于中等规模治理任务，主要工作量在文案梳理和批量替换，不在底层架构。

- **快速可用版（1-2 天）**：优先覆盖高频入口（Settings、Chat 主流程、错误弹窗），可显著降低混用感。
- **完整稳定版（3-6 天）**：覆盖全 UI + 错误文案 + 单元/UI 回归，形成持续可维护的本地化机制。

## 推荐实施方案

1. 建立 i18n 基础设施
   - 使用 Xcode String Catalog（推荐）或 `Localizable.strings`。
   - 至少创建 `en`、`zh-Hans` 两套资源。
   - 统一 key 命名，如 `settings.close`, `ssh.status.connected`。

2. 引入轻量访问层
   - 新增 `L10n` 工具（enum/struct），让视图层尽量不直接写裸字符串 key。
   - 统一参数化文案格式，减少字符串拼接。

3. 分批迁移
   - P1：Settings 与连接链路（用户最敏感路径）。
   - P2：Chat、Session、Files。
   - P3：错误文案、调试提示、边角页。

4. 验证与回归
   - iOS Scheme 分别切换 English / Chinese 运行。
   - 对关键页面做 UI snapshot 或最小 smoke test，避免回归混用。

## 本次建议（短平快）

先做一轮 UX 修补：把 Settings sheet 的“关闭”改成右上角 `Close`，保证当前英文主界面不被中文单点打断。再按上面的分批计划推进全量本地化。

## 风险与注意事项

- 不能只翻译静态文案：错误信息里常有服务端返回文本，需定义“原样透传 vs 本地模板”策略。
- 文案 key 需要冻结命名规范，否则后续多人协作会很快失控。
- 本地化推进时建议顺手清理历史硬编码，避免旧字符串反复回流。

## RFC（追加）：V1 一次覆盖 P1/P2/P3 的分期实施计划

> 背景 feedback：V1 可以做完 P1/P2/P3，但要有分期；“透传 error message 策略”是低优先级，不作为本轮交付目标。

### 1) 先修正对现状的判断（基于 repo 通读）

当前仓库并不是“没有 i18n 基础设施”，而是“**基础设施已存在，但迁移未完成**”：

- 已有 `OpenCodeClient/OpenCodeClient/Support/L10n.swift`，包含 `en/zh` 双字典和 key 枚举。
- 仍有大量 UI 文案硬编码在视图里（中英混用），尤其集中在：
  - `OpenCodeClient/OpenCodeClient/ContentView.swift`
  - `OpenCodeClient/OpenCodeClient/Views/SettingsTabView.swift`
  - `OpenCodeClient/OpenCodeClient/Views/Chat/ChatTabView.swift`
  - `OpenCodeClient/OpenCodeClient/Views/SessionListView.swift`
  - `OpenCodeClient/OpenCodeClient/Views/Chat/ToolPartView.swift`
  - `OpenCodeClient/OpenCodeClient/Views/Chat/PatchPartView.swift`
  - `OpenCodeClient/OpenCodeClient/Views/Chat/ContextUsageView.swift`
  - `OpenCodeClient/OpenCodeClient/Views/SplitSidebarView.swift`
  - `OpenCodeClient/OpenCodeClient/Views/FilesTabView.swift`
  - `OpenCodeClient/OpenCodeClient/Views/Chat/PermissionCardView.swift`
- 错误相关路径目前是混合模式：
  - 有模板化本地化（`AppError` + `L10n.errorMessage(...)`）
  - 也有直接 `error.localizedDescription`（`AppState` 多处）
  - assistant 消息的 `error.data.message` 直接展示（`Message.errorMessageForDisplay`）

结论：V1 最优策略是**继续使用现有 `L10n.swift`，完成全量接线**，而不是在本轮切换到 `.xcstrings`。

### 2) V1 目标与非目标

**V1 目标（本轮必须完成）**

- 覆盖 P1/P2/P3 全部 UI 文案，做到系统语言切换后页面语言一致。
- 消除“同屏中英混用”与“关键流程突然中文/英文跳变”。
- 建立可持续约束：新增文案默认走 `L10n` key，不再允许裸字符串进入 UI。

**V1 非目标（明确不做）**

- 不在本轮定义或重构“服务端错误文案透传策略”。
- 不把 `L10n.swift` 迁移到 String Catalog（可作为 V1.1+ 优化项）。
- 不改动服务端返回错误结构。

### 3) 分期方案（同一个 V1 内的里程碑）

#### M1（P1）— Settings + 连接链路（高感知）

目标：先把最常用、最容易暴露混用的问题收敛掉。

主要改动文件：

- `OpenCodeClient/OpenCodeClient/Views/SettingsTabView.swift`
- `OpenCodeClient/OpenCodeClient/ContentView.swift`（settings/file preview sheet 的 Close 等）
- `OpenCodeClient/OpenCodeClient/AppState.swift`（连接链路中可替换的固定提示）

改动内容：

- 全部 Section 标题、字段名、按钮、alert 文案改为 `L10n.t(...)`。
- 统一 “Close/关闭/Done/确定/取消” 在 sheet/alert 里的 key 使用。
- `schemeHelpText(...)` 两条帮助文案改为 `L10n.helpForURLScheme(...)`，避免双份硬编码。
- 补齐 `L10n.Key` 缺失项（如 Public Key Error、Copy Command、Command Copied、Theme、Untrusted、Rotate 等）。

验收：

- English/中文 Scheme 下，Settings 页不出现反向语言孤岛。
- SSH/AI Builder 相关弹窗与按钮语言一致。

#### M2（P2）— Chat + Session + Files 主流程

目标：覆盖用户每天最高频路径，降低会话期间的认知打断。

主要改动文件：

- `OpenCodeClient/OpenCodeClient/Views/Chat/ChatTabView.swift`
- `OpenCodeClient/OpenCodeClient/Views/SessionListView.swift`
- `OpenCodeClient/OpenCodeClient/Views/SplitSidebarView.swift`
- `OpenCodeClient/OpenCodeClient/Views/FilesTabView.swift`
- `OpenCodeClient/OpenCodeClient/ContentView.swift`（Preview 空态）

改动内容：

- Chat 的 alert/title/placeholder/empty state/speech precheck 全改 `L10n`。
- Session 列表标题、空态、状态文案（busy/retry/idle）改 `L10n`。
- `RelativeDateTimeFormatter` 由固定 `zh_Hans` 改为 `Locale.current`。
- Files/Workspace/Search prompt/Preview 相关硬编码改 `L10n`。

验收：

- 从 Chat 到 Session 切换、再到 Files/Preview，全链路无中英混用。
- 时间相对描述跟随系统语言。

#### M3（P3）— Tool/Patch/Context/Permission + 活动状态文案收尾

目标：处理边角但高曝光组件，完成视觉与术语一致性。

主要改动文件：

- `OpenCodeClient/OpenCodeClient/Views/Chat/ToolPartView.swift`
- `OpenCodeClient/OpenCodeClient/Views/Chat/PatchPartView.swift`
- `OpenCodeClient/OpenCodeClient/Views/Chat/ContextUsageView.swift`
- `OpenCodeClient/OpenCodeClient/Views/Chat/PermissionCardView.swift`
- `OpenCodeClient/OpenCodeClient/Controllers/ActivityTracker.swift`
- `OpenCodeClient/OpenCodeClient/Views/Chat/ChatTabView.swift`（Completed/Busy/Retrying/Idle 文案）

改动内容：

- Tool/Patch 的 “Reason/Command/Input/Output/Open in File Tree/选择文件” 全部接入 key。
- Context sheet 的 section/label/loading/empty 文案全部 key 化。
- Permission 卡片按钮与标题 key 化。
- ActivityTracker 的状态映射文案（Thinking/Planning/Running commands 等）引入 `L10n` key，避免 runtime 英文写死。

验收：

- Tool/Patch/Context/Permission 卡片在两种语言下术语一致。
- Activity 行文案在中英环境都可读且不混杂。

### 4) 低优先级项（本轮显式 postpone）

- “服务端错误 message 透传策略”留到后续专题（例如 V1.1 或 V2），本轮不新增策略分层。
- 仍允许 `error.localizedDescription` 与服务端 `error.data.message` 原样显示；本轮只保证 UI 框架文案本地化，不重写错误语义来源。

### 5) 质量门槛（Definition of Done）

- 代码层：
  - 新增/修改 UI 文案不得出现裸字符串（品牌名、模型 ID、协议常量除外）。
  - `L10n.Key` 命名遵循 `domain.actionOrNoun`（如 `settings.copyCommand`）。
- 测试层：
  - 增加最小单测：`L10n` 关键 key 在 `en/zh` 均有值（可做 key 集合对齐断言）。
  - 关键流程 smoke：Settings、Chat alert、Session empty、Tool/Patch dialog、Context sheet。
- 回归层：
  - 至少两轮人工回归（English + 中文系统）。
  - 不允许出现已知混用回归（例如 Close/关闭混用）。

### 6) 实施顺序与工时预估

- Day 1：M1（Settings + Connection）+ 自测
- Day 2：M2（Chat/Session/Files）+ 自测
- Day 3：M3（Tool/Patch/Context/Permission/Activity）+ 回归 + 收尾

即：**V1 仍可一次性交付完整 P1/P2/P3，但内部按 M1→M2→M3 分期推进，保证每天都有可验收里程碑**。
