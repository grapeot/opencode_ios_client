# Localization 调研与规划（iOS Client）

最后更新：2026-02-15

## 背景

当前 iOS 客户端处于中英文混用的状态：核心导航栏（Chat/Files/Settings）以英文为主，但大量按钮、提示信息与错误文案依然硬编码为中文。例如 Settings 面板中的“关闭”按钮就是这种局部混用问题的典型体现。

本文档的目标并非立即发起全量一次性重构，而是制定一条可落地、低风险且支持渐进式迭代的本地化实施路径。

## 现状结论

- UI 交互文案目前主要通过 SwiftUI 的 `Text("...")` 与 `Button("...")` 方式直接硬编码。
- 工程内部尚未建立起规范的 `Localizable.strings` 或 String Catalog（`.xcstrings`）资源管理体系。
- 缺少统一的国际化（i18n）抽象封装层（如 `L10n.xxx` 工具），导致界面文案难以进行自动化的一致性校验。
- 最终给用户带来的体验断层为：在英文系统语言下会突兀出现中文按钮，而在中文系统环境下又频繁夹杂英文提示。

## 复杂度评估

若将目标设定为“英文系统展示英文、中文系统展示中文”，从技术实现维度并不存在架构难题，本质上属于中等规模的代码治理任务。其主要工作量集中在零散文案的梳理清洗与批量替换，不涉及底层核心架构改造。

- **快速可用版（预计 1–2 天）**：优先覆盖高频主流程入口（Settings、Chat 核心交互、错误弹窗），可立竿见影地消除最明显的语言混杂感。
- **完整稳定版（预计 3–6 天）**：全面覆盖所有 UI 视图、错误提示文案，并补齐单元测试与 UI 自动化回归用例，形成长效可维护的本地化工程规范。

## 推荐实施方案

1. 搭建本地化基础设施
   - 优先采用 Xcode String Catalog（推荐）或标准的 `Localizable.strings` 文件管理。
   - 至少初始化创建 `en`（英文）与 `zh-Hans`（简体中文）两套语言资源包。
   - 确立统一规范的 Key 命名层级，例如 `settings.close`、`ssh.status.connected`。

2. 封装轻量访问工具层
   - 新增 `L10n` 辅助类型（Enum 或 Struct 封装），避免在 View 视图层直接硬编码裸字符串 Key。
   - 统一参数化插值模板规范，避免散乱的字符串动态拼接。

3. 分阶段推进迁移
   - P1：覆盖 Settings 页面与网络连接全链路（用户敏感度最高的配置路径）。
   - P2：覆盖 Chat 会话流、Session 列表管理与 Files 文件浏览。
   - P3：覆盖各类错误提示、调试信息与边缘冷门页面。

4. 建立验证与防回归机制
   - 在 Xcode Scheme 中分别切换 English 与 Chinese 运行环境进行双语验证。
   - 针对核心主页面引入 UI 快照测试或最小冒烟回归用例，杜绝后续迭代中混用问题再次滋生。

## 本次建议（短平快）

建议优先完成一轮轻量的 UX 修复：将 Settings 面板左上角的“关闭”文案替换为右上角的 `Close`，确保当前以英文为主的界面视觉不被孤立的中文单点打断。随后再依照上述分批规划，稳步推进全量本地化改造。

## 风险与注意事项

- 切忌仅关注静态 UI 文案的翻译：业务错误信息中大量包含服务端动态返回的文本，需预先明确“服务端原样透传”与“本地模板化映射”的治理边界。
- 文案 Key 的命名规范必须及早冻结固化，防止多人协同开发时产生命名混乱与冗余定义。
- 在推进本地化替换的同时，应顺手清理各处历史遗留的硬编码裸字符串，建立防回流机制。

## RFC（追加）：V1 一次覆盖 P1/P2/P3 的分期实施计划

> 背景 feedback：V1 可以做完 P1/P2/P3，但要有分期；“透传 error message 策略”是低优先级，不作为本轮交付目标。

### 1) 先修正对现状的判断（基于 repo 通读）

结合对当前代码仓库的全面通读，当前项目并不是“缺乏 i18n 基础设施”，而是“**基础设施已有雏形，但全局接入尚未闭环**”：

