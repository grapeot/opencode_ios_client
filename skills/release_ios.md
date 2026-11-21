# OpenCode iOS Client 发布手册

**常规 App Store Connect 上传只包含 iOS app。** Watch Ambient 仍属实验功能，只有明确改变发布范围时才随包发布。通用签名、导出和上传流程见 [iOS 发布 skill](https://github.com/grapeot/ios-development-skill/blob/master/skills/app_store_release.md)。

## 准备归档

1. `git fetch origin master` 后，用 `git worktree add --detach <临时目录> origin/master` 创建独立工作树，记录源提交。
2. 仅在临时工作树编辑 `OpenCodeClient/OpenCodeClient.xcodeproj/project.pbxproj`。从 `OpenCodeClient` iOS target 的 `buildPhases` 移除 `Embed Watch Content` 引用，再从 `dependencies` 移除 Watch companion target 引用。保留两处引用指向的定义和 Watch target 本身。
3. 用 `git diff` 确认恰好移除了这两行。临时打包改动不进 Git 历史。

## 归档、核验、上传

1. 固定满足项目 SDK 检查的 Xcode。本流程用 Xcode 27.1 验证过；每次发布前核对当前项目的 SDK 要求。运行 `xcodebuild archive`，使用 `OpenCodeClient` scheme、`Release` 配置和 `generic/platform=iOS`，以 `CURRENT_PROJECT_VERSION` 指定 App Store Connect 中尚未使用的 build number。归档、导出和日志放在 Git 不跟踪的目录。
2. 导出前检查 `.xcarchive` 内的 `Products/Applications/OpenCodeClient.app`，确认没有 `Watch/` 子目录。若导出错误提到 Watch bundle ID 或它的分发描述文件，先回查归档内容。
3. 本地导出 IPA 后，用 `unzip -Z1` 列出包内条目。列包失败，或出现 `Payload/OpenCodeClient.app/Watch/` 开头的条目，都要停下来；使用管道时也要检查列包命令的退出状态。再按通用 skill 核对 bundle ID、版本、build number、最低系统版本及分发签名。若导出报 `No Accounts`，在 Xcode → Settings → Accounts 恢复有分发权限的账号后重试。
4. 当前发布获得上传授权后，用同一份已核验的归档上传；本地导出和上传选项均设置 `manageAppVersionAndBuildNumber=false`，保持 build number 一致。报告 Apple 接收、处理完成或提交审核的实际状态。

**已验证**：源提交 `5538f7e` 使用 Xcode 27.1 生成 iOS-only 的 `1.0 (35)`。本地导出确认 IPA 不含 Watch，App Store Connect 接收后开始处理。
