import Foundation

struct ExportService: Sendable {
    func export(_ item: ExportSnapshot, toDirectory directory: URL) async throws -> URL {
        try await ExportSerialQueue.shared.run {
            let destination = ImportService.uniqueDestination(source: item.source, folder: directory)
            return try await perform(item, exactDestination: destination)
        }
    }
    func fulfillPromise(_ item: ExportSnapshot, exactDestination destination: URL) async throws -> URL {
        try await ExportSerialQueue.shared.run { try await perform(item, exactDestination: destination) }
    }
    private func perform(_ item: ExportSnapshot, exactDestination destination: URL) async throws -> URL {
        try FileBrowserService.validate(item.source, root: item.sourceRoot, dataRoot: item.dataRoot)
        let fm = FileManager.default
        try ImportService.validateTree(item.source)
        let canonicalDestination = destination.resolvingSymlinksInPath().standardizedFileURL
        guard destination.isFileURL,
              !FileBrowserService.isWithin(canonicalDestination, root: item.dataRoot.resolvingSymlinksInPath()),
              !FileBrowserService.isWithin(canonicalDestination, root: item.source.resolvingSymlinksInPath()) else { throw AppError("导出目标必须位于模拟器之外，且不能是源文件或源文件夹内部。") }
        guard !fm.fileExists(atPath: destination.path), (try? destination.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { throw AppError("目标已存在，未覆盖。请使用导出按钮保留两份，或选择其他位置。") }
        let parent = destination.deletingLastPathComponent()
        guard fm.isWritableFile(atPath: parent.path) else { throw AppError("目标文件夹不存在或没有写入权限。") }
        try Task.checkCancellation()
        let before = try ImportService.manifest(item.source)
        let staging = parent.appendingPathComponent(".simvoya-export-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        let staged = staging.appendingPathComponent(item.name)
        if item.isDirectory { try fm.createDirectory(at: staged, withIntermediateDirectories: false) }
        _ = try await ProcessRunner.shared.run("/usr/bin/rsync", ["-r", "--", item.source.path + (item.isDirectory ? "/" : ""), staged.path + (item.isDirectory ? "/" : "")], timeout: 120)
        try Task.checkCancellation()
        try FileBrowserService.validate(item.source, root: item.sourceRoot, dataRoot: item.dataRoot)
        let copied = try ImportService.manifest(staged), after = try ImportService.manifest(item.source)
        guard before == copied, before == after else { throw AppError("源内容在导出时发生变化，或复制校验失败。请停止 App 写入后重试。 缺少：\(Set(before.keys).subtracting(copied.keys).sorted())；额外：\(Set(copied.keys).subtracting(before.keys).sorted())；源变化：\(before != after)") }
        try fm.moveItem(at: staged, to: destination)
        return destination
    }
}

// A shared async tail serializes all promises and button exports, including hashing.
actor ExportSerialQueue {
    static let shared = ExportSerialQueue()
    private var tail: Task<Void, Never>?
    func run(_ operation: @escaping @Sendable () async throws -> URL) async throws -> URL {
        let previous = tail
        let task = Task {
            await previous?.value
            return try await operation()
        }
        tail = Task { _ = try? await task.value }
        return try await task.value
    }
}
