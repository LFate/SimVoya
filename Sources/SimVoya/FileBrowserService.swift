import Foundation
import UniformTypeIdentifiers

struct FileBrowserService: Sendable {
    func discover(_ device: SimulatorDevice) async throws -> [BrowserRoot] {
        guard let path = device.dataPath else { throw AppError("无法读取这台模拟器的数据路径，请刷新设备列表。") }
        let dataRoot = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        let output = try await ProcessRunner.shared.simctl(["listapps", device.id])
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("simvoya-apps-\(UUID().uuidString).plist")
        try Data(output.stdout.utf8).write(to: temporary)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let json = try await ProcessRunner.shared.run("/usr/bin/plutil", ["-convert", "json", "-o", "-", temporary.path])
        return try Self.roots(from: Data(json.stdout.utf8), dataRoot: dataRoot)
    }
    static func roots(from json: Data, dataRoot: URL) throws -> [BrowserRoot] {
        guard let apps = try JSONSerialization.jsonObject(with: json) as? [String: [String: Any]] else { throw AppError("应用列表格式无法读取。") }
        var roots = [BrowserRoot(id: "device", kind: .deviceData, name: "设备数据", subtitle: "所有可访问的 data 目录", url: dataRoot, dataRoot: dataRoot)]
        var groups: [String: (url: URL, names: Set<String>, ids: Set<String>)] = [:]
        for (bundleID, app) in apps {
            let name = app["CFBundleDisplayName"] as? String ?? app["CFBundleName"] as? String ?? bundleID
            let container = fileURL(app["DataContainer"] as? String)
            roots.append(BrowserRoot(id: "app:\(bundleID)", kind: .applications, name: name, subtitle: bundleID, url: container, dataRoot: dataRoot))
            for (groupID, raw) in app["GroupContainers"] as? [String: String] ?? [:] {
                guard let url = fileURL(raw) else { continue }
                let key = url.standardizedFileURL.path
                var group = groups[key] ?? (url, [], [])
                group.names.insert(name); group.ids.insert(groupID); groups[key] = group
                if bundleID == "com.apple.DocumentsApp", groupID == "group.com.apple.FileProvider.LocalStorage" {
                    roots.append(BrowserRoot(id: "local", kind: .localFiles, name: "本地文件", subtitle: "文件 App → 我的 iPhone / iPad", url: url.appendingPathComponent("File Provider Storage", isDirectory: true), dataRoot: dataRoot))
                }
            }
        }
        for (key, group) in groups {
            roots.append(BrowserRoot(id: "group:\(key)", kind: .sharedGroups, name: group.ids.sorted().joined(separator: ", "), subtitle: group.names.sorted().joined(separator: "、"), url: group.url, dataRoot: dataRoot))
        }
        return roots.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    private static func fileURL(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value), url.isFileURL else { return nil }; return url.standardizedFileURL
    }
    static func isWithin(_ url: URL, root: URL) -> Bool {
        let child = url.standardizedFileURL.pathComponents, parent = root.standardizedFileURL.pathComponents
        return child.count >= parent.count && Array(child.prefix(parent.count)) == parent
    }
    static func validate(_ url: URL, root: URL, dataRoot: URL) throws {
        guard url.isFileURL, root.isFileURL, dataRoot.isFileURL,
              isWithin(root, root: dataRoot), isWithin(url, root: root),
              isWithin(root.resolvingSymlinksInPath(), root: dataRoot.resolvingSymlinksInPath()),
              isWithin(url.resolvingSymlinksInPath(), root: root.resolvingSymlinksInPath()) else { throw AppError("路径超出所选模拟器来源，已停止访问。") }
        var current = dataRoot.standardizedFileURL
        try ImportService.rejectSymlink(current)
        for component in url.standardizedFileURL.pathComponents.dropFirst(current.pathComponents.count) {
            current.appendPathComponent(component)
            try ImportService.rejectSymlink(current)
        }
    }
    static func rootEntry(_ root: BrowserRoot) -> BrowserEntry {
        guard let url = root.url else { return BrowserEntry(url: nil, name: root.name, subtitle: root.subtitle, isDirectory: true, typeDescription: "应用数据", unavailableReason: "没有可发现的数据容器", root: root) }
        var entry = metadata(url)
        entry = BrowserEntry(url: url, name: root.name, subtitle: root.subtitle, isDirectory: true, byteCount: nil, modified: entry.modified, created: entry.created, typeDescription: "容器", unavailableReason: entry.unavailableReason, root: root)
        do { try validate(url, root: url, dataRoot: root.dataRoot) } catch { entry.unavailableReason = error.localizedDescription }
        return entry
    }
    static func list(_ directory: URL, root: BrowserRoot, showHidden: Bool) throws -> [BrowserEntry] {
        guard let rootURL = root.url else { throw AppError("此来源没有可访问的数据目录。") }
        try validate(directory, root: rootURL, dataRoot: root.dataRoot)
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey], options: showHidden ? [] : [.skipsHiddenFiles])
        return urls.map(metadata).sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
    static func metadata(_ url: URL) -> BrowserEntry {
        var entry = BrowserEntry(url: url, name: url.lastPathComponent)
        do {
            let v = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey, .contentTypeKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
            entry.isDirectory = v.isDirectory == true; entry.isSymbolicLink = v.isSymbolicLink == true
            entry.byteCount = v.fileSize.map(Int64.init); entry.modified = v.contentModificationDate; entry.created = v.creationDate
            entry.typeDescription = entry.isSymbolicLink ? "符号链接" : entry.isDirectory ? "文件夹" : v.contentType?.localizedDescription ?? "文件"
            if entry.isSymbolicLink { entry.unavailableReason = "符号链接只显示信息，不跟随或导出。" }
            else if v.isDirectory != true && v.isRegularFile != true { entry.unavailableReason = "特殊文件不支持导出。" }
            else if v.isUbiquitousItem == true, v.ubiquitousItemDownloadingStatus == .notDownloaded { entry.unavailableReason = "尚未下载，请先在模拟器下载完整文件。" }
            else if !FileManager.default.isReadableFile(atPath: url.path) { entry.unavailableReason = "没有读取权限。" }
        } catch { entry.unavailableReason = error.localizedDescription }
        return entry
    }
}
