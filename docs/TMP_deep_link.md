# OpenCode Session Deep Link 设计与测试计划

## 结论

Session 搜索继续是 Agent 能力，客户端不建设独立的搜索引擎或搜索页面。Agent 调 semantic-search 找到候选，用普通 Markdown 解释命中依据，并输出一个标准 session deep link。iOS 或 Android 客户端只负责解析、验证和跳转。

首版协议固定为：

```text
opencode://session/<session_id>
```

示例：

```markdown
### iOS 中文输入法提前发送

你当时提到：“中文输入法还在选字时，消息就被提前发送了……”

2026-06-18 · opencode_ios_client

[在 OpenCode 中打开](opencode://session/ses_example)
```

这条链路解决四件事：Agent 负责发现候选，Markdown 负责呈现证据，deep link 负责传递定位意图，客户端负责打开真实 session。链接可以来自当前 OpenCode 对话，也可以来自邮件、Notes、网页或其他 Agent。

本文聚焦 iOS 原型，同时把 URI contract 定义为跨平台协议。Android 后续使用相同格式注册 intent filter 和路由，不重新设计搜索输出。

## 成功标准

首版完成后，以下场景必须成立：

1. App 前台运行时，点击 assistant Markdown 中的 session link，能切换到目标 session。
2. App 未运行时，从系统打开同一链接，能启动 App，并在连接恢复后进入目标 session。
3. 目标 session 不属于当前项目时，客户端仍能按 ID 获取它，并把 Chat、Sessions 和 Files 切到目标 directory。
4. 非法链接、404、未连接和重复点击不会破坏当前 session，也不会执行任何写操作。
5. Agent 搜索多个历史 session 后，只为真实 OpenCode session ID 生成可点击链接，并在链接旁给出原文证据。
6. 同一 Markdown 输出在 iOS 和未来 Android 上使用同一个 URI contract。

## 一、Deep Link 协议与客户端实现

### 1.1 URI contract

V1 只接受一种资源：

```text
opencode://session/<session_id>
```

解析规则：

- scheme 必须严格等于 `opencode`，大小写归一后比较。
- host 必须严格等于 `session`。
- path 必须只有一个非空 segment。
- session ID 必须符合 `ses_` 前缀和安全字符白名单；建议接受 `[A-Za-z0-9_-]`，不把当前 ID 长度写死。
- V1 不接受 userinfo、port、fragment 或未知 query parameter。
- percent-decoding 后重新验证，拒绝 `/`、`..`、控制字符和重复编码。
- 无效链接只报错，不回退成文件路径或外部 URL。

V1 不在 URL 中加入本机 Host Profile UUID。Profile UUID 只在当前设备有效，加入链接后会破坏跨设备可移植性。V1 的解析范围明确为“当前配置的 Host”。

下面的扩展暂时保留，不在 V1 实现：

```text
opencode://session/<session_id>?message=<message_id>
```

只有当 Chat 已有可靠的 message scroll/highlight 能力后，才接受 `message` 参数。在此之前宁可拒绝未知参数，也不要看似成功但没有定位。

### 1.2 为什么使用 custom scheme

custom URL scheme 是原型成本最低的系统 deep link：iOS 用 `CFBundleURLTypes` 注册，Android 用 intent filter 注册，Markdown renderer 也能把它当普通链接。

`opencode://` 在操作系统层面不保证全局唯一。如果未来官方 OpenCode App 或其他客户端注册同名 scheme，正式发布版本应迁移到唯一 scheme 或 Universal Link，例如：

```text
yage-opencode://session/<session_id>
https://open.yage.ai/session/<session_id>
```

当前私有原型仍使用用户指定的 `opencode://`。URI parser 应把 scheme 常量集中定义，未来切换不改业务路由。

### 1.3 iOS 注册

当前 target 使用 `OpenCodeClient/Info.plist`，尚未声明 URL Types。加入：

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLName</key>
    <string>com.grapeot.OpenCodeClient.session</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>opencode</string>
    </array>
  </dict>
