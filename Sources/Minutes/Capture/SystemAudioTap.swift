// Adapted from Muesli (https://github.com/Muesli-HQ/muesli),
// native/MuesliNative/Sources/MuesliNativeApp/CoreAudioSystemRecorder.swift
// Copyright (c) 2026 Pranav Hari. MIT License; see THIRD_PARTY_NOTICES.md.

import AVFoundation
import CoreAudio
import Foundation

/// Captures the audio played by every other process through a Core Audio process tap wrapped in a private
/// aggregate device, and delivers it as 16 kHz mono Int16 samples.
///
/// The global tap sits upstream of the output device, so it keeps working when the output route changes
/// (headphones connected mid-meeting) without a rebuild.
// HAL handles are only touched by start()/stop(), which the owning RecordingSession actor serializes; sample
// conversion state lives in `SampleMixer`, confined to `processingQueue`.
final class SystemAudioTap: @unchecked Sendable {
    enum TapError: LocalizedError {
        case processLookupFailed
        case tapCreationFailed(OSStatus)
        case aggregateDeviceCreationFailed(OSStatus)
        case setupFailed(String, OSStatus)

        var errorDescription: String? {
            switch self {
            case .processLookupFailed: "Could not identify Minutes to exclude it from system audio."
            case .tapCreationFailed(let status): "System audio capture could not start (tap status \(status))."
            case .aggregateDeviceCreationFailed(let status): "System audio capture could not start (device status \(status))."
            case .setupFailed(let step, let status): "System audio capture failed at \(step) (status \(status))."
            }
        }
    }

    private static let deviceName = "Minutes System Audio"
    // A stable UID keeps a crashed session from accumulating HAL entries; the fallback covers a phantom device
    // still holding the stable one.
    private static let aggregateUIDs = ["com.minutes.system-audio-tap", "com.minutes.system-audio-tap-fallback"]

    private let onSamples: @Sendable ([Int16]) -> Void
    private let ioQueue = DispatchQueue(label: "com.minutes.system-audio.io", qos: .userInitiated)
    private let processingQueue = DispatchQueue(label: "com.minutes.system-audio.processing", qos: .userInitiated)
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID = AudioDeviceID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?

    init(onSamples: @escaping @Sendable ([Int16]) -> Void) {
        self.onSamples = onSamples
    }

    deinit { stop() }

    func start() throws {
        guard ioProcID == nil else { return }
        do {
            let tapDescription = try Self.makeTapDescription(name: "Minutes System Audio Tap")
            var status = AudioHardwareCreateProcessTap(tapDescription, &tapID)
            guard status == noErr, tapID != kAudioObjectUnknown else { throw TapError.tapCreationFailed(status) }

            // The tap list must hold UID dictionaries, not CATapDescription objects (those crash Core Audio).
            for uid in Self.aggregateUIDs {
                let description: NSDictionary = [
                    kAudioAggregateDeviceNameKey: Self.deviceName,
                    kAudioAggregateDeviceUIDKey: uid,
                    kAudioAggregateDeviceIsPrivateKey: true,
                    kAudioAggregateDeviceTapAutoStartKey: true,
                    kAudioAggregateDeviceTapListKey: [[
                        kAudioSubTapUIDKey: tapDescription.uuid.uuidString,
                        kAudioSubTapDriftCompensationKey: true,
                    ]],
                ]
                status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateDeviceID)
                if status == noErr, aggregateDeviceID != kAudioObjectUnknown { break }
                aggregateDeviceID = kAudioObjectUnknown
            }
            guard aggregateDeviceID != kAudioObjectUnknown else { throw TapError.aggregateDeviceCreationFailed(status) }

            let format = try Self.streamFormat(of: tapID)
            let mixer = SampleMixer(format: format)
            let processingQueue = processingQueue
            let onSamples = onSamples
            var procID: AudioDeviceIOProcID?
            status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateDeviceID, ioQueue) { _, inputData, _, _, _ in
                let buffers = SampleMixer.copyBuffers(inputData)
                guard !buffers.isEmpty else { return }
                processingQueue.async {
                    let samples = mixer.convert(buffers)
                    if !samples.isEmpty { onSamples(samples) }
                }
            }
            guard status == noErr, let procID else { throw TapError.setupFailed("IOProc creation", status) }
            ioProcID = procID
            status = AudioDeviceStart(aggregateDeviceID, procID)
            guard status == noErr else { throw TapError.setupFailed("device start", status) }
        } catch {
            stop()
            throw error
        }
    }

    /// Stops capture. Samples already queued for conversion are delivered before this returns.
    func stop() {
        if let ioProcID, aggregateDeviceID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateDeviceID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
        }
        ioProcID = nil
        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = kAudioObjectUnknown
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
        ioQueue.sync {}
        processingQueue.sync {}
    }

    // MARK: - Permission

    /// There is no API to read the system-audio permission; creating a tap succeeds only when it is granted.
    static func hasPermission() -> Bool {
        guard let description = try? makeTapDescription(name: "Minutes Permission Check") else { return false }
        var probeID = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateProcessTap(description, &probeID) == noErr, probeID != kAudioObjectUnknown else {
            return false
        }
        AudioHardwareDestroyProcessTap(probeID)
        return true
    }

    /// The system asks for permission the first time an aggregate device with a tap starts recording, so a
    /// short capture is started and the probe polled until the user answers or the timeout passes.
    static func requestPermission(timeout: Duration = .seconds(12)) async -> Bool {
        if hasPermission() { return true }
        let tap = SystemAudioTap { _ in }
        try? tap.start()
        defer { tap.stop() }
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if hasPermission() { return true }
            try? await Task.sleep(for: .milliseconds(300))
        }
        return hasPermission()
    }

    /// Removes aggregate devices left behind by a crash. Call once at launch.
    static func cleanUpStaleDevices() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &devices) == noErr else { return }

        for device in devices {
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var name: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(device, &nameAddress, 0, nil, &nameSize, &name) == noErr,
                  let name, name.takeRetainedValue() as String == deviceName else { continue }
            AudioHardwareDestroyAggregateDevice(device)
        }
    }

    // MARK: - Helpers

    private static func makeTapDescription(name: String) throws -> CATapDescription {
        var pid = ProcessInfo.processInfo.processIdentifier
        var processObject = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address,
            UInt32(MemoryLayout<pid_t>.size), &pid, &size, &processObject
        )
        guard status == noErr, processObject != kAudioObjectUnknown else { throw TapError.processLookupFailed }

        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [processObject])
        description.name = name
        description.isPrivate = true
        description.muteBehavior = .unmuted
        return description
    }

    private static func streamFormat(of tapID: AudioObjectID) throws -> AudioStreamBasicDescription {
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format)
        guard status == noErr else { throw TapError.setupFailed("reading the tap format", status) }
        return format
    }
}

