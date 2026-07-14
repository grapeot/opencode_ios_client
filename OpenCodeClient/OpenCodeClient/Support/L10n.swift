import Foundation

enum L10n {
    enum LanguagePreference: String, CaseIterable, Identifiable {
        case system
        case en
        case zh

        var id: String { rawValue }

        var localeIdentifier: String? {
            switch self {
            case .system: return nil
            case .en: return "en"
            case .zh: return "zh-Hans"
            }
        }
    }

    static let languagePreferenceUserDefaultsKey = "languagePreference"

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
        case commonRetry

        case carTab
        case navFiles
        case navSettings
        case navPreview
        case navWorkspace
        case navSessions
        case sidebarHideSessions
        case sidebarShowSessions

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
        case settingsAssignedRemotePort
        case settingsSetServerAddress
        case settingsKnownHost
        case settingsResetTrustedHost
        case settingsCopyPublicKey
        case settingsViewPublicKey
        case settingsReverseTunnelCommand
        case settingsNoTunnelCommand
        case settingsSshTunnel
        case settingsSshTunnelHelp
        case settingsSshSetupGuide
        case settingsSshSetupGuideTitle
        case settingsSshSetupGuideBody
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
        case settingsAIUsageDashboard
        case settingsAIUsageDashboardURL
        case settingsAIUsageDashboardFooter
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
        case settingsTrustHostKeyTitle
        case settingsTrustHostKeyMessage
        case settingsTrustHostKeyConfirm

        case settingsConnecting
        case settingsProject
        case settingsProjectServerDefault
        case settingsProjectCustomPath
        case settingsProjectCustomPathPlaceholder
        case settingsProjectMismatchWarning
        case settingsLanguage
        case settingsLanguageSystem
        case settingsLanguageEnglish
        case settingsLanguageChinese
        case chatCreateDisabledHint

        case hostCurrent
        case hostCurrentFooter
        case hostNoHost
        case hostAddToConnect
        case hostHosts
        case hostDelete
        case hostDuplicate
        case hostEdit
        case hostAdd
        case hostDeviceKey
        case hostCopyDevicePublicKey
        case hostDeviceKeyFooter
        case hostErrorTitle
        case hostNeverConnected
        case hostLastUsed
        case hostOverview
        case hostName
        case hostTransport
        case hostOpenCodeURL
        case hostStatus
        case hostManagedBySSHTunnel
        case hostSavedHost
        case hostSSHTunnel
        case hostSSHGateway
        case hostGatewayHost
        case hostSSHPort
        case hostSSHUsername
        case hostAssignedRemotePort
        case hostConnectionDiagnostics
        case hostUseThisHost
        case hostConfigCopied
        case hostCopyConfigJSON
        case hostNotFound
        case hostImportConfig
        case hostImportFooter
        case hostConnectionType
        case hostTransportFooter
        case hostSSHGatewayFooter
        case hostDeviceKeySendFooter
        case hostBasicAuth
        case hostSaveHelp
        case hostSave
        case hostEditTitle
        case hostAddTitle
        case hostTitle
        case hostTransportDirect
        case hostUntitled
        case hostDefaultLocalName
        case hostDefaultSSHName
        case hostDuplicateName
        case hostImportErrorDirectRequiresServerURL
        case hostImportErrorSSHTunnelRequiresSSHSettings
        case hostDeleteOnlyHostError
        case hostImportErrorInvalidUTF8
        case hostExportErrorEncodeConfigJSON
        case hostConnectionErrorInvalidURL
        case hostConnectionErrorBasicAuthRejected
        case hostConnectionErrorHTTPStatus
        case hostConnectionErrorCannotConnect
        case hostConnectionErrorTimedOut
        case hostConnectionErrorDNS
        case hostConnectionErrorNetwork
        case hostConnectionErrorHealthCheckFailed
        case hostConnectionErrorGeneric
        case hostDiagnosticCheckingHealth
        case hostDiagnosticCheckingHealthURL
        case hostDiagnosticConnectingSSHGateway
        case hostDiagnosticHintConfirmGateway
        case hostDiagnosticSSHTunnelFailed
        case hostDiagnosticHintCopyDeviceKeyAgain
        case hostDiagnosticTunnelReadyCheckingHealth
        case hostDiagnosticHintURLFormat
        case hostDiagnosticConnectedToOpenCode
        case hostDiagnosticHealthUnhealthy
        case hostDiagnosticHintCheckServerLogs
        case hostDiagnosticHintVerifyHostConfig
        case hostDiagnosticLocalListenerFailed
        case hostValidationVPSHostRequired
        case hostValidationSSHUsernameRequired
        case hostValidationSSHPortPositive
        case hostValidationAssignedRemotePortPositive
        case hostSSHTunnelUnavailableVisionOS
        case sshErrorConnectionFailed
        case sshErrorAuthenticationFailed
        case sshErrorKeyNotFound
        case sshErrorInvalidKeyFormat
        case sshErrorTunnelFailed
        case sshErrorHostKeyMismatch

        case connectionPhaseIdle
        case connectionPhaseSSHGateway
        case connectionPhaseSSHAuth
        case connectionPhaseLocalTunnel
        case connectionPhaseHealth
        case connectionPhaseBootstrap
        case connectionPhaseConnected
        case connectionPhaseFailed

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
        case chatSpeechStreamDisconnected
        case chatSpeechTapToSpeak
        case chatSpeechListening
        case chatSpeechTranscriptWillAppear
        case chatSpeechRecovering
        case chatSpeechTranscribing
        case chatSpeechTranscribingHint
        case chatSpeechPreservedAudio
        case chatSpeechStopWaiting
        case chatSpeechRetrySegment
        case chatSpeechDiscardAudio
        case chatAbortAgent
        case chatAgentRunning
        case chatMicrophoneDenied
        case chatSessionStatusBusy
        case chatSessionStatusRetrying
        case chatSessionStatusIdle
        case chatPullToLoadMore
        case chatLoadingMoreHistory
        case chatLargeMessagePreviewNotice
        case chatEditFromHere
        case chatForkFromHere
        case carTitle
        case carReady
        case carListening
        case carFinalizing
        case carWorking
        case carSpeaking
        case carNeedsConfirmation
        case carFailed
        case carStartSpeaking
        case carStopAndSend
        case carStopSpeaking
        case carSpeakConfirmation
        case carEmptyPrompt
        case carNewSession
        case carNewSessionPrompt
        case carConfirmUtterance
        case carCancelUtterance
        case carNotConnected
        case carServerDefaultRequired
        case carInvalidResponse
        case carUnsupportedAction
        case carMapsUnavailable
        case carTranscriptionFailed
        case attachmentImageTitle
        case attachmentFileTitle
        case attachmentRemoveImageAccessibilityLabel
        case attachmentImageReadFailed
        case attachmentImageTooLargeAfterCompression

        case permissionRequired
        case permissionAllowOnce
        case permissionAllowAlways
        case permissionReject
        case questionTitle
        case questionSingleHint
        case questionMultiHint
        case questionTypeOwnAnswer
        case questionCustomPlaceholder
        case questionDismiss
        case questionSubmit
        case questionBack
        case questionNext
        case questionOf

        case toolReason
        case toolCommandInput
        case toolPath
        case toolOutput
        case toolOpenInFileTree
        case toolOpenFile
        case toolSelectFile
        case toolCallsCountOne
        case toolCallsCountMany
        case toolImageFile
        case toolReadFileAccessibilityLabel
        case toolWriteFileAccessibilityLabel
        case toolReadDirectoryAccessibilityLabel
        case folderEmptyTitle
        case folderEmptyDescription

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
        case quotaTitle
        case quotaDataSource
        case quotaNotLoaded
        case quotaLoading
        case quotaRefreshing
        case quotaRefreshingProviders
        case quotaNoCachedData
        case quotaStale
        case quotaLastFetched
        case quotaGeneratedAt
        case quotaRemainingFormat
        case quotaUsedFormat
        case quotaResetFormat
        case quotaCurrentModelAccessibility

