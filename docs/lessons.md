# Lessons — OpenCode iOS Client

> 从实现与 Code Review 过程中总结的可复用经验

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
