# OpenCode iOS Client 测试策略

日期：2026-06-03

本文档系统阐述 OpenCode iOS 客户端的测试架构设计。日常改动记录请参阅 `docs/WORKING.md`；本文主要解答体系层面的核心问题：各测试层级分别验证什么、为何设立、如何运行以及依赖哪些前置条件。

这套设计对齐了 Android client 已落地的 four-tier testing model，并结合 iOS 现有架构进行了适配与重新梳理。工程既有的 Swift Testing、`AppState` mock flow 以及 fixture-driven XCUITest 均予以保留并归入对应层级；同时补充了真实 server integration 与 LLM-driven UI 的最小闭环。

## 为什么分四层

这四个层级并非依据测试工具划分，而是综合考虑了它们所回答的核心问题、执行成本以及触发频率。

首先，unit/contract 专注于保护纯业务逻辑与数据契约。这一层无需启动 app 或连接 server，执行速度最快、稳定性最高，应当在每次 commit 时运行。

其次，state/component 负责验证 client 内部状态机与 fixture UI。这也是 iOS 架构的一大优势：`AppState` 支持注入 `MockAPIClient` 与 `MockSSEClient`，因此大量贴近用户真实操作的状态流都可以在不依赖真实 server 的前提下精确复现。fixture-driven XCUITest 同样归属于该层：虽然启动了真实 app，但状态完全由测试用例注入，通过固定断言来确保 view wiring 正确。

再次，integration-UI 移除了 mock 依赖，直接连接真实的 OpenCode server 与真实 session。它核心回答的问题是：当 server 产生真实的 endpoint 响应、payload 数据以及 SSE/tool part shape 时，client 是否依然能够正确 decode、加载并完成渲染。Tier 2 无法捕捉 server 端发生的 protocol drift，而 Tier 3 正是用来把守这道边界。

最后，LLM-driven-UI 由 agent 驱动真实 app，通过读取 accessibility tree 与截图，对照具体场景目标对结果进行综合判定。前三层均属于过程确定性测试：断言规则预先写死，仅能覆盖已知且预料到的场景。而 Tier 4 则侧重于结果确定性：给出目标与验收标准后，由 agent 自主完成操作、观察、等待与评估，专门用于捕获未提前固化为断言的 UI/UX regression。Tier 4 同样可以使用 curated deterministic fixture；划分层级的标准并非数据是否经过预先构造（curated），而在于是否在真实 app/simulator 上生成了可观察的运行证据，并交由 agent 完成整屏级别的 UX 评估。

整体来看，层级越靠前（Tier 1/2），运行速度越快、确定性越高，越适合纳入日常提交流水线；层级越靠后（Tier 3/4），运行环境越真实、成本越高，也越能发掘潜在的未知缺陷。对于 Tier 4 探明的问题，凡是能够固化的验证逻辑，都应当逐步下沉沉淀到 Tier 3 或 Tier 2 中；在 Tier 4 探索过程中编写的稳定 harness 与 CLI 工具也应及时 check in，而运行产生的截图、`.xcresult` 以及临时 config 等产物则严格保留在 gitignored 路径下。

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
- `skills/operate_ios_simulator.md`
- `skills/ui_test_tasks.md`
- `skills/ui_test_prompts/01_read_card_visible.md`

## Tier 1：unit / contract

Tier 1 专注于纯逻辑与数据契约测试，既不需要依赖真实 server，也不涉及 UI 操作。测试位于 `OpenCodeClientTests`，采用 Swift Testing 框架。

该层级建设已相对成熟，主要覆盖：

- `Session` / `SessionStatus` / `Message` / `Part` decoding。
- `SSEEvent` payload shape。
- `TodoItem`、`Project`、`QuestionRequest` 等 API model。
- URL 修正、scheme 补全、路径规范化、文件路径提取。
- Client capability action/callback decoding、Pending/Outbox expiration 与幂等、权限和原 session continuation。
- `ToolCardClassifier`：哪些 part 进入 file-card grid，哪些折叠进 merged tool calls row；目录 read 的识别和 entries parsing。

这一层主要验证 client 针对已知输入格式与纯规则的处理是否正确。但它并不能证明真实 server 当前仍在发送符合该契约的数据格式；这一问题交由 Tier 3 验证。

运行：

```bash
xcodebuild test \
  -project "OpenCodeClient.xcodeproj" \
  -scheme "OpenCodeClient" \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4'
```

在新增纯逻辑、model decoding、path/URL 处理或 tool classification 逻辑时，应优先补充 Tier 1 测试。

## Tier 2：state flow / fixture UI

Tier 2 基于 fake data 或 mock 依赖来驱动真实的 client 状态机及真实 UI。由于无需连接真实 server，该层具备成本低、确定性强、可控度高的特点，非常适合覆盖各类边缘状态与异常分支。

