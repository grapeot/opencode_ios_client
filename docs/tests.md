# OpenCode iOS Client 测试策略

日期：2026-06-03

本文件定义 OpenCode iOS 客户端的测试系统设计。逐次改动记录放在 `docs/WORKING.md`；这里回答体系问题：每一层测什么、为什么存在、怎么运行、依赖什么前提。

这套设计对齐 Android client 已经落地的 four-tier testing model，但按 iOS 现有架构重新解释。iOS 已有的 Swift Testing、`AppState` mock flow、fixture-driven XCUITest 都保留，只是重新归类；新的缺口是 Tier 3 的真实 server integration-UI 和 Tier 4 的 LLM-driven UI。

## 为什么分四层

四层不是按工具分，而是按它们回答的问题、成本和触发频率分。

第一，unit/contract 保护纯逻辑和数据契约。它不启动 app、不连 server，最快、最稳定，每次 commit 都应该跑。

第二，state/component 保护 client 内部状态机和 fixture UI。iOS 的优势在这里：`AppState` 可以注入 `MockAPIClient` 和 `MockSSEClient`，所以很多接近用户行为的状态流可以在不连真实 server 的情况下精确复现。fixture-driven XCUITest 也属于这一层：启动真实 app，但状态是测试注入的。

第三，integration-UI 把 mock 拿掉，连真实 OpenCode server 和真实 session。它回答的是：server 当前真实返回的 endpoint、payload、SSE/tool part shape，client 还能不能 decode、加载并渲染。Tier 2 无法发现 server protocol drift，Tier 3 专门守这条边界。

第四，LLM-driven-UI 让 agent 驱动真实 app、读取 accessibility tree/截图，并按场景目标判断结果。下面三层都是过程确定性：断言写死，只能检查已经想到的东西。Tier 4 是结果确定性：给目标和验收标准，让 agent 自己操作、观察、等待和判断，用来发现没有提前写成断言的 UI/UX regression。

这四层越往下越快、越确定、越适合每次提交；越往上越真实、越贵、越能发现未知问题。Tier 4 探明的问题，能固化的部分应该沉淀回 Tier 3 或 Tier 2。

## 当前测试 Targets

当前工程暴露两个测试 target：

| Target | 框架 | 归属 | 当前状态 |
| --- | --- | --- | --- |
| `OpenCodeClientTests` | Swift Testing (`import Testing`) | Tier 1 + Tier 2 | 主力测试层 |
| `OpenCodeClientUITests` | XCTest UI Testing | Tier 2 | fixture UI / smoke guard |

主要文件：

- `OpenCodeClient/OpenCodeClientTests/OpenCodeClientTests.swift`
- `OpenCodeClient/OpenCodeClientTests/ToolCardClassifierTests.swift`
- `OpenCodeClient/OpenCodeClientUITests/OpenCodeClientUITests.swift`
- `OpenCodeClient/OpenCodeClientUITests/ToolCardsUITests.swift`
- `OpenCodeClient/OpenCodeClientUITests/OpenCodeClientUITestsLaunchTests.swift`

## Tier 1：unit / contract

Tier 1 是纯逻辑和数据契约测试，不需要真实 server，也不依赖 UI。位置在 `OpenCodeClientTests`，框架是 Swift Testing。

这一层已经比较成熟，覆盖：

- `Session` / `SessionStatus` / `Message` / `Part` decoding。
- `SSEEvent` payload shape。
- `TodoItem`、`Project`、`QuestionRequest` 等 API model。
- URL 修正、scheme 补全、路径规范化、文件路径提取。
- `ToolCardClassifier`：哪些 part 进入 file-card grid，哪些折叠进 merged tool calls row；目录 read 的识别和 entries parsing。

这一层回答的是：client 对它已知的输入格式和纯规则是否正确。它不证明真实 server 当前仍然发送这些格式；这个问题由 Tier 3 回答。

运行：

```bash
xcodebuild test \
  -project "OpenCodeClient.xcodeproj" \
  -scheme "OpenCodeClient" \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4'
```