- 代码中已内置 `OpenCodeClient/OpenCodeClient/Support/L10n.swift`，且包含 `en/zh` 双语字典与 Key 枚举。
- 但各处视图组件内部依然普遍存在硬编码字符串（导致中英混杂），主要集中在以下文件：
  - `OpenCodeClient/OpenCodeClient/ContentView.swift`
  - `OpenCodeClient/OpenCodeClient/Views/SettingsTabView.swift`
  - `OpenCodeClient/OpenCodeClient/Views/Chat/ChatTabView.swift`
  - `OpenCodeClient/OpenCodeClient/Views/SessionListView.swift`
  - `OpenCodeClient/OpenCodeClient/Views/Chat/ToolPartView.swift`
  - `OpenCodeClient/OpenCodeClient/Views/Chat/PatchPartView.swift`
  - `OpenCodeClient/OpenCodeClient/Views/Chat/ContextUsageView.swift`
  - `OpenCodeClient/OpenCodeClient/ContentView.swift`（侧边栏部分，原 `SplitSidebarView.swift` 逻辑已合入）
  - `OpenCodeClient/OpenCodeClient/Views/FilesTabView.swift`
  - `OpenCodeClient/OpenCodeClient/Views/Chat/PermissionCardView.swift`
- 错误信息的处理链路上目前处于多种模式并存的状态：
  - 存在模板化本地化实现（基于 `AppError` + `L10n.errorMessage(...)`）
  - 亦存在直接读取 `error.localizedDescription` 的逻辑（散落在 `AppState` 多处）
  - Assistant 消息体内的 `error.data.message` 则是直接透传展示（通过 `Message.errorMessageForDisplay`）

技术选型结论：V1 阶段的最优演进路径是**继续沿用并完善现有的 `L10n.swift` 架构，完成全量视图的接线替换**，本轮暂不引入切换到 `.xcstrings` 的迁移成本。

### 2) V1 目标与非目标

**V1 目标（本轮必须完成）**

- 全面覆盖 P1/P2/P3 涉及的所有 UI 交互文案，确保系统切换语言后界面呈现严格一致。
- 彻底消除“同一屏幕内中英文夹杂”以及“核心操作流程中语言突兀跳变”的体验断层。
- 建立长效工程规范：新增 UI 文案必须走 `L10n` Key，严禁裸字符串直接流入视图层。

**V1 非目标（明确不做）**

- 本轮不对“服务端错误文案透传策略”进行深度重构或策略分层。
- 暂不将 `L10n.swift` 迁移至 Xcode String Catalog 体系（留作后续 V1.1+ 的优化项）。
- 不调整或修改服务端返回的既有错误数据结构。

### 3) 分期方案（同一个 V1 内的里程碑）

#### M1（P1）— Settings + 连接链路（高感知）

目标：优先收敛用户最常用、且最容易暴露语言混杂的配置与连接模块。

主要改动文件列表：

- `OpenCodeClient/OpenCodeClient/Views/SettingsTabView.swift`
- `OpenCodeClient/OpenCodeClient/ContentView.swift`（Settings 与文件预览面板的 Close 等入口）
- `OpenCodeClient/OpenCodeClient/AppState.swift`（连接链路中的各项静态提示文案）

核心改动内容：

- 将所有 Section 标题、配置字段名称、按钮与 Alert 提示统一接入 `L10n.t(...)`。
- 规范并统一面板与弹窗中 “Close/关闭/Done/确定/取消” 的 Key 引用。
- 将 `schemeHelpText(...)` 中的两条帮助说明重构为 `L10n.helpForURLScheme(...)`，消除重复的硬编码。
- 补齐 `L10n.Key` 中缺失的枚举项（例如 Public Key Error、Copy Command、Command Copied、Theme、Untrusted、Rotate 等）。

验收标准：

- 在 English 与中文两种运行环境下，Settings 页面均不出现反向的单点语言孤岛。
- SSH 与 AI Builder 相关弹窗及操作按钮保持语言一致。

#### M2（P2）— Chat + Session + Files 主流程

目标：全面覆盖用户日常交互频次最高的主流路径，消除会话期间的认知打断。

主要改动文件列表：

- `OpenCodeClient/OpenCodeClient/Views/Chat/ChatTabView.swift`
- `OpenCodeClient/OpenCodeClient/Views/SessionListView.swift`
- `OpenCodeClient/OpenCodeClient/Views/FilesTabView.swift`
- `OpenCodeClient/OpenCodeClient/ContentView.swift`（Preview 预览空状态视图）

