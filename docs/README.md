# OpenCode iOS Client — Docs 索引

> 最后更新：2026-08-24（docs canonical 结构重整）。查阅与检索任何文档请先参考本索引。

## 顶层主文档（living）

| 文件 | 角色 | 状态 |
|---|---|---|
| `OpenCode_iOS_Client_PRD.md` | 产品需求（客户端全功能） | living |
| `OpenCode_iOS_Client_RFC.md` | 技术架构设计（客户端全链路） | living |
| `WORKING.md` | 进度、问题排查与决策记录（changelog） | living |
| `tests.md` | 测试体系设计规范（Tier 1–4） | living |
| `design.md` | 视觉设计 Spec（Quiet Tech 风格） | living |
| `OpenCode_Web_API.md` | OpenCode server HTTP API 参考（上游快照，以官方文档与 live `/doc` 为准） | living reference |
| `lessons.md` | 工程复盘与可复用经验 | living |

## features/ — 按 feature 的文档

| 目录 | feature | 文件 | 状态 |
|---|---|---|---|
| `client_capabilities/` | 设备能力扩展（V0: Health export） | `prd.md` / `rfc.md` / `protocol.md` | V0 shipped；protocol 是 wire contract 的 source of truth |
| `context_compaction/` | 手动 Context Compaction | `design.md` | proposal only，未实现 |
| `session_finder/` | Session Finder 智能会话检索 | `design.md` | 设计草案 |
| `push_notifications/` | 后台推送通知方案 | `research.md` | 调研 |
| `localization/` | en/zh-Hans 双语本地化 | `research.md` | Settings 已有 en/zh；research 文档偏旧 |

## archive/ — 一次性工作记录与冻结决策（只进不改）

| 文件 | 内容 |
|---|---|
| `2026-06_markdown_web_preview_prd.md` / `_rfc.md` | Markdown Web Preview 子项目设计；决策已并入主 PRD §4.3.5 / 主 RFC §7.5（untracked，gitignored） |
| `2026-06_visual_writing_weapon_system.md` | 视觉与写作风格讨论稿 |
| `2026-07_yage_fix_work.md` | opencode-official fork 修复记录 |
| `2026-08_qwen38_rendering_fix.md` | qwen38 渲染修复记录（PR #145） |

## skills/（repo 根，agent-facing 操作 skill）

| 文件 | 角色 |
|---|---|
| `skills/client_capabilities.md` | 新增 client capability 的 canonical agent 接入入口 |
| `skills/operate_ios_simulator.md` | iOS 模拟器自动化操作层 |
| `skills/ui_test_tasks.md` | Tier 4 UI 测试任务工作流（workflow） |
| `skills/ui_test_prompts/` | Tier 4 测试 Prompt 集合 |

## 其他

- `design_images/` — `design.md` 的 mockup 示意图（gpt-image-2 生成，非像素级最终实现稿）
- `logo_light.png` — 应用 Logo 图标

## 约定

- 顶层目录仅维护 living 主文档；单项功能文档统一归入 `features/<name>/`；一次性工作记录归档至 `archive/`（文件名前缀统一遵循 `YYYY-MM_` 规范）。
- `tmp_*` 文件属于未纳入版本跟踪的设计草稿，不进 git、不进 archive，亦不作为权威事实来源（source of truth）；关键结论须及时提炼沉淀至正式文档中。
- 新增客户端能力时，严格依照 `skills/client_capabilities.md` 中“输出位置”一节的规范同步更新对应文档。
