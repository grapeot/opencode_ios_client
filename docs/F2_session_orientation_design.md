# F2 · 会话辨识（Session Orientation）设计调研与提案

本文回应设计方向给出的 F2 brief。brief 的作者没有代码访问权限，所有关于"当前行为"的描述都是从截图和与维护者的对话里推断出来的假设。我的第一项工作就是把这些假设拿到源码里核对，确认哪些成立、哪些需要修正。下面先报告 grounding 结果，再给出会话状态模型、4b 的取舍建议，以及列表重做的几个具体方案。

调研基于对 `OpenCodeClient` 全部 66 个 Swift 文件、`docs/OpenCode_Web_API.md`，以及 `opencode-official/` 服务端源码的阅读，关键结论都附了 `文件:行号` 出处，我对 brief 里最关键的两条（blocked 信号、状态枚举）做了亲自复核。

---

## 一、对 brief §1–§3 假设的核对

总体上，brief 的方向判断是对的，但有几处事实需要修正，其中两处直接改变设计的可行性边界。

**修正一：blocked / "needs you" 信号已经存在，而且是纯客户端的。** 这是 brief 里标为最高价值、同时最担心可能需要服务端改动的一条。实际情况是，客户端已经在实时接收 `permission.asked` 和 `question.asked` 两类 SSE 事件，并各自维护 `pendingPermissions` 和 `pendingQuestions` 数组（`AppState+SSE.swift:122-135`）。每条 pending 项都带 `sessionID`（`AppState+SSE.swift:278`），所以"哪个会话在等我"这件事，客户端现在就能算出来，不依赖任何服务端新增能力。这条结论把 4a 里风险最高的"needs you"状态从"可能要改服务端"降级成"客户端组合已有数据"。

**修正二：会话已经有状态枚举，不只是一个 Running 圆点。** brief 推断会话只能靠一个小小的 Running 标签区分死活。源码里有完整的 `SessionStatus` 结构（`Models/Session.swift:39-44`），`type` 字段取值为 `idle` / `busy` / `retry`，另有 `attempt`、`message`，还有一个 `next: Int?`（下一次计划时间）。也就是说，4a 表格里的 Running 和 Done 两种状态，数据源现成；真正需要客户端去推导的只有 blocked 和 stale 两种。

**修正三：服务端的定时触发能力不存在，这条路要排除。** API 文档里没有任何 cron / 定时 / 延迟执行端点。服务端代码里 `SessionDelivery` 枚举确实定义了 `immediate` 和 `deferred` 两个值，但 `deferred` 只是声明，没有实现。HTTP handler 接收这个参数（`v2/session.ts:114-119`），可处理函数是空壳（`v2/session.ts:288-290`），没有任何代码分支真的按 `deferred` 走。git 历史里有过一个 scheduler 模块（commit `e2f1f4d81`），后来被移除，现在只存在于一个废弃分支上。结论是 4b 的选项 3（服务端定时重触发）目前没有落地基础，这印证了 brief 作者把它当成"另一场更大的服务端对话"的直觉。

**修正四：标题改造比预想的便宜。** brief 问"换成意图摘要的最便宜路径是什么"。会话创建时客户端传 `title: nil`（`AppState+Sessions.swift:229`），服务端回填了那串时间戳标题。而首条用户消息在消息加载后就在 `state.messages` 里，代码里已有提取首条用户消息文本的现成写法（`AppState+Messages.swift:45`）。所以最便宜的做法是消息加载完成后，本地取首条用户消息截断成一行覆盖显示，零服务端改动、零模型调用。需要时还有两个兜底：服务端有 `POST /session/:id/summarize` 端点（`OpenCode_Web_API.md:136`），以及用当前模型做一次廉价摘要。

**修正五：read / unread 今天完全没有，但补起来很轻。** 全代码库搜不到 unread / lastViewed / lastSeen / badge 任何痕迹，应用只跟踪 `session.time.updated` 和 `currentSessionID`。补一个 per-session last-viewed 大约 30 行，照着已有的 `AppState+Drafts` 那套 `[String: String]` 写进 UserDefaults 的模式来，在 `selectSession()`（`AppState+Sessions.swift:165-202`）里打一个时间戳即可，纯本地、无需服务端同步。

