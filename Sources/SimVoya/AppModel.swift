import SwiftUI
import AppKit

@MainActor final class AppModel: ObservableObject {
    @Published var devices: [SimulatorDevice] = []
    @Published var selectedID: String?
    @Published var mode: ImportMode = .automatic
    @Published var deviceError: String?
    @Published var notice: String?
    @Published var refreshing = false
    @Published var importing = false
    @Published var records: [ImportRecord] = []
    @Published var completed = 0
    @Published var total = 0
    @Published var batchDevice = ""
    @Published var summary = ""
    private var didLoad = false
    var selected: SimulatorDevice? { devices.first { $0.id == selectedID } }
    var canImport: Bool { selected != nil && deviceError == nil && !importing }
    func refresh() async {
        guard !refreshing else { return }; refreshing = true; defer { refreshing = false }
        do {
            let latest = try await SimulatorService().devices()
            devices = latest; deviceError = nil
            if !didLoad { selectedID = latest.first?.id; didLoad = true }
            else if let id = selectedID, !latest.contains(where: { $0.id == id }) {
                selectedID = nil; notice = "这台模拟器已关闭，请选择运行中的设备。"
            }
        } catch { deviceError = error.localizedDescription }
    }
    func chooseFiles() {
        guard canImport else { return }
        let panel = NSOpenPanel()
        panel.title = "选择要导入模拟器的文件"
        panel.prompt = "导入"; panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor in self?.startImport(panel.urls) }
        }
    }
    func startImport(_ urls: [URL]) {
        guard canImport, let device = selected, !urls.isEmpty else { return }
        importing = true; completed = 0; total = urls.count; batchDevice = device.name; summary = ""; notice = nil
        let batchMode = mode
        Task {
            var success = 0, failed = 0
            for url in urls {
                let record = ImportRecord(name: url.lastPathComponent, device: device.name)
                records.insert(record, at: 0)
                if records.count > 50 { records.removeLast(records.count - 50) }
                do {
                    let receipt = try await Task.detached { try await ImportService().importItem(url, to: device, mode: batchMode) }.value
                    if let index = records.firstIndex(where: { $0.id == record.id }) { records[index].receipt = receipt }
                    success += 1
                } catch {
                    if let index = records.firstIndex(where: { $0.id == record.id }) { records[index].error = error.localizedDescription }
                    failed += 1
                }
                completed += 1
            }
            summary = failed == 0 ? "已完成 \(success) 项导入" : "\(success) 项完成，\(failed) 项失败；失败内容可重新拖入重试。"
            importing = false
        }
    }
    func openFiles() {
        guard let device = selected else { return }
        Task { do { try await SimulatorService().openFiles(device); openSimulator() } catch { notice = error.localizedDescription } }
    }
    func openSimulator() {
        for bundle in ["com.apple.dt.Devices", "com.apple.iphonesimulator"] {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                    if let error { Task { @MainActor in self.notice = error.localizedDescription } }
                }
                return
            }
        }
        notice = "未找到 Device Hub 或 Simulator，请从 Xcode 的 Open Developer Tool 菜单打开。"
    }
}
