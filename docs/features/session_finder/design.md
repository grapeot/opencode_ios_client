# Session Finder 设计草案

## 结论

将其定位为现有 Sessions 入口内部的“智能查找”模式，而非新增独立的 Tab，亦非在已拉取的局部列表上做简单的标题模糊过滤。

用户输入一句对历史会话的模糊记忆描述，系统返回 3–8 个携带原文证据的匹配候选。用户在预览确认目标后，一键切回原 Session 继续输入。在架构权衡上，搜索响应稍慢是可以接受的，但结果必须明确告知用户搜索范围、召回依据，以及该 Session 当前是否处于可继续交互的状态。

在原型阶段，优先利用临时的 OpenCode Utility Session 编排现有的 Markdown 归档与语义检索（semantic-search）；客户端仅负责消费标准稳定的结构化结果。待交互体验（UX）验证闭环后，再将 Utility Session 无缝替换为专职的 Search Bridge 服务，保持界面展示与结果数据契约完全不变。

## 成功标准

用户无需精确记忆会话标题、创建日期或所属 Project，仅凭模糊的记忆片段发起描述，即可在单次检索流程中完成三项核心诉求：

1. 获取少量高置信度的候选列表，无需在几十个历史标题中费力翻找。
2. 借助原文引用片段快速核对并锁定真正的目标 Session。
3. 清晰知晓该 Session 是支持直接无缝继续提问，还是仅保留了只读历史备份。

首期版本以 Top 5 候选列表中包含目标 Session 作为核心质量指标。搜索耗时作为次要考量，但检索全过程必须提供可信的阶段性进度反馈，严禁长时间仅展示空白 Spinner。

## 入口与主流程

### iPhone

完整保留 Chat 工具栏现有的 Sessions 切换按钮与屏幕左边缘滑动呼出手势。在展开的 Sessions 抽屉（Sheet）顶部新增系统搜索框，其占位提示语（placeholder）设为 `描述你记得的内容`。

当搜索框为空时，界面继续呈现原有的 Active / Archived 会话列表。当用户在键盘上点击 Search 触发检索后，系统平滑切入智能查找模式：

```text
Sessions
┌──────────────────────────────┐
│ 讨论过 iPad 中文输入提前发送  │
└──────────────────────────────┘

Searching conversations...
Checking indexed history and live sessions

Possible matches
┌──────────────────────────────┐
│ iOS composer input fix       │
│ opencode_ios_client · Jun 18 │
│ You: “中文输入法还在选字时...” │
│                       Preview │
└──────────────────────────────┘
```

点击任一候选卡片将进入详情预览页，绝不直接粗暴替换当前正在进行的 Chat。预览页面集中呈现：

- 命中消息上下文前后各一轮对话。
- 该 Session 最后停顿的一轮交互。
- 所属 Project、发生日期以及当前的可继续状态。
- 底部常驻固定的主操作按钮 `Continue in This Session`。

若该会话属于 OpenCode 的软归档 Session，主按钮文案相应调整为 `Restore and Continue`。用户点击确认后，调用既有的 `selectSession` 逻辑，关闭抽屉并切回 Chat 主界面同时聚焦输入框；不自动触发语音录制，亦不自动提交消息。

常规 Sessions 列表依然维持“点击即切换”的直接交互。额外的二次确认机制仅作用于带有概率属性的语义搜索结果，不会增加日常会话切换的摩擦。

### iPad

搜索框常驻于 Sessions 侧边栏左栏顶部。左栏仅展示紧凑型候选列表；当用户点选某一候选后，中栏视图临时由 Files 切换为 Session Preview 预览，右栏则始终保留用户当前正在交互的 Chat 界面。只有当用户在预览中明确点击 `Continue in This Session` 时，右栏的活跃会话才会正式发生切换。

在 Compact 紧凑宽度模式下的 iPad 自动沿用 iPhone 的抽屉交互逻辑，不生硬依赖设备型号强制分栏。

