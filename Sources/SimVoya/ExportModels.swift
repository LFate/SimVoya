import Foundation
import UniformTypeIdentifiers

enum WorkspaceMode: String, CaseIterable, Identifiable { case importing = "导入", exporting = "导出"; var id: Self { self } }
enum ExportSourceKind: String, CaseIterable, Identifiable, Sendable {
    case localFiles = "文件 App 本地文件", applications = "应用数据", sharedGroups = "共享容器", deviceData = "设备数据（高级）"
    var id: Self { self }
}
struct BrowserRoot: Identifiable, Hashable, Sendable {
    let id: String
    let kind: ExportSourceKind
    let name: String
    let subtitle: String
    let url: URL?
    let dataRoot: URL
}
struct BrowserEntry: Identifiable, Hashable, Sendable {
    var id: String { url?.path ?? root?.id ?? name }
    let url: URL?
    let name: String
    var subtitle = ""
    var isDirectory = false
    var isSymbolicLink = false
    var byteCount: Int64?
    var modified: Date?
    var created: Date?
    var typeDescription = "未知"
    var unavailableReason: String?
    var root: BrowserRoot?
    var canExport: Bool { url != nil && unavailableReason == nil && !isSymbolicLink }
    var sizeText: String { isDirectory ? "—" : byteCount.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "未知" }
    var dateText: String { modified.map { $0.formatted(date: .numeric, time: .shortened) } ?? "未知" }
}
struct ExportSnapshot: Sendable {
    let id: UUID
    let deviceID: String
    let deviceName: String
    let sourceRoot: URL
    let dataRoot: URL
    let source: URL
    let isDirectory: Bool
    init(device: SimulatorDevice, root: BrowserRoot, entry: BrowserEntry) throws {
        guard entry.canExport, let source = entry.url, let sourceRoot = root.url else { throw AppError(entry.unavailableReason ?? "此条目无法导出。") }
        self.id = UUID(); self.deviceID = device.id; self.deviceName = device.name; self.sourceRoot = sourceRoot; self.dataRoot = root.dataRoot
        self.source = source; self.isDirectory = entry.isDirectory
    }
    init(source: URL, sourceRoot: URL, dataRoot: URL, isDirectory: Bool, deviceID: String = "test", deviceName: String = "测试设备") {
        self.id = UUID(); self.source = source; self.sourceRoot = sourceRoot; self.dataRoot = dataRoot; self.isDirectory = isDirectory; self.deviceID = deviceID; self.deviceName = deviceName
    }
    var name: String { source.lastPathComponent }
}
struct ExportRecord: Identifiable {
    let id: UUID
    let name: String
    var destination: URL?
    var error: String?
    var finished = false
}
