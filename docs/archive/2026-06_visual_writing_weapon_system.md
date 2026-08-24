# Visual Writing 武器系统:讨论稿 v2

> 这份文档不是结论,是讨论锚点;也是 dogfood —— 它本身按 low-cognitive-burden 原则写,试试这套原则能否承重。
>
> v2 改动:吃了三个 sub-agent 的批评,把"四轴"砍成"1 张力轴 + adaptive 路径 + 1 前置 gate + 1 不确定性轴";anti-pattern 分了 severity;self-eval 从问句改成扫描动作;原始辩论收进文末 `<details>`。
>
> v2.1 改动(读者反馈):把"注意力预算"从张力轴改成 adaptive 路径的输入 —— 不该预设 30 秒还是 30 分钟,该让文档同时承载两种 trajectory。这条 reframe 才接得住"同一份 RFC 第一稿 vs 大改动稿"这类反例。
>
> **2026-06-14 状态更新**:方法论本体已 sink 进 `rules/skills/workflow_internal_writing.md`(本 repo path 之外,`knowledge_working/rules/skills/` 下)的 "Visual Cognitive Load Reduction" 节。包括三公理、武器库总览、adaptive 路径机制、跟旧 markdown-first 实践的 delta、还没拍板的事。**这份文档保留为 dogfood case analysis,记录"一次 PRD/RFC dogfood + 三个 sub-agent 辩论"的完整路径**。要看 live methodology 看 skill,这里是历史 entry point。

## 真问题

不是"该不该用 visual",也不是"该多用还是少用"。这两个都是假问题。真问题是:

> **AI 写一段 internal 文档时,什么时候 visual 真的减负、什么时候 visual 添假信号?**

如果能把这个问题刻进 AI 写作回路,武器多少、长短、用不用 chip,都是自然推论。

## 证据先行:8 个 anti-pattern,从 dogfood 真材实料挖出

这 8 个不是想象,是 anti-pattern hunter 从我刚写的真实文档里找出的 ground truth。按"严重度 × 修复成本"排序,前 3 个**周末就要先动**。