        case sessionTitle
        case sessionsTitle
        case sessionsEmptyTitle
        case sessionsEmptyDescription
        case sessionsClose
        case sessionsNew
        case sessionsUntitled
        case sessionsFilesOne
        case sessionsFilesMany
        case sessionsStatusBusy
        case sessionsStatusRetry
        case sessionsStatusIdle
        case sessionsActive
        case sessionsArchived
        case sessionsArchive
        case sessionsRestore
        case sessionsLoadMore
        case sessionsActionFailedTitle
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
        case filePreviewMode
        case fileNativePreview
        case fileWebPreview
        case fileMarkdownSource
        case contentImageDecodeFailed
        case contentNoImageData
        case markdownPreviewLoading
        case markdownWebPreviewLoading
        case markdownWebPreviewLargeDocumentTitle
        case markdownWebPreviewLargeDocumentDescription
        case markdownWebPreviewRenderAnyway
        case markdownWebPreviewOpenNative
        case markdownWebPreviewOpenSource
        case markdownWebPreviewFailedTitle
        case markdownWebPreviewAssetsMissing
        case markdownWebPreviewPayloadEncodeFailed
        case markdownWebPreviewRenderCallFailed
        case markdownWebPreviewWebViewLoadFailed
        case markdownWebPreviewWebViewProvisionalLoadFailed
        case markdownWebPreviewUnknownRenderError

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
        case helpTailscaleHttp

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
        case configureTitle
        case configureModel
        case configureAgent
        case configureNoAgents