**修正六：本地通知能力为零。** 整个工程没有引入 UserNotifications 框架，Info.plist 里也没有任何通知相关键值，唯一的 NotificationCenter 用法是 `ContentView.swift:292-304` 的应用前后台生命周期，与用户通知无关。这意味着 4b 的选项 2（snooze + 本地通知）不是免费的：要新增框架引入、权限申请流程、调度服务、Info.plist 文案，工作量大致 2 到 3 天。

**brief 判断对了的部分：** 列表确实按 `time.updated` 降序排（`AppState.swift:585-612` 的 `buildSessionTree()`），live 和 long-dead 会话视觉权重几乎相同。每行靠 `isBusy` 给标题换色（`SessionListView.swift:234`），这正好是"状态→权重"要接入的那道缝：现有代码已经在这里按状态分叉 `foregroundStyle`，扩展它是顺势而为。列表是按 `parentID` 组织的可折叠树（支持会话 fork），任何重排方案都要兼顾这个层级。

---

## 二、确认后的会话状态模型

把 brief §4a 的五状态表对齐到 API 真实能提供的信号之后，得到下面这版。左边三列是状态定义，最后一列标注信号来源和它是现成的还是要推导的。

| 状态 | 含义 | 视觉意图 | 信号来源 |
|---|---|---|---|
| **Needs you（等你）** | 被 permission / question 阻塞 | 最强：accent、浮到顶部、一句动词文案（"等你回复"） | 现成。`pendingPermissions` / `pendingQuestions` 里有该 `sessionID` 即为此态 |
| **Running（运行中）** | 正在干活 | live 信号（细微 pulse）+ 已运行时长 | 现成。`SessionStatus.type == busy/retry` |
| **Done · unread（完成·未读）** | 已完成、还没看过 | 中等权重；未读点；一行结果（`+3 文件` / 测试通过数） | 状态现成（`type == idle`），未读需补 last-viewed；结果行可取 `session.summary` 的 additions/deletions/files |
| **Done · read（完成·已读）** | 已完成、已看过 | 后退 | `type == idle` 且 last-viewed 晚于 updated |
| **Stale（陈旧）** | 旧且久未动 | 最弱、置灰、留在时间流里 | 推导。`type == idle` 且 updated 早于某阈值（如 24 小时） |

几点说明。Needs you 之所以能成立，靠的是每条 pending 项都带 `sessionID`，客户端把它和会话列表做一次映射就行，这是整个 F2 里信息价值最高、实现成本却最低的一项，建议优先做。Done·unread 的"一行结果"不必现编：`Session.SummaryInfo` 已经带 `additions/deletions/files`（`Models/Session.swift:30-34`），对编码类会话可直接渲染成"+12 −3 · 4 文件"；研究类会话没有 diff，就回退到首条用户消息摘要或末条助手消息首行。

阻塞细分上还可以再进一步。`pendingPermissions` 和 `pendingQuestions` 是两类语义不同的阻塞：前者是"要你授权一个操作"，后者是"agent 在问你一个问题"。文案上可以分开，比如"等你授权"和"等你回答"，让用户在列表层面就知道点进去要做什么。这不增加数据成本，只是把现成区分用起来。

排序保持现有的按 `time.updated` 降序，不做状态分组重排。brief §4a 原本建议"先按状态、再按 recency"让需要注意的浮到顶部，但确定的方向（见第四章）是把辨识责任压到单行视觉编码上，靠色条、图标、明暗让 Needs you 在原位跳出来，而不是靠位置。这样排序逻辑不动，`buildSessionTree()` 的 comparator 保持现状，改动集中在行的渲染。状态只影响视觉权重，不影响位置。

---

## 三、4b（搁置与重访）的取舍建议

把四个选项对着 grounding 结论过一遍可行性，结论和 brief 作者的起始推荐基本一致，但我会把落地顺序排得更清楚。

**选项 1 · Pin / 星标。** 纯客户端，无时间维度。照 read-unread 那套 UserDefaults 模式存一个 pinned 集合即可，成本极低，半天以内。适合"把这个留在手边"，但回答不了"3 点钟回来看"。

**选项 2 · Snooze / boomerang 到指定时间。** 会话进入一个 Later 货架，到点用本地通知召回。无服务端依赖，UX 与意图最贴合。代价是本地通知能力当前为零，要从框架引入、权限申请、调度服务一路搭起来，约 2 到 3 天。还有一个 iOS 固有限制要写进预期：本地通知只在到点时提醒用户，它不会在应用关闭时让 agent 继续跑。"提醒我回来看"能做，"应用关着也让 agent 动起来"做不到。

