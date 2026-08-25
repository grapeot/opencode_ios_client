//
//  AIBuilderVoiceTests.swift
//  OpenCodeClientTests
//

import Foundation
import Testing
import VoiceFlowKit
@testable import OpenCodeClient

private actor SpeechSenderTestLatch {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let pendingWaiters = waiters
        waiters.removeAll()
        for waiter in pendingWaiters {
            waiter.resume()
        }
    }
}

private actor SpeechSenderTestRecorder {
    private(set) var values: [UInt8] = []

    func append(_ value: UInt8) {
        values.append(value)
    }
}

// MARK: - Speech Recognition Defaults

@Suite(.serialized)
struct SpeechRecognitionDefaultsTests {

    @Test @MainActor func speechRecognitionDefaultPromptAndTerminology() async {
        // Clear stored values so AppState falls back to defaults
        UserDefaults.standard.removeObject(forKey: "aiBuilderCustomPrompt")
        UserDefaults.standard.removeObject(forKey: "aiBuilderTerminology")
        let state = AppState()
        #expect(state.aiBuilderCustomPrompt.contains("snake_case"))
        #expect(state.aiBuilderCustomPrompt.contains("lowercase"))
        #expect(state.aiBuilderTerminology == "adhoc_jobs, life_consulting, survey_sessions, thought_review")
    }

    @Test @MainActor func speechRecognitionPersistence() async {
        let state = AppState()
        state.aiBuilderCustomPrompt = "test prompt"
        state.aiBuilderTerminology = "foo, bar"
        #expect(state.aiBuilderCustomPrompt == "test prompt")
        #expect(state.aiBuilderTerminology == "foo, bar")
        // Restore defaults for other tests
        UserDefaults.standard.removeObject(forKey: "aiBuilderCustomPrompt")
        UserDefaults.standard.removeObject(forKey: "aiBuilderTerminology")
    }

    @Test @MainActor func recordingStrategyPersistsAndDefaultsToGPTLive() async {
        let oldValue = UserDefaults.standard.string(forKey: AppState.aiBuilderRecordingStrategyKey)
        UserDefaults.standard.removeObject(forKey: AppState.aiBuilderRecordingStrategyKey)
        defer {
            if let oldValue {
                UserDefaults.standard.set(oldValue, forKey: AppState.aiBuilderRecordingStrategyKey)
            } else {
                UserDefaults.standard.removeObject(forKey: AppState.aiBuilderRecordingStrategyKey)
            }
        }
        let defaultState = AppState()
        #expect(defaultState.aiBuilderRecordingStrategy == .gptLiveTranscribe)

        for strategy in VoiceFlowRecordingStrategy.allCases {
            defaultState.aiBuilderRecordingStrategy = strategy
            #expect(AppState().aiBuilderRecordingStrategy == strategy)
        }
    }

    @Test func strategyRawValuesAndRealtimeCapabilityRemainStable() {
        #expect(VoiceFlowRecordingStrategy.openAIRealtime.rawValue == "openAIRealtime")
        #expect(VoiceFlowRecordingStrategy.gptLiveTranscribe.rawValue == "gptLiveTranscribe")
        #expect(VoiceFlowRecordingStrategy.grokBatch.rawValue == "grokBatch")
        #expect(VoiceFlowRecordingStrategy.openAIRealtime.usesRealtimeTransport)
        #expect(VoiceFlowRecordingStrategy.gptLiveTranscribe.usesRealtimeTransport)
        #expect(!VoiceFlowRecordingStrategy.grokBatch.usesRealtimeTransport)
    }
}

struct ChatComposerSpeechTests {

    @Test func mergedSpeechInputOmitsLeadingSpaceForEmptyPrefix() {
        #expect(ChatTabView.mergedSpeechInput(prefix: "", transcript: " hello world ") == "hello world")
    }

    @Test func mergedSpeechInputKeepsSeparatorForExistingInput() {
        #expect(ChatTabView.mergedSpeechInput(prefix: "Existing draft", transcript: "partial") == "Existing draft partial")
    }

