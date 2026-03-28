// AudioEngine.swift
// MeloNX Air5 Edition
//
// Audio emulation and mixing using AVAudioEngine with low-latency output.

import Foundation
import AVFoundation
import os.lock

/// Audio sample format produced by the emulator (stereo, 48 kHz, 16-bit PCM).
struct AudioSample {
    let left: Int16
    let right: Int16
}

/// Thread-safe ring buffer for audio samples, using a lock for producer/consumer safety.
final class AudioRingBuffer {
    private var buffer: [AudioSample]
    private var readIndex = 0
    private var writeIndex = 0
    private let capacity: Int
    private var lock = os_unfair_lock()

    init(capacity: Int = 4096) {
        self.capacity = capacity
        self.buffer = Array(repeating: AudioSample(left: 0, right: 0), count: capacity)
    }

    var availableRead: Int {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        let w = writeIndex, r = readIndex
        return w >= r ? w - r : capacity - r + w
    }

    func write(_ samples: [AudioSample]) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        for sample in samples {
            buffer[writeIndex] = sample
            writeIndex = (writeIndex + 1) % capacity
        }
    }

    func read(count: Int) -> [AudioSample] {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        let available = writeIndex >= readIndex
            ? writeIndex - readIndex
            : capacity - readIndex + writeIndex
        var result: [AudioSample] = []
        result.reserveCapacity(min(count, available))
        for _ in 0..<min(count, available) {
            result.append(buffer[readIndex])
            readIndex = (readIndex + 1) % capacity
        }
        return result
    }
}

/// Manages audio output for the emulator using AVAudioEngine.
/// Optimized for iPad Air 5's audio hardware with a target latency of ~5 ms.
final class EmulatorAudioEngine {

    // MARK: - Constants

    static let sampleRate: Double = 48_000
    static let channelCount: AVAudioChannelCount = 2
    static let bufferSize: AVAudioFrameCount = 256  // ~5.3 ms at 48 kHz

    // MARK: - AVAudioEngine

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let ringBuffer = AudioRingBuffer(capacity: 16384)

    private lazy var audioFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: Self.sampleRate,
        channels: Self.channelCount,
        interleaved: true
    )

    // MARK: - Init

    init() {
        configureAudioSession()
        configureEngine()
    }

    // MARK: - Lifecycle

    func start() {
        do {
            try engine.start()
            playerNode.play()
            scheduleNextBuffer()
        } catch {
            // Audio start failure – log and continue silently.
        }
    }

    func stop() {
        playerNode.stop()
        engine.stop()
    }

    // MARK: - Feed audio

    /// Push new audio samples from the emulator into the output queue.
    func pushSamples(_ samples: [AudioSample]) {
        ringBuffer.write(samples)
    }

    // MARK: - Private

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setPreferredIOBufferDuration(Double(Self.bufferSize) / Self.sampleRate)
        try? session.setActive(true)
    }

    private func configureEngine() {
        engine.attach(playerNode)
        guard let format = audioFormat else { return }
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
    }

    private func scheduleNextBuffer() {
        guard let format = audioFormat else { return }
        let frameCount = Int(Self.bufferSize)
        let samples = ringBuffer.read(count: frameCount)

        guard let pcmBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: Self.bufferSize
        ) else { return }

        pcmBuffer.frameLength = Self.bufferSize

        if let int16Ptr = pcmBuffer.int16ChannelData {
            for (i, sample) in samples.enumerated() {
                int16Ptr[0][i * 2]     = sample.left
                int16Ptr[0][i * 2 + 1] = sample.right
            }
        }

        playerNode.scheduleBuffer(pcmBuffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            self?.scheduleNextBuffer()
        }
    }
}
