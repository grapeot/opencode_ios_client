# Lessons — OpenCode iOS Client

> 从实现与 Code Review 过程中总结的可复用经验

## 0. 变更工作流：先对齐文档，再改代码

一个稳定且可复用的工作流（尤其适合这个 repo 这种「PRD/RFC 驱动 + 快速迭代」的项目）：

1. **先判断 PRD 是否受影响**：如果改动会影响产品行为/交互/范围（哪怕只是 iPad UI 行为），先更新 `docs/OpenCode_iOS_Client_PRD.md`
2. **再判断 RFC 是否受影响**：如果改动会影响技术方案/约束/阶段计划，更新 `docs/OpenCode_iOS_Client_RFC.md`
3. **再开始改 code**：按既定文档实现（或同步更新文档里的决策）
4. **补 test（如果应该有）**：能单测的逻辑尽量用单测锁住回归；UI 变化至少补关键的纯逻辑测试/模型解码测试
5. **编译通过 + 测试通过**：最后做 `xcodebuild build` + `xcodebuild test`，确保主流程无回归

Lesson：把“为什么这么做”放在 PRD/RFC 里，代码只负责“怎么做”。这样 review、回溯、以及后续迭代都更省力。

## 1. 直接验证 API，而非先写代码再猜

**场景**：调研 SSE 解析格式时，需要确认 OpenCode `/global/event` 实际返回什么。

**反模式**：先写假设、写代码、跑 iOS 客户端、从 log 里看 response。

**正确做法**：直接用 `curl` 或工具连 server 验证。例如：

```bash
curl -s -N -H "Accept: text/event-stream" "http://192.168.180.128:4096/global/event"
```

当场即可看到：`data: {"payload":{"type":"server.connected","properties":{}}}`，确认是单行 JSON。

**Lesson**：对外部 API 的调研，优先直接访问；能避免错误假设、减少无效实现。

---

## 2. 测试优先、小步快跑

**场景**：AppState 拆分、PathNormalizer 抽取、Session 过滤等 refactor。

**做法**：
- 拆分前先补 test coverage，覆盖核心逻辑
- 先写 test 规定 expected behavior，再 refactor
- 每做完一件事就 commit、更新 WORKING.md

**Lesson**：Test 是 refactor 的安全网；小步 commit 便于回滚与 review。

---

## 3. 用 Task List 组织任务，保证不重复、无遗漏

**场景**：Code Review 1.1–1.4 涉及多个任务：测试、拆分、SSE、session 过滤、PathNormalizer。

**做法**：用结构化 todo 列表管理，每完成一项标记为完成，避免遗漏或重复劳动。

**Lesson**：复杂任务拆成可追踪的 checklist，能显著减少「做到一半发现漏了」的情况。

---

## 4. API 实测 vs 规范假设

**场景**：SSE 规范里有多行 data、`event:`、comment keep-alive 等；Code Review 建议按规范实现。

**做法**：先实测 API，发现仅用单行 `data:`；当前实现已满足，无需过度实现。

**Lesson**：规范与实际实现可能不一致；先验证再决定投入，避免 over-engineering。

---

## 5. 拆分时保持对外 API 不变

**场景**：AppState 拆成 SessionStore/MessageStore/FileStore/TodoStore。

**做法**：通过 computed property 委托，保留 `state.messages`、`state.sessions` 等原有 API；View 无需改动。

**Lesson**：内部重构时尽量保持公共接口稳定，减少改动面和回归风险。

---

## 6. 多 Session 场景下的 SSE 过滤

**场景**：多 session 并发时，`message.updated` 未按 sessionID 过滤，导致跨 session 污染。

**做法**：基于 event 的 `sessionID` 过滤，仅处理当前 session 的事件。

**Lesson**：分布式/多租户场景下，事件要带 session/tenant 标识，并在客户端做过滤。

---

## 7. 跨模块逻辑集中到统一层

**场景**：路径规范化散落在 Message.swift、视图 trim 等处。

**做法**：抽到 `PathNormalizer`，统一处理 a/b 前缀、#、:line:col 等。

**Lesson**：跨模块的协议/规则应集中维护，避免重复实现与不一致。

---

## 8. @MainActor 与 test 可测性

**场景**：`shouldProcessMessageEvent` 在 AppState 内，测试调用时报错「main actor-isolated」。

**做法**：对纯逻辑函数加 `nonisolated`，使其可在 test 中同步调用。

**Lesson**：需单测的逻辑尽量抽成 nonisolated 或 static，减少与 MainActor 的耦合。

---

## 9. SSE-first 不等于“只靠 SSE”，要配一次性补偿同步

**场景**：iOS 前后台切换、网络抖动、切 session、重连后都可能错过部分 SSE 事件。

