import Foundation

enum L10n {
    enum Key: String, CaseIterable {
        case appChat
        case appClose
        case appDone
        case appLoading
        case appNoContent
        case appError
        case appSearchFiles
        case appSearchFilesTitle

        case commonOk
        case commonCancel

        case navFiles
        case navSettings
        case navPreview
        case navWorkspace

        case contentPreviewUnavailableTitle
        case contentPreviewUnavailableDescription
        case contentRefreshHelp

        case settingsTitle
        case settingsServerConnection
        case settingsAddress
        case settingsUsername
        case settingsPassword
        case settingsScheme
        case settingsStatus
        case settingsConnected
        case settingsDisconnected
        case settingsTestConnection
        case settingsConnectionTip
        case settingsEnableSshTunnel
        case settingsAfterEnableSshTip
        case settingsVpsHost
        case settingsSshPort
        case settingsVpsPort
        case settingsSetServerAddress
        case settingsKnownHost
        case settingsResetTrustedHost
        case settingsCopyPublicKey
        case settingsViewPublicKey
        case settingsReverseTunnelCommand
        case settingsNoTunnelCommand
        case settingsSshTunnel
        case settingsSshTunnelHelp
        case settingsAutoTheme
        case settingsLightTheme
        case settingsDarkTheme
        case settingsAppearance
        case settingsTheme
        case settingsSpeechRecognition
        case settingsAiBuilderBaseURL
        case settingsAiBuilderToken
        case settingsCustomPrompt
        case settingsTerminology
        case settingsTesting
        case settingsTested
        case settingsAbout
        case settingsServerVersion
        case settingsRotateKeyTitle
        case settingsRotateKeyPrompt
        case settingsPublicKeyTitle
        case settingsPublicKeyFooter
        case settingsCopyToClipboard
        case settingsPublicKeyCopied
        case settingsPublicKeyCopyFailed
        case settingsPublicKeyRotate
        case settingsPublicKeyErrorTitle
        case settingsCopyCommand
        case settingsCommandCopied
        case settingsUntrusted
        case settingsRotate

        case settingsConnecting

        case chatInputPlaceholder
        case chatSendFailed
        case chatRenameSession
        case chatRenameSessionPlaceholder
        case chatTitleField
        case chatSpeechTitle
        case chatSelectSessionFirst
        case chatSessionBusyMessage
        case chatNoMessages
        case chatSessionBusy
        case chatSessionRetrying
        case chatSessionIdle
        case chatTurnCompleted
        case chatSpeechTokenMissing
        case chatSpeechTesting
        case chatSpeechNotPassed
        case chatMicrophoneDenied
        case chatSessionStatusBusy
        case chatSessionStatusRetrying
        case chatSessionStatusIdle
        case chatPullToLoadMore
        case chatLoadingMoreHistory

        case permissionRequired
        case permissionAllowOnce
        case permissionAllowAlways
        case permissionReject

        case toolReason
        case toolCommandInput
        case toolPath
        case toolOutput
        case toolOpenInFileTree
        case toolOpenFile
        case toolSelectFile

        case patchFilesChangedOne
        case patchFilesChangedMany

        case contextUsageHelp
        case contextUsageClose
        case contextUsageTitle
        case contextUsageSectionSession
        case contextUsageSectionModel
        case contextUsageSectionTokens
        case contextUsageSectionCost
        case contextUsageTitleLabel
        case contextUsageIdLabel
        case contextUsageProviderLabel
        case contextUsageModelLabel
        case contextUsageLimitLabel
        case contextUsageTotalLabel
        case contextUsageInputLabel
        case contextUsageOutputLabel
        case contextUsageReasoningLabel
        case contextUsageCachedReadLabel
        case contextUsageCachedWriteLabel
        case contextUsageNoCostData
        case contextUsageLoadingConfig
        case contextUsageNoUsageData
        case contextUsageConfigNotLoaded