**选项 3 · 服务端定时重触发。** 唯一能在应用关闭时真正重跑 agent 的方案，但服务端现在没有这个能力（见修正三）。归到一场单独的、更大的服务端讨论里，F2 不依赖它。

**选项 4 · read / unread + revisit 标记。** 一个轻量底座，约 30 行。它本身价值不大，但它是 4a 里 Done·unread 状态的前置条件，也是上面几个选项共用的基础设施。换句话说，做 4a 的时候其实已经顺手把它做了。

**建议：`4 + 1` 先行，`2` 紧随。** 具体地说，read-unread 底座（选项 4）跟着 4a 一起落地，因为 4a 本来就要它；Pin（选项 1）作为一个近乎零成本的添头一并做掉，先满足"留在手边"这个高频小需求。Snooze（选项 2）单独作为第二批，因为它是这里唯一需要新建一整套本地通知基础设施的功能，把它隔离开能让第一批保持纯客户端、低风险、可快速验证。选项 3 明确划到客户端范围之外。

这个排序和 brief 作者的起始推荐（`2 + 4`，`1` 作添头）方向一致，差别只在我把 `2` 往后挪了一批。理由是它的本地通知成本是其余几项的数倍，不该拖住可以立刻上线的状态分层。

IA 上给搁置项一个轻量的 Later 标记。既然列表不分组、不折叠，搁置的会话也留在时间流里，用一个行内小标签（如"Later"）标注它是用户主动 park 的，区别于系统判断的 Stale。Stale 是越旧越淡的明暗退场，Later 是用户显式搁置的状态标记，两者语义不同但都不离开时间流。snooze 到点后该会话靠本地通知召回，并清掉 Later 标记。

---

## 四、列表重做方案：单行视觉编码（简化版 C）

方向已定，走简化版 C。原方案 C 的核心想法是"把需要注意的会话最强化"，但它靠的是顶部吸顶悬浮区，会引入一套新的布局逻辑、占纵向空间、并行多时还要设上限。简化的做法是去掉吸顶，回到单一列表流，把"识别"这件事全部压到单行的视觉编码上：位置不变，靠每行自身的样式差异拉开权重。

这版定下来的几条边界：

- 保留现有按 `time.updated` 降序的排序，不做状态分组重排。位置由时间决定。
- 不做 Stale 折叠分组，也不做任何折叠。陈旧会话留在时间流里，只是视觉上退到最弱。
- Needs you 不靠位置浮现，靠单行最强的视觉编码自己跳出来，即使它排在列表靠下也能一眼认出。
- 每行承载的视觉信息从现在的"标题 + 时间 + 一句状态文字"扩展到：左侧状态色条 + 状态图标、未读点 + 整行明暗分级、运行中的 live 元素（pulse + 计时）。

这套设计的赌注是单行的视觉带宽够不够。位置不再帮忙分辨轻重，全部责任落到色条、图标、明暗、动效这几个维度的组合上，所以下面把每个状态的具体编码写细，再说明它们叠加起来在一条时间序列表里能不能拉开足够辨识度。

### 设计 token 复用

全部沿用现有 Quiet Tech 系统，不引入新视觉语言。直接用到的：主色 `#3B82F6`（`DesignColors.Brand.primary`，交互/品牌），金色 `#D9A621`（`DesignColors.Brand` 金色，设计系统里严格保留给"AI 正在工作"态）。文字三级明暗阶梯现成：`Neutral.text`（primary）、`Neutral.textSecondary`（secondary）、`Neutral.textTertiary`（`DesignTokens.swift:44-51`），整行明暗分级直接映射到这三级，不用新增颜色。行内边距 `DesignSpacing.sm`（8pt）纵向、`DesignSpacing.lg`（16pt）横向，圆角 `DesignCorners.medium`（12pt）。现有左侧 3pt 选中竖条（`SessionListView.swift:195-206`）扩展成承载状态的色条。

### 每个状态的单行编码

下表把五个状态映射到四个视觉维度。色条在最左，宽度和颜色按权重递减；图标紧跟标题；标题字重和整行明暗按状态分级；右侧放时间和状态文字。

