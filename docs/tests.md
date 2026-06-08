# OpenCode iOS Client 测试策略

日期：2026-06-03

本文件定义 OpenCode iOS 客户端的测试系统设计。逐次改动记录放在 `docs/WORKING.md`；这里回答体系问题：每一层测什么、为什么存在、怎么运行、依赖什么前提。

这套设计对齐 Android client 已经落地的 four-tier testing model，但按 iOS 现有架构重新解释。iOS 已有的 Swift Testing、`AppState` mock flow、fixture-driven XCUITest 都保留，只是重新归类；真实 server integration 和 LLM-driven UI 也有了最小闭环。

## 为什么分四层

四层不是按工具分，而是按它们回答的问题、成本和触发频率分。

第一，unit/contract 保护纯逻辑和数据契约。它不启动 app、不连 server，最快、最稳定，每次 commit 都应该跑。

第二，state/component 保护 client 内部状态机和 fixture UI。iOS 的优势在这里：`AppState` 可以注入 `MockAPIClient` 和 `MockSSEClient`，所以很多接近用户行为的状态流可以在不连真实 server 的情况下精确复现。fixture-driven XCUITest 也属于这一层：启动真实 app，但状态是测试注入的，用固定断言保护 view wiring。

第三，integration-UI 把 mock 拿掉，连真实 OpenCode server 和真实 session。它回答的是：server 当前真实返回的 endpoint、payload、SSE/tool part shape，client 还能不能 decode、加载并渲染。Tier 2 无法发现 server protocol drift，Tier 3 专门守这条边界。

第四，LLM-driven-UI 让 agent 驱动真实 app、读取 accessibility tree/截图，并按场景目标判断结果。下面三层都是过程确定性：断言写死，只能检查已经想到的东西。Tier 4 是结果确定性：给目标和验收标准，让 agent 自己操作、观察、等待和判断，用来发现没有提前写成断言的 UI/UX regression。Tier 4 可以使用 curated deterministic fixture；分层依据不是数据是否 curated，而是是否在真实 app/simulator 上产出可观察证据，并由 agent 做整屏 UX 判断。

这四层越往下越快、越确定、越适合每次提交；越往上越真实、越贵、越能发现未知问题。Tier 4 探明的问题，能固化的部分应该沉淀回 Tier 3 或 Tier 2；Tier 4 过程里写出的稳定 harness/CLI 也应该 check in，截图、`.xcresult`、临时 config 留在 gitignored 路径。

## 当前测试 Targets

当前工程暴露两个测试 target：

| Target | 框架 | 归属 | 当前状态 |
| --- | --- | --- | --- |
| `OpenCodeClientTests` | Swift Testing (`import Testing`) | Tier 1 + Tier 2 | 主力测试层 |
| `OpenCodeClientUITests` | XCTest UI Testing | Tier 2 | fixture UI / smoke guard |

主要文件：

- `OpenCodeClient/OpenCodeClientTests/OpenCodeClientTests.swift`
- `OpenCodeClient/OpenCodeClientTests/ReadToolCardIntegrationTests.swift`
- `OpenCodeClient/OpenCodeClientTests/ToolCardClassifierTests.swift`
- `OpenCodeClient/OpenCodeClientUITests/OpenCodeClientUITests.swift`
- `OpenCodeClient/OpenCodeClientUITests/ToolCardsUITests.swift`
- `OpenCodeClient/OpenCodeClientUITests/OpenCodeClientUITestsLaunchTests.swift`
- `ui_driver/`
- `docs/skill_operate_ios_simulator.md`
- `docs/skill_ui_test_tasks.md`
- `docs/ui_test_prompts/01_read_card_visible.md`

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

- `UITEST_SESSION_TREE_FIXTURE`：验证 child/subagent session 在 session list 里可见；当前 fixture 也包含 active/archived session tree，用来覆盖 archive section wiring。
- `UITEST_TOOL_CARDS_FIXTURE`：验证 tool card grid、merged tool calls row、展开后的内容。
- `UITEST_F3_TRANSCRIBING_FIXTURE`：验证 voice rail 在 agent running + transcribing 并行状态下仍保留 text review/send，并把 agent interrupt 降到 `⋯` 菜单。
- `UITEST_F3_RETRY_FIXTURE`：验证 preserved-audio retry 状态清楚表达“重试同一段音频”，并且恢复动作与 agent abort 语义分离。
- launch/input smoke：验证 app 启动、chat input 可达、长输入保持可滚动。

Tier 2 保护 client 内部状态编排和 view wiring，但它仍然运行在我们构造的世界里。server 改了 protocol，而 mock 还在发旧 payload，Tier 2 可能继续通过。所以它不能替代 Tier 3。