        case sessionTitle
        case sessionsTitle
        case sessionsEmptyTitle
        case sessionsEmptyDescription
        case sessionsClose
        case sessionsUntitled
        case sessionsFilesOne
        case sessionsFilesMany
        case sessionsStatusBusy
        case sessionsStatusRetry
        case sessionsStatusIdle
        case sessionsDelete
        case sessionsDeleteConfirmTitle
        case sessionsDeleteConfirmMessage
        case sessionsDeleteFailedTitle

        case fileLoading
        case fileError
        case fileBinary
        case fileNoContent
        case fileMarkdown
        case filePreview

        case errorConnectionFailed
        case errorServerError
        case errorInvalidResponse
        case errorUnauthorized
        case errorSessionNotFound
        case errorFileNotFound
        case errorOperationFailed
        case errorUnknown
        case errorAiBuilderTokenEmpty
        case errorInvalidBaseURL
        case errorServerAddressEmpty
        case errorWanRequiresHttps
        case errorUsingLanHttp
        case helpLanHttp
        case helpWanHttp

        case activityRetrying
        case activityThinking
        case activityDelegating
        case activityPlanning
        case activityGatheringContext
        case activitySearchingCodebase
        case activitySearchingWeb
        case activityMakingEdits
        case activityRunningCommands
        case activityGatheringThoughts
    }

