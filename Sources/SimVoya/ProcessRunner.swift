import Foundation
import Darwin

struct CommandOutput: Sendable { let stdout: String; let stderr: String }
final class ProcessRunner: @unchecked Sendable {
    static let shared = ProcessRunner()
    private let lock = NSLock()
    private var active: [UUID: Process] = [:]
    func stopAll() {
        let processes = lock.withLock { Array(active.values) }
        for process in processes where process.isRunning { process.terminate() }
    }
    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 15) async throws -> CommandOutput {
        let token = UUID()
        return try await withTaskCancellationHandler(operation: {
            try await Task.detached(priority: .userInitiated) { [self] in
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("simvoya-process-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: folder) }
                let outURL = folder.appendingPathComponent("stdout"), errURL = folder.appendingPathComponent("stderr")
                FileManager.default.createFile(atPath: outURL.path, contents: nil)
                FileManager.default.createFile(atPath: errURL.path, contents: nil)
                let out = try FileHandle(forWritingTo: outURL), err = try FileHandle(forWritingTo: errURL)
                defer { try? out.close(); try? err.close() }
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
                process.standardOutput = out; process.standardError = err; process.standardInput = FileHandle.nullDevice
                try process.run()
                lock.withLock { active[token] = process }
                defer { _ = lock.withLock { active.removeValue(forKey: token) } }
                let deadline = Date().addingTimeInterval(timeout)
                var timedOut = false
                while process.isRunning {
                    if Date() >= deadline {
                        timedOut = true; process.terminate()
                        let grace = Date().addingTimeInterval(1)
                        while process.isRunning && Date() < grace { usleep(20_000) }
                        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                        break
                    }
                    usleep(30_000)
                }
                process.waitUntilExit()
                let stdout = (try? String(contentsOf: outURL, encoding: .utf8)) ?? ""
                let stderr = (try? String(contentsOf: errURL, encoding: .utf8)) ?? ""
                if timedOut { throw AppError("操作超时（\(Int(timeout)) 秒），请确认模拟器响应正常后重试。") }
                guard process.terminationStatus == 0 else {
                    throw AppError(stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "命令执行失败（\(process.terminationStatus)）：\(stdout)" : stderr.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                return CommandOutput(stdout: stdout, stderr: stderr)
            }.value
        }, onCancel: { [self] in
            let process = lock.withLock { active[token] }
            if let process, process.isRunning { process.terminate() }
        })
    }
    func simctl(_ arguments: [String], timeout: TimeInterval = 15) async throws -> CommandOutput {
        try await run("/usr/bin/xcrun", ["simctl"] + arguments, timeout: timeout)
    }
}
