// Adapted from Muesli (https://github.com/Muesli-HQ/muesli),
// native/MuesliNative/Sources/MuesliNativeApp/StreamingMicRecorder.swift
// Copyright (c) 2026 Pranav Hari. MIT License; see THIRD_PARTY_NOTICES.md.

import AudioGraphShim
@preconcurrency import AVFoundation
import Foundation

/// Captures the default microphone with AVAudioEngine and delivers 16 kHz mono Int16 samples.
///
/// When the default input changes mid-recording (AirPods connected), AVAudioEngine stops delivering buffers
/// and posts a configuration change; the recorder waits for the route to settle and restarts on the new device.
// Every engine operation runs on `queue`, which serializes start, stop and configuration-change restarts.
final class MicRecorder: @unchecked Sendable {
    private static let bufferSize: AVAudioFrameCount = 4096
    private static let routeSettleDelay: TimeInterval = 1.5

    private let onSamples: @Sendable ([Int16]) -> Void
    private let onFailure: @Sendable (Error) -> Void
    private let queue = DispatchQueue(label: "com.minutes.mic")
    private let engine = AVAudioEngine()
    private var isRunning = false
    private var observer: NSObjectProtocol?
    private var pendingRestart: DispatchWorkItem?

    init(onSamples: @escaping @Sendable ([Int16]) -> Void, onFailure: @escaping @Sendable (Error) -> Void) {
        self.onSamples = onSamples
        self.onFailure = onFailure
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func start() throws {
        try queue.sync {
            guard !isRunning else { return }
            try startEngine()
            isRunning = true
            observer = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
            ) { [weak self] _ in
                self?.scheduleRestart()
            }
        }
    }

    func stop() {
        queue.sync {
            guard isRunning else { return }
            isRunning = false
            pendingRestart?.cancel()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            _ = MinutesAudioGraphStopEngine(engine)
        }
    }

    private func startEngine() throws {
        var formatError: NSError?
        guard let hardwareFormat = MinutesAudioGraphInputFormat(engine, &formatError) else {
            throw formatError ?? CocoaError(.featureUnsupported)
        }
        let converter = try Int16Converter(from: hardwareFormat)
        let onSamples = onSamples
        if let error = MinutesAudioGraphInstallInputTap(engine, Self.bufferSize, { buffer, _ in
            let samples = converter.convert(buffer)
            if !samples.isEmpty { onSamples(samples) }
        }) {
            throw error
        }
        if let error = MinutesAudioGraphStartEngine(engine) {
            _ = MinutesAudioGraphStopEngine(engine)
            throw error
        }
    }

    // A route change fires a burst of notifications; restarting mid-burst fails, so restart once it is quiet.
    private func scheduleRestart() {
        queue.async { [self] in
            pendingRestart?.cancel()
            let item = DispatchWorkItem { [weak self] in self?.restart() }
            pendingRestart = item
            queue.asyncAfter(deadline: .now() + Self.routeSettleDelay, execute: item)
        }
    }

    private func restart() {
        guard isRunning else { return }
        _ = MinutesAudioGraphStopEngine(engine)
        do {
            try startEngine()
        } catch {
            isRunning = false
            onFailure(error)
        }
    }
}

/// Converts microphone buffers in the hardware format to 16 kHz mono Int16.
// Used only from the engine's tap callback, which AVAudioEngine invokes serially.
private final class Int16Converter: @unchecked Sendable {
    private let converter: AVAudioConverter?
    private let targetFormat: AVAudioFormat

    init(from hardwareFormat: AVAudioFormat) throws {
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(WavFormat.sampleRate), channels: 1, interleaved: false) else {
            throw CocoaError(.featureUnsupported)
        }
        targetFormat = target
        let needsConversion = hardwareFormat.sampleRate != target.sampleRate || hardwareFormat.channelCount != 1
            || hardwareFormat.commonFormat != .pcmFormatFloat32
        converter = needsConversion ? AVAudioConverter(from: hardwareFormat, to: target) : nil
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> [Int16] {
        var mono = buffer
        if let converter {
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * targetFormat.sampleRate / buffer.format.sampleRate) + 32
            guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return [] }
            var provided = false
            var error: NSError?
            converter.convert(to: output, error: &error) { _, status in
                if provided {
                    status.pointee = .noDataNow
                    return nil
                }
                provided = true
                status.pointee = .haveData
                return buffer
            }
            guard error == nil else { return [] }
            mono = output
        }
        guard let channel = mono.floatChannelData?[0] else { return [] }
        return UnsafeBufferPointer(start: channel, count: Int(mono.frameLength)).map { Int16(max(-1, min(1, $0)) * 32767) }
    }
}