        case todoButtonLabel
        case todoPanelTitle
        case todoPanelCompleted
        case todoPanelEmpty
        case todoUpdatedBadge
    }

    nonisolated private static let en: [String: String] = [
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
        Key.commonRetry.rawValue: "Retry",
        Key.carTab.rawValue: "Car",
        Key.navFiles.rawValue: "Files",
        Key.navSettings.rawValue: "Settings",
        Key.navPreview.rawValue: "Preview",
        Key.navWorkspace.rawValue: "Workspace",
        Key.navSessions.rawValue: "Sessions",
        Key.sidebarHideSessions.rawValue: "Hide sessions",
        Key.sidebarShowSessions.rawValue: "Show sessions",
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
        Key.settingsVpsPort.rawValue: "Remote Port",
        Key.settingsAssignedRemotePort.rawValue: "Assigned Remote Port",
        Key.settingsSetServerAddress.rawValue: "Set Server Address to 127.0.0.1:4096",
        Key.settingsKnownHost.rawValue: "Known Host",
        Key.settingsResetTrustedHost.rawValue: "Reset Trusted Host",
        Key.settingsCopyPublicKey.rawValue: "Copy Public Key",
        Key.settingsPublicKeyCopied.rawValue: "Public Key Copied",
        Key.settingsViewPublicKey.rawValue: "View Public Key",
        Key.settingsReverseTunnelCommand.rawValue: "SSH Tunnel Command",
        Key.settingsNoTunnelCommand.rawValue: "Fill Host, SSH Port, Username, and Assigned Remote Port.",
        Key.settingsSshTunnel.rawValue: "SSH Tunnel",
        Key.settingsSshTunnelHelp.rawValue: "Connects local 127.0.0.1:4096 through SSH to the assigned OpenCode remote port. Copy this device's public key to the server admin before connecting.",
        Key.settingsSshSetupGuide.rawValue: "Setup Guide",
        Key.settingsSshSetupGuideTitle.rawValue: "SSH Gateway Setup",
        Key.settingsSshSetupGuideBody.rawValue: "1. Tap Copy Public Key and send it to the server admin.\n\n2. The admin adds this device key to your user and gives you Host, SSH Port, Username, and Assigned Remote Port. For opencode-private-host, Username is usually opencode, SSH Port is usually 8006, and the first user's Remote Port is usually 19001.\n\n3. Fill those values here, enable SSH Tunnel, then tap Set Server Address to 127.0.0.1:4096.\n\n4. Tap Test Connection. The app will connect to local 127.0.0.1:4096; the SSH tunnel forwards it to your private OpenCode container.\n\n5. If provider auth is not configured yet, ask the admin to complete the first provider login in the OpenCode Web UI.",
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
        Key.settingsAIUsageDashboard.rawValue: "AI Usage Dashboard",
        Key.settingsAIUsageDashboardURL.rawValue: "Dashboard URL (optional)",
        Key.settingsAIUsageDashboardFooter.rawValue: "Leave blank for no quota UI. Enter the dashboard base URL or the full /api/v1/quotas endpoint.",
        Key.settingsRotateKeyTitle.rawValue: "Rotate SSH Key?",
        Key.settingsRotateKeyPrompt.rawValue: "This will generate a new key pair for this device. Update the public key on your SSH server before using SSH tunnel hosts again.",
        Key.settingsPublicKeyTitle.rawValue: "Your Public Key",
        Key.settingsPublicKeyFooter.rawValue: "Send this public key to the server admin. Do not share your private key.",
        Key.settingsCopyToClipboard.rawValue: "Copy to Clipboard",
        Key.settingsPublicKeyCopyFailed.rawValue: "Unable to load SSH public key.",
        Key.settingsPublicKeyRotate.rawValue: "Rotate Key",
        Key.settingsPublicKeyErrorTitle.rawValue: "Public Key Error",
        Key.settingsCopyCommand.rawValue: "Copy Command",
        Key.settingsCommandCopied.rawValue: "Command Copied",
        Key.settingsUntrusted.rawValue: "Untrusted",
        Key.settingsRotate.rawValue: "Rotate",
        Key.settingsTrustHostKeyTitle.rawValue: "Trust New SSH Host Key?",
        Key.settingsTrustHostKeyMessage.rawValue: "%@:%d presented a different host key.\n\nPrevious: %@\nNew: %@\n\nTrust it only if you expected the server to be rebuilt or reinstalled.",
        Key.settingsTrustHostKeyConfirm.rawValue: "Trust and Reconnect",
        Key.settingsConnecting.rawValue: "Connecting...",
        Key.settingsProject.rawValue: "Project (Workspace)",
        Key.settingsProjectServerDefault.rawValue: "Server default",
        Key.settingsProjectCustomPath.rawValue: "Custom path",
        Key.settingsProjectCustomPathPlaceholder.rawValue: "/path/to/project",
        Key.settingsProjectMismatchWarning.rawValue: "Server default project is {server}. New sessions will be created there, not in {effective}. To create sessions in {effective}, start OpenCode from the command line with that project as working directory.",
        Key.settingsLanguage.rawValue: "Language",
        Key.settingsLanguageSystem.rawValue: "System",
        Key.settingsLanguageEnglish.rawValue: "English",
        Key.settingsLanguageChinese.rawValue: "Chinese",
        Key.chatCreateDisabledHint.rawValue: "New sessions can only be created when using Server default project. To create sessions in another project, start OpenCode from the command line with a different working directory, then select Server default here.",

        Key.hostCurrent.rawValue: "Current Host",
        Key.hostCurrentFooter.rawValue: "A host is one OpenCode environment. It can be reached directly over LAN, Tailscale, VPN, HTTPS, or through an SSH tunnel.",
        Key.hostNoHost.rawValue: "No Host",
        Key.hostAddToConnect.rawValue: "Add a host to connect",
        Key.hostHosts.rawValue: "Hosts",
        Key.hostDelete.rawValue: "Delete",
        Key.hostDuplicate.rawValue: "Duplicate",
        Key.hostEdit.rawValue: "Edit",
        Key.hostAdd.rawValue: "Add Host",
        Key.hostDeviceKey.rawValue: "Device Key",
        Key.hostCopyDevicePublicKey.rawValue: "Copy This Device Public Key",
        Key.hostDeviceKeyFooter.rawValue: "Use this same device key for SSH tunnel hosts. Direct hosts do not need it.",
        Key.hostErrorTitle.rawValue: "Host Error",
        Key.hostNeverConnected.rawValue: "Never connected",
        Key.hostLastUsed.rawValue: "Last used %@",
        Key.hostOverview.rawValue: "Overview",
        Key.hostName.rawValue: "Name",
        Key.hostTransport.rawValue: "Transport",
        Key.hostOpenCodeURL.rawValue: "OpenCode URL",
        Key.hostStatus.rawValue: "Status",
        Key.hostManagedBySSHTunnel.rawValue: "Managed by SSH tunnel",
        Key.hostSavedHost.rawValue: "Saved Host",
        Key.hostSSHTunnel.rawValue: "SSH Tunnel",
        Key.hostSSHGateway.rawValue: "SSH Gateway",
        Key.hostGatewayHost.rawValue: "Gateway Host",
        Key.hostSSHPort.rawValue: "SSH Port",
        Key.hostSSHUsername.rawValue: "SSH Username",
        Key.hostAssignedRemotePort.rawValue: "Assigned Remote Port",
        Key.hostConnectionDiagnostics.rawValue: "Connection Diagnostics",
        Key.hostUseThisHost.rawValue: "Use This Host",
        Key.hostConfigCopied.rawValue: "Host Config Copied",
        Key.hostCopyConfigJSON.rawValue: "Copy Host Config JSON",
        Key.hostNotFound.rawValue: "Host not found",
        Key.hostImportConfig.rawValue: "Import Host Config",
        Key.hostImportFooter.rawValue: "Paste a setup JSON from your server admin, or continue with manual setup below.",
        Key.hostConnectionType.rawValue: "Connection Type",
        Key.hostTransportFooter.rawValue: "Direct is for LAN, VPN, Tailscale, or HTTPS. SSH Tunnel is for an OpenCode server behind an SSH gateway.",
        Key.hostSSHGatewayFooter.rawValue: "These values come from your OpenCode host admin. The app connects locally through the tunnel after this is saved.",
        Key.hostDeviceKeySendFooter.rawValue: "Send this public key to the server admin before testing. Never share the private key.",
        Key.hostBasicAuth.rawValue: "Basic Auth",
        Key.hostSaveHelp.rawValue: "Save is enabled after required fields are present. Test verifies the selected transport and OpenCode health endpoint.",
        Key.hostSave.rawValue: "Save",
        Key.hostEditTitle.rawValue: "Edit Host",
        Key.hostAddTitle.rawValue: "Add Host",
        Key.hostTitle.rawValue: "Host",
        Key.hostTransportDirect.rawValue: "Direct",
        Key.hostUntitled.rawValue: "Untitled Host",
        Key.hostDefaultLocalName.rawValue: "Local OpenCode",
        Key.hostDefaultSSHName.rawValue: "SSH OpenCode",
        Key.hostDuplicateName.rawValue: "%@ Copy",
        Key.hostImportErrorDirectRequiresServerURL.rawValue: "Direct host config requires serverURL.",
        Key.hostImportErrorSSHTunnelRequiresSSHSettings.rawValue: "SSH Tunnel host config requires ssh settings.",
        Key.hostDeleteOnlyHostError.rawValue: "Add another host before deleting this one.",
        Key.hostImportErrorInvalidUTF8.rawValue: "Host config is not valid UTF-8.",
        Key.hostExportErrorEncodeConfigJSON.rawValue: "Could not encode Host Config JSON.",
        Key.hostConnectionErrorInvalidURL.rawValue: "Invalid OpenCode URL. Check the host address and port.",
        Key.hostConnectionErrorBasicAuthRejected.rawValue: "OpenCode rejected Basic Auth. Check username and password.",
        Key.hostConnectionErrorHTTPStatus.rawValue: "OpenCode returned HTTP %d. Check the server logs or provider setup.",
        Key.hostConnectionErrorCannotConnect.rawValue: "Could not connect to OpenCode. Check network reachability and that the server is running.",
        Key.hostConnectionErrorTimedOut.rawValue: "Connection timed out. Check the host, port, VPN/Tailscale, and firewall.",
        Key.hostConnectionErrorDNS.rawValue: "Host name could not be resolved. Check the gateway or server host spelling.",
        Key.hostConnectionErrorNetwork.rawValue: "Network error: %@",
        Key.hostConnectionErrorHealthCheckFailed.rawValue: "OpenCode health check failed. Check that the server is running and reachable.",
        Key.hostConnectionErrorGeneric.rawValue: "Connection failed. Check the host configuration and try again.",
        Key.hostDiagnosticCheckingHealth.rawValue: "Checking OpenCode health...",
        Key.hostDiagnosticCheckingHealthURL.rawValue: "Checking %@/global/health...",
        Key.hostDiagnosticConnectingSSHGateway.rawValue: "Connecting to SSH gateway...",
        Key.hostDiagnosticHintConfirmGateway.rawValue: "Confirm the gateway host, SSH port, device public key, and network reachability.",
        Key.hostDiagnosticSSHTunnelFailed.rawValue: "SSH tunnel failed: %@",
        Key.hostDiagnosticHintCopyDeviceKeyAgain.rawValue: "Copy this device public key again if the server has not authorized it.",
        Key.hostDiagnosticTunnelReadyCheckingHealth.rawValue: "SSH tunnel is ready; checking OpenCode health...",
        Key.hostDiagnosticHintURLFormat.rawValue: "Use host:port, http://host:port, or https://host:port.",
        Key.hostDiagnosticConnectedToOpenCode.rawValue: "Connected to OpenCode%@.",
        Key.hostDiagnosticHealthUnhealthy.rawValue: "OpenCode health check returned unhealthy.",
        Key.hostDiagnosticHintCheckServerLogs.rawValue: "Check the OpenCode server process and logs.",
        Key.hostDiagnosticHintVerifyHostConfig.rawValue: "For SSH tunnel hosts, first verify the gateway values and device key. For direct hosts, verify the URL from this device.",
        Key.hostDiagnosticLocalListenerFailed.rawValue: "Local listener failed: %@",
        Key.hostValidationVPSHostRequired.rawValue: "VPS Host is required",
        Key.hostValidationSSHUsernameRequired.rawValue: "SSH Username is required",
        Key.hostValidationSSHPortPositive.rawValue: "SSH Port must be > 0",
        Key.hostValidationAssignedRemotePortPositive.rawValue: "Assigned Remote Port must be > 0",
        Key.hostSSHTunnelUnavailableVisionOS.rawValue: "SSH tunnels are not available in the visionOS build yet. Connect directly to an OpenCode server instead.",
        Key.sshErrorConnectionFailed.rawValue: "Connection failed: %@",
        Key.sshErrorAuthenticationFailed.rawValue: "Authentication failed. Please check your public key is added to the server.",
        Key.sshErrorKeyNotFound.rawValue: "SSH key not found. Please generate a key pair first.",
        Key.sshErrorInvalidKeyFormat.rawValue: "Invalid SSH key format.",
        Key.sshErrorTunnelFailed.rawValue: "Tunnel failed: %@",
        Key.sshErrorHostKeyMismatch.rawValue: "Host key mismatch. Expected %@, got %@. This may be a MITM attack or a reinstalled server. Reset trusted host and verify fingerprint before reconnecting.",

        Key.connectionPhaseIdle.rawValue: "Idle",
        Key.connectionPhaseSSHGateway.rawValue: "Connecting to SSH gateway",
        Key.connectionPhaseSSHAuth.rawValue: "Authenticating with device key",
        Key.connectionPhaseLocalTunnel.rawValue: "Starting local tunnel",
        Key.connectionPhaseHealth.rawValue: "Checking OpenCode health",
        Key.connectionPhaseBootstrap.rawValue: "Loading projects and sessions",
        Key.connectionPhaseConnected.rawValue: "Connected",
        Key.connectionPhaseFailed.rawValue: "Connection failed",

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
        Key.chatSpeechStreamDisconnected.rawValue: "The speech connection was lost and couldn't recover. Tap stop and try again.",
        Key.chatSpeechTapToSpeak.rawValue: "Tap to speak",
        Key.chatSpeechListening.rawValue: "Listening...",
        Key.chatSpeechTranscriptWillAppear.rawValue: "Transcript will appear here...",
        Key.chatSpeechRecovering.rawValue: "Reconnecting voice...",
        Key.chatSpeechTranscribing.rawValue: "Transcribing...",
        Key.chatSpeechTranscribingHint.rawValue: "Finishing transcript...",
        Key.chatSpeechPreservedAudio.rawValue: "Audio saved. Retry this segment.",
        Key.chatSpeechStopWaiting.rawValue: "Stop transcription wait",
        Key.chatSpeechRetrySegment.rawValue: "Retry this segment",
        Key.chatSpeechDiscardAudio.rawValue: "Discard audio",
        Key.chatAbortAgent.rawValue: "Interrupt agent",
        Key.chatAgentRunning.rawValue: "Agent running",
        Key.chatMicrophoneDenied.rawValue: "Microphone permission denied",
        Key.chatSessionStatusBusy.rawValue: "Running",
        Key.chatSessionStatusRetrying.rawValue: "Retrying",
        Key.chatSessionStatusIdle.rawValue: "Idle",
        Key.chatPullToLoadMore.rawValue: "Pull down to load more history",
        Key.chatLoadingMoreHistory.rawValue: "Loading more history...",
        Key.chatLargeMessagePreviewNotice.rawValue: "Large message: showing first %@ of %@ characters. Markdown rendering is skipped to keep the app responsive.",
        Key.chatEditFromHere.rawValue: "Edit from here",
        Key.chatForkFromHere.rawValue: "Fork from here",
        Key.carTitle.rawValue: "Car Mode",
        Key.carReady.rawValue: "Ready",
        Key.carListening.rawValue: "Listening",
        Key.carFinalizing.rawValue: "Finishing transcript",
        Key.carWorking.rawValue: "OpenCode is working",
        Key.carSpeaking.rawValue: "Speaking",
        Key.carNeedsConfirmation.rawValue: "Confirmation needed",
        Key.carFailed.rawValue: "Needs attention",
        Key.carStartSpeaking.rawValue: "Start speaking",
        Key.carStopAndSend.rawValue: "Stop and send",
        Key.carStopSpeaking.rawValue: "Stop speaking",
        Key.carSpeakConfirmation.rawValue: "Say confirm or cancel",
        Key.carEmptyPrompt.rawValue: "Ask about home, messages, traffic, or where to go.",
        Key.carNewSession.rawValue: "New Car Session",
        Key.carNewSessionPrompt.rawValue: "Start a new Car session and leave the current context behind?",
        Key.carConfirmUtterance.rawValue: "Confirm.",
        Key.carCancelUtterance.rawValue: "Cancel.",
        Key.carNotConnected.rawValue: "Connect to OpenCode before using Car Mode.",
        Key.carServerDefaultRequired.rawValue: "Car Mode can create sessions only in the Server default workspace.",
        Key.carInvalidResponse.rawValue: "OpenCode returned an invalid Car Mode response.",
        Key.carUnsupportedAction.rawValue: "OpenCode requested an unsupported client action.",
        Key.carMapsUnavailable.rawValue: "Apple Maps could not open this route.",
        Key.carTranscriptionFailed.rawValue: "The recording could not be transcribed.",
        Key.attachmentImageTitle.rawValue: "Image",
        Key.attachmentFileTitle.rawValue: "Attachment",
        Key.attachmentRemoveImageAccessibilityLabel.rawValue: "Remove image",
        Key.attachmentImageReadFailed.rawValue: "Could not read the selected image.",
        Key.attachmentImageTooLargeAfterCompression.rawValue: "Image is too large after compression (%@ MB). Please choose a smaller image.",

        Key.permissionRequired.rawValue: "Permission Required",
        Key.permissionAllowOnce.rawValue: "Allow Once",
        Key.permissionAllowAlways.rawValue: "Allow Always",
        Key.permissionReject.rawValue: "Reject",
        Key.questionTitle.rawValue: "Question",
        Key.questionSingleHint.rawValue: "Select one option",
        Key.questionMultiHint.rawValue: "Select one or more options",
        Key.questionTypeOwnAnswer.rawValue: "Type your own answer",
        Key.questionCustomPlaceholder.rawValue: "Type your answer...",
        Key.questionDismiss.rawValue: "Dismiss",
        Key.questionSubmit.rawValue: "Submit",
        Key.questionBack.rawValue: "Back",
        Key.questionNext.rawValue: "Next",
        Key.questionOf.rawValue: "%d of %d",

        Key.toolReason.rawValue: "Reason",
        Key.toolCommandInput.rawValue: "Command / Input",
        Key.toolPath.rawValue: "Path",
        Key.toolOutput.rawValue: "Output",
        Key.toolOpenInFileTree.rawValue: "Open \"%@\" in File Tree",
        Key.toolOpenFile.rawValue: "Open File",
        Key.toolSelectFile.rawValue: "Select file to open",
        Key.toolCallsCountOne.rawValue: "%d tool call",
        Key.toolCallsCountMany.rawValue: "%d tool calls",
        Key.toolImageFile.rawValue: "Image file",
        Key.toolReadFileAccessibilityLabel.rawValue: "Read file %@",
        Key.toolWriteFileAccessibilityLabel.rawValue: "Write file %@",
        Key.toolReadDirectoryAccessibilityLabel.rawValue: "Read directory %@",
        Key.folderEmptyTitle.rawValue: "Empty folder",
        Key.folderEmptyDescription.rawValue: "This directory has no entries.",

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
        Key.quotaTitle.rawValue: "Usage & Limits",
        Key.quotaDataSource.rawValue: "Data Source",
        Key.quotaNotLoaded.rawValue: "Quota data has not been loaded.",
        Key.quotaLoading.rawValue: "Loading quota data...",
        Key.quotaRefreshing.rawValue: "Refreshing cached quota data...",
        Key.quotaRefreshingProviders.rawValue: "Refreshing providers...",
        Key.quotaNoCachedData.rawValue: "No cached quota snapshot. Refresh AI Usage Dashboard on the host.",
        Key.quotaStale.rawValue: "Showing stale quota data",
        Key.quotaLastFetched.rawValue: "Last fetched",
        Key.quotaGeneratedAt.rawValue: "Generated at",
        Key.quotaRemainingFormat.rawValue: "%d%% left",
        Key.quotaUsedFormat.rawValue: "%d%% used",
        Key.quotaResetFormat.rawValue: "Resets %@",
        Key.quotaCurrentModelAccessibility.rawValue: "Current model quota: %@",

        Key.sessionTitle.rawValue: "Session",
        Key.sessionsTitle.rawValue: "Sessions",
        Key.sessionsEmptyTitle.rawValue: "No Sessions",
        Key.sessionsEmptyDescription.rawValue: "Tap + to create one, or pull to refresh for existing sessions.",
        Key.sessionsClose.rawValue: "Close",
        Key.sessionsNew.rawValue: "New",
        Key.sessionsUntitled.rawValue: "Untitled",
        Key.sessionsFilesOne.rawValue: "%d file",
        Key.sessionsFilesMany.rawValue: "%d files",
        Key.sessionsStatusBusy.rawValue: "Running",
        Key.sessionsStatusRetry.rawValue: "Retrying",
        Key.sessionsStatusIdle.rawValue: "Idle",
        Key.sessionsActive.rawValue: "Active",
        Key.sessionsArchived.rawValue: "Archived",
        Key.sessionsArchive.rawValue: "Archive",
        Key.sessionsRestore.rawValue: "Restore",
        Key.sessionsLoadMore.rawValue: "Load more sessions",
        Key.sessionsActionFailedTitle.rawValue: "Session Action Failed",
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
        Key.filePreviewMode.rawValue: "Preview Mode",
        Key.fileNativePreview.rawValue: "Native Preview",
        Key.fileWebPreview.rawValue: "Web Preview",
        Key.fileMarkdownSource.rawValue: "Markdown Source",
        Key.contentImageDecodeFailed.rawValue: "Failed to decode image",
        Key.contentNoImageData.rawValue: "No image data",
        Key.markdownPreviewLoading.rawValue: "Loading preview...",
        Key.markdownWebPreviewLoading.rawValue: "Loading web preview...",
        Key.markdownWebPreviewLargeDocumentTitle.rawValue: "Large document",
        Key.markdownWebPreviewLargeDocumentDescription.rawValue: "This file is large. Web Preview may be slow or memory-heavy.",
        Key.markdownWebPreviewRenderAnyway.rawValue: "Render anyway",
        Key.markdownWebPreviewOpenNative.rawValue: "Open Native Preview",
        Key.markdownWebPreviewOpenSource.rawValue: "Open Markdown Source",
        Key.markdownWebPreviewFailedTitle.rawValue: "Web Preview failed",
        Key.markdownWebPreviewAssetsMissing.rawValue: "Web Preview assets missing from app bundle.",
        Key.markdownWebPreviewPayloadEncodeFailed.rawValue: "Failed to encode preview payload.",
        Key.markdownWebPreviewRenderCallFailed.rawValue: "Render call failed: %@",
        Key.markdownWebPreviewWebViewLoadFailed.rawValue: "WebView load failed: %@",
        Key.markdownWebPreviewWebViewProvisionalLoadFailed.rawValue: "WebView provisional load failed: %@",
        Key.markdownWebPreviewUnknownRenderError.rawValue: "Unknown render error",

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
        Key.helpTailscaleHttp.rawValue: "Tailscale does not require HTTPS; other WAN addresses still require HTTPS.",

        Key.activityRetrying.rawValue: "Retrying",
        Key.activityThinking.rawValue: "Thinking",
        Key.activityDelegating.rawValue: "Delegating",
        Key.activityPlanning.rawValue: "Planning",
        Key.activityGatheringContext.rawValue: "Gathering context",
        Key.activitySearchingCodebase.rawValue: "Searching codebase",
        Key.activitySearchingWeb.rawValue: "Searching web",
        Key.activityMakingEdits.rawValue: "Making edits",
        Key.activityRunningCommands.rawValue: "Running commands",
        Key.activityGatheringThoughts.rawValue: "Gathering thoughts",

        Key.configureTitle.rawValue: "Configure",
        Key.configureModel.rawValue: "Model",
        Key.configureAgent.rawValue: "Agent",
        Key.configureNoAgents.rawValue: "No agents available",

        Key.todoButtonLabel.rawValue: "Todo",
        Key.todoPanelTitle.rawValue: "Todo",
        Key.todoPanelCompleted.rawValue: "%d/%d completed",
        Key.todoPanelEmpty.rawValue: "No todos yet",
        Key.todoUpdatedBadge.rawValue: "Todo updated · %d/%d",
    ]

    nonisolated private static let zh: [String: String] = [
        Key.appChat.rawValue: "聊天",
        Key.appClose.rawValue: "关闭",
        Key.appDone.rawValue: "完成",
        Key.appLoading.rawValue: "加载中...",
        Key.appNoContent.rawValue: "暂无内容",
        Key.appError.rawValue: "错误",
        Key.appSearchFiles.rawValue: "搜索文件",
        Key.appSearchFilesTitle.rawValue: "搜索文件",
        Key.commonOk.rawValue: "确定",
        Key.commonCancel.rawValue: "取消",
        Key.commonRetry.rawValue: "重试",
        Key.carTab.rawValue: "驾驶",
        Key.navFiles.rawValue: "文件",
        Key.navSettings.rawValue: "设置",
        Key.navPreview.rawValue: "预览",
        Key.navWorkspace.rawValue: "工作区",
        Key.navSessions.rawValue: "会话",
        Key.sidebarHideSessions.rawValue: "隐藏会话栏",
        Key.sidebarShowSessions.rawValue: "显示会话栏",
        Key.contentPreviewUnavailableTitle.rawValue: "选择文件预览",
        Key.contentPreviewUnavailableDescription.rawValue: "在左侧工作区选择文件，或在聊天里的工具/补丁卡片中点“打开文件”。",
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
        Key.settingsConnectionTip.rawValue: "AI Builder 服务地址",
        Key.settingsEnableSshTunnel.rawValue: "启用 SSH 隧道",
        Key.settingsAfterEnableSshTip.rawValue: "开启 SSH 隧道后，请在上方服务器连接中点击“测试连接”。",
        Key.settingsVpsHost.rawValue: "VPS 地址",
        Key.settingsSshPort.rawValue: "SSH 端口",
        Key.settingsVpsPort.rawValue: "远端端口",
        Key.settingsAssignedRemotePort.rawValue: "分配的远端端口",
        Key.settingsSetServerAddress.rawValue: "将服务器地址设置为 127.0.0.1:4096",
        Key.settingsKnownHost.rawValue: "已知主机",
        Key.settingsResetTrustedHost.rawValue: "重置已信任主机",
        Key.settingsCopyPublicKey.rawValue: "复制公钥",
        Key.settingsPublicKeyCopied.rawValue: "公钥已复制",
        Key.settingsViewPublicKey.rawValue: "查看公钥",
        Key.settingsReverseTunnelCommand.rawValue: "SSH 隧道命令",
        Key.settingsNoTunnelCommand.rawValue: "请先填写主机地址、SSH 端口、用户名和分配的远端端口。",
        Key.settingsSshTunnel.rawValue: "SSH 隧道",
        Key.settingsSshTunnelHelp.rawValue: "通过 SSH 把本机 127.0.0.1:4096 连到服务器分配的 OpenCode 远端端口。连接前先把本设备公钥发给管理员添加。",
        Key.settingsSshSetupGuide.rawValue: "设置说明",
        Key.settingsSshSetupGuideTitle.rawValue: "SSH 网关设置",
        Key.settingsSshSetupGuideBody.rawValue: "1. 点击复制公钥，把它发给服务器管理员。\n\n2. 管理员把这台设备的 key 加到你的用户下面，并给你 Host、SSH Port、Username 和分配的 Remote Port。opencode-private-host 默认 Username 通常是 opencode，SSH Port 通常是 8006，第一个用户的 Remote Port 通常是 19001。\n\n3. 在这里填入这些值，开启 SSH Tunnel，然后点击“将服务器地址设置为 127.0.0.1:4096”。\n\n4. 点击测试连接。App 会访问本机 127.0.0.1:4096，SSH 隧道会把它转发到你的私有 OpenCode 容器。\n\n5. 如果 provider auth 还没配置，请让管理员先在 OpenCode Web UI 里完成第一次 provider 登录。",
        Key.settingsAutoTheme.rawValue: "自动",
        Key.settingsLightTheme.rawValue: "亮色",
        Key.settingsDarkTheme.rawValue: "暗色",
        Key.settingsAppearance.rawValue: "外观",
        Key.settingsTheme.rawValue: "主题",
        Key.settingsSpeechRecognition.rawValue: "语音识别",
        Key.settingsAiBuilderBaseURL.rawValue: "AI Builder 服务地址",
        Key.settingsAiBuilderToken.rawValue: "AI Builder 访问令牌",
        Key.settingsCustomPrompt.rawValue: "自定义提示词",
        Key.settingsTerminology.rawValue: "术语（逗号分隔）",
        Key.settingsTesting.rawValue: "测试中...",
        Key.settingsTested.rawValue: "可用",
        Key.settingsAbout.rawValue: "关于",
        Key.settingsServerVersion.rawValue: "服务器版本",
        Key.settingsAIUsageDashboard.rawValue: "AI 用量面板",
        Key.settingsAIUsageDashboardURL.rawValue: "面板地址（可选）",
        Key.settingsAIUsageDashboardFooter.rawValue: "留空时不显示任何 quota 界面。可填写面板根地址或完整的 /api/v1/quotas 地址。",
        Key.settingsRotateKeyTitle.rawValue: "要更换 SSH 密钥吗？",
        Key.settingsRotateKeyPrompt.rawValue: "这将为本设备生成一对新密钥。再次使用 SSH Tunnel hosts 前，请同步更新 SSH server 上的公钥。",
        Key.settingsPublicKeyTitle.rawValue: "你的公钥",
        Key.settingsPublicKeyFooter.rawValue: "把这个公钥发给服务器管理员。不要分享私钥。",
        Key.settingsCopyToClipboard.rawValue: "复制到剪贴板",
        Key.settingsPublicKeyCopyFailed.rawValue: "无法加载 SSH 公钥。",
        Key.settingsPublicKeyRotate.rawValue: "更换密钥",
        Key.settingsPublicKeyErrorTitle.rawValue: "公钥错误",
        Key.settingsCopyCommand.rawValue: "复制命令",
        Key.settingsCommandCopied.rawValue: "命令已复制",
        Key.settingsUntrusted.rawValue: "未信任",
        Key.settingsRotate.rawValue: "更换",
        Key.settingsTrustHostKeyTitle.rawValue: "信任新的 SSH Host Key？",
        Key.settingsTrustHostKeyMessage.rawValue: "%@:%d 返回了不同的 host key。\n\n之前：%@\n新的：%@\n\n只有在你确认服务器刚重建或重装时，才信任这个新 key。",
        Key.settingsTrustHostKeyConfirm.rawValue: "信任并重连",
        Key.errorServerAddressEmpty.rawValue: "服务器地址不能为空",
        Key.errorWanRequiresHttps.rawValue: "WAN 地址必须使用 HTTPS",
        Key.errorUsingLanHttp.rawValue: "正在使用 LAN HTTP",
        Key.settingsConnecting.rawValue: "连接中...",
        Key.settingsProject.rawValue: "项目（工作区）",
        Key.settingsProjectServerDefault.rawValue: "服务器默认",
        Key.settingsProjectCustomPath.rawValue: "自定义路径",
        Key.settingsProjectCustomPathPlaceholder.rawValue: "/path/to/project",
        Key.settingsProjectMismatchWarning.rawValue: "服务器默认项目是 {server}。新会话会创建在 {server}，而不是 {effective}。如需在 {effective} 创建会话，请从命令行在该项目目录启动 OpenCode。",
        Key.settingsLanguage.rawValue: "语言",
        Key.settingsLanguageSystem.rawValue: "跟随系统",
        Key.settingsLanguageEnglish.rawValue: "英文",
        Key.settingsLanguageChinese.rawValue: "中文",
        Key.chatCreateDisabledHint.rawValue: "只有选择“服务器默认项目”时才能新建会话。如需在其他项目中创建会话，请从命令行在对应目录启动 OpenCode，然后在这里选择“服务器默认”。",

        Key.hostCurrent.rawValue: "当前主机",
        Key.hostCurrentFooter.rawValue: "Host 表示一个 OpenCode 环境，可以直连 LAN、Tailscale、VPN、HTTPS，也可以通过 SSH 隧道访问。",
        Key.hostNoHost.rawValue: "未配置 Host",
        Key.hostAddToConnect.rawValue: "添加 Host 后连接",
        Key.hostHosts.rawValue: "主机",
        Key.hostDelete.rawValue: "删除",
        Key.hostDuplicate.rawValue: "复制",
        Key.hostEdit.rawValue: "编辑",
        Key.hostAdd.rawValue: "添加 Host",
        Key.hostDeviceKey.rawValue: "设备密钥",
        Key.hostCopyDevicePublicKey.rawValue: "复制本设备公钥",
        Key.hostDeviceKeyFooter.rawValue: "SSH Tunnel hosts 复用同一把设备公钥。Direct hosts 不需要。",
        Key.hostErrorTitle.rawValue: "Host 错误",
        Key.hostNeverConnected.rawValue: "从未连接",
        Key.hostLastUsed.rawValue: "上次使用 %@",
        Key.hostOverview.rawValue: "概览",
        Key.hostName.rawValue: "名称",
        Key.hostTransport.rawValue: "连接方式",
        Key.hostOpenCodeURL.rawValue: "OpenCode 地址",
        Key.hostStatus.rawValue: "状态",
        Key.hostManagedBySSHTunnel.rawValue: "由 SSH 隧道管理",
        Key.hostSavedHost.rawValue: "已保存 Host",
        Key.hostSSHTunnel.rawValue: "SSH 隧道",
        Key.hostSSHGateway.rawValue: "SSH 网关",
        Key.hostGatewayHost.rawValue: "网关地址",
        Key.hostSSHPort.rawValue: "SSH 端口",
        Key.hostSSHUsername.rawValue: "SSH 用户名",
        Key.hostAssignedRemotePort.rawValue: "分配的远端端口",
        Key.hostConnectionDiagnostics.rawValue: "连接诊断",
        Key.hostUseThisHost.rawValue: "使用此主机",
        Key.hostConfigCopied.rawValue: "主机配置已复制",
        Key.hostCopyConfigJSON.rawValue: "复制 Host Config JSON",
        Key.hostNotFound.rawValue: "找不到 Host",
        Key.hostImportConfig.rawValue: "导入 Host Config",
        Key.hostImportFooter.rawValue: "粘贴管理员提供的配置 JSON，或继续手动配置。",
        Key.hostConnectionType.rawValue: "连接类型",
        Key.hostTransportFooter.rawValue: "直连适用于局域网、VPN、Tailscale 或 HTTPS。SSH 隧道适用于放在 SSH 网关后的 OpenCode 服务器。",
        Key.hostSSHGatewayFooter.rawValue: "这些值由 OpenCode host 管理员提供。保存后 app 会通过本地隧道连接。",
        Key.hostDeviceKeySendFooter.rawValue: "测试前把这个公钥发给服务器管理员。不要分享私钥。",
        Key.hostBasicAuth.rawValue: "Basic Auth",
        Key.hostSaveHelp.rawValue: "必填项完整后即可保存。测试连接会检查连接方式和 OpenCode 服务状态。",
        Key.hostSave.rawValue: "保存",
        Key.hostEditTitle.rawValue: "编辑 Host",
        Key.hostAddTitle.rawValue: "添加 Host",
        Key.hostTitle.rawValue: "主机",
        Key.hostTransportDirect.rawValue: "直连",
        Key.hostUntitled.rawValue: "未命名主机",
        Key.hostDefaultLocalName.rawValue: "本地 OpenCode",
        Key.hostDefaultSSHName.rawValue: "SSH OpenCode",
        Key.hostDuplicateName.rawValue: "%@ 副本",
        Key.hostImportErrorDirectRequiresServerURL.rawValue: "直连配置需要 serverURL。",
        Key.hostImportErrorSSHTunnelRequiresSSHSettings.rawValue: "SSH 隧道配置需要 ssh 设置。",
        Key.hostDeleteOnlyHostError.rawValue: "请先添加另一个主机，再删除这个主机。",
        Key.hostImportErrorInvalidUTF8.rawValue: "Host config 不是有效的 UTF-8。",
        Key.hostExportErrorEncodeConfigJSON.rawValue: "无法生成 Host Config JSON。",
        Key.hostConnectionErrorInvalidURL.rawValue: "OpenCode 地址无效，请检查主机地址和端口。",
        Key.hostConnectionErrorBasicAuthRejected.rawValue: "OpenCode 拒绝了 Basic Auth，请检查用户名和密码。",
        Key.hostConnectionErrorHTTPStatus.rawValue: "OpenCode 返回 HTTP %d。请检查服务器日志或服务商配置。",
        Key.hostConnectionErrorCannotConnect.rawValue: "无法连接到 OpenCode。请检查网络是否可达，以及服务器是否正在运行。",
        Key.hostConnectionErrorTimedOut.rawValue: "连接超时。请检查主机、端口、VPN/Tailscale 和防火墙。",
        Key.hostConnectionErrorDNS.rawValue: "无法解析主机名。请检查网关或服务器地址拼写。",
        Key.hostConnectionErrorNetwork.rawValue: "网络错误：%@",
        Key.hostConnectionErrorHealthCheckFailed.rawValue: "OpenCode 服务状态检查失败。请确认服务器正在运行且可以访问。",
        Key.hostConnectionErrorGeneric.rawValue: "连接失败。请检查主机配置后重试。",
        Key.hostDiagnosticCheckingHealth.rawValue: "正在检查 OpenCode 服务状态...",
        Key.hostDiagnosticCheckingHealthURL.rawValue: "正在检查 %@/global/health...",
        Key.hostDiagnosticConnectingSSHGateway.rawValue: "正在连接 SSH 网关...",
        Key.hostDiagnosticHintConfirmGateway.rawValue: "请确认网关地址、SSH 端口、设备公钥和网络可达性。",
        Key.hostDiagnosticSSHTunnelFailed.rawValue: "SSH 隧道失败：%@",
        Key.hostDiagnosticHintCopyDeviceKeyAgain.rawValue: "如果服务器还没有授权这台设备，请重新复制本设备公钥给管理员。",
        Key.hostDiagnosticTunnelReadyCheckingHealth.rawValue: "SSH 隧道已就绪，正在检查 OpenCode 服务状态...",
        Key.hostDiagnosticHintURLFormat.rawValue: "请使用 host:port、http://host:port 或 https://host:port。",
        Key.hostDiagnosticConnectedToOpenCode.rawValue: "已连接到 OpenCode%@。",
        Key.hostDiagnosticHealthUnhealthy.rawValue: "OpenCode 服务状态检查返回异常。",
        Key.hostDiagnosticHintCheckServerLogs.rawValue: "请检查 OpenCode 服务进程和日志。",
        Key.hostDiagnosticHintVerifyHostConfig.rawValue: "SSH 隧道主机请先检查网关参数和设备密钥；直连主机请确认这台设备能访问该地址。",
        Key.hostDiagnosticLocalListenerFailed.rawValue: "本地监听器失败：%@",
        Key.hostValidationVPSHostRequired.rawValue: "VPS 地址不能为空",
        Key.hostValidationSSHUsernameRequired.rawValue: "SSH 用户名不能为空",
        Key.hostValidationSSHPortPositive.rawValue: "SSH 端口必须大于 0",
        Key.hostValidationAssignedRemotePortPositive.rawValue: "分配的远端端口必须大于 0",
        Key.hostSSHTunnelUnavailableVisionOS.rawValue: "visionOS 版本暂不支持 SSH 隧道。请改用直连 OpenCode 服务器。",
        Key.sshErrorConnectionFailed.rawValue: "连接失败：%@",
        Key.sshErrorAuthenticationFailed.rawValue: "认证失败。请确认服务器已添加你的公钥。",
        Key.sshErrorKeyNotFound.rawValue: "找不到 SSH 密钥。请先生成密钥对。",
        Key.sshErrorInvalidKeyFormat.rawValue: "SSH 密钥格式无效。",
        Key.sshErrorTunnelFailed.rawValue: "隧道失败：%@",
        Key.sshErrorHostKeyMismatch.rawValue: "Host key 不匹配。预期 %@，实际 %@。这可能是中间人攻击，也可能是服务器重装。请重置信任主机，并核对 fingerprint 后再连接。",

        Key.connectionPhaseIdle.rawValue: "空闲",
        Key.connectionPhaseSSHGateway.rawValue: "正在连接 SSH 网关",
        Key.connectionPhaseSSHAuth.rawValue: "正在用设备密钥认证",
        Key.connectionPhaseLocalTunnel.rawValue: "正在启动本地隧道",
        Key.connectionPhaseHealth.rawValue: "正在检查 OpenCode 服务状态",
        Key.connectionPhaseBootstrap.rawValue: "正在加载项目和会话",
        Key.connectionPhaseConnected.rawValue: "已连接",
        Key.connectionPhaseFailed.rawValue: "连接失败",

        Key.chatInputPlaceholder.rawValue: "输入你的问题...",
        Key.chatSendFailed.rawValue: "发送失败",
        Key.chatRenameSession.rawValue: "重命名会话",
        Key.chatRenameSessionPlaceholder.rawValue: "输入新标题",
        Key.chatTitleField.rawValue: "标题",
        Key.chatSpeechTitle.rawValue: "语音识别",
        Key.chatSelectSessionFirst.rawValue: "请选择一个会话",
        Key.chatSessionBusyMessage.rawValue: "会话正在运行中，消息尚未可见，正在刷新中…",
        Key.chatNoMessages.rawValue: "暂无消息",
        Key.chatSessionBusy.rawValue: "忙碌",
        Key.chatSessionRetrying.rawValue: "重试中",
        Key.chatSessionIdle.rawValue: "空闲",
        Key.chatTurnCompleted.rawValue: "已完成",
        Key.chatSpeechTokenMissing.rawValue: "语音识别未配置：请先到“设置 > 语音识别”填写 AI Builder 访问令牌，并点击“测试连接”。",
        Key.chatSpeechTesting.rawValue: "AI Builder 正在测试连接，请稍候。",
        Key.chatSpeechNotPassed.rawValue: "AI Builder 连接未通过测试：请先到 Settings -> Speech Recognition 点击 Test Connection，确认 OK 后再录音。",
        Key.chatSpeechStreamDisconnected.rawValue: "语音连接断开且无法恢复，请按停止后重试。",
        Key.chatSpeechTapToSpeak.rawValue: "点击说话",
        Key.chatSpeechListening.rawValue: "正在听…",
        Key.chatSpeechTranscriptWillAppear.rawValue: "转写内容会显示在这里…",
        Key.chatSpeechRecovering.rawValue: "语音正在重连…",
        Key.chatSpeechTranscribing.rawValue: "正在转写…",
        Key.chatSpeechTranscribingHint.rawValue: "正在完成转写…",
        Key.chatSpeechPreservedAudio.rawValue: "音频已保留，可重试这段。",
        Key.chatSpeechStopWaiting.rawValue: "停止转写等待",
        Key.chatSpeechRetrySegment.rawValue: "重试这段",
        Key.chatSpeechDiscardAudio.rawValue: "丢弃音频",
        Key.chatAbortAgent.rawValue: "中断智能体",
        Key.chatAgentRunning.rawValue: "智能体正在运行",
        Key.chatMicrophoneDenied.rawValue: "未授权麦克风权限",
        Key.chatSessionStatusBusy.rawValue: "运行中",
        Key.chatSessionStatusRetrying.rawValue: "重试中",
        Key.chatSessionStatusIdle.rawValue: "空闲",
        Key.chatPullToLoadMore.rawValue: "下拉加载更多历史消息",
        Key.chatLoadingMoreHistory.rawValue: "正在加载更多历史消息...",
        Key.chatLargeMessagePreviewNotice.rawValue: "消息较长：当前只显示前 %@ / %@ 个字符。为保持流畅，已跳过 Markdown 渲染。",
        Key.chatEditFromHere.rawValue: "从这里编辑",
        Key.carTitle.rawValue: "驾驶模式",
        Key.carReady.rawValue: "可以说话",
        Key.carListening.rawValue: "正在听",
        Key.carFinalizing.rawValue: "正在完成转写",
        Key.carWorking.rawValue: "OpenCode 正在处理",
        Key.carSpeaking.rawValue: "正在朗读",
        Key.carNeedsConfirmation.rawValue: "需要确认",
        Key.carFailed.rawValue: "需要处理",
        Key.carStartSpeaking.rawValue: "开始说话",
        Key.carStopAndSend.rawValue: "停止并发送",
        Key.carStopSpeaking.rawValue: "停止朗读",
        Key.carSpeakConfirmation.rawValue: "说确认或取消",
        Key.carEmptyPrompt.rawValue: "可以询问家里状态、消息、路况，或要去哪里。",
        Key.carNewSession.rawValue: "新建驾驶会话",
        Key.carNewSessionPrompt.rawValue: "新建驾驶会话并离开当前上下文？",
        Key.carConfirmUtterance.rawValue: "确认。",
        Key.carCancelUtterance.rawValue: "取消。",
        Key.carNotConnected.rawValue: "使用驾驶模式前，请先连接 OpenCode。",
        Key.carServerDefaultRequired.rawValue: "驾驶模式目前只能在服务器默认工作区新建会话。",
        Key.carInvalidResponse.rawValue: "OpenCode 返回的驾驶模式响应无效。",
        Key.carUnsupportedAction.rawValue: "OpenCode 请求了不支持的客户端操作。",
        Key.carMapsUnavailable.rawValue: "Apple 地图无法打开这条路线。",
        Key.carTranscriptionFailed.rawValue: "无法完成这段录音的转写。",
        Key.chatForkFromHere.rawValue: "从这里分叉",
        Key.attachmentImageTitle.rawValue: "图片",
        Key.attachmentFileTitle.rawValue: "附件",
        Key.attachmentRemoveImageAccessibilityLabel.rawValue: "移除图片",
        Key.attachmentImageReadFailed.rawValue: "无法读取所选图片。",
        Key.attachmentImageTooLargeAfterCompression.rawValue: "图片压缩后仍过大（%@ MB）。请选择更小的图片。",

        Key.permissionRequired.rawValue: "需要授权",
        Key.permissionAllowOnce.rawValue: "允许一次",
        Key.permissionAllowAlways.rawValue: "始终允许",
        Key.permissionReject.rawValue: "拒绝",
        Key.questionTitle.rawValue: "提问",
        Key.questionSingleHint.rawValue: "选择一个选项",
        Key.questionMultiHint.rawValue: "选择一个或多个选项",
        Key.questionTypeOwnAnswer.rawValue: "输入自定义答案",
        Key.questionCustomPlaceholder.rawValue: "输入你的答案...",
        Key.questionDismiss.rawValue: "跳过",
        Key.questionSubmit.rawValue: "提交",
        Key.questionBack.rawValue: "上一步",
        Key.questionNext.rawValue: "下一步",
        Key.questionOf.rawValue: "第 %d 题，共 %d 题",

        Key.toolReason.rawValue: "原因",
        Key.toolCommandInput.rawValue: "命令 / 输入",
        Key.toolPath.rawValue: "路径",
        Key.toolOutput.rawValue: "输出",
        Key.toolOpenInFileTree.rawValue: "在文件树中打开“%@”",
        Key.toolOpenFile.rawValue: "打开文件",
        Key.toolSelectFile.rawValue: "选择要打开的文件",
        Key.toolCallsCountOne.rawValue: "%d 个工具调用",
        Key.toolCallsCountMany.rawValue: "%d 个工具调用",
        Key.toolImageFile.rawValue: "图片文件",
        Key.toolReadFileAccessibilityLabel.rawValue: "读取文件 %@",
        Key.toolWriteFileAccessibilityLabel.rawValue: "写入文件 %@",
        Key.toolReadDirectoryAccessibilityLabel.rawValue: "读取目录 %@",
        Key.folderEmptyTitle.rawValue: "文件夹为空",
        Key.folderEmptyDescription.rawValue: "此目录没有条目。",

        Key.patchFilesChangedOne.rawValue: "%d 个文件已变更",
        Key.patchFilesChangedMany.rawValue: "%d 个文件已变更",

        Key.contextUsageHelp.rawValue: "上下文用量",
        Key.contextUsageClose.rawValue: "关闭",
        Key.contextUsageTitle.rawValue: "上下文",
        Key.contextUsageSectionSession.rawValue: "会话",
        Key.contextUsageSectionModel.rawValue: "模型",
        Key.contextUsageSectionTokens.rawValue: "令牌",
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
        Key.contextUsageLoadingConfig.rawValue: "正在加载服务商配置...",
        Key.contextUsageNoUsageData.rawValue: "无使用数据",
        Key.contextUsageConfigNotLoaded.rawValue: "未加载服务商配置",
        Key.quotaTitle.rawValue: "用量与限额",
        Key.quotaDataSource.rawValue: "数据来源",
        Key.quotaNotLoaded.rawValue: "尚未加载 quota 数据。",
        Key.quotaLoading.rawValue: "正在加载 quota 数据...",
        Key.quotaRefreshing.rawValue: "正在刷新缓存的 quota 数据...",
        Key.quotaRefreshingProviders.rawValue: "正在从服务商更新数据...",
        Key.quotaNoCachedData.rawValue: "没有缓存的 quota 快照。请先在主机上刷新 AI Usage Dashboard。",
        Key.quotaStale.rawValue: "正在显示过期 quota 数据",
        Key.quotaLastFetched.rawValue: "上次获取",
        Key.quotaGeneratedAt.rawValue: "生成时间",
        Key.quotaRemainingFormat.rawValue: "剩余 %d%%",
        Key.quotaUsedFormat.rawValue: "已用 %d%%",
        Key.quotaResetFormat.rawValue: "%@ 重置",
        Key.quotaCurrentModelAccessibility.rawValue: "当前模型 quota：%@",

        Key.sessionTitle.rawValue: "会话",
        Key.sessionsTitle.rawValue: "会话",
        Key.sessionsEmptyTitle.rawValue: "暂无会话",
        Key.sessionsEmptyDescription.rawValue: "点击右上角新建，或下拉刷新获取已有 Session",
        Key.sessionsClose.rawValue: "关闭",
        Key.sessionsNew.rawValue: "新建",
        Key.sessionsUntitled.rawValue: "无标题",
        Key.sessionsFilesOne.rawValue: "%d 个文件",
        Key.sessionsFilesMany.rawValue: "%d 个文件",
        Key.sessionsStatusBusy.rawValue: "运行中",
        Key.sessionsStatusRetry.rawValue: "重试中",
        Key.sessionsStatusIdle.rawValue: "空闲",
        Key.sessionsActive.rawValue: "活跃",
        Key.sessionsArchived.rawValue: "已归档",
        Key.sessionsArchive.rawValue: "归档",
        Key.sessionsRestore.rawValue: "恢复",
        Key.sessionsLoadMore.rawValue: "加载更多会话",
        Key.sessionsActionFailedTitle.rawValue: "会话操作失败",
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
        Key.filePreviewMode.rawValue: "预览方式",
        Key.fileNativePreview.rawValue: "原生预览",
        Key.fileWebPreview.rawValue: "Web 预览",
        Key.fileMarkdownSource.rawValue: "Markdown 源码",
        Key.contentImageDecodeFailed.rawValue: "图片解码失败",
        Key.contentNoImageData.rawValue: "没有图片数据",
        Key.markdownPreviewLoading.rawValue: "正在加载预览...",
        Key.markdownWebPreviewLoading.rawValue: "正在加载 Web 预览...",
        Key.markdownWebPreviewLargeDocumentTitle.rawValue: "文档较大",
        Key.markdownWebPreviewLargeDocumentDescription.rawValue: "这个文件较大，Web 预览可能较慢或占用较多内存。",
        Key.markdownWebPreviewRenderAnyway.rawValue: "仍然渲染",
        Key.markdownWebPreviewOpenNative.rawValue: "打开原生预览",
        Key.markdownWebPreviewOpenSource.rawValue: "打开 Markdown 源码",
        Key.markdownWebPreviewFailedTitle.rawValue: "Web 预览失败",
        Key.markdownWebPreviewAssetsMissing.rawValue: "App bundle 中缺少 Web 预览资源。",
        Key.markdownWebPreviewPayloadEncodeFailed.rawValue: "无法编码预览 payload。",
        Key.markdownWebPreviewRenderCallFailed.rawValue: "渲染调用失败：%@",
        Key.markdownWebPreviewWebViewLoadFailed.rawValue: "WebView 加载失败：%@",
        Key.markdownWebPreviewWebViewProvisionalLoadFailed.rawValue: "WebView 预加载失败：%@",
        Key.markdownWebPreviewUnknownRenderError.rawValue: "未知渲染错误",

        Key.errorConnectionFailed.rawValue: "连接失败：%@",
        Key.errorServerError.rawValue: "服务器错误：%@",
        Key.errorInvalidResponse.rawValue: "服务器返回了无效的响应",
        Key.errorUnauthorized.rawValue: "未授权，请检查认证信息",
        Key.errorSessionNotFound.rawValue: "会话不存在",
        Key.errorFileNotFound.rawValue: "文件不存在：%@",
        Key.errorOperationFailed.rawValue: "操作失败：%@",
        Key.errorUnknown.rawValue: "未知错误：%@",
        Key.errorAiBuilderTokenEmpty.rawValue: "访问令牌为空",
        Key.errorInvalidBaseURL.rawValue: "无效的 URL",
        Key.helpLanHttp.rawValue: "LAN: HTTP 允许，但建议仅在可信局域网内使用。HTTP 不安全。",
        Key.helpWanHttp.rawValue: "WAN: 需要 HTTPS（HTTP 会被阻止）。HTTP 不安全。",
        Key.helpTailscaleHttp.rawValue: "Tailscale 不要求 HTTPS；其他广域网地址仍需使用 HTTPS。",

        Key.activityRetrying.rawValue: "重试中",
        Key.activityThinking.rawValue: "思考中",
        Key.activityDelegating.rawValue: "委派任务",
        Key.activityPlanning.rawValue: "规划中",
        Key.activityGatheringContext.rawValue: "收集上下文",
        Key.activitySearchingCodebase.rawValue: "搜索代码库",
        Key.activitySearchingWeb.rawValue: "搜索网络",
        Key.activityMakingEdits.rawValue: "修改代码",
        Key.activityRunningCommands.rawValue: "执行命令",
        Key.activityGatheringThoughts.rawValue: "整理思路",

        Key.configureTitle.rawValue: "配置",
        Key.configureModel.rawValue: "模型",
        Key.configureAgent.rawValue: "智能体",
        Key.configureNoAgents.rawValue: "暂无可用智能体",

        Key.todoButtonLabel.rawValue: "任务",
        Key.todoPanelTitle.rawValue: "任务",
        Key.todoPanelCompleted.rawValue: "%d/%d 已完成",
        Key.todoPanelEmpty.rawValue: "暂无任务",
        Key.todoUpdatedBadge.rawValue: "任务更新 · %d/%d",
    ]

    static var languagePreference: LanguagePreference {
        get {
            let raw = UserDefaults.standard.string(forKey: languagePreferenceUserDefaultsKey)
            return raw.flatMap(LanguagePreference.init(rawValue:)) ?? .system
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: languagePreferenceUserDefaultsKey)
        }
    }

    static var currentLocale: Locale {
        if let identifier = languagePreference.localeIdentifier {
            return Locale(identifier: identifier)
        }
        return Locale.current
    }

    private static var languageIsChinese: Bool {
        switch languagePreference {
        case .system:
            let preferred = Locale.preferredLanguages.first ?? "en"
            return preferred.lowercased().hasPrefix("zh")
        case .en:
            return false
        case .zh:
            return true
        }
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
        return String(format: template, locale: currentLocale, arguments: arguments)
    }

    static func toolCallsCount(_ count: Int) -> String {
        let key: Key = count == 1 ? .toolCallsCountOne : .toolCallsCountMany
        return formatCount(key: key, count: count)
    }

    static func sessionsFiles(_ count: Int) -> String {
        let key: Key = count == 1 ? .sessionsFilesOne : .sessionsFilesMany
        return formatCount(key: key, count: count)
    }

    static func patchFilesChanged(_ count: Int) -> String {
        let key: Key = count == 1 ? .patchFilesChangedOne : .patchFilesChangedMany
        return formatCount(key: key, count: count)
    }

    private static func formatCount(key: Key, count: Int) -> String {
        t(key).replacingOccurrences(of: "%d", with: count.formatted(.number.locale(currentLocale)))
    }

    static func toolOpenFileLabel(path: String) -> String {
        return t(.toolOpenInFileTree, path)
    }

    static func helpForURLScheme(isLocal: Bool, isTailscale: Bool) -> String {
        if isTailscale { return t(.helpTailscaleHttp) }
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