| 状态 | 左侧色条 | 图标 | 标题字重 / 明暗 | 右侧 + live |
|---|---|---|---|---|
| **Needs you** | 主色实心，4pt（最宽） | 主色实心圆点或 `bell.fill` | headline 加粗，`Neutral.text` 满亮 | "等你授权" / "等你回答" + 阻塞时长 |
| **Running** | 金色实心，3pt | 金色 `circle` + pulse 动画 | headline，`Neutral.text` | "运行中" + 已运行时长（live 计时） |
| **Done · unread** | 主色，2pt（细） | 主色未读小圆点（标题左侧） | headline，`Neutral.text` | 时间；可选结果摘要 |
| **Done · read** | 无 | 无 | body，`Neutral.textSecondary` | 时间 |
| **Stale** | 无 | 无 | body，`Neutral.textTertiary`（最弱） | 时间 |

几个要点。Needs you 的强度来自四个维度同时拉满：最宽的主色条、实心图标、加粗满亮标题、一句带动词的文案，所以即使它排在第十行，扫过去也是整列里最跳的一个。Running 用金色而非主色，是因为金色在系统里就是 AI 工作态专用色，语义自洽，同时和 Needs you 的主色形成色相区分，两个强信号并置时不会糊成一团。明暗分级是承载时间纵深的主力：Done·unread 满亮、Done·read 退到 secondary、Stale 退到 tertiary，越旧越淡，这条明暗梯度让陈旧会话自然沉下去，不需要折叠也不会干扰。

阻塞还能再细分。`pendingPermissions` 是"等你授权一个操作"，`pendingQuestions` 是"agent 在问你问题"，文案上分成"等你授权"和"等你回答"，用户在列表层面就知道点进去要做什么，这不增加数据成本。

### 示意

```
┃ 重构认证中间件          🔔 等你授权 · 2m       ← Needs you：4pt 主色条，加粗满亮，最跳
· 修复 markdown 渲染              1h            ← Done·read：无条，secondary 明度
┃ 给搜索加分页            ⟳ 运行中 · 3m         ← Running：3pt 金色条 + pulse + live 计时
• 调研向量数据库选型              2h            ← Done·unread：2pt 细主色条 + 未读点，满亮
  部署脚本重写                    21h           ← Stale：无条，tertiary 最淡，沉在流里
```

注意上面是严格时间序（2m / 1h / 3m / 2h / 21h 并非排序，是各自的状态时长/更新时间），Needs you 和 Running 并没有被挪到顶部，它们靠色条、图标、字重、明暗在原位跳出来。这正是简化版 C 的核心：辨识靠视觉编码，不靠位置。

### 结果摘要：可选，默认不放

`Session.summary` 现成带 `additions/deletions/files`（`Models/Session.swift:30-34`），技术上可以在 Done·unread 行渲染成"+12 −3 · 4 文件"。但每行再加一段摘要会增加视觉密度，和"克制"的取向相反，所以默认不放，列为可选项：如果实测发现仅靠未读点不足以让用户判断"这个完成的会话值不值得点进去"，再加摘要行。研究类会话没有 diff，回退到末条助手消息首行。是否启用建议放到真机验证后再定。

### 父子层级

列表是按 `parentID` 组织的可折叠树（支持会话 fork）。单行编码作用于每一行，包括子会话行；子会话继续跟随父节点、按时间排，状态色条和明暗同样适用。这一层不受本方案影响。

---

## 五、交还设计方向：需要你定的几件事

第一，单行编码的强度配比。每个状态的色条宽度（4/3/2pt）、图标选择、明暗三级映射，是不是你要的落差。尤其 Needs you 是否够跳、Stale 是否够沉，这个在真机上最直观，hi-fi 时可以微调。

第二，Running 的金色 pulse。金色在系统里专属 AI 工作态，用在这里语义自洽，但它会和 Needs you 的主色在同一屏出现。两个强信号并置的视觉平衡需要你在 hi-fi 里定。

第三，结果摘要行要不要默认开。我倾向默认不放、保持克制，验证后再决定。如果你希望 Done·unread 一开始就带摘要，我按你说的来。

第四，4b 的落地顺序。建议 read-unread 底座 + Pin 跟 4a 一起先上（read-unread 本来就是 Done·unread 和明暗分级的前置），Snooze 单独作第二批，服务端定时排除在外。

关于 Stale 阈值。既然不折叠，Stale 只是明暗最弱的一档，阈值只决定"多旧算 Stale、退到 tertiary"，建议暂定 24 小时未更新，这个数值 hi-fi 时按维护者节奏微调即可。

我这边等你在 hi-fi 里把这套单行编码的强度定下来。落地上，4a 的状态模型、排序和单行样式都是纯客户端、低风险的，可以最先实现验证；本地通知那批因为要新建基础设施，单独排。
