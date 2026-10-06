import Foundation

/// 16 kHz mono 16-bit PCM WAV files: the only audio format Minutes writes while recording.
enum WavFormat {
    static let sampleRate = 16_000
    static let headerSize = 44
}

/// Streams samples into a WAV file; the header gets its final size on `finish()`. A file left behind by a crash
/// keeps a zero-size header, which `readSamples(from:)` ignores.
final class WavWriter {
    let url: URL
    private let handle: FileHandle
    private(set) var sampleCount = 0

    init(url: URL) throws {
        FileManager.default.createFile(atPath: url.path, contents: Self.header(sampleCount: 0))
        self.url = url
        self.handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
    }

    func append(_ samples: [Int16]) throws {
        guard !samples.isEmpty else { return }
        try handle.write(contentsOf: samples.withUnsafeBufferPointer { Data(buffer: $0) })
        sampleCount += samples.count
    }

    func finish() throws {
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: Self.header(sampleCount: sampleCount))
        try handle.close()
    }

    static func write(_ samples: [Int16], to url: URL) throws {
        var data = header(sampleCount: samples.count)
        samples.withUnsafeBufferPointer { data.append(Data(buffer: $0)) }
        try data.write(to: url, options: .atomic)
    }

    /// Reads the samples of a WAV written by this type. The header is ignored, so a file whose header was never
    /// finalized (crash) is still read completely.
    static func readSamples(from url: URL) throws -> [Int16] {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count > WavFormat.headerSize else { return [] }
        return data.dropFirst(WavFormat.headerSize).withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
    }

    static func header(sampleCount: Int) -> Data {
        let dataSize = UInt32(sampleCount * 2)
        let byteRate = UInt32(WavFormat.sampleRate * 2)
        var header = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) } }
        header.append(contentsOf: Array("RIFF".utf8)); append(36 + dataSize)
        header.append(contentsOf: Array("WAVE".utf8))
        header.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16))
        append(UInt16(1)); append(UInt16(1))  // PCM, mono
        append(UInt32(WavFormat.sampleRate)); append(byteRate)
        append(UInt16(2)); append(UInt16(16))  // block align, bits per sample
        header.append(contentsOf: Array("data".utf8)); append(dataSize)
        return header
    }
}