    private static let en: [String: String] = [
        Key.appChat.rawValue: "Chat",
        Key.appClose.rawValue: "Close",
        Key.appDone.rawValue: "Done",
        Key.appLoading.rawValue: "Loading...",
        Key.appNoContent.rawValue: "No content",
        Key.appError.rawValue: "Error",
        Key.appSearchFiles.rawValue: "Search files",
        Key.appSearchFilesTitle.rawValue: "Search files",
        Key.commonOk.rawValue: "OK",
        Key.commonCancel.rawValue: "Cancel",
        Key.navFiles.rawValue: "Files",
        Key.navSettings.rawValue: "Settings",
        Key.navPreview.rawValue: "Preview",
        Key.navWorkspace.rawValue: "Workspace",
        Key.contentPreviewUnavailableTitle.rawValue: "Select file to preview",
        Key.contentPreviewUnavailableDescription.rawValue: "Choose file from Workspace, or use Open File in the Chat tool/patch cards.",
        Key.contentRefreshHelp.rawValue: "Refresh preview",

        Key.settingsTitle.rawValue: "Settings",
        Key.settingsServerConnection.rawValue: "Server Connection",
        Key.settingsAddress.rawValue: "Address",
        Key.settingsUsername.rawValue: "Username",
        Key.settingsPassword.rawValue: "Password",
        Key.settingsScheme.rawValue: "Scheme",
        Key.settingsStatus.rawValue: "Status",
        Key.settingsConnected.rawValue: "Connected",
        Key.settingsDisconnected.rawValue: "Disconnected",
        Key.settingsTestConnection.rawValue: "Test Connection",
        Key.settingsConnectionTip.rawValue: "AI Builder Base URL",
        Key.settingsEnableSshTunnel.rawValue: "Enable SSH Tunnel",
        Key.settingsAfterEnableSshTip.rawValue: "After enabling SSH Tunnel, tap Test Connection in Server Connection above.",
        Key.settingsVpsHost.rawValue: "VPS Host",
        Key.settingsSshPort.rawValue: "SSH Port",
        Key.settingsVpsPort.rawValue: "VPS Port",
        Key.settingsSetServerAddress.rawValue: "Set Server Address to 127.0.0.1:4096",
        Key.settingsKnownHost.rawValue: "Known Host",
        Key.settingsResetTrustedHost.rawValue: "Reset Trusted Host",
        Key.settingsCopyPublicKey.rawValue: "Copy Public Key",
        Key.settingsPublicKeyCopied.rawValue: "Public Key Copied",
        Key.settingsViewPublicKey.rawValue: "View Public Key",
        Key.settingsReverseTunnelCommand.rawValue: "Reverse Tunnel Command",
        Key.settingsNoTunnelCommand.rawValue: "Fill VPS Host, SSH Port, Username, and VPS Port to generate the reverse tunnel command.",
        Key.settingsSshTunnel.rawValue: "SSH Tunnel",
        Key.settingsSshTunnelHelp.rawValue: "Forwards iOS 127.0.0.1:4096 to VPS 127.0.0.1:<VPS Port>. 1) Copy the public key and add it to VPS ~/.ssh/authorized_keys. 2) Run the generated reverse tunnel command on your computer. 3) First connect uses TOFU to trust host key; later connections must match. 4) Set Server Address to 127.0.0.1:4096 and tap Test Connection above.",
        Key.settingsAutoTheme.rawValue: "Auto",
        Key.settingsLightTheme.rawValue: "Light",
        Key.settingsDarkTheme.rawValue: "Dark",
        Key.settingsAppearance.rawValue: "Appearance",
        Key.settingsTheme.rawValue: "Theme",
        Key.settingsSpeechRecognition.rawValue: "Speech Recognition",
        Key.settingsAiBuilderBaseURL.rawValue: "AI Builder Base URL",
        Key.settingsAiBuilderToken.rawValue: "AI Builder Token",
        Key.settingsCustomPrompt.rawValue: "Custom Prompt",
        Key.settingsTerminology.rawValue: "Terminology (comma-separated)",
        Key.settingsTesting.rawValue: "Testing...",
        Key.settingsTested.rawValue: "OK",
        Key.settingsAbout.rawValue: "About",
        Key.settingsServerVersion.rawValue: "Server Version",
        Key.settingsRotateKeyTitle.rawValue: "Rotate SSH Key?",
        Key.settingsRotateKeyPrompt.rawValue: "This will generate a new key pair. You will need to update the public key on your VPS.",
        Key.settingsPublicKeyTitle.rawValue: "Your Public Key",
        Key.settingsPublicKeyFooter.rawValue: "Add this key to your VPS: ~/.ssh/authorized_keys",
        Key.settingsCopyToClipboard.rawValue: "Copy to Clipboard",
        Key.settingsPublicKeyCopyFailed.rawValue: "Unable to load SSH public key.",
        Key.settingsPublicKeyRotate.rawValue: "Rotate Key",
        Key.settingsPublicKeyErrorTitle.rawValue: "Public Key Error",
        Key.settingsCopyCommand.rawValue: "Copy Command",
        Key.settingsCommandCopied.rawValue: "Command Copied",
        Key.settingsUntrusted.rawValue: "Untrusted",
        Key.settingsRotate.rawValue: "Rotate",
        Key.settingsConnecting.rawValue: "Connecting...",

        Key.chatInputPlaceholder.rawValue: "Ask anything...",
        Key.chatSendFailed.rawValue: "Send failed",
        Key.chatRenameSession.rawValue: "Rename Session",
        Key.chatRenameSessionPlaceholder.rawValue: "Input new title",
        Key.chatTitleField.rawValue: "Title",
        Key.chatSpeechTitle.rawValue: "Speech Recognition",
        Key.chatSelectSessionFirst.rawValue: "Please pick a session first",
        Key.chatSessionBusyMessage.rawValue: "Session is running, messages are not visible yet, refreshing...",
        Key.chatNoMessages.rawValue: "No messages yet",
        Key.chatSessionBusy.rawValue: "Busy",
        Key.chatSessionRetrying.rawValue: "Retrying...",
        Key.chatSessionIdle.rawValue: "Idle",
        Key.chatTurnCompleted.rawValue: "Completed",
        Key.chatSpeechTokenMissing.rawValue: "Speech recognition is not configured. Set AI Builder Token in Settings → Speech Recognition and tap Test Connection.",
        Key.chatSpeechTesting.rawValue: "AI Builder connection is being tested, please wait.",
        Key.chatSpeechNotPassed.rawValue: "AI Builder connection test failed. Go to Settings → Speech Recognition, tap Test Connection, and confirm it's OK before recording.",
        Key.chatMicrophoneDenied.rawValue: "Microphone permission denied",
        Key.chatSessionStatusBusy.rawValue: "Running",
        Key.chatSessionStatusRetrying.rawValue: "Retrying",
        Key.chatSessionStatusIdle.rawValue: "Idle",
        Key.chatPullToLoadMore.rawValue: "Pull down to load more history",
        Key.chatLoadingMoreHistory.rawValue: "Loading more history...",

        Key.permissionRequired.rawValue: "Permission Required",
        Key.permissionAllowOnce.rawValue: "Allow Once",
        Key.permissionAllowAlways.rawValue: "Allow Always",
        Key.permissionReject.rawValue: "Reject",

        Key.toolReason.rawValue: "Reason",
        Key.toolCommandInput.rawValue: "Command / Input",
        Key.toolPath.rawValue: "Path",
        Key.toolOutput.rawValue: "Output",
        Key.toolOpenInFileTree.rawValue: "Open \"%@\" in File Tree",
        Key.toolOpenFile.rawValue: "Open File",
        Key.toolSelectFile.rawValue: "Select file to open",

        Key.patchFilesChangedOne.rawValue: "%d file changed",
        Key.patchFilesChangedMany.rawValue: "%d files changed",

        Key.contextUsageHelp.rawValue: "Context usage",
        Key.contextUsageClose.rawValue: "Close",
        Key.contextUsageTitle.rawValue: "Context",
        Key.contextUsageSectionSession.rawValue: "Session",
        Key.contextUsageSectionModel.rawValue: "Model",
        Key.contextUsageSectionTokens.rawValue: "Tokens",
        Key.contextUsageSectionCost.rawValue: "Cost",
        Key.contextUsageTitleLabel.rawValue: "Title",
        Key.contextUsageIdLabel.rawValue: "ID",
        Key.contextUsageProviderLabel.rawValue: "Provider",
        Key.contextUsageModelLabel.rawValue: "Model",
        Key.contextUsageLimitLabel.rawValue: "Context limit",
        Key.contextUsageTotalLabel.rawValue: "Total",
        Key.contextUsageInputLabel.rawValue: "Input",
        Key.contextUsageOutputLabel.rawValue: "Output",
        Key.contextUsageReasoningLabel.rawValue: "Reasoning",
        Key.contextUsageCachedReadLabel.rawValue: "Cached read",
        Key.contextUsageCachedWriteLabel.rawValue: "Cached write",
        Key.contextUsageNoCostData.rawValue: "No cost data",
        Key.contextUsageLoadingConfig.rawValue: "Loading provider config...",
        Key.contextUsageNoUsageData.rawValue: "No usage data",
        Key.contextUsageConfigNotLoaded.rawValue: "Provider config not loaded",

        Key.sessionTitle.rawValue: "Session",
        Key.sessionsTitle.rawValue: "Sessions",
        Key.sessionsEmptyTitle.rawValue: "No Sessions",
        Key.sessionsEmptyDescription.rawValue: "Tap + to create one, or pull to refresh for existing sessions.",
        Key.sessionsClose.rawValue: "Close",
        Key.sessionsUntitled.rawValue: "Untitled",
        Key.sessionsFilesOne.rawValue: "%d file",
        Key.sessionsFilesMany.rawValue: "%d files",
        Key.sessionsStatusBusy.rawValue: "Running",
        Key.sessionsStatusRetry.rawValue: "Retrying",
        Key.sessionsStatusIdle.rawValue: "Idle",
        Key.sessionsDelete.rawValue: "Delete",
        Key.sessionsDeleteConfirmTitle.rawValue: "Delete Session",
        Key.sessionsDeleteConfirmMessage.rawValue: "Delete this session and all its messages? This cannot be undone.",
        Key.sessionsDeleteFailedTitle.rawValue: "Delete Failed",

        Key.fileLoading.rawValue: "Loading...",
        Key.fileError.rawValue: "Error",
        Key.fileBinary.rawValue: "Binary file",
        Key.fileNoContent.rawValue: "No content",
        Key.fileMarkdown.rawValue: "Markdown",
        Key.filePreview.rawValue: "Preview",

        Key.errorConnectionFailed.rawValue: "Connection failed: %@",
        Key.errorServerError.rawValue: "Server error: %@",
        Key.errorInvalidResponse.rawValue: "Server returned invalid response",
        Key.errorUnauthorized.rawValue: "Unauthorized; check your credentials",
        Key.errorSessionNotFound.rawValue: "Session not found",
        Key.errorFileNotFound.rawValue: "File not found: %@",
        Key.errorOperationFailed.rawValue: "Operation failed: %@",
        Key.errorUnknown.rawValue: "Unknown error: %@",
        Key.errorAiBuilderTokenEmpty.rawValue: "Token is empty",
        Key.errorInvalidBaseURL.rawValue: "Invalid base URL",
        Key.errorServerAddressEmpty.rawValue: "Server address is empty",
        Key.errorWanRequiresHttps.rawValue: "WAN address must use HTTPS",
        Key.errorUsingLanHttp.rawValue: "Using HTTP on LAN",
        Key.helpLanHttp.rawValue: "LAN: HTTP is allowed only on trusted local networks.",
        Key.helpWanHttp.rawValue: "WAN: HTTPS is required. HTTP will be blocked.",

        Key.activityRetrying.rawValue: "Retrying",
        Key.activityThinking.rawValue: "Thinking",
        Key.activityDelegating.rawValue: "Delegating",
        Key.activityPlanning.rawValue: "Planning",
        Key.activityGatheringContext.rawValue: "Gathering context",
        Key.activitySearchingCodebase.rawValue: "Searching codebase",
        Key.activitySearchingWeb.rawValue: "Searching web",
        Key.activityMakingEdits.rawValue: "Making edits",
        Key.activityRunningCommands.rawValue: "Running commands",
        Key.activityGatheringThoughts.rawValue: "Gathering thoughts"
    ]