</array>
```

Debug 和 Release 共用该 plist，因此不在 `project.pbxproj` 里维护两份重复配置。构建后用 `plutil` 或已安装 App 的 Info.plist 验证最终产物确实包含 scheme，不能只检查源码 plist。

### 1.4 代码结构

建议新增两个小文件，不把解析、网络和 View 生命周期混在一起：

```text
OpenCodeClient/OpenCodeClient/Utils/OpenCodeDeepLink.swift
OpenCodeClient/OpenCodeClient/AppState+DeepLinks.swift
```

核心类型：

```swift
enum OpenCodeDeepLink: Equatable {
    case session(id: String)
}

enum OpenCodeDeepLinkParser {
    static func parse(_ url: URL) -> Result<OpenCodeDeepLink, DeepLinkParseError>
}

enum DeepLinkRouteState: Equatable {
    case idle
    case pending(OpenCodeDeepLink)
    case resolving(OpenCodeDeepLink)
    case failed(String)
}
```

`OpenCodeDeepLinkParser` 是纯函数、`nonisolated`，由 unit test 完整覆盖。`AppState+DeepLinks` 负责异步解析和 session 状态变更。

不要把 `.session` 直接塞进 `WorkspaceLinkResolver`。后者当前负责 http、file、fragment 和 workspace path 安全边界；deep link 是 App action，单独 parser 能同时服务系统 `onOpenURL` 和 Markdown 点击，也避免文件导航规则越来越混杂。

### 1.5 路由状态机

统一入口：

```swift
func receiveDeepLink(_ url: URL)
func processPendingDeepLinkIfPossible() async
```

状态流：

```text
收到 URL
  -> 纯函数 parse
  -> 保存为 pendingDeepLink
  -> 未连接：等待 restoreConnectionFlow
  -> 已连接：GET /session/:id
  -> 成功：切 project + upsert + selectSession + 切到 Chat
  -> 404/网络错误：保留当前 session，显示全局错误