在 iOS 工程中，这一层包含两种形态：

第一种是 `AppState` 状态流测试。由于 `AppState` 支持注入 `MockAPIClient` 与 `MockSSEClient`，测试用例可以精确控制 API 响应、错误注入及 SSE event 分发，从而驱动真实的 `AppState` 完成确定性的状态迁移。现有覆盖范围包括：

- `loadSessions()` / `loadMoreSessions()`。
- `createSession()` / `deleteSession()` / fallback selection。
- `message.updated` / `message.part.updated` / `session.updated`。
- optimistic user row dedupe 和失败回滚。
- session tree、sidebar root-only helper、archived filtering。

第二种是 fixture-driven XCUITest。app 在启动时通过 launch arguments 注入确定性的 deterministic state，随后由 UI test 驱动真实 app 进行操作验证：

- `UITEST_SESSION_TREE_FIXTURE`：验证 child/subagent session 在 session list 里可见；当前 fixture 也包含 active/archived session tree，用来覆盖 archive section wiring。
- `UITEST_TOOL_CARDS_FIXTURE`：验证 tool card grid、merged tool calls row、展开后的内容。
- `UITEST_F3_TRANSCRIBING_FIXTURE`：验证 voice rail 在 agent running + transcribing 并行状态下仍保留 text review/send，并把 agent interrupt 降到 `⋯` 菜单。
- `UITEST_F3_RETRY_FIXTURE`：验证 preserved-audio retry 状态清楚表达“重试同一段音频”，并且恢复动作与 agent abort 语义分离。
- `UITEST_CLIENT_CAPABILITY_FIXTURE`：验证 Health export 本地授权理由、仅这次、以后自动允许和取消入口。
- launch/input smoke：验证 app 启动、chat input 可达、长输入保持可滚动。

Tier 2 能够有效保护 client 内部的状态流转编排与 view wiring，但它本质上仍运行在测试构造的假定环境里。一旦 server 变更了 protocol 而 mock 仍在使用旧 payload，Tier 2 测试依然可能假性通过，因此它无法替代 Tier 3。

需要特别区分的是：fixture-driven XCUITest 可以同时服务于 Tier 2 和 Tier 4。当仅执行固定代码断言时，它属于 Tier 2；而当复用相同的 fixture 启动真实 app、展开目标 UI 并导出截图，再交由 agent 读图评估界面布局、层级结构、视觉密度与隐私合规性时，它便构成了 Tier 4 的 deterministic visual QA 模式。该模式虽然不使用真实 server 数据，但换取了高可复现、无敏感 secret、可快速迭代的视觉反馈证据，非常适合用于设计打磨与 UI 回归定损。

## Tier 3：integration

Tier 3 通过直连真实的 OpenCode server、创建真实 session 并接收 server 端实际生成的 message 与 tool part，借助固定断言来验证 client 的契约正确性。其核心目标在于尽早捕获 client 与 server 接口边界上的协议漂移（drift）。

目前该层级的最小落地实现为 `ReadToolCardIntegrationTests.swift`。该测试默认跳过 live path，仅在显式设置环境变量 `OPENCODE_INTEGRATION_TESTS=1` 时才会真正连接测试 server。测试进程会优先读取 `ProcessInfo.processInfo.environment`，若缺少对应配置，则会从 repo root 下被 git 忽略的 `.env` 中按需补齐缺失 key，同时确保不覆盖已存在的环境变量。

其完整执行流程包括：

1. 连接本地测试 server，通常是 4097，避免碰用户正在使用的 4096。
2. 用真实 `APIClient` health check。
3. 创建真实 session。
4. 发送 read-only prompt：读取 `AGENTS.md`，明确禁止创建、编辑、写文件。
5. 轮询真实 messages，直到出现 read tool part。
6. 用真实 decode 结果和 `ToolCardClassifier` 验证 read tool part 能被识别为 read/file operation。
7. best-effort 删除创建的 session。

当前版本的 Tier 3 重点把守真实 server -> client 的 decode 与 classification 契约，尚未包含完整的 app 端到端 UI 导航链路。后续可进一步扩展完整 UI 版本：拉起 app、配置 server 连接、下发 prompt 并对整屏 UI 表现进行端到端检验。

相关的 credential 以及 model/agent 配置必须通过 gitignored `.env` 或测试运行参数提供，严禁硬编码进源码、文档示例或 Xcode project。在从 Android client 合并 `.env` 配置时，应仅补充缺失的 key，不覆盖 iOS 现存配置；此外，`OPENCODE_SERVER_URL` 须使用 iOS Simulator 能够正常访问的宿主机地址（如 `127.0.0.1`），不可直接复用 Android emulator 专用的 `10.0.2.2`。当未检测到配置或 server 不可达时，测试应当明确执行 skip/block 并输出具体原因，避免将环境缺失误报为 app 自身的功能故障。

