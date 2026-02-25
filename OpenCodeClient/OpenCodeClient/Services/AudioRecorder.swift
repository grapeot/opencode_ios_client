//
//  AudioRecorder.swift
//  OpenCodeClient
//

import AVFoundation
import Foundation

final class AudioRecorder: NSObject, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    private(set) var currentFileURL: URL?

    var isRecording: Bool { recorder?.isRecording == true }

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

    func start() throws {
        #if os(iOS) || os(visionOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true, options: [])
        #endif

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("opencode-recording-\(UUID().uuidString).m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000,
        ]

        let r = try AVAudioRecorder(url: url, settings: settings)
        r.delegate = self
        r.isMeteringEnabled = false
        r.record()

        recorder = r
        currentFileURL = url
    }

    func stop() -> URL? {
        recorder?.stop()
        recorder = nil
        return currentFileURL
    }
}