新增纯逻辑、model decoding、path/URL/tool classification 行为时，优先补 Tier 1。

## Tier 2：state flow / fixture UI

Tier 2 使用 fake data 或 mocked dependency，但跑真实 client 状态机或真实 UI。它不连真实 server，成本低、可控、适合覆盖大量边界条件。

iOS 这一层有两种形态。

第一种是 `AppState` 状态流测试。`AppState` 可注入 `MockAPIClient` 和 `MockSSEClient`，所以测试可以精确控制 API 返回、错误、SSE event，并让真实 `AppState` 从状态 A 走到状态 B。现有覆盖包括：

- `loadSessions()` / `loadMoreSessions()`。
- `createSession()` / `deleteSession()` / fallback selection。
- `message.updated` / `message.part.updated` / `session.updated`。
- optimistic user row dedupe 和失败回滚。
- session tree、sidebar root-only helper、archived filtering。

第二种是 fixture-driven XCUITest。app 通过 launch arguments 注入 deterministic state，然后 UI test 操作真实 app：

- `UITEST_SESSION_TREE_FIXTURE`：验证 child/subagent session 在 session list 里可见。
- `UITEST_TOOL_CARDS_FIXTURE`：验证 tool card grid、merged tool calls row、展开后的内容。
- launch/input smoke：验证 app 启动、chat input 可达、长输入保持可滚动。

Tier 2 保护 client 内部状态编排和 view wiring，但它仍然运行在我们构造的世界里。server 改了 protocol，而 mock 还在发旧 payload，Tier 2 可能继续通过。所以它不能替代 Tier 3。

## Tier 3：integration-UI

Tier 3 连接真实 OpenCode server、真实 session 和真实 server-produced message/tool part，再用固定断言验证 client 的渲染契约。它的核心目标是发现 client-server 边界上的 drift。

这一层在 iOS 还需要系统化落地。第一条建议测试与 Android 的 `ReadToolCardIntegrationTest` 对齐：

1. 连接本地测试 server（优先 4097，避免碰用户正在使用的 4096）。
2. 用真实 API 创建 session。
3. 发送 read-only prompt，例如读取 `AGENTS.md` 第一行，明确禁止创建、编辑、写文件。
4. 轮询真实 messages，直到出现 read tool part。
5. 让真实 iOS decode/render path 消费这些 messages。
6. 断言 UI/accessibility 中存在 read file card。

第一版可以不用启动完整 app navigation。像 Android 一样，先通过 public API client 拿到真实 messages，再喂给真实渲染/状态路径，验证 decode + render contract。这样更小、更稳定，也不需要为了测试在生产 app 里加入额外入口。等这一层稳定后，再补完整 XCUITest 版本：启动 app、配置 server、发送 prompt、看整屏 UI。

credential 和 model/agent 配置必须来自 gitignored `.env` 或 test runtime arguments，不写进源码、文档样例或 Xcode project。未配置或 server 不可达时，这一层应该明确 skip/block，并报告原因；不要把环境缺失伪装成 app failure。

Tier 3 默认只跑 read 类安全场景。真实 write/edit 会写入当前 workspace，除非 server cwd 指向专用 sandbox，否则不允许在 Tier 3 触发。

## Tier 4：LLM-driven UI

Tier 4 由 agent 驱动真实 app，读 accessibility tree/截图，根据用户场景和验收标准判断结果。它不追求穷举覆盖，目标是发现固定断言没有想到的问题，尤其是异步、时序、整屏可理解性和 UX regression。

Android 已经证明的结构应该迁移到 iOS：

- `ui_driver` CLI 是 skeleton：把启动 app、配置 server、输入 prompt、读取 tree、截图、滚动查找这些机械动作封装成确定性命令。
- agent 是判断层：读命令返回的 tree/screenshot，决定是否等待、滚动、重试，并给出 PASS / FAIL / BLOCKED。
- 每个 test 是一个 prompt：描述目标、可做 setup、验收标准和安全边界，而不是写死点击坐标或逐步操作。
- 两个 skill 分层：一个操作层 skill 说明 iOS simulator/client 怎么驱动，一个测试任务 skill 说明如何用操作层完成 Tier 4。