Tier 3 默认仅允许执行只读类安全场景。真实的 write/edit 操作会直接修改当前 workspace，除非 server cwd 明确指向专用的隔离 sandbox，否则严禁在 Tier 3 中触发写操作。

Live run 示例：

```bash
xcodebuild test \
  -project "OpenCodeClient.xcodeproj" \
  -scheme "OpenCodeClient" \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' \
  -only-testing:OpenCodeClientTests/ReadToolCardIntegrationTests
```

本地 `.env` 至少需配置 `OPENCODE_INTEGRATION_TESTS=1`、`OPENCODE_SERVER_URL` 及 `OPENCODE_AGENT`；若 server 开启了鉴权，还需提供 `OPENCODE_USERNAME` / `OPENCODE_PASSWORD`。如需指定 model，可通过 `OPENCODE_MODEL_PROVIDER` / `OPENCODE_MODEL_ID` 配置。

## Tier 4：LLM-driven UI

Tier 4 由 agent 实际驱动真实 app，通过解析工具返回的 UI 状态或截屏，对照用户业务场景与验收准则自主作出判定。该层级并不追求全量穷举覆盖，其核心在于发现固定代码断言难以预料的隐性问题，尤其是涉及异步时序、整屏信息可读性以及交互体验退化等 UX regression。

当前 iOS 端落地的最小闭环包括：

- `ui_driver/`：`simctl` backed Python CLI skeleton。
- `skills/operate_ios_simulator.md`：操作层 skill。
- `skills/ui_test_tasks.md`：Tier 4 测试任务 workflow。
- `skills/ui_test_prompts/01_read_card_visible.md`：第一条 read-card prompt。
- `OpenCodeClientUITests/testCaptureSessionArchiveFixtureScreenshot`：默认 skip 的 deterministic screenshot harness。设置 `TIER4_SCREENSHOT_PATH` 或 `/tmp/opencode-ios-tier4-config.json` 的 `screenshot_path` 后，它用 synthetic session tree fixture 启动真实 app、展开 Archive section，并把 PNG 写到指定路径。

`ui_driver` 目前支持 `devices`、`launch`、`screenshot`、`tree`、`run-xcuitest`、`configure-server` 以及 `send-prompt` 等子命令。其中 `tree` 命令提供两种工作模式：在未传入 Xcode 参数时，执行诚实的 screenshot-only observation，返回 `observability: screenshot_only`、空的 `nodes` / `compact` 并附带 warning 提示；而在传入 `--project`、`--scheme`、`--destination` 参数时，则会调用 `Tier4DriverUITests/testAccessibilityObservationSnapshot`，返回 `observability: xcuitest_accessibility_snapshot` 以及对应的 XCTest summary。这里依然不做 Android 式完整 accessibility tree 的失真模拟。当需要精确断言特定 UI element 时，建议通过 `run-xcuitest` 或基于 XCTest 的 `tree` 命令触发聚焦的 UI harness，这比硬编码坐标点击或构造虚假 tree 更符合 iOS 平台的最佳工程实践。Tier 4 综合利用截图证据、XCTest summary 以及 agent 的自主认知输出最终 verdict；在信息不足以得出结论时明确报告 BLOCKED。

`configure-server` 与 `send-prompt` 在 live 4097 测试端口下的执行链路已验证通过。driver 借助权限为 `0600` 的临时文件 `/tmp/opencode-ios-tier4-config.json` 向 XCTest 传递运行配置，确保命令行与 `xcodebuild_args` 中不泄露任何明文密码；对于 password 输入，统一通过 paste/`Cmd+V` 注入，且 JSON 输出会对 stdout/stderr 尾部日志中的敏感 password 进行脱敏（redact）。此外，Xcode UI test 固定显式指定 `-parallel-testing-enabled NO`，防止因 clone runner 冲突导致测试启动失败。

### Deterministic screenshot QA

在处理纯 UI 布局或视觉设计改动时，应优先采用 deterministic screenshot harness，而非依赖 live server 的动态截图。live screenshot 容易将 server 运行状态、账号凭证、网络波动时序以及动态 session 数据掺杂进测试评估中；而 fixture screenshot 则专注于检验当前界面设计是否在 iPhone/iPad 上得到了精准渲染。该流程的成功验收标准并非单纯的“测试用例执行通过”，而在于产出的截图能够通过读图人工或智能复核。

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

同一套 harness 仅需切换 destination 即可复用到 iPad 设备验证。截图产物建议输出至 `tmp/visual_qa/` 目录下，严禁提交入库。执行完成后必须打开图像逐项核验：界面是否正确停留在目标页面、目标 section 是否已正常展开、是否存在未预期的系统弹窗或陈旧 UI 残留、是否泄露真实私有数据，以及整体视觉层级是否严格符合设计预期。

