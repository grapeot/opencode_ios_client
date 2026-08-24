# Session Finder 设计草案

## 结论

把它做成现有 Sessions 入口里的智能查找模式，而不是新增 Tab，也不是在已加载列表上做标题过滤。

用户输入一句对旧对话的描述，系统返回 3-8 个带原文证据的候选。用户先确认候选，再进入原 session 继续输入。搜索慢可以接受，但结果必须说明搜索范围、命中依据，以及该 session 当前是否还能继续。

原型先用临时 OpenCode utility session 编排现有 Markdown archive 和 semantic-search；客户端只消费稳定的结构化结果。验证 UX 后，再把 utility session 换成正式 search bridge，界面和结果 contract 不变。

## 成功标准

用户不需要记住标题、日期或项目名，只需描述记得的内容，并在一次搜索中完成三件事：

1. 找到少量可信候选，而不是浏览几十个标题。
2. 从原文片段判断哪一个才是目标 session。
3. 明确知道该 session 可以直接继续，还是只剩只读历史。

首版以 Top 5 候选中包含正确 session 为核心指标。搜索耗时是次要指标，但必须有可信的阶段反馈，不能长时间只显示 spinner。

## 入口与主流程

### iPhone

保留 Chat 工具栏现有 Sessions 按钮和左缘滑动入口。打开 Sessions sheet 后，顶部增加系统搜索框，placeholder 为 `描述你记得的内容`。

查询为空时，继续显示现有 Active / Archived 列表。用户按键盘 Search 后进入智能查找模式：

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

点候选进入预览页，不立即替换当前 Chat。预览页显示：

- 命中消息前后各一轮。
- session 最后停留的一轮。
- 项目、日期和可继续状态。
- 底部固定主按钮 `Continue in This Session`。

如果它是 OpenCode 的软归档 session，按钮写 `Restore and Continue`。确认后调用现有 `selectSession`，关闭 sheet，回到 Chat，并聚焦 composer；不自动录音，也不自动发送。

普通 Sessions 列表保持点击即打开。额外确认只用于概率性的搜索结果，不增加日常切换成本。

### iPad

搜索框放在常驻 Sessions 左栏。左栏只放紧凑候选；选择候选后，中栏暂时从 Files 切成 session preview，右栏继续保留用户当前 Chat。只有点击 `Continue in This Session`，右栏才切换。

compact width 的 iPad 沿用 iPhone 流程，不按设备型号强制三栏。

## 搜索范围

默认范围是：当前 Host、所有项目、包含 OpenCode 软归档 session。

不默认跨 Host 搜索。不同 Host 代表不同连接、凭证和 session namespace；混合结果会出现“找到了但当前 Host 打不开”的假成功。搜索框下方显示一个低干扰 scope 行，例如：

```text
Home Mac · All Projects · Includes Archived
```

结果命中其他项目时，确认继续后自动把客户端项目切到该 session 的 `directory`，让 Sessions、Files 和 Chat 保持同一 workspace 上下文。

这里必须区分两种 archive：

- OpenCode 软归档：仍在 server main DB，可恢复并继续。
- 离线历史：已迁到 archive DB 或只剩 Markdown，当前 server 无法 append。

用户界面不要都叫 Archived。离线历史显示 `Read-only copy`，避免和现有 Archive/Restore 混淆。

## 候选卡

候选卡只显示帮助识别的信息：

- session 标题，最多两行。
- 项目短名称，不显示绝对路径。
- 绝对日期；旧 session 仅显示相对时间不够辨识。
- 2-3 行原文摘录，并标明 `You` 或 `Assistant`。
- 特殊状态：`Archived`、`Read-only copy`、`Child session`；普通 idle 不显示。
- 可选的一行 `Last stopped at`，用于区分“命中了旧话题”和“适合从结尾继续”。

不显示 0.83 之类的相似度数字。它对用户没有可操作含义，也会制造伪精确感。AI 摘要只能辅助，不能替代原文证据。

搜索结果按 session 聚合，不按 chunk 展示。多个 chunk 命中同一个 session 时，保留最有辨识度的一段，并用命中数量作为内部排序信号。子 session 命中时优先归入父 session，并标注命中来自 child，避免同一工作流占满候选列表。

## 搜索与排序

V0 需要 semantic retrieval，不需要生成式 LLM rerank。

推荐排序管线：

1. 从现有 Markdown semantic index 召回 Top 20-30 chunks。
2. 补充 live DB 的标题精确匹配和最近 session 匹配。
3. 按 `(host namespace, session_id)` 聚合。
4. 以最高语义分、重复命中数、关键词命中为主，recency 只做弱加权。
5. 验证候选当前位于 main DB、archive DB，还是仅有 Markdown。
6. 返回 Top 5，低置信度时最多放宽到 8 个。

只有离线评测证明 hybrid retrieval 的 Top-3/Top-5 不够，才给前 20 个候选加 reranker。reranker 必须可超时降级，不能成为结果首屏的硬依赖，也不能改写命中原文。

## V0 执行架构

### 为什么先用 utility session

