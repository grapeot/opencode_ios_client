# OpenCode iOS Client 测试体系

日期：2026-05-01

## 文档目的

这份文档不是单纯的测试计划，而是当前项目测试系统的说明文档。它主要回答三件事：

1. 现在这个项目已经有哪些测试层。
2. 这些测试各自负责保护什么。
3. 后续还值得继续补哪些 behavior guard。

这份文档的背景，是最近出现过一次 session 列表回归：底层能力本身没有消失，但用户可见的交互路径被改坏了。因此，这里不仅介绍现状，也把“什么行为值得被自动化测试保护”讲清楚。

## 当前测试 Target

仓库当前有两个测试 target：

| Target | 框架 | 主要作用 | 当前状态 |
| --- | --- | --- | --- |
| `OpenCodeClientTests` | Swift Testing（`import Testing`） | 单元测试、契约测试、状态流测试 | 主力测试层 |
| `OpenCodeClientUITests` | XCTest UI Testing | 启动与关键交互 smoke test | 轻量但有效 |
| `OpenCodeClientVision` | xcodebuild target build | visionOS 原生 target 编译 smoke | 保护平台条件编译与 target 配置 |

## 主要测试文件

- `OpenCodeClient/OpenCodeClientTests/OpenCodeClientTests.swift`
- `OpenCodeClient/OpenCodeClientUITests/OpenCodeClientUITests.swift`
- `OpenCodeClient/OpenCodeClientUITests/OpenCodeClientUITestsLaunchTests.swift`

## 当前测试系统的结构

### 1. 契约测试（contract tests）

这层主要保护服务端返回结构和本地模型之间的契约。

当前已经覆盖的例子包括：

- `Session` / `SessionStatus` 解码
- `Message` / `Part` 解码
- `SSEEvent` 各种 payload 结构
- `TodoItem`、`Project`、`QuestionRequest` 等模型解码

这类测试的价值在于：一旦 API 字段名、optional 字段、嵌套结构发生变化，可以尽早在本地测试里报出来，而不会等到 UI 里出现奇怪行为才发现。

### 2. 业务逻辑 / 纯状态测试

这层主要保护那些不需要真实网络和真实 UI 就能验证的规则。

当前已经覆盖的例子包括：

- URL 修正与 scheme 补全
- 路径规范化
- session 删除后的 fallback 选择
- session tree 构建
- message / session 分页 limit 计算

这类测试的优点是快、稳定、定位清晰，适合保护确定性的业务规则。

### 3. AppState 状态流测试

这是当前项目最有价值的一层。

`AppState` 可以注入 `MockAPIClient` 和 `MockSSEClient`，所以可以在不依赖真实网络的情况下验证：

- `loadSessions()`
- `loadMoreSessions()`
- `createSession()`
- `deleteSession()`
- `message.updated` / `message.part.updated` / `session.updated` 这类 SSE 驱动的状态变化

这一层的价值在于，它测试的不是孤立纯函数，而是真正贴近用户行为的“状态编排”。

### 4. UI smoke tests

这层目前保持得比较轻，但已经开始承担关键交互兜底职责。

当前已经有的 smoke coverage 包括：

- App 启动成功
- Chat tab 输入框可见
- Session list fixture 下 child session 仍然可见

UI smoke tests 的目标不是把所有视觉细节都测掉，而是保护那些“状态没坏，但接线错了，用户已经用不了”的问题。

## 为什么这个项目适合做行为测试

这个项目的一大优势，是 `AppState` 已经支持依赖注入：

- 测试时可以给它 `MockAPIClient`
- 测试时可以给它 `MockSSEClient`
- 不需要真的连服务器，就能精确控制输入和状态变化

这意味着很多原本只会在手工测试里发现的问题，其实都能前移到自动化测试里。

相比强耦合写法，这样做的好处是：

- 测试更快
- 测试更稳定
- 更容易构造边界条件
- 更容易复现时序型 bug

## 当前测试体系的优势

- `AppState` 相关逻辑已经具备较好的可测试性。
- 现有测试已经不只是测解码，也开始测状态编排和用户行为。
- session、SSE、删除 fallback、分页这些关键行为已经有不错基础。
- UI test 虽然轻，但现在已经可以开始承担行为 guard 的职责，而不只是做 launch check。

## 当前测试体系的缺口

当前系统最强的是：

- 数据契约正确性
- 局部状态逻辑正确性

当前系统相对薄弱的是：

- 跨 view / state seam 的行为保护

最近的 session 列表回归就是一个典型例子：

- `sessionTree` 本身没有坏
- `sidebarSessions` 本身也没有坏
- 真正坏的是 view 选错了数据源，导致用户可见行为退化成 root-only 列表

这说明仅有纯逻辑测试还不够，还需要少量但明确的 behavior guard。

## 当前已经补上的 P0 / P1 保护

这轮已经实际补上了两类保护，重点就是 session list 回归。

### P0：状态层 behavior guards

已补的重点断言包括：

1. `sessionTree` 仍然是完整层级结构的 canonical 列表。
2. `sidebarSessions` 仍然只是 root-only 分页 helper，而不是完整列表真相。
3. `loadMoreSessions()` 在补更多 root session 时，不能把 child hierarchy 从 canonical tree 里弄丢。
4. archived 过滤在 `sessionTree` 与 `sidebarSessions` 两侧保持一致。

这些测试主要落在：