iOS 版 `ui_driver` 可以建立在 `xcodebuild`、`xcrun simctl`、XCTest helper 或 Accessibility tooling 之上，但对 agent 的契约应保持简单：每个会改变 UI 的命令返回操作后的可读 UI state；截图存到 ignored artifact 目录；错误返回原始命令、exit code 和 stderr，方便定位。

第一条 Tier 4 prompt 可以对齐 Android：用户打开 app、连上 4097、发送 read-only prompt，并确认 UI 中出现一张明确标成 read 的 file card，同时不出现 write/edit card。

Tier 4 不进每次 commit。它按需或定期运行；当 Tier 4 探明一个稳定可断言的行为后，把能固化的部分下沉到 Tier 3 或 Tier 2。

## 贯穿全局的前提：UI 可观测性

Tier 2、Tier 3、Tier 4 都依赖稳定的 accessibility surface。需要测试或 agent 判断的 UI 元素必须有语义化的 `accessibilityIdentifier` / `accessibilityLabel`，不能靠坐标、颜色或排版细节。

当前 iOS tool card 使用 `toolcard.file.<basename>`、`toolcard.folder.<basename>`、`toolcard.toolcalls`。这足以证明 file card 存在，但不足以区分 read 与 write。要完整支持 four-tier strategy，需要把 read/write 在 accessibility 层暴露出来。推荐同时做两件事：

1. deterministic tests 使用稳定 identifier，例如 `toolcard.read.<basename>` / `toolcard.write.<basename>`。
2. agent 和无障碍使用 label，例如 `Read file <basename>` / `Write file <basename>` / `Read directory <basename>`。

write/edit/patch 的真实 server 场景不安全，但 write card 的渲染必须在 Tier 2 fixture 里覆盖。read card 则可以在 Tier 2 fixture 和 Tier 3/Tier 4 真实 read 场景里共同覆盖。

## 边界与安全

本地 OpenCode server 可能共享 `/Users/grapeot/co/knowledge_working` 工作目录。只要没有专用 sandbox，Tier 3 和 Tier 4 都只能触发 read 类 tool call。任何创建、编辑、写文件的 prompt 都越界。

截图和 UI tree 可能包含 server URL、用户名、session 内容或其他私人信息。Tier 4 artifact 必须写到 gitignored 目录，分享或提交前需要确认不含 token、密码、真实私有内容。

测试命令运行规则仍按项目 `AGENTS.md`：`xcodebuild build` 和 `xcodebuild test` 顺序执行，不并行，避免共享 DerivedData/build database 出现 `build.db: database is locked`。

## 推荐验证命令

常规代码或测试改动至少顺序跑：

```bash
xcodebuild build \
  -project "OpenCodeClient.xcodeproj" \
  -scheme "OpenCodeClient" \
  -destination 'generic/platform=iOS Simulator'

xcodebuild test \
  -project "OpenCodeClient.xcodeproj" \
  -scheme "OpenCodeClient" \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4'
```

Tier 3 额外需要本地测试 server、credential、agent/model 配置。Tier 4 额外需要 booted simulator、已安装 app、iOS `ui_driver` 及其 skill/prompt。

## 落地顺序

建议按这个顺序实现 four-tier：

1. 更新本文档，明确分层、现有测试归属和缺口。
2. 补 tool card read/write accessibility observability。
3. 扩展 Tier 2 fixture UI test，证明 read/write card 可区分。
4. 补 Tier 3 的最小 real-server read-card integration test。
5. 建 iOS `ui_driver` skeleton，并给它自己的 unit tests。
6. 写 `skill_operate_ios_simulator.md`、`skill_ui_test_tasks.md` 和第一条 Tier 4 prompt。
7. 跑通 Tier 1/Tier 2 常规测试，手动验证 Tier 3/Tier 4 的 read-only happy path。

这套顺序保证现有 unit/state/UI smoke 不丢失，同时把 Android 已落地的真实 server 和 LLM-driven 两层系统化迁移过来。
