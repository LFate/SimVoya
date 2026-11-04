import SwiftUI
import AppKit

@MainActor final class ExportModel: ObservableObject {
    @Published var source: ExportSourceKind = .localFiles
    @Published var roots: [BrowserRoot] = []
    @Published var currentRoot: BrowserRoot?
    @Published var directory: URL?
    @Published var entries: [BrowserEntry] = []
    @Published var selected = Set<String>()
    @Published var search = ""
    @Published var showHidden = false
    @Published var loading = false
    @Published var error: String?
    @Published var records: [ExportRecord] = []
    @Published var activeExports = 0
    @Published var info: BrowserEntry?
    private(set) var device: SimulatorDevice?
    private var generation = UUID()
    var filtered: [BrowserEntry] {
        entries.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.subtitle.localizedCaseInsensitiveContains(search) }
    }
    var chosen: [BrowserEntry] { filtered.filter { selected.contains($0.id) && $0.canExport } }
    var canGoUp: Bool {
        guard let directory, let root = currentRoot?.url else { return false }
        return directory.standardizedFileURL != root.standardizedFileURL || source == .applications || source == .sharedGroups
    }
    func setDevice(_ value: SimulatorDevice?) {
        guard value?.id != device?.id || value?.dataPath != device?.dataPath else { return }
        device = value; roots = []; currentRoot = nil; directory = nil; selected = []; entries = []; error = nil
        generation = UUID()
        if value != nil { discover() } else { loading = false }
    }
    func discover() {
        guard let device else { return }
        let token = UUID(); generation = token; loading = true; error = nil; entries = []; selected = []
        Task {
            do {
                let found = try await FileBrowserService().discover(device)
                guard generation == token, self.device?.id == device.id else { return }
                roots = found; loading = false; chooseSource()
            } catch {
                guard generation == token else { return }; self.error = error.localizedDescription; loading = false
            }
        }
    }
    func chooseSource() {
        if roots.isEmpty, device != nil { discover(); return }
        generation = UUID(); search = ""; selected = []; directory = nil; currentRoot = nil; entries = []; error = nil; loading = false
        if source == .applications || source == .sharedGroups {
            let found = roots.filter { $0.kind == source }
            let token = generation
            loading = true
            Task {
                let rows = await Task.detached { found.map(FileBrowserService.rootEntry) }.value
                guard generation == token else { return }; entries = rows; loading = false
            }
        } else if let root = roots.first(where: { $0.kind == source }), let url = root.url { navigate(url, root: root) }
        else { error = "未发现此来源。请先打开模拟器中的「文件」App，再刷新重试。" }
    }
    func navigate(_ url: URL, root: BrowserRoot) {
        let token = UUID(); generation = token; currentRoot = root; directory = url; entries = []; selected = []; search = ""; error = nil; loading = true
        let hidden = showHidden
        Task {
            do {
                let rows = try await Task.detached { try FileBrowserService.list(url, root: root, showHidden: hidden) }.value
                guard generation == token else { return }; entries = rows; loading = false
            } catch {
                guard generation == token else { return }; self.error = error.localizedDescription; loading = false
            }
        }
    }
    func open(_ entry: BrowserEntry) {
        guard entry.canExport, entry.isDirectory, let url = entry.url, let root = entry.root ?? currentRoot else { info = entry; return }
        navigate(url, root: root)
    }
    func up() {
        guard let url = directory, let root = currentRoot, let rootURL = root.url else { return }
        if url.standardizedFileURL == rootURL.standardizedFileURL { chooseSource() }
        else { navigate(url.deletingLastPathComponent(), root: root) }
    }
    func refresh() {
        if let directory, let currentRoot { navigate(directory, root: currentRoot) } else { discover() }
    }
    func snapshot(_ entry: BrowserEntry) throws -> ExportSnapshot {
        guard let device, let root = entry.root ?? currentRoot else { throw AppError("请先选择设备和文件来源。") }
        return try ExportSnapshot(device: device, root: root, entry: entry)
    }
    func chooseDestination() {
        guard activeExports == 0, !chosen.isEmpty else { return }
        let snapshots: [ExportSnapshot]
        do { snapshots = try chosen.map(snapshot) } catch { self.error = error.localizedDescription; return }
        let panel = NSOpenPanel(); panel.title = "选择 Mac 上的导出文件夹"; panel.prompt = "导出到这里"
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let destination = panel.url else { return }
            Task { @MainActor in self?.export(snapshots, to: destination) }
        }
    }
    private func export(_ items: [ExportSnapshot], to folder: URL) {
        guard activeExports == 0 else { return }; activeExports += items.count
        Task {
            let scoped = folder.startAccessingSecurityScopedResource(); defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
            for item in items {
                begin(item)
                do {
                    let destination = try await Task.detached { try await ExportService().export(item, toDirectory: folder) }.value
                    finish(item, destination: destination, error: nil)
                } catch { finish(item, destination: nil, error: error.localizedDescription) }
                activeExports -= 1
            }
        }
    }
    func promiseStarted(_ item: ExportSnapshot) { activeExports += 1; begin(item) }
    func promiseFinished(_ item: ExportSnapshot, destination: URL?, error: String?) { finish(item, destination: destination, error: error); activeExports = max(0, activeExports - 1) }
    private func begin(_ item: ExportSnapshot) {
        records.insert(ExportRecord(id: item.id, name: item.name), at: 0)
        if records.count > 50 { records.removeLast(records.count - 50) }
    }
    private func finish(_ item: ExportSnapshot, destination: URL?, error: String?) {
        guard let index = records.firstIndex(where: { $0.id == item.id }) else { return }
        records[index].destination = destination; records[index].error = error; records[index].finished = true
    }
}