## 搜索范围

默认检索范围严格界定为：当前连接的 Host、覆盖所有关联 Project、且包含处于 OpenCode 软归档状态的 Session。

默认不支持跨 Host 检索。不同 Host 对应着独立的连接通道、认证凭证与 Session 命名空间；若将不同 Host 的结果混杂在一起，极易造成“搜出了匹配项但在当前环境无法打开”的假成功陷阱。搜索框正下方展示一行低视觉干扰的 Scope 范围说明，例如：

```text
Home Mac · All Projects · Includes Archived
```

当检索命中的 Session 属于其他 Project 时，用户确认继续后，客户端将自动把当前 Project 切换至该 Session 对应的 `directory`，确保 Sessions、Files 与 Chat 视图时刻处于统一的 Workspace 上下文之中。

在设计上必须清晰界定两种不同属性的 Archive：

- OpenCode 软归档：数据依然完整保留在服务端的 Main DB 中，支持即时恢复并继续交互。
- 离线历史归档：数据已被迁移至独立的 Archive DB 或仅以 Markdown 文本形式留存，当前运行的服务端无法对其执行追加操作。

在用户界面上切忌将二者混为一谈统称为 Archived。对于离线历史，统一标记为 `Read-only copy`，避免与系统既有的 Archive/Restore 状态造成心智混淆。

## 候选卡

候选卡片仅展示辅助用户识别与决策的关键信息：

- Session 标题，最多渲染两行。
- Project 简短名称，省略冗长的绝对路径。
- 绝对发生日期；针对久远的历史会话，仅展示相对时间不足以建立清晰的时间锚点。
- 2–3 行关键命中原文摘录，并显式标注角色为 `You` 还是 `Assistant`。
- 特殊状态标签：`Archived`、`Read-only copy`、`Child session`；常规的 Idle 状态不作冗余展示。
- 可选的一行状态提示 `Last stopped at`，用于帮助用户分辨“仅仅命中了早期的相关讨论”还是“适合直接从结尾接续上下文”。

界面坚决不展示如 0.83 等抽象的相似度数值。此类打分对用户缺乏明确的操作指导意义，反而容易制造伪精确的认知误导。AI 生成的提炼摘要只能作为辅助参考，绝不能替代真实的原文引用证据。

检索结果统一按 Session 维度聚合呈现，不按切片（Chunk）散乱罗列。当多个 Chunk 命中同一个 Session 时，优先保留辨识度最高的一段原文，并将多点命中作为内部提升排名的置信度信号。当命中子会话（Child Session）时，默认优先归纳到父 Session 维度展示，并标注命中来源为 Child，防止单一复杂工作流的碎片霸占候选列表。

## 搜索与排序

V0 阶段核心需要的是语义检索能力（semantic retrieval），暂不需要引入高开销的生成式 LLM 重排序（rerank）。

推荐的轻量排序流水线设计：

1. 从现有的 Markdown 语义索引库中召回 Top 20–30 个候选 Chunks。
2. 补充从 Live DB 中检索出的会话标题精确匹配项及最近活跃 Session。
3. 按照 `(host namespace, session_id)` 元组进行去重与 Session 维度聚合。
4. 综合以最高语义相似度得分、多切片重复命中数以及关键词精确命中为主排序权重，时间衰减（recency）仅作为弱修正因子。
5. 校验候选 Session 当前归属于 Main DB、Archive DB 还是仅存 Markdown 文件。
6. 最终输出 Top 5 候选，在整体置信度偏低时最多动态放宽至 8 个。

仅当后续离线评测数据明确证明混合检索（Hybrid Retrieval）给出的 Top-3/Top-5 准确率不足时，才考虑对前 20 个候选引入专职 Reranker 模型。且 Reranker 必须支持超时自动降级机制，绝不能成为阻塞首屏渲染的强依赖，更严禁对召回的原文片段进行篡改。

## V0 执行架构

