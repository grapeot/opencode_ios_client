# OpenCode iOS Client — Docs 索引

> 最后更新：2026-08-24（docs canonical 结构重整）。找任何文档先查这里。

## 顶层主文档（living）

| 文件 | 角色 | 状态 |
|---|---|---|
| `OpenCode_iOS_Client_PRD.md` | 产品需求（整个 client） | living |
| `OpenCode_iOS_Client_RFC.md` | 技术架构（整个 client） | living |
| `WORKING.md` | 进度、问题与决策记录（changelog） | living |
| `tests.md` | 测试体系设计（Tier 1–4） | living |
| `design.md` | 视觉设计 spec（Quiet Tech） | living |
| `OpenCode_Web_API.md` | OpenCode server HTTP API 参考（上游快照，以官方文档与 live `/doc` 为准） | living reference |
| `lessons.md` | 可复用经验 | living |

## features/ — 按 feature 的文档

| 目录 | feature | 文件 | 状态 |
|---|---|---|---|
| `client_capabilities/` | 设备能力（V0: Health export） | `prd.md` / `rfc.md` / `protocol.md` | V0 shipped；protocol 是 wire contract 的 source of truth |
| `context_compaction/` | 手动 context compaction | `design.md` | proposal only，未实现 |
| `session_finder/` | Session Finder | `design.md` | 设计草案 |
| `push_notifications/` | 推送通知 | `research.md` | 调研 |
| `localization/` | en/zh-Hans 双语 | `research.md` | 规划 |

## archive/ — 一次性工作记录与冻结决策（只进不改）

| 文件 | 内容 |
|---|---|
| `2026-06_markdown_web_preview_prd.md` / `_rfc.md` | Markdown Web Preview 子项目；决策已并入主 PRD §4.3.5 / 主 RFC §7.5（untracked，gitignored） |
| `2026-06_visual_writing_weapon_system.md` | 写作风格讨论稿 |
| `2026-07_yage_fix_work.md` | opencode-official fork 修复记录 |
| `2026-08_qwen38_rendering_fix.md` | qwen38 渲染修复记录（PR #145） |

## skills/（repo 根，agent-facing 操作 skill）

| 文件 | 角色 |
|---|---|
| `skills/client_capabilities.md` | 新增 client capability 的 canonical agent 入口 |
| `skills/operate_ios_simulator.md` | 模拟器操作层 |
| `skills/ui_test_tasks.md` | Tier 4 UI 测试任务 workflow |
| `skills/ui_test_prompts/` | Tier 4 测试 prompt |

## 其他

- `design_images/` — `design.md` 的 mockup 图（gpt-image-2 生成，非像素级实现稿）
- `logo_light.png` — logo

## 约定

- 顶层只放 living 主文档；feature 文档进 `features/<name>/`；一次性工作记录进 `archive/`（文件名带 `YYYY-MM_` 前缀）。
- `tmp_*` 文件是未跟踪的设计过程，不进 git、不进 archive、不作为 source of truth；结论必须蒸馏进正式文档。
- 新增能力按 `skills/client_capabilities.md` 的"输出位置"一节更新对应文档。
