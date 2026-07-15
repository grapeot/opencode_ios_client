import Foundation
@preconcurrency import AVFoundation

@MainActor
protocol CarSpeechOutputProviding: AnyObject {
    func speak(_ text: String) async
    func stop()
}

nonisolated enum CarSpeechAudioPolicy {
    static let category: AVAudioSession.Category = .playback
    static let mode: AVAudioSession.Mode = .spokenAudio
    static let options: AVAudioSession.CategoryOptions = [.duckOthers]
}

@MainActor
final class CarSpeechOutputService: NSObject, AVSpeechSynthesizerDelegate, CarSpeechOutputProviding {
    private let synthesizer = AVSpeechSynthesizer()
    private var continuation: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) async {
        stop()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        // VoiceFlow leaves the shared session in a recording-oriented route.
        // Reset it before TTS so playback reaches the speaker, car, or A2DP route.
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        try? audioSession.setCategory(
            CarSpeechAudioPolicy.category,
            mode: CarSpeechAudioPolicy.mode,
            options: CarSpeechAudioPolicy.options
        )
        try? audioSession.setActive(true)
        #endif

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: preferredLanguage(for: text))
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = 1
        utterance.preUtteranceDelay = 0.05

        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                synthesizer.speak(utterance)
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.stop() }
        }
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        finishCurrentUtterance()
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.finishCurrentUtterance() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.finishCurrentUtterance() }
    }

    private func finishCurrentUtterance() {
        let pending = continuation
        continuation = nil
        pending?.resume()
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    private func preferredLanguage(for text: String) -> String {
        text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) } ? "zh-CN" : "en-US"
    }
}