### 为什么先用 utility session

现有 OpenCode 服务端的 `search` 接口仅能按 Session Title 进行字面过滤；而 iOS 客户端内存中仅维护一个逐步向前加载的局部窗口。两者的现状均无法真正支撑起全量历史内容的深度搜索。与此相对，Workspace 环境下已经具备了每日导出的 Markdown 归档、命令行语义检索工具（semantic-search CLI）以及具备工具调用能力的 OpenCode Agent。

因此，原型阶段可设计如下轻量执行链路：

```text
iOS query
  -> create ephemeral utility session
  -> structured prompt calls semantic-search and checks DB availability
  -> JSON result
  -> delete utility session after successful parsing
  -> render candidates
```

Utility Session 强制采用 JSON Schema 约束其输出格式。客户端严禁通过解析模型自由文本来猜测提取 Session ID。当流程异常失败时，保留该 Utility Session 用于排查诊断；下一次发起检索时统一新建干净会话，避免历史多轮上下文干扰排序精度。

该方案的核心优势在于客户端改动极小，能以最低成本快速验证用户使用自然语言检索旧会话的真实频次与价值。其代价是端到端延迟稍高、每次搜索会消耗一次 Agent 交互轮次，且依赖服务端所在的 Workspace 具备访问 Session 归档与语义检索工具的权限。

### 稳定结果 contract

```json
{
  "query": "讨论过 iPad 中文输入提前发送",
  "scope": {
    "host_namespace": "current-host",
    "projects": "all",
    "indexed_through": "2026-07-15T04:00:00-07:00"
  },
  "results": [
    {
      "source": "opencode",
      "host_namespace": "current-host",
      "session_id": "ses_example",
      "title": "iOS composer input fix",
      "project_directory": "/workspace/project",
      "updated_at": 1784102400000,
      "matched_message_id": "msg_example",
      "matched_role": "user",
      "excerpt": "中文输入法还在选字时...",
      "availability": "live",
      "is_soft_archived": false,
      "parent_session_id": null
    }
  ]
}
```

`availability` 字段至少支持以下枚举状态：

- `live`：当前服务端可直接加载并支持消息追加。
- `offline_db`：存在于离线的 Archive DB 中，V0 阶段仅支持只读查看。
- `markdown_only`：仅留存有导出的 Markdown 文本，V0 阶段仅支持只读查看。
- `missing`：索引命中但底层原始数据已无法解析定位，不作为正常候选卡片渲染。

在数据模型设计上，唯一主键绝不能仅依赖 `session_id`，而必须由 `(source, host_namespace, session_id)` 三元组复合构成。否则后续接入多 Host 或异构 Session 源时，将直接丧失全局唯一定位能力。

### 正式 bridge

在完成 UX 闭环验证后，可将 Utility Session 平滑演进为专职的 Companion Search 端点：

```http
GET /session-search?q=...&host=...&project=all&limit=5
GET /session-search/opencode/{session_id}/preview
```

Bridge 服务端统一接管索引构建、DB 可用性解析（availability resolve）以及 Preview 渲染，iOS 客户端的数据契约保持零改动。严禁让移动端直接越级访问服务端的 SQLite 数据库文件、Markdown 绝对物理路径或底层 Embedding 缓存。

## 加载、弱匹配与失败

搜索操作必须由用户显式触发提交，绝不应在用户每次按键输入时都触发昂贵的语义查询。

- 400ms 内完成响应：直接平滑呈现搜索结果，不闪烁加载动画。
- 耗时超过 400ms：展示 `Searching conversations...` 状态。
- 耗时超过 2s：追加提示文案 `Checking older indexed sessions...`。
- 用户修改描述并重新提交：保留上一次的结果列表但降低其视觉透明度，同时展示刷新状态，避免界面频繁闪烁空白。

当命中置信度较低（弱匹配）时展示友好提示：

```text
No strong match found. These sessions may be related.
```