一个容易混淆的点：fixture-driven XCUITest 同时可以服务 Tier 2 和 Tier 4。只做固定断言时，它是 Tier 2；如果同一个 fixture 被用来启动真实 app、展开真实 UI、导出截图，再由 agent 读图判断布局、层级、视觉密度和 privacy，它就是 Tier 4 的 deterministic visual QA 模式。这个模式牺牲真实 server 数据，换来可重复、无 secret、可快速迭代的视觉证据，适合设计 polish 和 regression triage。

## Tier 3：integration

Tier 3 连接真实 OpenCode server、真实 session 和真实 server-produced message/tool part，再用固定断言验证 client 的契约。它的核心目标是发现 client-server 边界上的 drift。

当前最小落地是 `ReadToolCardIntegrationTests.swift`。它默认不运行 live path；只有设置 `OPENCODE_INTEGRATION_TESTS=1` 才会连真实 server。测试进程优先读 `ProcessInfo.processInfo.environment`，缺失时会从 repo root 的 gitignored `.env` 补齐 key，且不会覆盖已经存在的环境变量。

它做的事：

1. 连接本地测试 server，通常是 4097，避免碰用户正在使用的 4096。
2. 用真实 `APIClient` health check。
3. 创建真实 session。
4. 发送 read-only prompt：读取 `AGENTS.md`，明确禁止创建、编辑、写文件。
5. 轮询真实 messages，直到出现 read tool part。
6. 用真实 decode 结果和 `ToolCardClassifier` 验证 read tool part 能被识别为 read/file operation。
7. best-effort 删除创建的 session。

这版 Tier 3 先守真实 server -> client decode/classification contract，还不是完整 app navigation E2E。完整 UI 版本可以后续补：启动 app、配置 server、发送 prompt、看整屏 UI。

credential 和 model/agent 配置必须来自 gitignored `.env` 或 test runtime arguments，不写进源码、文档样例或 Xcode project。从 Android client 合并 `.env` 时只补缺失 key，不覆盖 iOS 已有值；`OPENCODE_SERVER_URL` 需要使用 iOS Simulator 可访问的宿主机地址，例如 `127.0.0.1`，不能沿用 Android emulator 专用的 `10.0.2.2`。未配置或 server 不可达时，这一层应该明确 skip/block，并报告原因；不要把环境缺失伪装成 app failure。

Tier 3 默认只跑 read 类安全场景。真实 write/edit 会写入当前 workspace，除非 server cwd 指向专用 sandbox，否则不允许在 Tier 3 触发。

Live run 示例：

```bash
xcodebuild test \
  -project "OpenCodeClient.xcodeproj" \
  -scheme "OpenCodeClient" \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' \
  -only-testing:OpenCodeClientTests/ReadToolCardIntegrationTests
```

本地 `.env` 至少需要包含 `OPENCODE_INTEGRATION_TESTS=1`、`OPENCODE_SERVER_URL`、`OPENCODE_AGENT`；如果 server 需要认证，还需要 `OPENCODE_USERNAME` / `OPENCODE_PASSWORD`。指定 model 时使用 `OPENCODE_MODEL_PROVIDER` / `OPENCODE_MODEL_ID`。

## Tier 4：LLM-driven UI

Tier 4 由 agent 驱动真实 app，读工具返回的 UI state/截图，根据用户场景和验收标准判断结果。它不追求穷举覆盖，目标是发现固定断言没有想到的问题，尤其是异步、时序、整屏可理解性和 UX regression。

当前 iOS 最小落地包括：

- `ui_driver/`：`simctl` backed Python CLI skeleton。
- `docs/skill_operate_ios_simulator.md`：操作层 skill。
- `docs/skill_ui_test_tasks.md`：Tier 4 测试任务 workflow。
- `docs/ui_test_prompts/01_read_card_visible.md`：第一条 read-card prompt。
- `OpenCodeClientUITests/testCaptureSessionArchiveFixtureScreenshot`：默认 skip 的 deterministic screenshot harness。设置 `TIER4_SCREENSHOT_PATH` 或 `/tmp/opencode-ios-tier4-config.json` 的 `screenshot_path` 后，它用 synthetic session tree fixture 启动真实 app、展开 Archive section，并把 PNG 写到指定路径。

`ui_driver` 支持 `devices`、`launch`、`screenshot`、`tree`、`run-xcuitest`、`configure-server`、`send-prompt`。其中 `tree` 有两种模式：不传 Xcode 参数时是诚实的 screenshot-only observation，返回 `observability: screenshot_only`、空 `nodes` / `compact`，并带 warning；传 `--project`、`--scheme`、`--destination` 时走 `Tier4DriverUITests/testAccessibilityObservationSnapshot`，返回 `observability: xcuitest_accessibility_snapshot` 和 XCTest summary。它仍然不伪装 Android 式完整 accessibility tree。需要精确 element 断言时，用 `run-xcuitest` 或 XCTest-backed `tree` 调用 focused UI harness；这比坐标点击或伪造 tree 更符合 iOS best practice。Tier 4 用截图、XCTest summary 和 agent 判断组合出 verdict，无法判断时报告 BLOCKED。