<style>
.ap-grid{display:grid;grid-template-columns:1fr;gap:8px;margin:12px 0}
.ap-crit{padding:10px 12px;border-left:4px solid var(--bad-border,#ef4444);background:var(--card-bg,#fafbfc);color:var(--fg,#243244);border-radius:0 8px 8px 0}
.ap-form{padding:10px 12px;border-left:4px solid var(--warn-border,#f59e0b);background:var(--card-bg,#fafbfc);color:var(--fg,#243244);border-radius:0 8px 8px 0}
.ap-style{padding:10px 12px;border-left:4px solid var(--block-border,#6b7280);background:var(--card-bg,#fafbfc);color:var(--fg,#243244);border-radius:0 8px 8px 0}
.ap-grid h4{margin:0 0 4px;font-size:.95rem;color:var(--fg,#243244)}
.ap-evi{display:block;margin:3px 0;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:.85rem;color:var(--link,#2e5c8a)}
.ap-grid p{margin:3px 0;font-size:.9rem;color:var(--fg,#243244)}
</style>

<div class="ap-grid">

<div class="ap-crit">
<h4>① 跨文档自相矛盾(必须立刻修)</h4>
<span class="ap-evi">证据 · 子 PRD §5.1 留删除线"~~Native 默认~~ 更新:Web 默认";子 RFC §12 仍写"决策:先不默认"</span>
<p>同一决策在 5 个版本流通(子 PRD / 子 RFC / 主 PRD / 主 RFC / WORKING),只有 2 个进 git。读者不知道哪个是 source of truth。</p>
</div>

<div class="ap-crit">
<h4>② 表格 + 卡片镜像作"fallback",双重维护(必须立刻修)</h4>
<span class="ap-evi">证据 · visual_explainer_html_md.md "第一屏状态卡" + "纯 Markdown 兜底"逐项对应</span>
<p>理由是渲染器兼容,代价是同一信息两份维护。漏改就不一致;fallback 该是渲染降级,不是手抄副本。</p>
</div>

<div class="ap-crit">
<h4>③ <code>&lt;details&gt;</code> 装核心结论而非可选材料(必须立刻修)</h4>
<span class="ap-evi">证据 · 主 RFC §7.5 的 details 里塞了渲染路径 / JS 依赖 / 安全模型 —— 这些是 RFC 工程读者的目标内容</span>
<p>"按需展开"暗示非必读,但内容是必读。读者要么点开等于没折叠,要么不点开导致 RFC 退化为营销页。</p>
</div>

<div class="ap-form">
<h4>④ 决策反转用删除线+更新戳堆叠,而非重写正文</h4>
<span class="ap-evi">证据 · 子 PRD §5.1 "~~第一版保留 Native~~ **更新(2026-06-14):...**"</span>
<p>把 git history 倒灌进正文。半年后文档失修就是这么累积的。</p>
</div>

<div class="ap-form">
<h4>⑤ 状态分类粒度过细且文档内漂移</h4>
<span class="ap-evi">证据 · visual_explainer_html_md.md 不同 section 切换 chip 轴 3 次</span>
<p>"成立但弱/否定/候选/阻塞" vs "完成/下一轮" vs "不优先/优先/并行" —— 读者要维护多套色码语义映射。</p>
</div>

<div class="ap-form">
<h4>⑥ Chip 用作行末状态戳,色彩单一无信息</h4>
<span class="ap-evi">证据 · OpenCode_iOS_Client_PRD.md §4.3.5 状态表 7/8 行都是"上线"</span>
<p>chip 在这里没筛选价值也没对比价值,只是给"上线"两字加胶囊。读者反而要逐行扫"哪里没完成"。<br><em>注:这条 anti-pattern 的存在,本文档 v1 自己就翻车过(8 张全红卡)——v2 把卡分了 3 个 severity tier 才修掉。</em></p>
</div>

<div class="ap-style">
<h4>⑦ 状态表行 key 用 Phase/Sprint 而非用户体验</h4>
<span class="ap-evi">证据 · 2026-06_markdown_web_preview_prd.md（archive/）§"实施进度" vs 主 PRD §4.3.5 同信息不同排</span>
<p>同一团队同周写出两版,说明 AI 默认退回工程时序。Row key 替换成"用户在 App 看到什么"后顺序若变化,当前排序就是反模式。</p>
</div>

<div class="ap-style">
<h4>⑧ 标题写范畴名而非判决</h4>
<span class="ap-evi">证据 · 子 RFC §5 "方案总览"、§6 "组件设计"、§7 "安全模型"、§8 "UI 设计"</span>
<p>skill 已警告别写"Flowchart""Matrix",但"安全模型"是同类问题深一层。"安全模型" → "WebView 只跑 bundle JS,sanitizer 在渲染后剥脚本"才是判决。</p>
</div>

</div>

<p><em>红边 = 内容/事实错误,会误导读者;橙边 = 维护性问题,长期会失修;灰边 = 形式问题,读起来累但不流血。</em></p>

## 从证据里长出的 framing

把上面 8 条 anti-pattern 反过来看,真正在打架的不是"visual 多还是少",是这两条张力轴 + 一前一后两个判断 gate。

### 一张张力轴 + adaptive 路径(块级)

**轴 A · 读者在这一块要做什么** — commit-to-action(扫一眼下决策)还是 explore-to-understand(读完想清楚)?
前者 visual 是利器,后者 visual 制造"以为看懂了"的幻觉。**判断信号**:这块紧跟 action item 列表 / 标题含动词?commit。这块在论证"为什么 X 不成立" / 后面跟着 tradeoff 段?explore。

**"注意力预算"不是张力轴,是 adaptive 阅读路径的输入信号**。同一份 RFC,intuitive 的小改读者 30 秒扫完就够;大改动稿读者会逐段 audit。**把预算预设成一个静态值,无论 30 秒还是 30 分钟,都会错** —— 该让文档同时承载两种 trajectory。具体做法:首屏给扫读层(visual + 一句话 takeaway);文中通过 anchor / link / `<details>` 给深读 hook —— 扫到不放心的点能 zoom in 到证据、tradeoff、推理。这就是为什么我们需要 HTML 扩展层而不是只用 markdown:adaptive 路径靠的是 anchor / 折叠 / hover 这些机制,markdown 本身不够。

判断单位是**块**不是**整份**。一份周报可以首屏是 commit(状态卡顶用)、下面是 explore(论证段必须文字)。把整份文档锁定在一个端点是 overfitting。

### 一前一后两个 gate(先过 gate 再谈张力轴)

**前置 gate · 共享上下文厚度** — 读者能否解码你打算用的 visual 语义?
读者集合 ≤ 3 人且本周内 = 厚;跨团队 / 跨季度 / 新人 = 薄。**薄,直接否决 visual,无论张力轴怎么投票**。这一 gate 不是张力,是先决条件。

**后置 gate · 事实可信度** — 底层结论稳吗?
visual 让"看起来很确定"。当事实在变(决策反转、数据未稳、PR 还没 merge),visual 的确定性外观就是负债 —— 读者会过度信任。anti-pattern ①②④ 的根因都是 visual 把不稳的事实包装成确定。**事实未稳时,visual 降级为表格 + 时间戳,或纯文字**。

## Self-evaluation:写完扫描三件事

不是写之前问问题(AI 没答案),是写完后**扫描 + 阈值 + 修复路径**。

<style>
.se-tbl{margin:8px 0}
.se-tbl table{width:100%;border-collapse:collapse}
.se-tbl th,.se-tbl td{padding:8px 10px;text-align:left;border-bottom:1px solid var(--border,#e6e8eb);color:var(--fg,#243244);font-size:.9rem;vertical-align:top}
.se-tbl th{font-weight:600;background:var(--card-bg,#fafbfc)}
.se-tbl code{font-size:.85rem;background:var(--code-bg,#f0f0f0);padding:1px 5px;border-radius:3px}
</style>

<div class="se-tbl">

| 扫描 | 阈值 = 触发 | 修复 |
|---|---|---|
| chip 那一列颜色枚举值出现次数 | 主色 ≥ 80% | 删 chip 列,例外行改成行末 `⚠ 阻塞` 标注 |
| 本段核心结论 `grep -r` 当前 repo | 命中 ≥ 2 处 | 本段改成 `详见 [path]`,不复制文本 |
| 每个 `##` / `###` 标题:删掉后正文第一句话能否独当小标题 | 能 = 标题是范畴名 | 重写标题为正文那句判决 |
| 文中是否出现删除线 + "(日期)" 戳 | 有 = 历史倒灌正文 | 重写正文为最新决策,旧版搬文末 changelog |
| `<details>` 里的内容删掉,读者还能完成首要判断吗 | 不能 = details 装了核心 | 把核心搬出 details,折叠区只留审计材料 |
| chip / 状态分类的枚举值,本文档前后章节是否同一套 | 不同 = 语义漂移 | 全文统一一套(建议 ok/warn/bad/block 封顶) |

</div>

## 武器谱系 vs 决策机制:不对等,后者是地基

User 提的 joint optimization 是个 trade-off,但**两条腿不一样重**。

**地基:决策机制**。如果 AI internalize 了"先过两 gate、再判两轴",哪怕武器只给 4 件(短段落 / 短表 / details / chip 在分布均匀时用),也能命中绝大多数场景。

**上层:武器谱系**。武器多 → form factor 精准命中,单次减负深;但武器多 → AI 决策成本和错误率上升。所以"补武器"必须有 dogfood 证据(反复缺位了再补),不为"丰富武器库"加任何东西。

skill 升级优先级:① internalize 两 gate + 两轴(地基) → ② 把 self-eval 扫描表写成可执行护栏 → ③ 把 8 个 anti-pattern 加进失败模式表 → ④ 谨慎补武器(目前没有必须补的)。

## 还没拍板的几件事

1. **chip 整体降级?** Anti-pattern ⑥ 暴露 chip 在同列同色场景纯装饰。是不是 chip 该改成"只用于异常/例外标注",默认不出现?
2. **跨文档复制的修法**:(a) 单一 source + 其他文档 link / (b) 接受复制 + last-synced 戳 —— (a) 干净但读者要跳,(b) 现实但 6 个月后必然失修。
3. **决策反转的标准操作**:直接重写正文 + changelog 搬历史,vs 删除线 + 更新戳保留 audit trail —— 后者销毁可追溯性。
4. **"读者意图"vs"注意力预算"两轴的边界**:Framing Skeptic 建议把它们合,但我留两轴 —— 老板看 6 屏季度 doc 是 commit + 高预算,合了就抓不到这个反例。这个判断对吗?

---

## 附录:三个 sub-agent 的原始辩论(审计材料,可不读)

<details>
<summary>Framing Skeptic:四轴 framing 经不经得起拍?</summary>

读完全文,直接进入攻击。我分五点回答,最后给出我的建议拓扑。

**一、四轴的独立性:有一对是同义反复,有一对是嵌套**

**轴 2(生命周期)和轴 4(读者意图)高度相关**。一次性看完就丢的文档,读者几乎一定是 commit-to-action;长期维护的 PRD/RFC,读者大概率是 explore-to-understand。两轴几乎共变(~70%)。但**6 个月后给自己看的复盘**是长生命周期 + explore;**给陌生新人的 onboarding doc** 是长生命周期 + commit-to-action。所以两轴不能合并,但承认它们有共变。

**轴 3(共享上下文厚度)根本不是张力轴,而是元 gate**。这是这套框架最该被攻击的一点。轴 1/2/4 都在描述"读者要做什么、文档要活多久",在同一抽象层级;轴 3 在描述"读者能不能解码 visual 的语义"。它的作用机制不是"在这端 visual 更好、另一端更糟",而是"上下文薄 → 任何 visual 都要先付解释税,可能直接否决 visual"。它跟前三轴不是平行的判断维度,而是一个前置条件。

**二、被忽略的更深维度**

筛出两个真正独立于现有四轴的候选:

- **作者熟练度** —— AI 写作场景下熟练度是常数(低),不构成判断变量
- **读者数量(1 vs 100)** —— 实际可被轴 3 吸收
- **读者注意力预算(30 秒 vs 30 分钟)** —— **这是真正独立的新轴,且解释力强**。30 秒预算下,即使开放判断,读者也只能依赖 visual 先 frame;30 分钟预算下,即使结构化,读者也愿意读完表格背后的解释。MD 里"周报 vs PRD"的对比其实混了两件事:判断结构性 + 注意力预算。**反例:给老板写 6 屏季度 doc** 是结构化 + 长预算,四轴框架说"用 visual",但老板会读 30 分钟,visual 反而是噪音。**注意力预算这一轴应该补。**
- **信任级别** —— 可被轴 3 吸收

**三、极端测试**

- 给老板写季度 doc → 四轴一致投"重 visual",但直觉是错的:老板会逐段读。框架失灵,缺**注意力预算**
- 团队"要不要 adopt X"方案对比 → 轴 1 看似结构化,但实际是 explore-to-understand;轴 4 是 commit-to-action。**轴 1 和轴 4 直接冲突**,框架不告诉你听哪个
- 6 个月后给自己看的复盘 → 四轴一致投"少 visual",框架有效
- 跨部门 status update → 轴 1/2/4 都投 visual;轴 3 薄,直接否决前三票。**证明轴 3 是 gate 不是 axis**

**四、轴 1 的混合状态**

MD 自己的例子已经暴露问题:周报"哪条路径成立"是结构化 visual,"为什么 confidence 不能用"是开放式文字。**同一份周报里两者并存**才是常态。判断单位不该是"整份文档"而该是"段落/块"。

**五、建议拓扑**

- 留两条核心张力轴:**轴 A 读者要做的判断**(原轴 1,块级),**轴 B 注意力预算 × 生命周期**(合并)
- 把原轴 4 降级为轴 A 的子情形
- 把轴 3 提升为前置 gate,不再列张力轴
- 新增第三轴:**作者的事实可信度** —— anti-pattern ①②④ 的根因都是 visual 让"看起来很确定"超出底层事实的确定性

最终:**2 张力轴 + 1 前置 gate + 1 不确定性轴**。

</details>

<details>
<summary>Implementation Surgeon:abstract 原则磨成可操作 instruction</summary>

**1. 太抽象的 rule**

"判断读者在哪端"对人是直觉,对 AI 是空概念。需要可观察信号:

- 读者要做 commit 决策的信号:文档结尾是 action item 列表 / "Recommended Action" section / 文档标题含"周报""status""decision";作者本人在 24 小时内会基于这份文档做调度
- 读者要 explore 的信号:文档要回答"为什么 X 不成立"、含"reasoning""分析""tradeoff" section、长度 >2000 字、文末没有可执行清单
- 文档生命周期短的信号:文件名带日期 / 路径在 `weekly_reports/` `status/` `worklog/` 下
- 共享上下文厚的信号:读者集合 ≤ 3 人且在同一项目同一周

**2. 冲突调和**

MD anti-pattern 4 vs skill "每个 HTML visual 都要有 Markdown fallback" —— 表面冲突,本质不冲突。fallback 是渲染失败时承载等价信息,不是"为所有读者并列两份"。调和:fallback 应放在 `<details>` 里;两份信息可见性必须互斥,不能并列首屏。

**3. 8 个 anti-pattern 的自检信号**

可直接用:#2(details 装核心 —— "把 details 里内容删掉,读者还能完成首要判断吗?")、#4(镜像 —— "卡片和表格的每一行是否一一对应")、#7→现 #6(chip 单色 —— "这一列 ≥80% 同色")。

需要更清晰判别信号的:

- #1(Phase/Sprint 排序):"行 key 替换成'用户在 App 里看到什么'后,顺序是否变化?变化 = 反模式"
- #3(chip 语义漂移):"本文档之前章节的 chip 颜色语义,和当前是同一套吗?"
- #5(跨文档复制):"这段结论的文本字符串,grep 整个 repo 是否 ≥2 处?"
- #6→现 #8(范畴名标题):"删掉这个标题,正文第一句话能否独立做小标题?能 = 范畴名"
- #8→现 #4(删除线戳):"这段文字里有删除线或'更新(日期)'戳吗?"

**4. Self-eval 改成"写完扫描"**

MD 现在的 checklist 全是问句,AI 写之前不知道答案。改成"写完一遍后执行的扫描":

- 色彩分布 → "写完整张表后,数 chip 那列的颜色枚举值次数;若主色 ≥ 80%,删掉这列"
- 跨文档复制 → "把本段核心结论复制成一行 grep;命中 ≥ 2 处,改 link"
- 标题判决 → "扫一遍所有 H2/H3,逐个问'删掉标题,正文第一句话能不能直接当小标题'"

关键改造:**问句换成"动作 + 阈值 + 修复路径"三元组**。

**5. 四轴改成"每段四个 yes/no"**

写 visual 之前必须答完:

1. 读者读完这段会在 24 小时内执行某动作吗?
2. 这份文档下周会被改 / 6 个月后会被引用吗?(yes = 长生命周期,visual 是税)
3. 文档的目标读者集合 ≤ 3 人且都在本项目本周吗?(no = 薄上下文)
4. 读者扫完是"下决策"还是"想清楚"?(后者 = 不加 visual)

四个里出现 ≥1 "no / 想清楚",当前段不加 visual。**硬门禁,不是建议**。

**6. 分类:skill 主体 vs self-eval**

- 进 skill 主体(写之前 / 写之中):四轴 yes/no 门禁、HTML fallback 可见性互斥、anti-pattern 1/2/6(影响骨架,事后改成本高)
- 进 self-eval(写完扫描):anti-pattern 3/4/7(局部扫描就抓)、anti-pattern 5/8(grep + 正则能查)

</details>

<details>
<summary>Visual Form Critic:MD 自己的 form 站得住吗</summary>

**1. "真正的张力轴"4 行表**

比 markdown 表低负担吗?**不明显**。这表 2 列固定宽度、内容主要是散文,本质就是"加粗标签 + 段落"。改成纯 markdown 的 `**X**:Y<br><sub>例:...</sub>` 损失为零。CSS 块是首次出现的"轴卡"形式,读者要花一拍学,但学完发现只是表格 —— ROI 负。

层级跳得合适吗?主标题 600 字重 + 灰副 em 0.92x 对比偏弱。轴名建议 1rem/700 + 圈码 ① ② ③ ④。

**改成**:换 markdown 表,2 列 `| 张力轴 | visual 减负 / 添负担 |`。

**2. Anti-pattern 库 8 张红边卡**

**全红冲突 #7 自己** —— 是,而且尴尬。8 张卡全红 = 8 个"危险等级相同"的隐含信号,正是 #7 说的"色彩单一无信息"。chip/红边的语义本该承载严重度,现在沦为装饰外框。

**改成**:引入两个 severity tier。"必须立刻修"(#5/#2/#4)红边;"形式问题但不流血"(#6/#7/#1)橙或灰边。这一改,#7 当场被 dogfood 印证。

`.ap-evi` 小灰证据会被跳过。卡是扫的,小灰字 0.85rem 在卡底就是"装饰元数据"。但证据恰恰是这份文档相对其他空谈的关键差异(它声称的 ground truth) —— 应该上浮。

**改成**:证据行从卡底搬到 h4 下一行,用单色 monospace。

**排序?** 现在 1-8 看不出逻辑。按"严重度 + 修复成本"排:#5 → #4 → #2 → #8 → #3 → #7 → #1 → #6。

**3. "武器谱系 vs 决策机制"双栏**

两栏是同一 tradeoff 两面?**部分是**。两边都是"精细度 vs internalize 成本"。把它们并列暗示"独立维度",但作者自己下一句就说"两条腿不一样重,决策是地基" —— 既然不对等,双栏就误导。

移动端折单列后还有意义吗?没有。

**改成**:删双栏,改成两段普通段落,层级关系明示在标签里。

**4. 整篇 narrative**

当前 6 个 ## :真问题 → 四轴 → anti-pattern → 双腿 → checklist → 讨论项。

**问题**:anti-pattern 才是这份稿 unique evidence,埋在第三屏太可惜。frame 应该从证据里长出来,而不是先立 frame 再找证据。

**改成**:anti-pattern 提到第二节(紧接"真问题"),用真证据砸开局;frame 变成"从这 8 条看,真正的对立是这两轴 + 两 gate"。

**5. `<details>` 缺席**

该 dogfood,而且现在没用是真破绽 —— 文档明确把 details 列为关键工具,自己一个没用。可折的合法对象:三个 sub-agent 辩论的原始输出(audit trail,非必读)。这些是教科书式"审计材料"用例,正好示范 #2 的正面。

**改成**:文末加 `## 附录` 三个 details 折 sub-agent 输出。

---

**一句话总结**:稿在论点层是真东西,在 form 层有 3 处自己打自己 —— 全红 anti-pattern 卡撞 #7、双栏双腿撞"不对等"自陈、整篇缺 details 撞自己的 toolkit 主张。修这 3 处 + 把 anti-pattern 上浮做开局,文档就能真正承重它鼓吹的原则。

</details>