    @Test func liveSpeechInputOnlyRendersGPTLiveSnapshots() {
        #expect(ChatTabView.liveSpeechInput(
            strategy: .gptLiveTranscribe,
            prefix: "Existing draft",
            transcript: "live words"
        ) == "Existing draft live words")
        #expect(ChatTabView.liveSpeechInput(
            strategy: .openAIRealtime,
            prefix: "Existing draft",
            transcript: "hidden words"
        ) == nil)
    }

    @Test func speechFailureInputPreservesLastPartialTranscript() {
        #expect(ChatTabView.speechFailureInput(prefix: "", lastPartialTranscript: "partial result") == "partial result")
        #expect(ChatTabView.speechFailureInput(prefix: "Existing draft", lastPartialTranscript: "partial result") == "Existing draft partial result")
    }

    @Test func speechFailureInputFallsBackToPrefixWithoutPartialTranscript() {
        #expect(ChatTabView.speechFailureInput(prefix: "Existing draft", lastPartialTranscript: "   ") == "Existing draft")
    }

    @Test func finalSpeechResultReplacesPartialWithoutDuplicatingPrefix() {
        let prefix = "Existing draft"
        let partial = ChatTabView.mergedSpeechInput(prefix: prefix, transcript: "partial")
        let final = ChatTabView.mergedSpeechInput(prefix: prefix, transcript: "final result")
        #expect(partial == "Existing draft partial")
        #expect(final == "Existing draft final result")
    }

    @Test func speechAttemptGateRejectsStaleAndCompletedAttempts() {
        let current = UUID()
        #expect(SpeechAttemptGate.accepts(
            current,
            activeAttemptID: current,
            originatingSessionID: "session-1",
            currentSessionID: "session-1"
        ))
        #expect(!SpeechAttemptGate.accepts(
            UUID(),
            activeAttemptID: current,
            originatingSessionID: "session-1",
            currentSessionID: "session-1"
        ))
        #expect(!SpeechAttemptGate.accepts(
            current,
            activeAttemptID: nil,
            originatingSessionID: "session-1",
            currentSessionID: "session-1"
        ))
        #expect(!SpeechAttemptGate.accepts(
            current,
            activeAttemptID: current,
            originatingSessionID: "session-1",
            currentSessionID: "session-2"
        ))

        var activeAttemptID: UUID? = current
        var acceptedCallbacks = 0
        for _ in 0..<2 where SpeechAttemptGate.accepts(
            current,
            activeAttemptID: activeAttemptID,
            originatingSessionID: "session-1",
            currentSessionID: "session-1"
        ) {
            activeAttemptID = nil
            acceptedCallbacks += 1
        }
        #expect(acceptedCallbacks == 1)
    }

    @Test func chatSpeechOwnersKeepPendingAudioSessionScoped() {
        #expect(ChatSpeechOwner(sessionID: "session-1") == .session("session-1"))
        #expect(ChatSpeechOwner(sessionID: "session-1") != ChatSpeechOwner(sessionID: "session-2"))
        #expect(ChatSpeechOwner(sessionID: nil) == .noSession)
    }

    @Test @MainActor func completedSpeechAfterSwitchUpdatesOnlySourceDraft() {
        let sourceSessionID = "speech-source"
        let destinationSessionID = "speech-destination"
        let state = AppState()
        defer {
            state.setDraftText("", for: sourceSessionID)
            state.setDraftText("", for: destinationSessionID)
        }
        state.setDraftText("destination draft", for: destinationSessionID)

        // Navigation snapshots the old composer before asynchronous cleanup starts.
        state.setDraftText("source prefix", for: sourceSessionID)
        let route = ChatSpeechRouting.draftRoute(
            prefix: "source prefix",
            transcript: "completed utterance",
            sourceSessionID: sourceSessionID,
            currentSessionID: destinationSessionID
        )
        state.setDraftText(route.sourceDraftText, for: route.sourceSessionID)

        #expect(route.currentComposerText == nil)
        #expect(state.draftText(for: sourceSessionID) == "source prefix completed utterance")
        #expect(state.draftText(for: destinationSessionID) == "destination draft")
    }

    @Test @MainActor func sessionSwitchDetachesFinalizationWithoutRevokingOwnership() {
        let finalizationID = UUID()
        #expect(ChatSpeechRouting.navigationDisposition(
            detachFinalizationOnSessionSwitch: true,
            finalizationID: finalizationID,
            sourceSessionID: "speech-source",
            currentSessionID: "speech-destination"
        ) == .detachFinalization)
        #expect(SpeechAttemptGate.owns(finalizationID, activeAttemptID: finalizationID))
        #expect(!SpeechAttemptGate.accepts(
            finalizationID,
            activeAttemptID: finalizationID,
            originatingSessionID: "speech-source",
            currentSessionID: "speech-destination"
        ))

        #expect(ChatSpeechRouting.navigationDisposition(
            detachFinalizationOnSessionSwitch: false,
            finalizationID: finalizationID,
            sourceSessionID: "speech-source",
            currentSessionID: "speech-destination"
        ) == .cancelAndPreserve)
        #expect(ChatSpeechRouting.navigationDisposition(
            detachFinalizationOnSessionSwitch: true,
            finalizationID: nil,
            sourceSessionID: "speech-source",
            currentSessionID: "speech-destination"
        ) == .cancelAndPreserve)
    }

    @Test @MainActor func completedSpeechWithoutSwitchStillTargetsCurrentComposer() {
        let route = ChatSpeechRouting.draftRoute(
            prefix: "source prefix",
            transcript: "completed utterance",
            sourceSessionID: "speech-source",
            currentSessionID: "speech-source"
        )
        #expect(route.sourceDraftText == "source prefix completed utterance")
        #expect(route.currentComposerText == route.sourceDraftText)
    }

    @Test func carSpeechAttemptGateRejectsOldGenerations() {
        let current = UUID()
        let generation = UUID()
        #expect(CarSpeechAttemptGate.accepts(
            current,
            activeAttemptID: current,
            generation: generation,
            currentGeneration: generation
        ))
        #expect(!CarSpeechAttemptGate.accepts(
            current,
            activeAttemptID: current,
            generation: UUID(),
            currentGeneration: generation
        ))
        #expect(!CarSpeechAttemptGate.accepts(
            UUID(),
            activeAttemptID: current,
            generation: generation,
            currentGeneration: generation
        ))
    }

    @Test func orderedSpeechAudioSenderPreservesOrderBoundsAndDrain() async {
        let firstSendStarted = SpeechSenderTestLatch()
        let releaseFirstSend = SpeechSenderTestLatch()
        let capacityReached = SpeechSenderTestLatch()
        let recorder = SpeechSenderTestRecorder()
        let sender = OrderedSpeechAudioSender(capacity: 2) { chunk in
            guard let value = chunk.first else { return }
            await recorder.append(value)
            if value == 0 {
                await firstSendStarted.open()
                await releaseFirstSend.wait()
            }
        }

        #expect(sender.enqueue(Data([0])))
        await firstSendStarted.wait()

        let producer = Task.detached {
            guard sender.enqueue(Data([1])), sender.enqueue(Data([2])) else { return false }
            await capacityReached.open()
            return sender.enqueue(Data([3]))
        }
        await capacityReached.wait()
        #expect(sender.maximumBufferedCount == 2)

        await releaseFirstSend.open()
        let producerFinished = await producer.value
        #expect(producerFinished)
        await sender.finishAndDrain()

        let sentValues = await recorder.values
        #expect(sentValues == [0, 1, 2, 3])
        #expect(!sender.enqueue(Data([4])))
    }

    @Test func closedPartialBufferRejectsLateCallbacks() {
        let buffer = SpeechPartialTranscriptBuffer()
        #expect(buffer.update("partial"))
        buffer.close()
        #expect(!buffer.update("stale"))
        #expect(buffer.current() == "partial")
    }

    @Test func speechTranscriptAutoScrollsOnlyDuringGeneratedUpdates() {
        #expect(ChatTabView.shouldAutoScrollSpeechTranscript(isTranscribing: true, isRetryingSpeech: false) == true)
        #expect(ChatTabView.shouldAutoScrollSpeechTranscript(isTranscribing: false, isRetryingSpeech: true) == true)
        #expect(ChatTabView.shouldAutoScrollSpeechTranscript(isTranscribing: false, isRetryingSpeech: false) == false)
    }

    @Test func chatComposerReturnUsesSystemDuringMarkedTextComposition() {
        #expect(ChatComposerKeyAction.action(for: "\n", hasMarkedText: true, isShiftReturn: false) == .system)
    }

    @Test func chatComposerPlainReturnInsertsNewlineWhenNoMarkedText() {
        #expect(ChatComposerKeyAction.action(for: "\n", hasMarkedText: false, isShiftReturn: false) == .insertNewline)
    }

    @Test func chatComposerShiftReturnInsertsNewlineWhenNoMarkedText() {
        #expect(ChatComposerKeyAction.action(for: "\n", hasMarkedText: false, isShiftReturn: true) == .insertNewline)
    }

    @Test func chatComposerNonReturnLeavesSystemHandling() {
        #expect(ChatComposerKeyAction.action(for: "x", hasMarkedText: false, isShiftReturn: false) == .system)
    }

    @Test func chatComposerSendGateRejectsMarkedText() {
        #expect(ChatComposerSendGate.canSend(text: "nihao", isSending: false, hasMarkedText: true) == false)
    }

    @Test func chatComposerSendGateRejectsWhitespaceAndActiveSend() {
        #expect(ChatComposerSendGate.canSend(text: "   ", isSending: false, hasMarkedText: false) == false)
        #expect(ChatComposerSendGate.canSend(text: "hello", isSending: true, hasMarkedText: false) == false)
    }

    @Test func chatComposerSendGateAllowsCommittedText() {
        #expect(ChatComposerSendGate.canSend(text: "hello", isSending: false, hasMarkedText: false) == true)
    }
}

// MARK: - VoiceFlowKit integration tests

struct VoiceFlowKitIntegrationTests {

    @Test @MainActor func transcribeAudioThrowsMissingTokenWhenTokenEmpty() async {
        let state = AppState()
        state.aiBuilderToken = "   "
        await #expect(throws: VoiceFlowError.missingToken) {
            _ = try await state.transcribeAudio(
                audioFileURL: URL(fileURLWithPath: "/tmp/does-not-exist.wav"),
                strategy: .gptLiveTranscribe,
                surface: .chat
            )
        }
    }

    @Test @MainActor func startRealtimeSpeechSessionThrowsMissingTokenWhenTokenEmpty() async {
        let state = AppState()
        state.aiBuilderToken = ""
        await #expect(throws: VoiceFlowError.missingToken) {
            _ = try await state.startRealtimeSpeechSession(strategy: .gptLiveTranscribe, surface: .car)
        }
    }
}
