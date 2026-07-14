import Foundation

nonisolated enum FluidVoiceWAVError: LocalizedError, Equatable {
    case emptyAudio
    case invalidPCM
    case audioTooLong
    case invalidWAV

    var errorDescription: String? {
        switch self {
        case .emptyAudio:
            return "No audio was recorded."
        case .invalidPCM:
            return "The recorded audio is not valid PCM16 audio."
        case .audioTooLong:
            return "FluidVoice recordings are limited to 300 seconds."
        case .invalidWAV:
            return "The recorded audio is not a valid WAV file."
        }
    }
}

nonisolated struct FluidVoiceWAVMetadata: Equatable, Sendable {
    let sampleRate: UInt32
    let channelCount: UInt16
    let bitsPerSample: UInt16
    let pcmByteCount: Int

    var duration: TimeInterval {
        let bytesPerSecond = Double(sampleRate) * Double(channelCount) * Double(bitsPerSample / 8)
        return bytesPerSecond > 0 ? Double(pcmByteCount) / bytesPerSecond : 0
    }
}

nonisolated enum FluidVoiceWAV {
    static let sampleRate: UInt32 = 24_000
    static let channelCount: UInt16 = 1
    static let bitsPerSample: UInt16 = 16
    static let headerByteCount = 44
    static let maximumDuration: TimeInterval = 300
    static let maximumPCMByteCount = Int(sampleRate) * Int(channelCount) * Int(bitsPerSample / 8) * Int(maximumDuration)

    static func makeData(pcmData: Data) throws -> Data {
        guard !pcmData.isEmpty else { throw FluidVoiceWAVError.emptyAudio }
        guard pcmData.count.isMultiple(of: 2) else { throw FluidVoiceWAVError.invalidPCM }
        guard pcmData.count <= maximumPCMByteCount else { throw FluidVoiceWAVError.audioTooLong }
        guard pcmData.count <= Int(UInt32.max) - 36 else { throw FluidVoiceWAVError.audioTooLong }

        let byteRate = sampleRate * UInt32(channelCount) * UInt32(bitsPerSample / 8)
        let blockAlign = channelCount * (bitsPerSample / 8)
        var wav = Data(capacity: headerByteCount + pcmData.count)
        appendASCII("RIFF", to: &wav)
        appendUInt32LE(36 + UInt32(pcmData.count), to: &wav)
        appendASCII("WAVE", to: &wav)
        appendASCII("fmt ", to: &wav)
        appendUInt32LE(16, to: &wav)
        appendUInt16LE(1, to: &wav)
        appendUInt16LE(channelCount, to: &wav)
        appendUInt32LE(sampleRate, to: &wav)
        appendUInt32LE(byteRate, to: &wav)
        appendUInt16LE(blockAlign, to: &wav)
        appendUInt16LE(bitsPerSample, to: &wav)
        appendASCII("data", to: &wav)
        appendUInt32LE(UInt32(pcmData.count), to: &wav)
        wav.append(pcmData)
        return wav
    }

    static func write(pcmData: Data, to url: URL) throws {
        let wav = try makeData(pcmData: pcmData)
        try wav.write(to: url, options: .atomic)
    }

    static func validate(fileURL: URL) throws -> FluidVoiceWAVMetadata {
        let fileSize = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard fileSize >= headerByteCount else { throw FluidVoiceWAVError.invalidWAV }

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        guard let header = try handle.read(upToCount: headerByteCount), header.count == headerByteCount else {
            throw FluidVoiceWAVError.invalidWAV
        }

        guard ascii(in: header, range: 0..<4) == "RIFF",
              uint32LE(in: header, offset: 4) == UInt32(fileSize - 8),
              ascii(in: header, range: 8..<12) == "WAVE",
              ascii(in: header, range: 12..<16) == "fmt ",
              uint32LE(in: header, offset: 16) == 16,
              uint16LE(in: header, offset: 20) == 1,
              ascii(in: header, range: 36..<40) == "data" else {
            throw FluidVoiceWAVError.invalidWAV
        }

        let channels = uint16LE(in: header, offset: 22)
        let rate = uint32LE(in: header, offset: 24)
        let bits = uint16LE(in: header, offset: 34)
        let dataSize = Int(uint32LE(in: header, offset: 40))
        guard channels == channelCount,
              rate == sampleRate,
              bits == bitsPerSample,
              uint32LE(in: header, offset: 28) == sampleRate * 2,
              uint16LE(in: header, offset: 32) == 2,
              dataSize > 0,
              fileSize == headerByteCount + dataSize else {
            throw FluidVoiceWAVError.invalidWAV
        }

        let metadata = FluidVoiceWAVMetadata(
            sampleRate: rate,
            channelCount: channels,
            bitsPerSample: bits,
            pcmByteCount: dataSize
        )
        guard metadata.duration <= maximumDuration else { throw FluidVoiceWAVError.audioTooLong }
        return metadata
    }

    private static func appendASCII(_ value: String, to data: inout Data) {
        data.append(Data(value.utf8))
    }

    private static func appendUInt16LE(_ value: UInt16, to data: inout Data) {
        var littleEndian = value.littleEndian
        data.append(Data(bytes: &littleEndian, count: MemoryLayout<UInt16>.size))
    }

    private static func appendUInt32LE(_ value: UInt32, to data: inout Data) {
        var littleEndian = value.littleEndian
        data.append(Data(bytes: &littleEndian, count: MemoryLayout<UInt32>.size))
    }

    private static func ascii(in data: Data, range: Range<Int>) -> String? {
        String(data: data.subdata(in: range), encoding: .ascii)
    }

    private static func uint16LE(in data: Data, offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func uint32LE(in data: Data, offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}