- `SessionTreeTests`
- `AppStateFlowTests`

### P1：轻量 UI smoke guard

已补一条关键 smoke test：

- 在 UI test fixture 下打开 session list，验证 child session 真正可见。

这条测试的意义不是测视觉，而是防止未来再次出现“状态里有 child session，但列表 UI 实际只渲染 root sessions”的回归。

## 当前推荐的测试分层方式

后续建议继续把测试系统看成四层，各层分工明确：

| 层级 | 作用 | 代表对象 |
| --- | --- | --- |
| Layer 0 | 契约与解码保护 | model / SSE decoding tests |
| Layer 1 | 纯逻辑与确定性状态规则 | helper / property tests |
| Layer 2 | 带 mock 的状态流保护 | `AppState` flow tests |
| Layer 3 | 用户可见交互 reachability | UI smoke tests |

这个分层的目的，是避免两种极端：

- 要么全靠单元测试，接线错误测不出来
- 要么什么都扔给 UI test，导致测试又慢又脆

## 什么样的问题值得加 Behavior Guard

建议只给下面几类问题加 behavior guard：

- 对用户重要且必须持续可达的 workflow
- 跨多层的关键行为不变量
- 已经出现过、并且很容易在重构中再次出现的 bug 模式

典型例子：

- child / subagent session 在列表中仍然可见
- 删除当前 session 后自动选中正确 fallback
- 非当前 session 的 SSE 更新不会污染当前可见内容
- 发送消息后不会留下重复 optimistic user row

## 后续值得继续做的工作

### 1. 继续扩展高价值 P0 / P1 coverage

优先建议：

- session switch 后 conversation 内容切换的 smoke test
- 当前 session 删除后的 UI-level guard
- SSE reload 只作用于当前 session 的更明确行为测试

### 2. 把已知 bug 模式转成测试

当前最值得继续跟进的是“发送后偶发重复消息 / 底部 ghost row”问题。

目前的初步判断是：

- optimistic user message append 与真实消息 reload 的合并逻辑之间存在时序 race
- `session.status`、`message.updated`、streaming state 收口之间可能没有完全对齐
- session switch 会触发清理和 reload，所以肉眼上表现为“切出去再切回来就好了”

这个问题后续很适合转成：

- 一条状态流测试：保护 optimistic message merge
- 一条状态/UI 组合测试：保护 ghost row 不会在 session switch 前长期残留

### 3. 继续保持 UI smoke test 的节制

UI smoke tests 应该继续保持少而关键。

建议原则：

- 测 reachability，不测排版细节
- 测关键 workflow，不测所有分支
- 只在 view wiring 真正有回归风险时增加

## 改动时的默认规则

建议以后在这个项目里默认遵守下面这些规则：

1. 只要改动了用户可见 workflow，就在同一分支补一条回归测试，或者更新已有测试。
2. 如果改动的是 view 的数据源选择，必须补一条 guard，证明原有行为没有 silently regression。
3. 如果某个 bug 的表现是“切 session / 刷新 / 重进页面就好了”，要优先怀疑它是状态与展示之间的跨层问题，而不只是纯函数 bug。
4. UI tests 保持轻量，重点验证交互可达性。
5. 能用带 mock 的状态流测试覆盖的，优先不用重型端到端测试。

## 推荐验证方式

与测试系统相关的改动，推荐至少跑：

```bash
xcodebuild build -project "OpenCodeClient.xcodeproj" -scheme "OpenCodeClient" -destination 'generic/platform=iOS Simulator'
xcodebuild test -project "OpenCodeClient.xcodeproj" -scheme "OpenCodeClient" -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4'
```

涉及 visionOS target、平台条件编译、或共享 SwiftUI view 的改动，还要跑：

```bash
xcodebuild -project "OpenCodeClient.xcodeproj" \
  -target "OpenCodeClientVision" \
  -configuration Debug \
  -sdk xrsimulator \
  CODE_SIGNING_ALLOWED=NO build
```

当前 `OpenCodeClientVision` 是编译 smoke target，还没有单独的 visionOS test bundle。它的主要保护面是：Xcode project target 配置正确、共享源码没有引用 visionOS unavailable API、visionOS 不链接 iOS-only/暂不支持的功能依赖，并且本地 patched MarkdownUI / NetworkImage package 链可以在 visionOS SDK 下完整编译。

Markdown 渲染相关改动还需要同时跑 iOS app build。原因是 iOS 与 visionOS 共用同一套 SPM 依赖（`grapeot/swift-markdown-ui` 与 `grapeot/NetworkImage` 的 pinned revision），visionOS build 只能证明 package patch 对 xrOS 可用，iOS build 才能证明这条依赖图没有破坏原有 iOS target。

如果遇到 simulator 本身的 creation / launch 问题，需要明确区分：

- 测试环境失败
- 代码逻辑失败

二者不能混为一谈。

## 总结

OpenCode iOS client 现在已经有了一套不错的测试骨架：契约测试、纯逻辑测试、状态流测试、轻量 UI smoke tests 四层都在，只是成熟度不同。

这份文档的核心观点是：后续不应该只是“再多写一些测试”，而应该有意识地把测试资源放到真正容易回归、用户又最敏感的行为上。session list 这轮回归保护是第一步，接下来应该继续把重复 optimistic row、ghost row、session switch 等问题逐步纳入 behavior guard 体系。
