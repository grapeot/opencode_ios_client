//
//  AudioRecorder.swift
//  OpenCodeClient
//

import AVFoundation
import Foundation
import os

final class AudioRecorder {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "OpenCodeClient",
        category: "SpeechProfile"
    )

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    private let audioProcessingQueue = DispatchQueue(label: "com.grapeot.OpenCodeClient.liveAudioProcessing")
    private let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 24_000,
        channels: 1,
        interleaved: true
    )!
    private var chunkHandler: (@Sendable (Data) -> Void)?

    var isRecording: Bool { engine.isRunning }

    func requestPermission() async -> Bool {
        #if os(iOS) || os(visionOS)
        if #available(iOS 17.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        } else {
            return await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                    continuation.resume(returning: allowed)
                }
            }
        }
        #else
        return false
        #endif
    }

    func start(onPCMChunk: @escaping @Sendable (Data) -> Void) throws {
        #if os(iOS) || os(visionOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true, options: [])
        #endif

        let inputNode = engine.inputNode
        let sourceFormat = inputNode.outputFormat(forBus: 0)
        guard sourceFormat.channelCount > 0 else {
            throw AIBuildersAudioError.audioConversionFailed
        }
        guard let converter = AVAudioConverter(from: sourceFormat, to: outputFormat) else {
            throw AIBuildersAudioError.audioConversionFailed
        }

        self.inputFormat = sourceFormat
        self.converter = converter
        self.chunkHandler = onPCMChunk

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: sourceFormat) { [weak self] buffer, _ in
            self?.audioProcessingQueue.sync {
                self?.handleInputBuffer(buffer)
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            self.inputFormat = nil
            self.converter = nil
            self.chunkHandler = nil
            throw error
        }
    }

    func stop() {
        if inputFormat != nil {
            engine.inputNode.removeTap(onBus: 0)
        }
        engine.stop()
        audioProcessingQueue.sync {}
        inputFormat = nil
        converter = nil
        chunkHandler = nil
        #if os(iOS) || os(visionOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        #endif
    }

    private func handleInputBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let data = convertToPCM16Mono24k(buffer), !data.isEmpty else { return }
        chunkHandler?(data)
    }

    private func convertToPCM16Mono24k(_ inputBuffer: AVAudioPCMBuffer) -> Data? {
        guard let converter else { return nil }
        let ratio = outputFormat.sampleRate / inputBuffer.format.sampleRate
        let outputCapacity = max(1, AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio) + 8)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputCapacity) else {
            return nil
        }

        var didProvideInput = false
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if didProvideInput {
                outStatus.pointee = .noDataNow
                return nil
            }
            didProvideInput = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        if status == .error {
            Self.logger.error("[SpeechProfile] live audio convert failed error=\(String(describing: conversionError), privacy: .public)")
            return nil
        }
        guard outputBuffer.frameLength > 0 else { return nil }

        let audioBuffer = outputBuffer.audioBufferList.pointee.mBuffers
        guard let bytes = audioBuffer.mData, audioBuffer.mDataByteSize > 0 else { return nil }
        return Data(bytes: bytes, count: Int(audioBuffer.mDataByteSize))
    }
}