`configure-server` 和 `send-prompt` 的 live 4097 路径已经验证通过。driver 用 `/tmp/opencode-ios-tier4-config.json` 这个临时 `0600` 文件把配置传给 XCTest，命令行和 `xcodebuild_args` 不包含密码；password 输入走 paste/`Cmd+V`，JSON 输出会 redact stdout/stderr tail 里的 password。Xcode UI test 固定带 `-parallel-testing-enabled NO`，避免 clone runner 启动失败。

### Deterministic screenshot QA

对纯 UI/设计改动，优先使用 deterministic screenshot harness，而不是 live server 截图。live screenshot 会把 server 状态、credential、网络时序和真实 session 内容混进判断里；fixture screenshot 则只验证当前设计是否真实渲染到了 iPhone/iPad 上。它的成功标准不是“测试跑过”，而是截图能被读图复核。

运行方式：

```bash
# 写入 gitignored 临时配置；也可以改用 TIER4_SCREENSHOT_PATH 环境变量。
printf '{"screenshot_path":"%s"}\n' \
  "$PWD/tmp/visual_qa/session_archive_fixture.png" \
  > /tmp/opencode-ios-tier4-config.json

xcodebuild test \
  -project "OpenCodeClient.xcodeproj" \
  -scheme "OpenCodeClient" \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' \
  -only-testing:OpenCodeClientUITests/OpenCodeClientUITests/testCaptureSessionArchiveFixtureScreenshot \
  -parallel-testing-enabled NO
```

F3 voice composer 的 deterministic fixture 可以用同一层 UI test 单独跑：

```bash
xcodebuild test \
  -project "OpenCodeClient.xcodeproj" \
  -scheme "OpenCodeClient" \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' \
  -only-testing:OpenCodeClientUITests/OpenCodeClientUITests/testF3TranscribingComposerFixtureScreenshot \
  -only-testing:OpenCodeClientUITests/OpenCodeClientUITests/testF3RetryComposerFixtureScreenshot
```

同一条 harness 可以换 iPad destination 复用。截图建议写到 `tmp/visual_qa/`，不要提交。跑完必须打开图片检查：是否落在目标屏、是否展开了目标 section、是否存在系统弹窗或 stale UI、是否含真实私有内容、视觉层级是否符合设计意图。

这个 workflow 在 session archive 设计中暴露了两个固定断言抓不到的问题：第一，`DisclosureGroup`/系统 list row 会把 section header 变成笨重的默认 cell；第二，用负 top padding 去抵消 sheet/list inset 会让 `Active` header 被标题栏盖住。截图复核把这类 layout regression 变成可见证据，随后再把稳定行为沉淀回 fixture UI test。

这个结构保留 Android 已证明的原则：CLI 是 skeleton，agent 是判断层，test 是 prompt。不同点在于 iOS 没有 Android `uiautomator dump` 的等价低成本接口，所以当前用 XCTest 作为精确 UI 身份桥。`configure-server` 和 `send-prompt` 已经作为高层命令进入 `ui_driver`；后续如果补到可靠 iOS accessibility tree，再把通用 `tap-label` 一类命令接上。

Tier 4 不进每次 commit。它按需或定期运行；当 Tier 4 探明一个稳定可断言的行为后，把能固化的部分下沉到 Tier 3 或 Tier 2。

Tier 4 过程中产生的长期有用代码应进 repo，例如 launch fixture、XCTest screenshot harness、`ui_driver` 子命令、redaction/helper 脚本。一次性 artifacts 不进 repo，包括真实截图、fixture 截图、`.xcresult`、DerivedData、Xcode workspace `xcuserdata`、`/tmp/opencode-ios-tier4-config.json`、credential JSON。

## 贯穿全局的前提：UI 可观测性

Tier 2、Tier 3、Tier 4 都依赖稳定的 accessibility surface。需要测试或 agent 判断的 UI 元素必须有语义化的 `accessibilityIdentifier` / `accessibilityLabel`，不能靠坐标、颜色或排版细节。

当前 iOS tool card 已在 accessibility 层区分 read/write：

- file read：`toolcard.read.<basename>`，label `Read file <basename>`。
- write/edit/patch：`toolcard.write.<basename>`，label `Write file <basename>`。
- directory read：`toolcard.folder.<basename>`，label `Read directory <basename>`。
- merged non-file tools：`toolcard.toolcalls`。

`ToolCardsUITests` 使用 `UITEST_TOOL_CARDS_FIXTURE` 验证 read/write card 都能被 XCUITest 看见。write/edit/patch 的真实 server 场景不安全，但 write card 的渲染在 Tier 2 fixture 里覆盖。read card 同时由 Tier 2 fixture 和 Tier 3 real-server read path 覆盖。

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

`ui_driver` 自身测试：

```bash
cd ui_driver
.venv/bin/python -m pytest -q
```