对于真正的零结果场景，界面必须明确说明检索的 Host 范围与索引时间水位，并提供三条清晰的兜底出口：修改搜索描述、按时间倒序翻阅全部 Sessions、或切换至其他 Host。对于网络异常、索引尚未就绪与检索无结果三类场景必须严格区分状态呈现，不能笼统使用一句 `No results` 掩盖问题。

## 直接继续与只读历史

V0 阶段的核心目标是辅助用户快速找回会话并继续对话，因此 `live` 状态的结果始终享有最高展示优先级。`offline_db` 与 `markdown_only` 状态的结果则归纳到独立的 `Older read-only matches` 区域展示，仅允许用户查阅历史，界面上不提供易引起误解的 Continue 操作入口。

若后续需要支持将离线归档的会话重新唤醒，必须建立明确的 `Restore to OpenCode` 数据流转规范：将完整的 Session Subtree、关联 Messages 与 Parts 数据从 Archive DB 完整校验并写回 Main DB，确认无误后方可允许继续追加。目前底层数据工具链仅具备 Main -> Archive 单向的安全迁移流程（plan/apply），尚未提供现成的反向恢复命令；且在 OpenCode 活跃运行并写入 DB 的过程中进行底层文件覆写极易引发数据损坏。因此该能力暂不纳入首期原型范围。

## 不采用的方案

- 不做“仅过滤当前客户端已加载的会话标题”。由于列表初始仅拉取局部的有限窗口，此类 UI 极易给用户造成“已在全量历史中完成搜索”的错误假象。
- 不由 AI 自动打开唯一命中的会话。历史会话检索天然带有歧义性，必须交由用户查看原文证据后自主确认。
- 不在用户点击搜索候选后立即静默替换当前 Chat。检索本身属于概率性决策，而当前的活跃会话属于宝贵的持久化工作上下文。
- 不在每次发起搜索前全量重新导出全部会话。优先复用每日定时构建的语义索引；仅在索引明显滞后时提供手动的显式刷新入口。
- 不让 iOS 客户端直接读取服务端的 SQLite 或 Markdown 文件。移动端严格依托标准化的 Search 与 Preview 数据契约进行通信。

## 现有代码接点

- iPhone Sessions sheet 和点击切换：`OpenCodeClient/OpenCodeClient/Views/SessionListView.swift:25-135`。
- iPad Sessions 左栏：`OpenCodeClient/OpenCodeClient/ContentView.swift:890-1042`。
- 现有 session 切换及消息加载：`OpenCodeClient/OpenCodeClient/AppState+Sessions.swift:221-257`。
- 当前 session list 只按 directory + limit 请求：`OpenCodeClient/OpenCodeClient/Services/APIClient.swift:99-112`。
- `Session` 当前没有 excerpt 或 availability：`OpenCodeClient/OpenCodeClient/Models/Session.swift:8-40`。
- 现有设计已经明确拒绝把本地 title filter 画成搜索：`docs/design.md:209-217`、`docs/OpenCode_iOS_Client_RFC.md:526-537`。

## 原型范围

首期原型严格聚焦于 iPhone 端，并收敛以下功能边界：

1. 检索范围限定为当前 Host、包含全部关联 Project、且覆盖软归档会话。
2. 仅支持显式提交自然语言 Query 发起检索。
3. 返回 Top 5 候选列表，并呈现对应的原文摘录片段。
4. 交互上支持 Preview 后确认继续；软归档会话先执行 Restore 唤醒再继续对话。
5. 离线 DB 与 Markdown 归档结果仅支持纯文本只读浏览。
6. 基于 Utility Session 与结构化 JSON Schema 实现，暂不引入 LLM Rerank。

本原型验证的核心不在于 Semantic-Search 底层技术选型的终极形态，而在于验证“描述模糊记忆 -> 查验原文证据 -> 一键接续原会话”这一交互闭环，能否真正显著降低用户找回并复用历史会话的心智负担。