/// Mixes the tap's buffers to mono and resamples them to 16 kHz Int16.
// Used only on SystemAudioTap's serial processing queue.
private final class SampleMixer: @unchecked Sendable {
    struct CapturedBuffer: Sendable {
        let channels: Int
        let data: Data
    }

    private let format: AudioStreamBasicDescription
    private let converter: AVAudioConverter?
    private let inputFormat: AVAudioFormat?
    private let outputFormat: AVAudioFormat?

    init(format: AudioStreamBasicDescription) {
        self.format = format
        let target = Double(WavFormat.sampleRate)
        if abs(format.mSampleRate - target) >= 1,
           let input = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: format.mSampleRate, channels: 1, interleaved: false),
           let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: target, channels: 1, interleaved: false) {
            inputFormat = input
            outputFormat = output
            converter = AVAudioConverter(from: input, to: output)
        } else {
            inputFormat = nil
            outputFormat = nil
            converter = nil
        }
    }

    static func copyBuffers(_ inputData: UnsafePointer<AudioBufferList>) -> [CapturedBuffer] {
        UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData)).compactMap { buffer in
            guard let bytes = buffer.mData, buffer.mDataByteSize > 0 else { return nil }
            return CapturedBuffer(channels: Int(buffer.mNumberChannels), data: Data(bytes: bytes, count: Int(buffer.mDataByteSize)))
        }
    }

    func convert(_ buffers: [CapturedBuffer]) -> [Int16] {
        guard let mono = mixToMono(buffers), !mono.isEmpty else { return [] }
        return toInt16(resample(mono))
    }

    private func mixToMono(_ buffers: [CapturedBuffer]) -> [Float]? {
        guard format.mFormatID == kAudioFormatLinearPCM else { return nil }
        let isFloat = format.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let isNonInterleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        let frameChannels = max(Int(format.mChannelsPerFrame), 1)
        guard (isFloat && format.mBitsPerChannel == 32) || (!isFloat && format.mBitsPerChannel == 16) else { return nil }

        var mono: [Float] = []
        var channelsMixed = 0
        for buffer in buffers {
            let channels = isNonInterleaved ? max(buffer.channels, 1) : max(buffer.channels, frameChannels)
            let samples: [Float] = buffer.data.withUnsafeBytes { raw in
                isFloat ? Array(raw.bindMemory(to: Float.self)) : raw.bindMemory(to: Int16.self).map { Float($0) / 32768 }
            }
            let frames = samples.count / channels
            if mono.isEmpty { mono = [Float](repeating: 0, count: frames) }
            for frame in 0..<min(mono.count, frames) {
                for channel in 0..<channels { mono[frame] += samples[frame * channels + channel] }
            }
            channelsMixed += channels
        }
        guard channelsMixed > 0 else { return nil }
        let scale = 1 / Float(channelsMixed)
        return mono.map { $0 * scale }
    }

    private func resample(_ samples: [Float]) -> [Float] {
        guard let converter, let inputFormat, let outputFormat,
              let input = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(samples.count)) else {
            return samples
        }
        input.frameLength = AVAudioFrameCount(samples.count)
        input.floatChannelData![0].update(from: samples, count: samples.count)
        let capacity = AVAudioFrameCount(Double(samples.count) * outputFormat.sampleRate / inputFormat.sampleRate) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return [] }

        var provided = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if provided {
                inputStatus.pointee = .noDataNow
                return nil
            }
            provided = true
            inputStatus.pointee = .haveData
            return input
        }
        guard status != .error, error == nil, let channel = output.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }

    private func toInt16(_ samples: [Float]) -> [Int16] {
        samples.map { Int16(max(-1, min(1, $0)) * 32767) }
    }
}
