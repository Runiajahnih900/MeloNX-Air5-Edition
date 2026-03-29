//
//  LogCapture.swift
//  MeloNX
//
//  Created by Stossy11 on 22/09/2025.
//


import Foundation

final class LogCapture: ObservableObject {
    static let shared = LogCapture()

    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private let originalStdout: Int32
    private let originalStderr: Int32

    private var continuation: AsyncStream<String>.Continuation?
    public private(set) var capturedLogs: [String] = []
    private let fileIOQueue = DispatchQueue(label: "com.melonx.logcapture.file-io")
    private var sessionFileHandle: FileHandle?

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
            let originalFD = isStdout ? self.originalStdout : self.originalStderr
            write(originalFD, (data as NSData).bytes, data.count)

            guard let logString = String(data: data, encoding: .utf8),
                  let cleanedLog = self.cleanLog(logString),
                  !cleanedLog.0.isEmpty else { return }

            self.capturedLogs.append(cleanedLog.1)
            self.appendToSessionLog(cleanedLog.1)
            self.continuation?.yield(cleanedLog.0)

        }
    }

    func startGameSessionLog(gameTitle: String, titleId: String) {
        capturedLogs.removeAll(keepingCapacity: true)

        let safeTitle = sanitizeFilenameComponent(gameTitle, fallback: "UnknownGame")
        let safeTitleId = sanitizeFilenameComponent(titleId, fallback: "UnknownTitleId")

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())

        let logName = "\(timestamp)-\(safeTitle)-\(safeTitleId).log"
        let logsDirectory = URL.documentsDirectory
            .appendingPathComponent("logs")
            .appendingPathComponent("games")
        let logURL = logsDirectory.appendingPathComponent(logName)

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

                let header = "Session started: \(Date())\nGame: \(gameTitle)\nTitle ID: \(titleId)\n\n"
                if let data = header.data(using: .utf8) {
                    try handle.write(contentsOf: data)
                }
            } catch {
                sessionFileHandle = nil
            }
        }
    }

    func endGameSessionLog() {
        fileIOQueue.sync {
            closeSessionFileHandleLocked()
        }
    }

    private func appendToSessionLog(_ logLine: String) {
        fileIOQueue.async {
            guard let sessionFileHandle = self.sessionFileHandle,
                  let data = (logLine + "\n").data(using: .utf8) else {
                return
            }

            do {
                try sessionFileHandle.seekToEnd()
                try sessionFileHandle.write(contentsOf: data)
            } catch {
                self.closeSessionFileHandleLocked()
            }
        }
    }

    private func closeSessionFileHandleLocked() {
        do {
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

    private func cleanLog(_ raw: String) -> (String, String)? {
        let lines = raw.split(separator: "\n")
        
        let filteredLines = lines.filter { line in
            if UserDefaults.standard.bool(forKey: "showFullLogs") {
                return true
            }
            
            let regex = try? NSRegularExpression(pattern: "\\d{2}:\\d{2}:\\d{2}\\.\\d{3} \\|[A-Z]+\\|", options: .caseInsensitive)
            let matches = regex?.matches(in: String(line), options: [], range: NSRange(location: 0, length: line.utf16.count)) ?? []
            
            return matches.count >= 1
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