**做法**：
- 常态只用 SSE 推增量，避免 busy 常驻轮询
- 在关键时机（如 SSE 重连成功、进入会话）执行一次 bootstrap：`loadMessages + refreshPendingPermissions`
- 把 bootstrap 触发点和日志打清楚（reason / elapsed / messages / permissions）

**Lesson**：移动端实时系统要用“增量主通道 + 一次性全量补偿”组合，既稳又省电。

---

## 10. SSH 安全默认值：TOFU + mismatch hard fail

**场景**：SSH 隧道若直接 `acceptAnything`，等于关闭主机身份校验。

**做法**：
- 首次连接：TOFU 记录 host key（按 host:port）
- 后续连接：指纹不一致立即失败并提示风险（MITM/重装）
- UI 提供 fingerprint 展示与 reset trusted host

**Lesson**：远程能力一旦上线，安全基线必须先落地；“能连上”不是完成标准，“可信地连上”才是。

---

## 11. 复杂重构采用 Gate 式 Test-First

**场景**：AppState 拆分会跨状态机、SSE、UI 显示规则，回归风险高。

**做法**：
- 按 Iteration A/B/C/D 分轮，每轮先补测试，再改结构
- 每轮定义 Gate（例如行为测试全绿）再进入下一轮
- 每轮结束记录到 `WORKING.md`，说明新增测试与风险结论

**Lesson**：重构不是“大改一把梭”，而是可验证的增量迁移；Gate 比“感觉没问题”更可靠。

---

## 12. Activity 文案要有“防抖语义”，而不是盲目实时

**场景**：tool/reasoning 文案高频切换会导致 UI 抖动与体感噪声。

**做法**：
- 把文案推导与 debounce 逻辑收敛到统一逻辑层
- 规则明确：2.5s 窗口内延迟更新，窗口外立即更新
- 对 completed/running 的时长来源定义优先级，避免伪精确

**Lesson**：可读性是实时体验的一部分；“稳定且可信”的状态比“每次变化都立刻显示”更有价值。

---

## 13. SSH UX 需要把“用户下一步动作”写进界面

**场景**：用户常卡在“开了 SSH 但连不上 / 不知道下一步点哪里”。

**做法**：
- 提供可直接复制执行的 SSH command（降低脑内拼接成本）
- 公钥复制入口常驻可见，不与启用状态强耦合
- 在 SSH 区域明确提示：启用后还要到上方点 `Test Connection`

**Lesson**：配置型功能的核心不是字段齐全，而是“用户能一次走通”。把关键下一步直接写进 UI 文案。

---

## 14. 长会话弱网优化优先做“消息分页”，不是先重做渲染

**场景**：渲染优化后，LAN 已明显流畅，但 SSH tunnel/WAN 首屏仍慢。

**做法**：
- 先确认后端支持 `GET /session/:id/message?limit=`，再在客户端默认只拉最近 3 轮（6 条 message）
- 提供显式的“下拉加载更多历史消息”交互，每次按固定步长（+6）扩展
- 文案和状态做本地化，避免用户误解成“数据丢失”

**Lesson**：弱网场景下的首屏体验瓶颈通常是 payload 规模和往返时延。先做可控分页，往往比继续优化 View 层收益更大、更稳定。

---

## 15. 先澄清 message 语义，再做 limit 策略

**场景**：用户问“10 次 tool + 1 次最终回答，到底是 11 条 message 还是 1 条？”

**做法**：
- 对齐后端数据模型：tool 是 `part`，不是独立 `message`
- `limit` 限制的是 message 数，不是 tool 次数
- 在产品文档（PRD/RFC）中明确该语义，避免后续对“3 轮=6 条”的误解

**Lesson**：分页策略之前必须先统一计数口径。否则体验讨论会反复卡在“看起来像一条/实际上几条”的语义分歧上。


---

## 16. Session 与 Project 的 directory 过滤不匹配

**场景**：新建 session 后，点 Session List 或切后台回前台，新 session 消失。见 [session_disappear_investigation.md](session_disappear_investigation.md)。

**根因**：`POST /session` 不支持传 directory，server 在其 current project 下创建；iOS 的 `loadSessions()` 用 `effectiveProjectDirectory`（用户选的 project）过滤。当两者不一致时，新 session 不在 GET 结果中，`sessions = serverResponse` 覆盖后新 session 从列表消失。

**做法**：在 `loadSessions()` 中，若 `currentSessionID` 不在 server 返回列表，单独 `GET /session/:id` 拉取并 prepend，保证 `currentSession` 仍可解析。不依赖「选 project 时设为 server current」：OpenCode API 无 `PUT /project/current`。

**Lesson**：多 project 场景下，创建与列表过滤的 scope 必须一致；若 API 不支持创建时指定 project，客户端需防御性 merge。
