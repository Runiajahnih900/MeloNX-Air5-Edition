//
//  LogCapture.swift
//  MeloNX
//
//  Created by Stossy11 on 22/09/2025.
//


import Foundation
#if canImport(Network)
import Network
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AVFAudio)
import AVFAudio
#endif

final class LogCapture: ObservableObject {
    static let shared = LogCapture()
    private static let coreLogRegex = try? NSRegularExpression(pattern: "\\d{2}:\\d{2}:\\d{2}\\.\\d{3} \\|[A-Z]+\\|", options: .caseInsensitive)
    private static let activeSessionPathKey = "activeGameSessionLogPath"
    private static let activeSessionStartedAtKey = "activeGameSessionStart"

    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private let originalStdout: Int32
    private let originalStderr: Int32

    private var continuation: AsyncStream<String>.Continuation?
    public private(set) var capturedLogs: [String] = []
    private let fileIOQueue = DispatchQueue(label: "com.melonx.logcapture.file-io")
    private var sessionFileHandle: FileHandle?
    private var sessionLogURL: URL?
    private let maxCapturedLogs = 1500
    private let maxSessionLogBytes: UInt64 = 64 * 1024 * 1024
    private let mirrorLogsToOriginalFD = UserDefaults.standard.bool(forKey: "mirrorLogsToOriginalFD")

