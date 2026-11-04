import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindow: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            self?.mainWindow = NSApplication.shared.windows.first { $0.canBecomeMain }
            self?.mainWindow?.isReleasedWhenClosed = false
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            let window = mainWindow ?? sender.windows.first { $0.canBecomeMain }
            window?.makeKeyAndOrderFront(nil)
            sender.activate(ignoringOtherApps: true)
        }
        return true
    }
    func applicationWillTerminate(_ notification: Notification) { ProcessRunner.shared.stopAll() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
struct SimVoyaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel()
    var body: some Scene {
        Window("SimVoya", id: "main") { ContentView(model: model) }
            .defaultSize(width: 1080, height: 760)
            .commands { CommandGroup(replacing: .newItem) { Button("选择文件…") { model.chooseFiles() }.keyboardShortcut("o").disabled(!model.canImport) } }
    }
}
@main enum Entry {
    @MainActor static func main() {
        if let index = CommandLine.arguments.firstIndex(of: "--smoke-test"), CommandLine.arguments.count > index + 1 {
            Task {
            do {
                let id = CommandLine.arguments[index + 1]
                guard let device = try await SimulatorService().devices().first(where: { $0.id == id }) else { throw AppError("目标设备未启动") }
                let urls = CommandLine.arguments.dropFirst(index + 2).map { URL(fileURLWithPath: $0) }
                guard !urls.isEmpty else { throw AppError("用法：SimVoya --smoke-test UUID 文件路径…") }
                for url in urls {
                    let receipt = try await ImportService().importItem(url, to: device, mode: .automatic)
                    print("PASS \(url.lastPathComponent): \(receipt.message)\n\(receipt.destination?.path ?? receipt.detail)")
                }
            } catch { fputs("FAIL: \(error.localizedDescription)\n", stderr); exit(1) }
            exit(0)
            }
            dispatchMain()
        } else { SimVoyaApp.main() }
    }
}