```

冷启动时，SwiftUI 可能先收到 URL，随后 `.task` 才完成 Host、SSH tunnel 和 server 连接。`onOpenURL` 不能直接假设 `AppState.isConnected == true`。它只保存 pending route；`restoreConnectionFlow()` 完成并确认连接后，再调用 `processPendingDeepLinkIfPossible()`。

前台点击 Markdown link 时也走同一个 pending/router，不写第二套“内部链接快速路径”。这样 warm launch、cold launch 和外部唤起共享行为。

并发规则：

- 同一 session link 重复点击必须幂等。
- 新链接到达时取消或失效旧的 in-flight resolve，使用 UUID generation token，模式与当前 `sessionLoadingID` 一致。
- Router 只保留最后一个 pending link，不建立无限队列。
- 解析、GET 或 loadMessages 失败时，不清空当前 messages，不改变 `currentSessionID`。
- App 从后台恢复可能同时触发 foreground refresh 和 deep-link resolve；两者必须串行协调，避免 refresh 用旧 project 覆盖刚解析的 session。

### 1.6 Session resolve 与项目切换

不要要求目标 session 已存在于当前 `state.sessions` window。当前列表有 directory filter 和逐步扩大的 limit，历史 session 很可能未加载。Router 应直接调用现有：

```text
GET /session/:sessionID
```

成功后：

1. 读取返回 `Session.directory`。
2. 如果 directory 对应已知 project，设置 `selectedProjectWorktree`。
3. 如果它是项目内自定义目录，设置 custom project sentinel 与 `customProjectPath`。
4. `upsertSession(session)`，保证 `currentSession` 能立即提供标题和 directory。
5. 调用现有 `selectSession(session)` 加载 messages、permissions、questions、diff 和 todos。
6. 设置 `state.selectedTab = RootTab.chat.rawValue`。

`selectSession` 当前会先清空旧消息，再异步刷新和加载，因此 Router 必须先完成 GET 验证，再调用它。不能先切 `currentSessionID`，然后才发现 404。

如果 deep link 指向当前 session，V1 直接切到 Chat，不重复清空和加载。未来加入 message 定位后，同 session link 可以只执行 scroll/highlight。

### 1.7 Host 与 archive 边界

V1 只在当前 Host 上解析，不自动轮询其他 Host。原因是自动轮询可能依次触发 SSH tunnel、认证和网络请求，延迟与错误语义都不透明。

当前 Host 返回 404 时显示：

```text
当前 Host 上找不到这个会话。它可能属于其他 Host，或只存在于离线历史中。
```

可以提供 `Open Hosts` 恢复入口，但 V1 不自动切 Host。后续若需要跨 Host，先定义稳定的 server namespace，不能把设备本地 UUID 写入 URI。

还要区分两种 archive：

- OpenCode 软归档：session 仍在 main DB，GET 可以成功；允许打开。用户发送下一条消息时，现有逻辑会 restore 后再发送。
- 离线 archive DB / Markdown-only：当前 server GET 返回 404；V1 不恢复数据库，只显示错误。

Deep link 解决的是定位和导航，不负责把离线 SQLite 数据写回 live DB。

### 1.8 UI 反馈

解析过程超过约 300ms 时，显示低干扰状态 `正在打开会话…`。成功后状态自动消失，不弹确认框。

错误必须挂在 root，而不是只复用 Chat composer 的 `sendError`。外部 deep link 可能在 Settings、冷启动或连接失败状态进入；全局 alert 才能保证用户看到。

建议增加稳定 accessibility identifiers：

```text
deep-link-opening
deep-link-error
```

显式 `在 OpenCode 中打开` 已经是用户确认动作，因此成功路径直接 switch，不再加 popup。不要把整张候选卡做成链接，避免误触。

### 1.9 安全边界

Deep link 是低权限导航 action，不是命令通道：

- 必须由用户点击或操作系统明确唤起；Markdown 渲染后不得自动执行。
- 只允许打开 session，不允许发送 prompt、删除、archive、approve permission、执行 tool 或修改文件。
- 不接受 URL 内携带 server URL、用户名、密码、token、模型或任意 command。
- session GET 成功前不改变当前状态。
- unknown scheme/path/query 全部拒绝，不能宽松猜测。
- 日志只记录 route 类型和失败类别；不要把真实 session ID、server URL 或 Markdown 正文写入公开测试 artifact。

### 1.10 Deep Link 测试

#### Tier 1：parser 与 contract

新增 `OpenCodeDeepLinkTests.swift`，至少覆盖：

- 正常 `opencode://session/ses_example`。
- scheme/host 大小写归一。
- 缺 session ID、多个 path segment、错误 host、错误 scheme。
- ID 前缀错误、空白、Unicode 控制字符、slash、`..`。
- 单次和多次 percent encoding。
- userinfo、port、fragment、unknown query。
- 极长 ID，防止异常内存或日志污染。
- parser 不接受未来 `message` 参数，直到该能力真正实现。

Info.plist 加一个 build-product contract test 或构建后脚本，断言最终 App bundle 注册 `opencode`，避免源码正确但 build setting 覆盖。

#### Tier 2：AppState 路由

使用现有可注入 `MockAPIClient` 覆盖：

- 已连接、目标 session 已在列表。
- 已连接、目标 session 不在当前 session window。
- 目标位于不同 directory，project 状态正确切换。
- 目标是软归档 session，仍能打开。
- 当前 session 与目标相同，操作幂等。
- GET 404、401、网络错误时保留原 `currentSessionID` 和 messages。
- 未连接时只 pending；连接成功后处理。
- 连续收到两个链接时只应用最后一个。
- resolve 尚未完成时 Host 被切换，旧结果不得污染新 Host。
- 成功后选中 Chat tab，并调用现有 message hydration。

`MockAPIClient` 已有 `sessionResult` / `sessionError`，可以直接扩展 request recording，不需要新造整套 mock。

#### Tier 2：fixture XCUITest

新增 `UITEST_DEEP_LINK_FIXTURE`：

- 当前 session 含一条 assistant Markdown 消息。
- 消息正文包含一个合法 session link、一个非法 link。
- fixture sessions 含 source 与 target 两个合成 session。
- 点击合法链接后，Chat navigation title 变成 target title。
- 点击非法链接后，当前 title 不变并出现 `deep-link-error`。

Production router 始终通过 `GET /session/:id` 验证后再切换。Deterministic fixture 应在 DEBUG 测试入口给 `AppState` 注入一个只返回 synthetic target 的 fixture API client，而不是让 production 路由绕过验证。这样 fixture 不需要真实 server，正常行为和安全边界仍保持一致。