    lazy var logs: AsyncStream<String> = {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.onTermination = { _ in
                self.continuation = nil
            }
        }
    }()

    private init() {
        originalStdout = dup(STDOUT_FILENO)
        originalStderr = dup(STDERR_FILENO)
        setupLifecycleDiagnostics()
        startCapturing()
    }

    func startCapturing() {
        stdoutPipe = Pipe()
        stderrPipe = Pipe()

        redirectOutput(to: stdoutPipe!, fileDescriptor: STDOUT_FILENO)
        redirectOutput(to: stderrPipe!, fileDescriptor: STDERR_FILENO)

        setupReadabilityHandler(for: stdoutPipe!, isStdout: true)
        setupReadabilityHandler(for: stderrPipe!, isStdout: false)
    }

    func stopCapturing() {
        dup2(originalStdout, STDOUT_FILENO)
        dup2(originalStderr, STDERR_FILENO)

        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
    }

    private func redirectOutput(to pipe: Pipe, fileDescriptor: Int32) {
        dup2(pipe.fileHandleForWriting.fileDescriptor, fileDescriptor)
    }

    private func setupReadabilityHandler(for pipe: Pipe, isStdout: Bool) {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] fileHandle in
            guard let self else { return }

            let data = fileHandle.availableData
            if self.mirrorLogsToOriginalFD {
                let originalFD = isStdout ? self.originalStdout : self.originalStderr
                write(originalFD, (data as NSData).bytes, data.count)
            }

            guard let logString = String(data: data, encoding: .utf8) else { return }

            let cleanedAll = self.cleanAllLines(logString)
            if !cleanedAll.isEmpty {
                self.appendToSessionLog(cleanedAll)
            }

            guard let cleanedLog = self.cleanLog(logString),
                  !cleanedLog.0.isEmpty else { return }

            self.appendCapturedLog(cleanedLog.1)
            self.continuation?.yield(cleanedLog.0)

        }
    }

    func startGameSessionLog(gameTitle: String, titleId: String) {
        capturedLogs.removeAll(keepingCapacity: true)
        markPreviousSessionAsAbnormalIfNeeded()

        let safeTitle = sanitizeFilenameComponent(gameTitle, fallback: "UnknownGame")
        let safeTitleId = sanitizeFilenameComponent(titleId, fallback: "UnknownTitleId")

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())

        let logName = "MeloNX-GameLog-\(timestamp)-\(safeTitle)-\(safeTitleId).log"
        let logsDirectory = URL.documentsDirectory.appendingPathComponent("logs")
        let logURL = logsDirectory.appendingPathComponent(logName)
        sessionLogURL = logURL

        fileIOQueue.sync {
            closeSessionFileHandleLocked()

            do {
                try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
                if !FileManager.default.fileExists(atPath: logURL.path) {
                    FileManager.default.createFile(atPath: logURL.path, contents: nil)
                }

                let handle = try FileHandle(forWritingTo: logURL)
                try handle.seekToEnd()
                sessionFileHandle = handle

                let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
                let appBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
                let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
#if canImport(UIKit)
                let deviceName = UIDevice.current.model
#else
                let deviceName = "Unknown"
#endif
                let header = "Session started: \(Date())\nGame: \(gameTitle)\nTitle ID: \(titleId)\nApp: \(appVersion) (\(appBuild))\nOS: \(osVersion)\nDevice: \(deviceName)\n\n"
                if let data = header.data(using: .utf8) {
                    try handle.write(contentsOf: data)
                }
            } catch {
                sessionFileHandle = nil
            }
        }

        UserDefaults.standard.set(logURL.path, forKey: Self.activeSessionPathKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.activeSessionStartedAtKey)
    }

    private func appendCapturedLog(_ logLine: String) {
        capturedLogs.append(logLine)
        if capturedLogs.count > maxCapturedLogs {
            capturedLogs.removeFirst(capturedLogs.count - maxCapturedLogs)
        }
    }

    func endGameSessionLog() {
        logDiagnostic("Session finished normally")

        fileIOQueue.sync {
            closeSessionFileHandleLocked()
        }

        UserDefaults.standard.removeObject(forKey: Self.activeSessionPathKey)
        UserDefaults.standard.removeObject(forKey: Self.activeSessionStartedAtKey)
        sessionLogURL = nil
    }

    func logDiagnostic(_ message: String) {
        appendToSessionLog("[DIAG] \(message)")
    }

    private func appendToSessionLog(_ logLine: String) {
        fileIOQueue.async {
            LiveLogStreamer.shared.send(logLine)

            guard let sessionFileHandle = self.sessionFileHandle,
                  let data = (logLine + "\n").data(using: .utf8) else {
                return
            }

            do {
                let fileSize = try sessionFileHandle.seekToEnd()
                if fileSize >= self.maxSessionLogBytes {
                    try sessionFileHandle.truncate(atOffset: 0)
                    let header = "[DIAG] Session log rotated after reaching \(self.maxSessionLogBytes / (1024 * 1024))MB to keep latest crash context.\n"
                    if let headerData = header.data(using: .utf8) {
                        try sessionFileHandle.write(contentsOf: headerData)
                    }
                }
                try sessionFileHandle.write(contentsOf: data)
            } catch {
                self.closeSessionFileHandleLocked()
            }
        }
    }

    private func closeSessionFileHandleLocked() {
        do {
            if let sessionFileHandle,
               let footerData = "Session ended: \(Date())\n".data(using: .utf8) {
                try sessionFileHandle.write(contentsOf: footerData)
            }
            try sessionFileHandle?.close()
        } catch {
            // Ignore close failures; log capture should not crash the app.
        }
        sessionFileHandle = nil
    }

    private func sanitizeFilenameComponent(_ input: String, fallback: String) -> String {
        let replaced = input.replacingOccurrences(of: "[^A-Za-z0-9_-]+", with: "_", options: .regularExpression)
        let trimmed = replaced.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return trimmed.isEmpty ? fallback : String(trimmed.prefix(80))
    }

    private var includeTraceLogsInSession: Bool {
        if let explicit = UserDefaults.standard.object(forKey: "includeTraceLogsInSession") as? Bool {
            return explicit
        }

        return UserDefaults.standard.object(forKey: "crashForensicsMode") as? Bool ?? true
    }

    private func isTraceLogLine(_ line: String) -> Bool {
        line.contains("|T|")
    }

    private func cleanAllLines(_ raw: String) -> String {
        raw
            .split(separator: "\n")
            .filter { line in
                includeTraceLogsInSession || !isTraceLogLine(String(line))
            }
            .map { line -> String in
                if let tabRange = line.range(of: "\t") {
                    return line[tabRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                }
                return line.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .joined(separator: "\n")
    }

    private func markPreviousSessionAsAbnormalIfNeeded() {
        guard let previousPath = UserDefaults.standard.string(forKey: Self.activeSessionPathKey),
              !previousPath.isEmpty else {
            return
        }

        let previousURL = URL(fileURLWithPath: previousPath)
        let startedAt = UserDefaults.standard.double(forKey: Self.activeSessionStartedAtKey)
        let uptime = startedAt > 0 ? String(format: "%.1f", Date().timeIntervalSince1970 - startedAt) : "unknown"
        let abnormalNote = "\n[DIAG] Previous session ended unexpectedly (force close / crash / OS kill).\n[DIAG] Approx uptime before abnormal end: \(uptime)s\n"

        if let data = abnormalNote.data(using: .utf8),
           FileManager.default.fileExists(atPath: previousURL.path),
           let handle = try? FileHandle(forWritingTo: previousURL) {
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } catch {
                try? handle.close()
            }
        }

        UserDefaults.standard.removeObject(forKey: Self.activeSessionPathKey)
        UserDefaults.standard.removeObject(forKey: Self.activeSessionStartedAtKey)
    }

    private func setupLifecycleDiagnostics() {
#if canImport(UIKit)
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil) { [weak self] _ in
            self?.logDiagnostic("iOS memory warning received")
        }

        NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: nil) { [weak self] _ in
            self?.logDiagnostic("App will resign active")
        }

        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) { [weak self] _ in
            self?.logDiagnostic("App became active")
        }

        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { [weak self] _ in
            self?.logDiagnostic("App entered background")
        }

        NotificationCenter.default.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: nil) { [weak self] _ in
            self?.logDiagnostic("UIApplication.willTerminate received")
            self?.endGameSessionLog()
        }

        NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: nil) { [weak self] _ in
            let thermalState = ProcessInfo.processInfo.thermalState
            self?.logDiagnostic("Thermal state changed: \(thermalState.rawValue)")
        }