    private static let zh: [String: String] = [
        Key.appChat.rawValue: "Chat",
        Key.appClose.rawValue: "关闭",
        Key.appDone.rawValue: "完成",
        Key.appLoading.rawValue: "加载中...",
        Key.appNoContent.rawValue: "暂无内容",
        Key.appError.rawValue: "错误",
        Key.appSearchFiles.rawValue: "搜索文件",
        Key.appSearchFilesTitle.rawValue: "搜索文件",
        Key.commonOk.rawValue: "确定",
        Key.commonCancel.rawValue: "取消",
        Key.navFiles.rawValue: "文件",
        Key.navSettings.rawValue: "设置",
        Key.navPreview.rawValue: "预览",
        Key.navWorkspace.rawValue: "Workspace",
        Key.contentPreviewUnavailableTitle.rawValue: "选择文件预览",
        Key.contentPreviewUnavailableDescription.rawValue: "在左侧 Workspace 选择文件，或在 Chat 的 tool/patch 卡片中点“打开文件”。",
        Key.contentRefreshHelp.rawValue: "刷新预览",

        Key.settingsTitle.rawValue: "设置",
        Key.settingsServerConnection.rawValue: "服务器连接",
        Key.settingsAddress.rawValue: "地址",
        Key.settingsUsername.rawValue: "用户名",
        Key.settingsPassword.rawValue: "密码",
        Key.settingsScheme.rawValue: "协议",
        Key.settingsStatus.rawValue: "状态",
        Key.settingsConnected.rawValue: "已连接",
        Key.settingsDisconnected.rawValue: "未连接",
        Key.settingsTestConnection.rawValue: "测试连接",
        Key.settingsConnectionTip.rawValue: "AI Builder Base URL",
        Key.settingsEnableSshTunnel.rawValue: "启用 SSH 隧道",
        Key.settingsAfterEnableSshTip.rawValue: "开启 SSH 隧道后，请在上方 Server Connection 点击 Test Connection。",
        Key.settingsVpsHost.rawValue: "VPS 地址",
        Key.settingsSshPort.rawValue: "SSH 端口",
        Key.settingsVpsPort.rawValue: "VPS 端口",
        Key.settingsSetServerAddress.rawValue: "将服务器地址设置为 127.0.0.1:4096",
        Key.settingsKnownHost.rawValue: "Known Host",
        Key.settingsResetTrustedHost.rawValue: "重置已信任主机",
        Key.settingsCopyPublicKey.rawValue: "复制公钥",
        Key.settingsPublicKeyCopied.rawValue: "公钥已复制",
        Key.settingsViewPublicKey.rawValue: "查看公钥",
        Key.settingsReverseTunnelCommand.rawValue: "反向隧道命令",
        Key.settingsNoTunnelCommand.rawValue: "请先填写 VPS Host、SSH Port、Username、VPS Port 来生成反向隧道命令。",
        Key.settingsSshTunnel.rawValue: "SSH 隧道",
        Key.settingsSshTunnelHelp.rawValue: "将 iOS 127.0.0.1:4096 转发到 VPS 127.0.0.1:<VPS Port>。1）将公钥加到 VPS ~/.ssh/authorized_keys。2）在本机运行生成的反向隧道命令。3）首次连接使用 TOFU 方式信任主机指纹，后续连接需匹配该主机。4）将 Server Address 设置为 127.0.0.1:4096 并点击上方 Test Connection。",
        Key.settingsAutoTheme.rawValue: "自动",
        Key.settingsLightTheme.rawValue: "亮色",
        Key.settingsDarkTheme.rawValue: "暗色",
        Key.settingsAppearance.rawValue: "外观",
        Key.settingsTheme.rawValue: "主题",
        Key.settingsSpeechRecognition.rawValue: "语音识别",
        Key.settingsAiBuilderBaseURL.rawValue: "AI Builder Base URL",
        Key.settingsAiBuilderToken.rawValue: "AI Builder Token",
        Key.settingsCustomPrompt.rawValue: "自定义提示词",
        Key.settingsTerminology.rawValue: "术语（逗号分隔）",
        Key.settingsTesting.rawValue: "测试中...",
        Key.settingsTested.rawValue: "可用",
        Key.settingsAbout.rawValue: "关于",
        Key.settingsServerVersion.rawValue: "Server Version",
        Key.settingsRotateKeyTitle.rawValue: "要更换 SSH Key 吗？",
        Key.settingsRotateKeyPrompt.rawValue: "这将生成新的一对密钥。请同步更新 VPS 上的公钥。",
        Key.settingsPublicKeyTitle.rawValue: "你的公钥",
        Key.settingsPublicKeyFooter.rawValue: "请将公钥添加到 VPS 的 ~/.ssh/authorized_keys",
        Key.settingsCopyToClipboard.rawValue: "复制到剪贴板",
        Key.settingsPublicKeyCopyFailed.rawValue: "无法加载 SSH 公钥。",
        Key.settingsPublicKeyRotate.rawValue: "旋转密钥",
        Key.settingsPublicKeyErrorTitle.rawValue: "公钥错误",
        Key.settingsCopyCommand.rawValue: "复制命令",
        Key.settingsCommandCopied.rawValue: "命令已复制",
        Key.settingsUntrusted.rawValue: "未信任",
        Key.settingsRotate.rawValue: "旋转",
        Key.errorServerAddressEmpty.rawValue: "服务器地址不能为空",
        Key.errorWanRequiresHttps.rawValue: "WAN 地址必须使用 HTTPS",
        Key.errorUsingLanHttp.rawValue: "正在使用 LAN HTTP",
        Key.settingsConnecting.rawValue: "连接中...",

        Key.chatInputPlaceholder.rawValue: "输入你的问题...",
        Key.chatSendFailed.rawValue: "发送失败",
        Key.chatRenameSession.rawValue: "重命名 Session",
        Key.chatRenameSessionPlaceholder.rawValue: "输入新标题",
        Key.chatTitleField.rawValue: "标题",
        Key.chatSpeechTitle.rawValue: "语音识别",
        Key.chatSelectSessionFirst.rawValue: "请选择一个 Session",
        Key.chatSessionBusyMessage.rawValue: "Session 正在运行中，消息尚未可见，正在刷新中…",
        Key.chatNoMessages.rawValue: "暂无消息",
        Key.chatSessionBusy.rawValue: "忙碌",
        Key.chatSessionRetrying.rawValue: "重试中",
        Key.chatSessionIdle.rawValue: "空闲",
        Key.chatTurnCompleted.rawValue: "已完成",
        Key.chatSpeechTokenMissing.rawValue: "语音识别未配置：请先到 Settings -> Speech Recognition 设置 AI Builder Token，并点击 Test Connection。",
        Key.chatSpeechTesting.rawValue: "AI Builder 正在测试连接，请稍候。",
        Key.chatSpeechNotPassed.rawValue: "AI Builder 连接未通过测试：请先到 Settings -> Speech Recognition 点击 Test Connection，确认 OK 后再录音。",
        Key.chatMicrophoneDenied.rawValue: "未授权麦克风权限",
        Key.chatSessionStatusBusy.rawValue: "运行中",
        Key.chatSessionStatusRetrying.rawValue: "重试中",
        Key.chatSessionStatusIdle.rawValue: "空闲",
        Key.chatPullToLoadMore.rawValue: "下拉加载更多历史消息",
        Key.chatLoadingMoreHistory.rawValue: "正在加载更多历史消息...",

        Key.permissionRequired.rawValue: "需要授权",
        Key.permissionAllowOnce.rawValue: "允许一次",
        Key.permissionAllowAlways.rawValue: "始终允许",
        Key.permissionReject.rawValue: "拒绝",

        Key.toolReason.rawValue: "原因",
        Key.toolCommandInput.rawValue: "命令 / 输入",
        Key.toolPath.rawValue: "路径",
        Key.toolOutput.rawValue: "输出",
        Key.toolOpenInFileTree.rawValue: "在 File Tree 中打开 %@",
        Key.toolOpenFile.rawValue: "打开文件",
        Key.toolSelectFile.rawValue: "选择要打开的文件",

        Key.patchFilesChangedOne.rawValue: "%d 文件已变更",
        Key.patchFilesChangedMany.rawValue: "%d 个文件已变更",

        Key.contextUsageHelp.rawValue: "上下文用量",
        Key.contextUsageClose.rawValue: "关闭",
        Key.contextUsageTitle.rawValue: "上下文",
        Key.contextUsageSectionSession.rawValue: "会话",
        Key.contextUsageSectionModel.rawValue: "模型",
        Key.contextUsageSectionTokens.rawValue: "Token",
        Key.contextUsageSectionCost.rawValue: "成本",
        Key.contextUsageTitleLabel.rawValue: "标题",
        Key.contextUsageIdLabel.rawValue: "ID",
        Key.contextUsageProviderLabel.rawValue: "提供商",
        Key.contextUsageModelLabel.rawValue: "模型名",
        Key.contextUsageLimitLabel.rawValue: "上下文上限",
        Key.contextUsageTotalLabel.rawValue: "总计",
        Key.contextUsageInputLabel.rawValue: "输入",
        Key.contextUsageOutputLabel.rawValue: "输出",
        Key.contextUsageReasoningLabel.rawValue: "推理",
        Key.contextUsageCachedReadLabel.rawValue: "缓存读",
        Key.contextUsageCachedWriteLabel.rawValue: "缓存写",
        Key.contextUsageNoCostData.rawValue: "无成本数据",
        Key.contextUsageLoadingConfig.rawValue: "正在加载 provider 配置...",
        Key.contextUsageNoUsageData.rawValue: "无使用数据",
        Key.contextUsageConfigNotLoaded.rawValue: "未加载 Provider 配置",

        Key.sessionTitle.rawValue: "会话",
        Key.sessionsTitle.rawValue: "会话",
        Key.sessionsEmptyTitle.rawValue: "暂无 Session",
        Key.sessionsEmptyDescription.rawValue: "点击右上角新建，或下拉刷新获取已有 Session",
        Key.sessionsClose.rawValue: "关闭",
        Key.sessionsUntitled.rawValue: "无标题",
        Key.sessionsFilesOne.rawValue: "%d 个文件",
        Key.sessionsFilesMany.rawValue: "%d 个文件",
        Key.sessionsStatusBusy.rawValue: "运行中",
        Key.sessionsStatusRetry.rawValue: "重试中",
        Key.sessionsStatusIdle.rawValue: "空闲",
        Key.sessionsDelete.rawValue: "删除",
        Key.sessionsDeleteConfirmTitle.rawValue: "删除会话",
        Key.sessionsDeleteConfirmMessage.rawValue: "确认删除这个会话及其全部消息吗？此操作无法撤销。",
        Key.sessionsDeleteFailedTitle.rawValue: "删除失败",

        Key.fileLoading.rawValue: "加载中...",
        Key.fileError.rawValue: "错误",
        Key.fileBinary.rawValue: "二进制文件",
        Key.fileNoContent.rawValue: "无内容",
        Key.fileMarkdown.rawValue: "Markdown",
        Key.filePreview.rawValue: "预览",

        Key.errorConnectionFailed.rawValue: "连接失败：%@",
        Key.errorServerError.rawValue: "服务器错误：%@",
        Key.errorInvalidResponse.rawValue: "服务器返回了无效的响应",
        Key.errorUnauthorized.rawValue: "未授权，请检查认证信息",
        Key.errorSessionNotFound.rawValue: "Session 不存在",
        Key.errorFileNotFound.rawValue: "文件不存在：%@",
        Key.errorOperationFailed.rawValue: "操作失败：%@",
        Key.errorUnknown.rawValue: "未知错误：%@",
        Key.errorAiBuilderTokenEmpty.rawValue: "Token 为空",
        Key.errorInvalidBaseURL.rawValue: "无效的 URL",
        Key.helpLanHttp.rawValue: "LAN: HTTP 允许，但建议仅在可信局域网内使用。HTTP 不安全。",
        Key.helpWanHttp.rawValue: "WAN: 需要 HTTPS（HTTP 会被阻止）。HTTP 不安全。",

        Key.activityRetrying.rawValue: "重试中",
        Key.activityThinking.rawValue: "思考中",
        Key.activityDelegating.rawValue: "委派任务",
        Key.activityPlanning.rawValue: "规划中",
        Key.activityGatheringContext.rawValue: "收集上下文",
        Key.activitySearchingCodebase.rawValue: "搜索代码库",
        Key.activitySearchingWeb.rawValue: "搜索网络",
        Key.activityMakingEdits.rawValue: "修改代码",
        Key.activityRunningCommands.rawValue: "执行命令",
        Key.activityGatheringThoughts.rawValue: "整理思路"
    ]

