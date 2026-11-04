import Foundation
import CryptoKit

struct ImportService: Sendable {
    private var fm: FileManager { .default }
    func importItem(_ source: URL, to device: SimulatorDevice, mode: ImportMode) async throws -> ImportReceipt {
        guard source.isFileURL else { throw AppError("仅支持从 Finder 拖入本地文件。") }
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        guard fm.isReadableFile(atPath: source.path) else { throw AppError("无法读取源文件，请检查权限或重新选择文件。") }
        try Self.validateTree(source)
        try await SimulatorService().requireBooted(device)
        if try mode.usesPhotos(source) {
            _ = try await ProcessRunner.shared.simctl(["addmedia", device.id, source.path], timeout: 120)
            return ImportReceipt(message: "已导入照片", detail: "\(device.name) · 照片图库", destination: nil)
        }
        let root = try await storageRoot(device)
        let destinationFolder = root.appendingPathComponent("SimVoya", isDirectory: true)
        if fm.fileExists(atPath: destinationFolder.path) { try Self.rejectSymlink(destinationFolder) }
        try fm.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        let name = source.lastPathComponent
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/") else { throw AppError("无效文件名。") }
        let destination = Self.uniqueDestination(source: source, folder: destinationFolder)
        let staging = destinationFolder.appendingPathComponent(".simvoya-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        let staged = staging.appendingPathComponent(name)
        let isDirectory = try source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
        if isDirectory { try fm.createDirectory(at: staged, withIntermediateDirectories: false) }
        let sourcePath = source.path + (isDirectory ? "/" : "")
        let stagedPath = staged.path + (isDirectory ? "/" : "")
        _ = try await ProcessRunner.shared.run("/usr/bin/rsync", ["-r", "--", sourcePath, stagedPath], timeout: 120)
        try Self.verify(source, staged)
        // FileManager move does not overwrite an existing destination.
        try fm.moveItem(at: staged, to: destination)
        try Self.verify(source, destination)
        return ImportReceipt(message: "已复制到文件存储", detail: "\(device.name) · 文件 → 我的 iPhone / iPad → SimVoya → \(destination.lastPathComponent)\n如未出现，请重新打开文件 App。", destination: destination)
    }
    func storageRoot(_ device: SimulatorDevice) async throws -> URL {
        for attempt in 0...1 {
            let output = try await ProcessRunner.shared.simctl(["get_app_container", device.id, "com.apple.DocumentsApp", "groups"])
            if let container = Self.localContainer(output.stdout) {
                let root = container.appendingPathComponent("File Provider Storage", isDirectory: true)
                var directory: ObjCBool = false
                if fm.fileExists(atPath: root.path, isDirectory: &directory), directory.boolValue {
                    try Self.rejectSymlink(container); try Self.rejectSymlink(root)
                    return root
                }
            }
            if attempt == 0 { try await SimulatorService().openFiles(device); try await Task.sleep(nanoseconds: 500_000_000) }
        }
        throw AppError("未找到文件 App 的本地存储。请先在模拟器中打开「文件」并进入「我的 iPhone / iPad」，然后重试。")
    }
    static func localContainer(_ output: String) -> URL? {
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: "\t", maxSplits: 1).map(String.init)
            if fields.count == 2, fields[0] == "group.com.apple.FileProvider.LocalStorage", fields[1].hasPrefix("/") {
                return URL(fileURLWithPath: fields[1], isDirectory: true)
            }
        }
        return nil
    }
    static func uniqueDestination(source: URL, folder: URL) -> URL {
        let fm = FileManager.default
        var candidate = folder.appendingPathComponent(source.lastPathComponent)
        let isDirectory = (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        let ext = isDirectory ? "" : source.pathExtension
        let stem = ext.isEmpty ? source.lastPathComponent : source.deletingPathExtension().lastPathComponent
        var index = 2
        while fm.fileExists(atPath: candidate.path) || (try? candidate.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            candidate = folder.appendingPathComponent("\(stem) (\(index))" + (ext.isEmpty ? "" : ".\(ext)")); index += 1
        }
        return candidate
    }
    static func rejectSymlink(_ url: URL) throws {
        guard try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw AppError("为避免写入意外位置，不支持符号链接：\(url.lastPathComponent)") }
    }
    static func validateTree(_ source: URL) throws {
        try rejectSymlink(source)
        let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
        guard values.isDirectory == true || values.isRegularFile == true else { throw AppError("不支持此文件类型：\(source.lastPathComponent)") }
        if values.isDirectory == true {
            var enumerationError: Error?
            guard let iterator = FileManager.default.enumerator(at: source, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey], options: [], errorHandler: { _, error in enumerationError = error; return false }) else { throw AppError("无法读取文件夹。") }
            for case let child as URL in iterator {
                try rejectSymlink(child)
                let v = try child.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
                guard v.isDirectory == true || v.isRegularFile == true else { throw AppError("文件夹包含不支持的条目：\(child.lastPathComponent)") }
            }
            if let enumerationError { throw enumerationError }
        }
    }
    static func manifest(_ original: URL) throws -> [String: String] {
        try rejectSymlink(original)
        let url = original.resolvingSymlinksInPath().standardizedFileURL
        var result: [String: String] = [:]
        func entry(_ item: URL, key: String) throws {
            try Task.checkCancellation()
            let values = try item.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
            try rejectSymlink(item)
            if values.isDirectory == true { result[key] = "directory" }
            else if values.isRegularFile == true {
                let handle = try FileHandle(forReadingFrom: item); defer { try? handle.close() }
                var digest = SHA256()
                while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { try Task.checkCancellation(); digest.update(data: data) }
                result[key] = digest.finalize().map { String(format: "%02x", $0) }.joined()
            } else { throw AppError("无法校验文件类型。") }
        }
        try entry(url, key: "")
        if (try url.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true {
            var enumerationError: Error?
            guard let iterator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [], errorHandler: { _, error in enumerationError = error; return false }) else { throw AppError("无法校验目录。") }
            for case let child as URL in iterator {
                try Task.checkCancellation()
                let relative = child.standardizedFileURL.pathComponents.dropFirst(url.pathComponents.count).joined(separator: "/")
                try entry(child, key: relative)
            }
            if let enumerationError { throw enumerationError }
        }
        return result
    }
    static func verify(_ source: URL, _ destination: URL) throws {
        let expected = try manifest(source), actual = try manifest(destination)
        guard expected == actual else {
            let missing = Set(expected.keys).subtracting(actual.keys).sorted().joined(separator: ", ")
            let extra = Set(actual.keys).subtracting(expected.keys).sorted().joined(separator: ", ")
            let changed = expected.keys.filter { actual[$0] != nil && actual[$0] != expected[$0] }.sorted().joined(separator: ", ")
            throw AppError("复制后内容校验失败，未确认导入成功。缺少：\(missing)；额外：\(extra)；内容变化：\(changed)")
        }
    }
}