#if canImport(AVFAudio)
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { [weak self] notification in
            guard let self else { return }

            let typeRaw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let type = AVAudioSession.InterruptionType(rawValue: typeRaw ?? 0)

            switch type {
            case .began:
                self.logDiagnostic("Audio session interruption began")
            case .ended:
                let optionsRaw = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
                self.logDiagnostic("Audio session interruption ended (shouldResume=\(options.contains(.shouldResume)))")
            default:
                self.logDiagnostic("Audio session interruption event received (typeRaw=\(typeRaw ?? 0))")
            }
        }

        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { [weak self] notification in
            let reasonRaw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
            self?.logDiagnostic("Audio route changed (reason=\(reasonRaw))")
        }

        NotificationCenter.default.addObserver(forName: AVAudioSession.mediaServicesWereLostNotification, object: nil, queue: nil) { [weak self] _ in
            self?.logDiagnostic("Audio media services were lost")
        }

        NotificationCenter.default.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: nil) { [weak self] _ in
            self?.logDiagnostic("Audio media services were reset")
        }
#endif
#endif
    }

    private func cleanLog(_ raw: String) -> (String, String)? {
        let lines = raw.split(separator: "\n")
        
        let filteredLines = lines.filter { line in
            if !includeTraceLogsInSession && isTraceLogLine(String(line)) {
                return false
            }

            if UserDefaults.standard.bool(forKey: "showFullLogs") {
                return true
            }
            
            guard let regex = Self.coreLogRegex else { return false }
            let range = NSRange(location: 0, length: line.utf16.count)
            return regex.firstMatch(in: String(line), options: [], range: range) != nil
        }

        let cleaned = filteredLines.map { line -> String in
            if let tabRange = line.range(of: "\t") {
                return line[tabRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return line.trimmingCharacters(in: .whitespacesAndNewlines)
        }.joined(separator: "\n")
        
        
        let cleaned2 = lines.map { line -> String in
            if let tabRange = line.range(of: "\t") {
                return line[tabRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return line.trimmingCharacters(in: .whitespacesAndNewlines)
        }.joined(separator: "\n")

        return cleaned.isEmpty ? nil : (cleaned.replacingOccurrences(of: "\n\n", with: "\n"), cleaned2)
    }

    deinit {
        endGameSessionLog()
        stopCapturing()
        continuation?.finish()
    }
}

#if canImport(Network)
private final class LiveLogStreamer {
    static let shared = LiveLogStreamer()

    private let queue = DispatchQueue(label: "com.melonx.live-log-stream")
    private let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private var connection: NWConnection?
    private var endpointKey: String?

    private init() {}

    func send(_ message: String) {
        queue.async {
            guard UserDefaults.standard.bool(forKey: "liveLogStreamingEnabled") else {
                self.resetConnection()
                return
            }

            let host = UserDefaults.standard.string(forKey: "liveLogTargetHost")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if host.isEmpty {
                self.resetConnection()
                return
            }

            let storedPort = UserDefaults.standard.integer(forKey: "liveLogTargetPort")
            let portValue = storedPort == 0 ? 19191 : storedPort

            guard let port = NWEndpoint.Port(rawValue: UInt16(clamping: portValue)) else {
                self.resetConnection()
                return
            }

            self.ensureConnection(host: host, port: port)

            let payload = "[\(self.formatter.string(from: Date()))] \(message)\n"
            self.connection?.send(content: Data(payload.utf8), completion: .idempotent)
        }
    }

    private func ensureConnection(host: String, port: NWEndpoint.Port) {
        let key = "\(host):\(port.rawValue)"
        guard endpointKey != key || connection == nil else {
            return
        }

        resetConnection()

        let endpointHost = NWEndpoint.Host(host)
        let connection = NWConnection(host: endpointHost, port: port, using: .udp)
        connection.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                self?.queue.async {
                    self?.resetConnection()
                }
            }
        }

        connection.start(queue: queue)

        self.connection = connection
        endpointKey = key
    }

    private func resetConnection() {
        connection?.cancel()
        connection = nil
        endpointKey = nil
    }
}
#endif