    private static var languageIsChinese: Bool {
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.lowercased().hasPrefix("zh")
    }

    static var dictionaries: ([String: String], [String: String]) {
        return (en, languageIsChinese ? zh : en)
    }

    static func t(_ key: Key) -> String {
        let translations = languageIsChinese ? zh : en
        return translations[key.rawValue] ?? en[key.rawValue] ?? key.rawValue
    }

    static func t(_ key: Key, _ arguments: CVarArg...) -> String {
        let template = t(key)
        guard !arguments.isEmpty else { return template }
        return String(format: template, locale: Locale.current, arguments)
    }

    static func sessionsFiles(_ count: Int) -> String {
        let key: Key = count == 1 ? .sessionsFilesOne : .sessionsFilesMany
        return t(key, Int32(clamping: count))
    }

    static func patchFilesChanged(_ count: Int) -> String {
        let key: Key = count == 1 ? .patchFilesChangedOne : .patchFilesChangedMany
        return t(key, Int32(clamping: count))
    }

    static func toolOpenFileLabel(path: String) -> String {
        return t(.toolOpenInFileTree, path)
    }

    static func helpForURLScheme(_ isLocal: Bool) -> String {
        return isLocal ? t(.helpLanHttp) : t(.helpWanHttp)
    }

    static func errorMessage(_ key: Key, _ detail: String) -> String {
        return t(key, detail)
    }

    static var missingEnglishKeys: [String] {
        Key.allCases.map(\.rawValue).filter { en[$0] == nil }
    }

    static var missingChineseKeys: [String] {
        Key.allCases.map(\.rawValue).filter { zh[$0] == nil }
    }
}