现有 OpenCode server 的 `search` 只搜 session title；iOS 当前又只持有逐步扩大的 session window。两者都不能诚实地称为历史内容搜索。与此同时，workspace 已有每日 Markdown export、semantic-search CLI 和可调用工具的 OpenCode agent。

因此原型可以这样跑：

```text
iOS query
  -> create ephemeral utility session
  -> structured prompt calls semantic-search and checks DB availability
  -> JSON result
  -> delete utility session after successful parsing
  -> render candidates
```

utility session 使用 JSON schema 输出。客户端不能解析自然语言答案来猜 session ID。失败时保留 utility session 供诊断，下一次搜索新建干净 session，避免前一次对话污染排序。

这条路径的优点是改动小，并且能验证用户是否真的愿意用自然语言寻找旧 session。代价是延迟高、会消耗一次 agent turn，也需要保证 server 所在 workspace 能访问 session archive 和 semantic-search。

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

`availability` 至少支持：

- `live`：当前 server 可直接打开和 append。
- `offline_db`：存在于离线 archive DB，V0 只读。
- `markdown_only`：只有导出文本，V0 只读。
- `missing`：索引命中但原始数据无法解析，不展示为正常候选。

稳定主键不能只有 `session_id`，应使用 `(source, host_namespace, session_id)`。否则多 Host 或其他 session 来源接入后会失去定位能力。

### 正式 bridge

UX 验证后，把 utility session 替换为 companion search endpoint：

```http
GET /session-search?q=...&host=...&project=all&limit=5
GET /session-search/opencode/{session_id}/preview
```

bridge 负责索引、DB availability resolve 和 preview，iOS contract 不变。不要让移动端直接访问 SQLite、Markdown 绝对路径或 embedding cache。

## 加载、弱匹配与失败

搜索由用户显式提交，不在每次键入时运行昂贵语义查询。

- 400ms 内完成：直接显示结果，不闪 loading。
- 超过 400ms：显示 `Searching conversations...`。
- 超过 2s：补充 `Checking older indexed sessions...`。
- 用户修改并重新提交：保留旧结果但降低视觉权重，显示更新状态，避免空白跳动。

弱匹配显示：

```text
No strong match found. These sessions may be related.
```

真正零结果必须说明范围和索引时间，并提供三个出口：修改描述、按时间浏览 Sessions、切换 Host。网络错误、索引未完成和零结果分别处理，不能都显示 `No results`。

## 直接继续与只读历史

V0 的主任务是继续讲话，因此 `live` 结果排在前面。`offline_db` 和 `markdown_only` 放在单独的 `Older read-only matches` 区域，允许查看，但不显示假的 Continue 按钮。

后续如果要支持离线 session 恢复，应增加明确的 `Restore to OpenCode` 数据操作：把完整 session subtree、messages 和 parts 从 archive DB 复制回 main DB，验证后再允许 append。当前数据工具只有 main -> archive 的 plan/apply 安全流程，没有现成的反向恢复命令；在 live OpenCode 正在写 DB 时直接复制也不安全。因此这不进入首版原型。

## 不采用的方案

- 不做“过滤当前已加载标题”。当前列表初始只加载有限窗口，UI 会误导成全量历史搜索。
- 不让 AI 自动打开唯一结果。旧会话检索天然有歧义，用户需要候选和证据。
- 不让搜索候选点击后立即替换 Chat。搜索是概率判断，而当前 session 是持久化工作上下文。
- 不在每次搜索前重新导出全部 session。优先使用每日索引；只在索引明显过期时提供显式 refresh。
- 不让 iOS 直接读取 server SQLite 或 Markdown。移动端只消费 search/preview contract。

## 现有代码接点

- iPhone Sessions sheet 和点击切换：`OpenCodeClient/OpenCodeClient/Views/SessionListView.swift:25-135`。
- iPad Sessions 左栏：`OpenCodeClient/OpenCodeClient/ContentView.swift:890-1042`。
- 现有 session 切换及消息加载：`OpenCodeClient/OpenCodeClient/AppState+Sessions.swift:221-257`。
- 当前 session list 只按 directory + limit 请求：`OpenCodeClient/OpenCodeClient/Services/APIClient.swift:99-112`。
- `Session` 当前没有 excerpt 或 availability：`OpenCodeClient/OpenCodeClient/Models/Session.swift:8-40`。
- 现有设计已经明确拒绝把本地 title filter 画成搜索：`docs/design.md:209-217`、`docs/OpenCode_iOS_Client_RFC.md:526-537`。

## 原型范围

第一轮只做 iPhone，并固定以下边界：

1. 当前 Host、所有项目、包含软归档。
2. 显式提交自然语言 query。
3. Top 5 候选和原文 excerpt。
4. preview 后继续；软归档先 restore，再继续。
5. 离线 DB/Markdown 结果只读。
6. utility session + structured JSON，不做 LLM rerank。

这个原型验证的不是 semantic-search 的最终技术选型，而是用户是否能用“描述记忆 -> 看证据 -> 回到原 session”明显降低找旧会话的成本。