核心改动内容：

- 将 Chat 模块的 Alert 弹窗、导航标题、输入框 Placeholder、空状态文案及语音预检提示全部替换为 `L10n`。
- 将 Session 列表标题、空状态及会话状态描述（busy/retry/idle）统一接入 `L10n`。
- 将 `RelativeDateTimeFormatter` 的语言环境由写死的 `zh_Hans` 重构为跟随系统的 `Locale.current`。
- 将 Files 树、Workspace 提示、搜索 Prompt 与文件预览相关的硬编码文案全面接入 `L10n`。

验收标准：

- 从 Chat 提问到 Session 列表切换、再到 Files 浏览与文件预览，全流程无中英文混杂。
- 相对时间描述（如“5分钟前”）准确跟随系统语言动态本地化。

#### M3（P3）— Tool/Patch/Context/Permission + 活动状态文案收尾

目标：系统性治理高曝光但处于边缘的卡片组件，实现全局视觉风格与术语的一致性。

主要改动文件列表：

- `OpenCodeClient/OpenCodeClient/Views/Chat/ToolPartView.swift`
- `OpenCodeClient/OpenCodeClient/Views/Chat/PatchPartView.swift`
- `OpenCodeClient/OpenCodeClient/Views/Chat/ContextUsageView.swift`
- `OpenCodeClient/OpenCodeClient/Views/Chat/PermissionCardView.swift`
- `OpenCodeClient/OpenCodeClient/Controllers/ActivityTracker.swift`
- `OpenCodeClient/OpenCodeClient/Views/Chat/ChatTabView.swift`（Completed/Busy/Retrying/Idle 状态文案）

核心改动内容：

- Tool 与 Patch 卡片中的 “Reason/Command/Input/Output/Open in File Tree/选择文件” 等全部接入标准化 Key。
- 将 Context 详情面板的 Section 标题、数据 Label、Loading 加载态与 Empty 空状态文案全部完成 Key 化。
- 将 Permission 授权卡片的按钮文案与标题统一 Key 化。
- 为 ActivityTracker 的状态映射文案（Thinking/Planning/Running commands 等）引入 `L10n` Key，消除运行时硬编码的英文文案。

验收标准：

- Tool、Patch、Context 以及 Permission 卡片在两种语言环境下均保持专业术语对齐。
- Activity 状态行的动态文案在中英文环境下排版工整且无夹杂。

### 4) 低优先级项（本轮显式 postpone）

- “服务端错误文案透传策略”明确延后至后续专项治理（如 V1.1 或 V2 阶段），本轮不增加额外的策略转换层。
- 维持现状，继续允许 `error.localizedDescription` 与服务端原生的 `error.data.message` 原样输出；本轮重点保障客户端 UI 框架层文案的本地化，不改写错误信息的语义来源。

### 5) 质量门槛（Definition of Done）

- 代码规范：
  - 所有新增与修改的 UI 文案严禁出现裸字符串（产品品牌名、模型 ID 与协议底层常量除外）。
  - `L10n.Key` 命名严格遵循 `domain.actionOrNoun` 规范（例如 `settings.copyCommand`）。
- 测试保障：
  - 增加基础单元测试：校验 `L10n` 中的核心 Key 在 `en` 与 `zh` 字典中均存在对应映射（通过双向集合对齐断言保障）。
  - 覆盖关键流程的冒烟验证：Settings 页面、Chat Alert 弹窗、Session 空态、Tool/Patch 卡片弹窗与 Context 详情面板。
- 回归标准：
  - 完成至少两轮端到端人工走查（分别在 English 与中文系统语言下执行）。
  - 严禁出现已修复混用问题的再次回归（如 Close 与“关闭”混用）。

### 6) 实施顺序与工时预估

- Day 1：推进 M1 里程碑（Settings + 连接链路）并完成自测。
- Day 2：推进 M2 里程碑（Chat / Session / Files 主流程）并完成自测。
- Day 3：推进 M3 里程碑（Tool / Patch / Context / Permission / Activity 状态收尾）并执行全量回归验收。

总结：**V1 整体一次性完整交付 P1/P2/P3 的全量改造，但在执行节奏上严格依照 M1 → M2 → M3 分期推进，确保每个阶段均具备明确的可验收里程碑**。