在 session archive 功能的设计实践中，该 workflow 成功捕获了固定代码断言未能发现的两个典型问题：其一，`DisclosureGroup` 与系统 list row 的组合容易导致 section header 退化为视觉笨重的默认样式 cell；其二，尝试通过负向 top padding 抵消 sheet/list 内边距的做法，会导致 `Active` header 在特定视口下被上方标题栏遮挡。截图复核机制将此类布局退化（layout regression）转化为直观可见的确定性证据，从而便于后续将修复后的稳定交互行为下沉沉淀到 fixture UI test 中。

该架构延续了在 Android 端得到验证的核心理念：CLI 充当骨架（skeleton），agent 充当智能决策判断层，test 用例即是 prompt。不同之处在于，iOS 平台缺乏类似于 Android `uiautomator dump` 那样低开销的直接导出接口，因此现阶段采用 XCTest 作为精确识别 UI 身份的桥梁。目前 `configure-server` 与 `send-prompt` 已作为高阶命令封装进 `ui_driver`；后续若能建立起稳定可靠的 iOS accessibility tree 解析能力，将进一步接入通用的 `tap-label` 等交互指令。

Tier 4 测试无需纳入每次 commit 的日常触发链路，通常按需触发或定期执行。当 Tier 4 探索并明确了某种具备稳定断言特征的交互行为后，应及时将可固化部分下沉至 Tier 3 或 Tier 2 中维护。

在 Tier 4 实施过程中沉淀出的具备长期维护价值的代码应纳入版本库（如 launch fixture、XCTest screenshot harness、`ui_driver` 子命令以及脱敏/辅助脚本等）；而各类单次运行产生的一次性 artifacts 严禁入库，具体包括真实截图、fixture 截图、`.xcresult`、DerivedData 缓存、Xcode workspace 的 `xcuserdata`、临时配置文件 `/tmp/opencode-ios-tier4-config.json` 以及包含凭证的 credential JSON。

## 贯穿全局的前提：UI 可观测性

Tier 2、Tier 3 与 Tier 4 的有效运作均高度依赖于稳定、语义化的 accessibility surface。凡是需要供自动化测试断言或 agent 感知判断的 UI 元素，必须显式声明清晰的 `accessibilityIdentifier` 与 `accessibilityLabel`，严禁依赖脆弱的绝对坐标、视图颜色或排版间距等渲染细节。

目前 iOS 端 tool card 组件已在 accessibility 层对 read/write 操作进行了细致区分：

- file read：`toolcard.read.<basename>`，label `Read file <basename>`。
- write/edit/patch：`toolcard.write.<basename>`，label `Write file <basename>`。
- directory read：`toolcard.folder.<basename>`，label `Read directory <basename>`。
- merged non-file tools：`toolcard.toolcalls`。

`ToolCardsUITests` 通过 `UITEST_TOOL_CARDS_FIXTURE` 确保 read 与 write 类型的卡片均能在 XCUITest 中被正确捕获识别。鉴于在真实 server 上执行 write/edit/patch 操作存在安全隐患，write card 的 UI 渲染主要依托 Tier 2 fixture 开展验证；而 read card 则由 Tier 2 fixture 与 Tier 3 真实 server 的 read 路径提供双重覆盖保障。

## 边界与安全

本地运行的 OpenCode server 可能会共享 `/Users/grapeot/co/knowledge_working` 工作目录。在未配置专用隔离 sandbox 的情况下，Tier 3 与 Tier 4 仅被允许触发只读（read）类 tool call。任何包含新建、修改或写文件意图的 prompt 均被视为越界操作，必须严格禁止。

自动化测试产出的截图及 UI tree 中可能携带 server URL、用户名、session 详情或其他敏感隐私信息。因此 Tier 4 生成的所有 artifact 必须强制输出至 gitignored 目录；在对外共享或提交之前，须严格核验确保未夹带 token、密码或真实私有数据。

测试命令的执行规则须严格遵循项目 `AGENTS.md` 规范：`xcodebuild build` 与 `xcodebuild test` 必须按序串行执行，严禁并发运行，以避免因共享 DerivedData / build database 出现 `build.db: database is locked`。

## 推荐验证命令

日常进行业务代码或测试用例修改后，应至少按序执行如下构建与测试命令：

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

若要运行 Tier 3，还需额外准备本地测试 server、认证凭据以及 agent/model 配置；若要运行 Tier 4，则需确保目标 simulator 已处于 booted 状态、app 已预装，并就绪 iOS `ui_driver` 及其配套 skill/prompt。

执行 `ui_driver` 自带的单元测试：

```bash
cd ui_driver
.venv/bin/python -m pytest -q
```
