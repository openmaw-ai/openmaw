import AVFoundation
import CoreAudio
import Foundation

struct RecordedAudio {
    let data: Data
    let filename: String
    let contentType: String
}

final class AudioRecorder {
    private var audioEngine = AVAudioEngine()
    private var buffers: [AVAudioPCMBuffer] = []
    private var isRecording = false

    private let sampleRate: Double = 16000
    private let channels: AVAudioChannelCount = 1

    private var silenceTimer: Timer?
    private var maxDurationTimer: Timer?
    private var speechDetected = false

    var onSilenceStop: ((RecordedAudio?) -> Void)?

    /// Reset the audio engine after system wake to pick up fresh device handles.
    func resetEngine() {
        audioEngine.stop()
        audioEngine.reset()
        audioEngine = AVAudioEngine()
    }

    // MARK: - Device Enumeration

    struct InputDevice {
        let id: AudioDeviceID
        let uid: String
        let name: String
    }

    static func availableInputDevices() -> [InputDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress, 0, nil, &dataSize
        )
        guard status == noErr, dataSize > 0 else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress, 0, nil, &dataSize, &deviceIDs
        )
        guard status == noErr else { return [] }

        var result: [InputDevice] = []
        for deviceID in deviceIDs {
            // Check if device has input channels
            var inputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var inputSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(deviceID, &inputAddress, 0, nil, &inputSize) == noErr,
                  inputSize > 0 else { continue }

            let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
            defer { bufferListPointer.deallocate() }
            guard AudioObjectGetPropertyData(deviceID, &inputAddress, 0, nil, &inputSize, bufferListPointer) == noErr else { continue }

            let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
            let inputChannels = bufferList.reduce(0) { $0 + Int($1.mNumberChannels) }
            guard inputChannels > 0 else { continue }

            // Get UID
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var uidRef: Unmanaged<CFString>?
            var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &uidSize, &uidRef) == noErr,
                  let uid = uidRef?.takeUnretainedValue() as String? else { continue }

            // Get name
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var nameRef: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, &nameRef) == noErr,
                  let name = nameRef?.takeUnretainedValue() as String? else { continue }

            result.append(InputDevice(id: deviceID, uid: uid, name: name))
        }
        return result
    }

    private func setInputDevice(uid: String) {
        let devices = AudioRecorder.availableInputDevices()
        guard let device = devices.first(where: { $0.uid == uid }) else { return }

        let inputNode = audioEngine.inputNode
        guard let audioUnit = inputNode.audioUnit else { return }

        var deviceID = device.id
        AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
    }

    func startRecording() {
        buffers.removeAll()
        speechDetected = false
        isRecording = true

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let recordingFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: false
        ) else {
            return
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: recordingFormat) else {
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self, self.isRecording else { return }

            let frameCount = AVAudioFrameCount(
                Double(buffer.frameLength) * self.sampleRate / inputFormat.sampleRate
            )
            guard frameCount > 0,
                  let convertedBuffer = AVAudioPCMBuffer(pcmFormat: recordingFormat, frameCapacity: frameCount)
            else { return }

            var error: NSError?
            let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            if status == .haveData {
                self.buffers.append(convertedBuffer)
            }
        }

        let selectedMic = Config.shared.selectedMicrophoneID
        if !selectedMic.isEmpty {
            setInputDevice(uid: selectedMic)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            print("Audio engine failed to start: \(error)")
            isRecording = false
        }
    }

    func recordUntilSilence() {
        startRecording()

        let config = Config.shared

        // Start max duration safety timer
        DispatchQueue.main.async {
            self.maxDurationTimer = Timer.scheduledTimer(withTimeInterval: config.maxRecordingDuration, repeats: false) { [weak self] _ in
                self?.stopAndDeliver()
            }
        }

        // Start silence detection polling
        DispatchQueue.main.async {
            self.silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.checkSilence()
            }
        }
    }

    private func checkSilence() {
        let config = Config.shared
        let threshold = config.silenceThresholdRMS
        let requiredSilenceDuration = config.silenceDuration

        // Calculate RMS of recent buffers (last ~0.1s)
        guard let lastBuffer = buffers.last,
              let channelData = lastBuffer.floatChannelData?[0]
        else { return }

        let frameLength = Int(lastBuffer.frameLength)
        guard frameLength > 0 else { return }

        var sumSquares: Float = 0
        for i in 0..<frameLength {
            let sample = channelData[i]
            sumSquares += sample * sample
        }
        let rms = sqrt(sumSquares / Float(frameLength))

        if rms > threshold {
            speechDetected = true
        }

        // Only auto-stop after speech has been detected
        guard speechDetected else { return }

        // Check if the last N seconds of buffers are all below threshold
        let buffersPerSecond = sampleRate / 1024.0
        let silenceBufferCount = Int(requiredSilenceDuration * buffersPerSecond)
        let recentCount = min(silenceBufferCount, buffers.count)

        guard recentCount > 0 else { return }

        let recentBuffers = buffers.suffix(recentCount)
        let allSilent = recentBuffers.allSatisfy { buf in
            guard let data = buf.floatChannelData?[0] else { return true }
            let len = Int(buf.frameLength)
            guard len > 0 else { return true }
            var ss: Float = 0
            for i in 0..<len {
                ss += data[i] * data[i]
            }
            return sqrt(ss / Float(len)) < threshold
        }

        if allSilent && recentCount >= silenceBufferCount {
            stopAndDeliver()
        }
    }

    private func stopAndDeliver() {
        let audio = stopRecording()
        onSilenceStop?(audio)
    }

    func stopRecording() -> RecordedAudio? {
        isRecording = false
        silenceTimer?.invalidate()
        silenceTimer = nil
        maxDurationTimer?.invalidate()
        maxDurationTimer = nil

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()

        guard !buffers.isEmpty else { return nil }

        if let m4aData = createM4AData() {
            return RecordedAudio(data: m4aData, filename: "audio.m4a", contentType: "audio/mp4")
        }
        if let wavData = createWAVData() {
            return RecordedAudio(data: wavData, filename: "audio.wav", contentType: "audio/wav")
        }
        return nil
    }

    private func createM4AData() -> Data? {
        let totalFrames = buffers.reduce(0) { $0 + Int($1.frameLength) }
        guard totalFrames > 0 else { return nil }

        guard let pcmFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: false
        ) else { return nil }

        // Collect all PCM samples into a single buffer
        guard let fullBuffer = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: AVAudioFrameCount(totalFrames)) else { return nil }
        var offset: AVAudioFrameCount = 0
        for buf in buffers {
            guard let src = buf.floatChannelData?[0],
                  let dst = fullBuffer.floatChannelData?[0] else { continue }
            let count = Int(buf.frameLength)
            (dst + Int(offset)).update(from: src, count: count)
            offset += buf.frameLength
        }
        fullBuffer.frameLength = offset

        // Write to a temp M4A file with AAC encoding
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let aacSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
        ]

        // Use a do block so AVAudioFile is deallocated (and flushed) before we read the data back
        do {
            let outputFile = try AVAudioFile(
                forWriting: tempURL,
                settings: aacSettings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            try outputFile.write(from: fullBuffer)
        } catch {
            return nil
        }

        return try? Data(contentsOf: tempURL)
    }

    private func createWAVData() -> Data? {
        // Count total frames
        let totalFrames = buffers.reduce(0) { $0 + Int($1.frameLength) }
        guard totalFrames > 0 else { return nil }

        // Collect all samples
        var allSamples = [Float]()
        allSamples.reserveCapacity(totalFrames)
        for buf in buffers {
            guard let channelData = buf.floatChannelData?[0] else { continue }
            let count = Int(buf.frameLength)
            for i in 0..<count {
                allSamples.append(channelData[i])
            }
        }

        // Convert Float32 samples to Int16
        let int16Samples = allSamples.map { sample -> Int16 in
            let clamped = max(-1.0, min(1.0, sample))
            return Int16(clamped * Float(Int16.max))
        }

        // Build WAV file
        let dataSize = int16Samples.count * 2
        let fileSize = 44 + dataSize

        var wav = Data()
        wav.reserveCapacity(fileSize)

        // RIFF header
        wav.append(contentsOf: "RIFF".utf8)
        wav.appendUInt32(UInt32(fileSize - 8))
        wav.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        wav.append(contentsOf: "fmt ".utf8)
        wav.appendUInt32(16)            // chunk size
        wav.appendUInt16(1)             // PCM format
        wav.appendUInt16(UInt16(channels))
        wav.appendUInt32(UInt32(sampleRate))
        wav.appendUInt32(UInt32(sampleRate) * UInt32(channels) * 2) // byte rate
        wav.appendUInt16(UInt16(channels) * 2) // block align
        wav.appendUInt16(16)            // bits per sample

        // data chunk
        wav.append(contentsOf: "data".utf8)
        wav.appendUInt32(UInt32(dataSize))

        for sample in int16Samples {
            wav.appendUInt16(UInt16(bitPattern: sample))
        }

        return wav
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        var v = value.littleEndian
        append(Data(bytes: &v, count: 2))
    }

    mutating func appendUInt32(_ value: UInt32) {
        var v = value.littleEndian
        append(Data(bytes: &v, count: 4))
    }
}