## 二、Agent 搜索与 Markdown Action Link

### 2.1 职责边界

搜索不是客户端功能。用户在任意 OpenCode session 中自然地说：

```text
帮我找之前讨论 iPad 中文输入法提前发送问题的 session。
```

Agent 决定调用 semantic-search，读取候选，做必要的去重和解释，然后返回普通 Markdown。客户端不知道 query、embedding、reranking 或索引目录，只识别最终 deep link。

因此不需要：

- 新增 Session Search tab 或搜索框。
- 新增搜索 server endpoint。
- 让 iOS 直接访问 Markdown archive、SQLite 或 embedding cache。
- 要求 semantic-search CLI 输出客户端专用 UI model。

### 2.2 Private overlay 修改

修改 workspace 私有 overlay `rules/skills/semantic_search.md`，canonical public skill 不加入 OpenCode 客户端协议。建议新增一节：

```markdown
## OpenCode Session 搜索输出

当用户明确要寻找、打开或继续以前的 OpenCode session 时：

1. 优先检索 contexts/ai_sessions/opencode/；需要补充其他来源时可搜索，但只有 source: opencode 能生成可执行链接。
2. 按 session_id 聚合 chunk，同一 session 不重复列出。
3. 默认返回 3-5 个候选；强匹配不足时明确写“以下可能相关”，不要编造唯一答案。
4. 每个候选展示 title、date、project short name，以及一段可核对的原文 excerpt。
5. session_id 必须来自 Markdown frontmatter metadata，不得根据文件名、标题或模型猜测。
6. 可执行链接严格写成 `[在 OpenCode 中打开](opencode://session/<session_id>)`。
7. source 不是 opencode、缺少 session_id、ID 格式非法时，只能给普通文件引用，不生成 opencode:// link。
8. 不把相似度分数显示给用户，不用 AI 摘要替代原文证据。
9. 链接是否仍能由当前 Host 打开，以客户端 GET /session/:id 验证为准；Agent 不宣称“已恢复”或“可继续”，除非另有实时验证。
10. 不自动打开链接，不要求客户端发送消息或执行工具。
```

这个 contract 属于 private overlay，因为它绑定了本 workspace 的 AI session archive 路径和私有客户端行为。public semantic-search skill 只提供通用 retrieval，不应该知道 `opencode://`。

### 2.3 推荐 Markdown 结构

```markdown
我找到 3 个可能相关的会话：

### 1. iOS 中文输入法提前发送

> 你当时提到：“中文输入法还在选字时，消息就被提前发送了……”

2026-06-18 · opencode_ios_client
[在 OpenCode 中打开](opencode://session/ses_example_1)

### 2. Composer UIKit bridge 调试

> Assistant：“问题发生在 markedTextRange 尚未结束时……”

2026-06-20 · opencode_ios_client
[在 OpenCode 中打开](opencode://session/ses_example_2)
```

链接文字必须是显式动作，不把标题或整段候选变成链接。候选正文已经承担 preview；点击 action 后直接 switch，不再弹二次确认。

### 2.4 Markdown 拦截与渲染

Chat 当前使用 MarkdownUI 渲染短消息，并在 `MessageRowView.ResolvedMarkdownView` 注入 `OpenURLAction`。assistant 消息当前先经过 `WorkspaceLinkResolver`；未知 scheme 会被拒绝。实现时按以下顺序处理：

```text
用户点击 URL
  -> OpenCodeDeepLinkParser 尝试解析
  -> 成功：交给 AppState deep-link router，返回 .handled
  -> 不是 opencode scheme：继续现有 WorkspaceLinkResolver
  -> http/https：系统外部打开
  -> workspace file：现有 Files 跳转
  -> unsafe/unknown：拒绝
```

系统 `.onOpenURL` 也调用同一个 `OpenCodeDeepLinkParser`，但不经过 WorkspaceLinkResolver。

用户消息中的链接可以保留可点击，因为仍然需要用户手势，且 deep link 只有只读导航权限。不能根据“assistant 消息可信”放宽 parser；所有来源使用同一白名单。

两个现有降级需要明确：

- 超大消息当前走 `LargeMessagePreview`，跳过 Markdown 渲染，因此其中的 deep link 不可点击。V1 接受这个限制；Agent 搜索结果应保持短小。
- 文件 Markdown 的 Web Preview 有另一套 JS bridge。V1 只要求 Chat message 支持 session action；不要顺手让任意 workspace Markdown 文件获得 action 能力。若以后需要，再让 Web Preview 显式接同一个 parser。

### 2.5 Overlay 与 Markdown 测试

#### 静态 contract fixture

准备不含真实数据的 synthetic archive：

- 两个 `source: opencode` session，各有合法 `session_id`。
- 一个 `source: claude_code` session。
- 一个缺失或非法 `session_id` 的 OpenCode 文件。
- 两个 chunk 指向同一 session，用于验证去重。

给定固定 query 后，输出 validator 检查：

- 所有 `opencode://session/` ID 都存在于 synthetic frontmatter。
- 非 OpenCode source 没有 action link。
- 同一 session 只出现一次。
- 每个 action link 附近有 title、date 和 excerpt。
- Markdown link destination 与可见文本分离。
- 没有真实路径、session ID 或私有内容进入 committed fixture。

静态 validator 不判断语言质量，只守 machine contract。

#### Prompt-level acceptance

Agent 行为不是纯函数，另设 opt-in acceptance test：

1. 使用 synthetic corpus 和固定 query。
2. 让真实 Agent 按 private overlay 调 semantic-search。
3. 保存输出到 gitignored temp。
4. 用同一 validator 检查 link contract。
5. 人工或 Agent 复核候选证据是否真的支持 query。

不要把 LLM acceptance 放进每次 unit test。它适合 overlay 变更后手动运行或定期运行。

#### Markdown renderer test

Tier 1 验证 MarkdownUI 能把 synthetic `opencode://session/ses_fixture` 交给 `OpenURLAction`。Tier 2 fixture XCUITest 验证真实 tap 后 router 被调用并切换 session。两层缺一不可：parser 通过不代表 renderer 会发出链接，renderer 显示蓝色文本也不代表点击接到了 App。

## 三、End-to-End 测试计划

### 3.1 测试分层

端到端不是一条昂贵测试覆盖所有内容。把故障面拆成四层：

| 层级 | 回答的问题 | 数据与依赖 |
| --- | --- | --- |
| Tier 1 | URI 和 Markdown contract 是否正确 | 纯 Swift / synthetic Markdown |
| Tier 2 | App 状态机和真实 UI 点击是否正确 | MockAPIClient / fixture app |
| Tier 3 | OS scheme、真实 server GET 和 session hydration 是否兼容 | 临时 4097 server / synthetic session |
| Tier 4 | 用户从自然语言搜索到继续对话的完整体验是否成立 | synthetic corpus + real Agent + Simulator |

### 3.2 Tier 2 deterministic UI 场景

场景 A：App warm，点击 assistant link。

```text
启动 UITEST_DEEP_LINK_FIXTURE
-> 当前标题 Source Session
-> 点击“在 OpenCode 中打开”
-> 标题变 Target Session
-> chat-input 仍可用
```

场景 B：非法 Markdown link。

```text
点击 malformed link
-> deep-link-error 出现
-> 标题仍为 Source Session
-> messages 未清空
```

场景 C：用 launch environment 模拟 cold pending URL。

```text
UITEST_INITIAL_DEEP_LINK=opencode://session/target-session
-> App 初始化 fixture state
-> restore flow 完成
-> pending route 被消费
-> 进入 Target Session
```

这个场景验证冷启动状态机，但不证明 iOS 已注册 scheme；系统注册由下一层验证。

### 3.3 Tier 3 system deep-link integration

使用独立 4097 或临时端口，不触碰用户正在使用的 4096：

1. 启动 disposable OpenCode server，cwd 指向临时 sandbox。
2. 通过真实 API 创建一个 synthetic target session，记录 ID。
3. 配置并启动 Simulator App，确认连接 4097。
4. 终止 App。
5. 执行：

```bash
xcrun simctl openurl booted "opencode://session/<synthetic_session_id>"
```

6. 断言 App 被启动，Chat title 等于 synthetic session title，`chat-input` 可见。
7. 再测 warm launch：App 保持前台，再次 `simctl openurl` 到第二个 synthetic session。
8. 删除测试创建的 sessions，停止临时 server。

补充失败场景：

- 合法格式但不存在的 session ID，显示 `deep-link-error`。
- App 当前项目与 target directory 不同，最终 Files/Chat directory 一致。
- soft-archived target 仍可打开。
- server 不可达时保留 pending 或显示连接错误，不切换当前 session。

Tier 3 只创建和删除 synthetic session，不发送会修改 workspace 的 prompt。凭证继续走 gitignored `.env` 或 `/tmp/opencode-ios-tier4-config.json`，不出现在命令行 artifact。

### 3.4 Tier 4 完整搜索到跳转

这条测试验证真正的产品闭环，但不进入每次提交：

```text
synthetic OpenCode session archive
-> rebuild/query semantic index
-> 用户在 Finder session 提自然语言问题
-> Agent 返回 3-5 个 Markdown candidates
-> 点击目标 deep link
-> iOS 切到原 session
-> 在 composer 输入 follow-up，但不发送
```

推荐 synthetic corpus 使用一个唯一、无隐私的概念，例如：

```text
“blue llama capacitor calibration”
```

完整步骤：

1. 在临时 workspace 和测试 server 创建 target session，消息中包含唯一概念。
2. 用 exporter 生成 synthetic Markdown，或直接准备符合真实 frontmatter contract 的 fixture。
3. 建立独立 temp semantic cache，不污染全局 `.knowledge_cache`。
4. 在 Finder session 询问语义相近但措辞不同的问题。
5. 等待 Agent 调 semantic-search 并输出候选。
6. validator 先确认 Markdown action link ID 与 target frontmatter 一致。
7. XCUITest 点击 action link。
8. 断言 Chat title、target message 片段和 composer 可见。
9. 在 composer 输入一段 synthetic follow-up，确认草稿属于 target session；不必真正发送。
10. 清理 temp server、sessions、Markdown、cache、截图和 xcresult。

Tier 4 验收重点：

- 用户是否看得懂为什么命中。
- action link 是否足够明显但不抢占正文。
- 从点击到目标 Chat 的 loading 是否清楚。
- 错误是否保留原上下文并提供恢复路径。
- 截图和 accessibility artifact 是否完全使用 synthetic 内容。

### 3.5 推荐验证命令

实现后按顺序执行，禁止并行 xcodebuild：

```bash
cd OpenCodeClient

xcodebuild build \
  -project "OpenCodeClient.xcodeproj" \
  -scheme "OpenCodeClient" \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4'

xcodebuild test \
  -project "OpenCodeClient.xcodeproj" \
  -scheme "OpenCodeClient" \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' \
  -only-testing:OpenCodeClientTests/OpenCodeDeepLinkTests \
  -only-testing:OpenCodeClientTests/OpenCodeClientTests \
  -parallel-testing-enabled NO

xcodebuild test \
  -project "OpenCodeClient.xcodeproj" \
  -scheme "OpenCodeClient" \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' \
  -only-testing:OpenCodeClientUITests/OpenCodeClientUITests/testAssistantSessionDeepLinkFixture \
  -only-testing:OpenCodeClientUITests/OpenCodeClientUITests/testColdPendingSessionDeepLinkFixture \
  -parallel-testing-enabled NO
```

实际 test symbol 以实现时的 target discovery 为准。测试产物写入 gitignored 目录；真实 session 内容、Host URL、凭证和全局 semantic cache 不进入截图、fixture 或 commit。

## 四、实施顺序

### Phase 1：Deep link vertical slice

1. 定义 `OpenCodeDeepLink` parser 和 unit tests。
2. 注册 `opencode` URL scheme。
3. 实现 AppState pending/router 与全局错误状态。
4. 在 ContentView 接 `.onOpenURL`，处理 cold/warm lifecycle。
5. 加 deterministic fixture UI test。
6. 用 `simctl openurl` 对 synthetic session 做一次 4097 integration。

Phase 1 完成后，即使没有 semantic-search，用户也能从任意文本来源点击已知 session link 打开 App。

### Phase 2：Chat Markdown action

1. 在 `ResolvedMarkdownView` 先拦截 OpenCode deep link，再走现有 WorkspaceLinkResolver。
2. 加 synthetic assistant message fixture。
3. 验证合法、非法和普通 http/file link 没有回归。
4. 给 action link 点击增加 opening/error 可观测状态。

### Phase 3：Semantic-search private overlay

1. 给 private overlay 增加 OpenCode session 输出 contract。
2. 建 synthetic archive 和静态 output validator。
3. 跑 prompt-level acceptance，确认 Agent 能返回 3-5 个候选和合法链接。
4. 运行完整 Tier 4 搜索到跳转场景。

### Phase 4：跨平台与增强

1. Android 注册相同 URI contract 和 intent filter。
2. 抽取跨平台 synthetic contract fixtures。
3. 评估 `?message=` 定位。
4. 评估稳定 server namespace 与跨 Host resolver。
5. 如需公开分发，迁移到唯一 scheme 或 Universal Link。

## 五、明确不做

- 不新增客户端 session 搜索页面。
- 不新增独立搜索 server endpoint。
- 不让 iOS 读取本地 SQLite、Markdown archive 或 semantic cache。
- 不把 deep link 扩展成任意 client action 或 command protocol。
- 不在 URL 中放 Host 凭证、本机 Profile UUID、绝对路径或用户 query。
- 不自动扫描并切换所有 Host。
- 不在 V1 恢复离线 archive DB。
- 不在 message scroll 尚未实现时接受 `?message=` 并假装定位成功。
- 不让 Agent 自动打开候选；必须保留用户点击动作。

## 六、现有代码接点

- App 入口尚未处理 URL：`OpenCodeClient/OpenCodeClient/OpenCodeClientApp.swift:15-37`。
- Root connection restore 和 foreground refresh：`OpenCodeClient/OpenCodeClient/ContentView.swift:546-576`、`623-640`。
- Chat Markdown 的 `OpenURLAction`：`OpenCodeClient/OpenCodeClient/Views/Chat/MessageRowView.swift:116-151`。
- 现有 workspace link 安全解析：`OpenCodeClient/OpenCodeClient/Utils/WorkspaceLinkResolver.swift:10-58`。
- 按 ID 获取 session：`OpenCodeClient/OpenCodeClient/Services/APIClient.swift:114-117`。
- session 切换和异步 hydration：`OpenCodeClient/OpenCodeClient/AppState+Sessions.swift:221-257`。
- project directory 状态：`OpenCodeClient/OpenCodeClient/AppState.swift:465-518`。
- AppState connection bootstrap：`OpenCodeClient/OpenCodeClient/AppState.swift:711-728`。
- 可复用 mock session result/error：`OpenCodeClient/OpenCodeClientTests/OpenCodeClientTests.swift:2739-2893`。
- 当前 fixture-driven UI 测试模式：`OpenCodeClient/OpenCodeClient/ContentView.swift:32-190`、`OpenCodeClient/OpenCodeClientUITests/OpenCodeClientUITests.swift:62-107`。
- 私有 semantic-search overlay：`../../../rules/skills/semantic_search.md`。
- 四层测试策略和 4097 约束：`docs/tests.md:45-128`、`130-206`。

## 七、验收清单

- [ ] `opencode://session/<id>` 能从系统冷启动 App。
- [ ] warm launch 和 Chat Markdown 点击走同一个 parser/router。
- [ ] 目标不在当前列表或项目时仍能打开。
- [ ] 失败不会清空或切换当前 session。
- [ ] unknown URI 不能触发网络、文件或写操作。
- [ ] assistant Markdown 同时保留 http、workspace file 和 session link 行为。
- [ ] private overlay 只从 OpenCode frontmatter 生成 action link。
- [ ] synthetic contract validator 能发现伪造 ID、错误 source 和重复 session。
- [ ] Tier 2 覆盖 warm/cold fixture，Tier 3 覆盖 `simctl openurl`，Tier 4 覆盖 Agent 搜索到跳转。
- [ ] 所有 committed fixture 不含真实 session、路径、Host、凭证或对话内容。

这份设计替代 `session_finder_design.md` 中“专门搜索 UI + utility session JSON contract”的主路径。保留其中关于 session availability、Host namespace 和离线 archive 的分析，但产品入口改为 Agent 对话中的 Markdown deep link。
