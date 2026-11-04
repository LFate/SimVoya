import SwiftUI
import AppKit
import UniformTypeIdentifiers

// Each promise owns a frozen source; neither sorting nor navigation can retarget a drag.
final class ExportPromiseDelegate: NSObject, NSFilePromiseProviderDelegate, @unchecked Sendable {
    let snapshot: ExportSnapshot
    private let queue: OperationQueue
    var onStart: (@Sendable (ExportSnapshot) async -> Void)?
    var onFinish: (@Sendable (ExportSnapshot, URL?, String?) async -> Void)?
    private let lock = NSLock()
    private var started = false
    init(snapshot: ExportSnapshot) {
        self.snapshot = snapshot
        queue = OperationQueue(); queue.name = "SimVoya file promises"; queue.maxConcurrentOperationCount = 1
    }
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String { snapshot.name }
    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue { queue }
    func filePromiseProvider(_ provider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void) {
        let first = lock.withLock { if started { return false }; started = true; return true }
        guard first else { completionHandler(AppError("同一拖拽条目已开始导出。")); return }
        Task.detached { [self] in
            await onStart?(snapshot)
            do {
                let destination = try await ExportService().fulfillPromise(snapshot, exactDestination: url)
                await onFinish?(snapshot, destination, nil); completionHandler(nil)
            } catch { await onFinish?(snapshot, nil, error.localizedDescription); completionHandler(error) }
            ExportPromiseStore.shared.completed(snapshot.id)
        }
    }
}
// NSFilePromiseProvider's delegate is weak. Keep both objects beyond drag-session end,
// until Finder has completed fulfillment (or until an unaccepted drag is cancelled).
final class ExportPromiseStore: @unchecked Sendable {
    static let shared = ExportPromiseStore()
    private let lock = NSLock()
    private var retained: [UUID: (NSFilePromiseProvider, ExportPromiseDelegate)] = [:]
    func retain(_ provider: NSFilePromiseProvider, delegate: ExportPromiseDelegate) { lock.withLock { retained[delegate.snapshot.id] = (provider, delegate) } }
    func completed(_ id: UUID) { _ = lock.withLock { retained.removeValue(forKey: id) } }
    func cancelled(_ ids: [UUID]) { lock.withLock { for id in ids { retained.removeValue(forKey: id) } } }
}

struct ExportFileTable: NSViewRepresentable {
    @ObservedObject var model: ExportModel
    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeNSView(context: Context) -> NSScrollView {
        let table = BrowserTableView()
        table.allowsMultipleSelection = true; table.usesAlternatingRowBackgroundColors = true; table.rowHeight = 36
        table.style = .inset; table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        for (id, title, width) in [("name", "名称", 310.0), ("type", "类型", 105.0), ("size", "大小", 76.0), ("date", "修改时间", 130.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id)); column.title = title; column.width = width
            column.minWidth = id == "name" ? 180 : 60; column.sortDescriptorPrototype = NSSortDescriptor(key: id, ascending: true)
            table.addTableColumn(column)
        }
        table.delegate = context.coordinator; table.dataSource = context.coordinator
        table.target = context.coordinator; table.doubleAction = #selector(Coordinator.openRow)
        table.onReturn = { [weak coordinator = context.coordinator] in coordinator?.openSelectedRow() }
        table.setDraggingSourceOperationMask(.copy, forLocal: false); table.setDraggingSourceOperationMask(.copy, forLocal: true)
        let menu = NSMenu(); let info = NSMenuItem(title: "查看信息", action: #selector(Coordinator.showInfo), keyEquivalent: ""); info.target = context.coordinator; menu.addItem(info); table.menu = menu
        context.coordinator.table = table
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true; scroll.documentView = table; scroll.borderType = .bezelBorder
        return scroll
    }
    func updateNSView(_ view: NSScrollView, context: Context) {
        let coordinator = context.coordinator; coordinator.model = model
        let rows = coordinator.sorted(model.filtered)
        if rows != coordinator.rows {
            coordinator.rows = rows; coordinator.updating = true; coordinator.table?.reloadData(); coordinator.updating = false
        }
        let indexes = IndexSet(coordinator.rows.indices.filter { model.selected.contains(coordinator.rows[$0].id) })
        if coordinator.table?.selectedRowIndexes != indexes { coordinator.updating = true; coordinator.table?.selectRowIndexes(indexes, byExtendingSelection: false); coordinator.updating = false }
    }
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var model: ExportModel
        weak var table: NSTableView?
        var rows: [BrowserEntry] = []
        var updating = false
        var dragIDs: [UUID] = []
        init(model: ExportModel) { self.model = model }
        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let entry = rows[row], key = tableColumn?.identifier.rawValue ?? "name"
            let cell = NSTableCellView(); let text = NSTextField(labelWithString: ""); text.lineBreakMode = .byTruncatingMiddle
            text.font = .systemFont(ofSize: key == "name" ? 12 : 11); text.textColor = entry.unavailableReason == nil ? .labelColor : .secondaryLabelColor
            switch key {
            case "name": text.stringValue = entry.name + (entry.subtitle.isEmpty ? "" : "  ·  " + entry.subtitle)
            case "type": text.stringValue = entry.unavailableReason == nil ? entry.typeDescription : "不可导出"
            case "size": text.stringValue = entry.sizeText; text.alignment = .right
            default: text.stringValue = entry.dateText
            }
            text.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(text); cell.textField = text
            if key == "name" {
                let icon = NSImageView(); icon.image = NSImage(systemSymbolName: entry.isSymbolicLink ? "link" : entry.isDirectory ? "folder" : ["zip", "7z", "rar", "gz"].contains(entry.url?.pathExtension.lowercased() ?? "") ? "archivebox" : "doc", accessibilityDescription: nil)
                icon.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(icon); cell.imageView = icon
                NSLayoutConstraint.activate([icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 5), icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor), icon.widthAnchor.constraint(equalToConstant: 18), icon.heightAnchor.constraint(equalToConstant: 18), text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8)])
            } else { text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 5).isActive = true }
            NSLayoutConstraint.activate([text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6), text.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
            cell.toolTip = entry.name + "\n" + (entry.url?.path ?? entry.subtitle) + (entry.unavailableReason.map { "\n" + $0 } ?? "")
            cell.setAccessibilityLabel("\(entry.name)，\(entry.typeDescription)，\(entry.sizeText)，\(entry.dateText)")
            return cell
        }
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !updating, let table else { return }; model.selected = Set(table.selectedRowIndexes.compactMap { rows.indices.contains($0) ? rows[$0].id : nil })
        }
        @MainActor func openSelectedRow() {
            guard let table, rows.indices.contains(table.selectedRow) else { return }; model.open(rows[table.selectedRow])
        }
        @MainActor @objc func openRow() {
            guard let table else { return }; let row = table.clickedRow >= 0 ? table.clickedRow : table.selectedRow
            guard rows.indices.contains(row) else { return }; model.open(rows[row])
        }
        @MainActor @objc func showInfo() {
            guard let table else { return }; let row = table.clickedRow >= 0 ? table.clickedRow : table.selectedRow
            if rows.indices.contains(row) { model.info = rows[row] }
        }
        func sorted(_ entries: [BrowserEntry]) -> [BrowserEntry] {
            let descriptor = table?.sortDescriptors.first
            return entries.sorted { a, b in
                if a.isDirectory != b.isDirectory { return a.isDirectory }
                let ascending = descriptor?.ascending ?? true
                switch descriptor?.key {
                case "type": if a.typeDescription != b.typeDescription { return ascending ? a.typeDescription.localizedStandardCompare(b.typeDescription) == .orderedAscending : a.typeDescription.localizedStandardCompare(b.typeDescription) == .orderedDescending }
                case "size": if a.byteCount != b.byteCount { return ascending ? (a.byteCount ?? -1) < (b.byteCount ?? -1) : (a.byteCount ?? -1) > (b.byteCount ?? -1) }
                case "date": if a.modified != b.modified { return ascending ? (a.modified ?? .distantPast) < (b.modified ?? .distantPast) : (a.modified ?? .distantPast) > (b.modified ?? .distantPast) }
                default: break
                }
                let order = a.name.localizedStandardCompare(b.name); return ascending ? order == .orderedAscending : order == .orderedDescending
            }
        }
        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            rows = sorted(rows); updating = true; tableView.reloadData(); tableView.selectRowIndexes(IndexSet(rows.indices.filter { model.selected.contains(rows[$0].id) }), byExtendingSelection: false); updating = false
        }
        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard rows.indices.contains(row), rows[row].canExport, model.activeExports == 0, let snapshot = try? model.snapshot(rows[row]) else { return nil }
            let delegate = ExportPromiseDelegate(snapshot: snapshot)
            delegate.onStart = { [weak model] item in await model?.promiseStarted(item) }
            delegate.onFinish = { [weak model] item, url, error in await model?.promiseFinished(item, destination: url, error: error) }
            let type = snapshot.isDirectory ? UTType.folder : UTType(filenameExtension: snapshot.source.pathExtension) ?? .data
            let provider = NSFilePromiseProvider(fileType: type.identifier, delegate: delegate)
            ExportPromiseStore.shared.retain(provider, delegate: delegate); dragIDs.append(snapshot.id)
            return provider
        }
        func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            if operation.isEmpty { ExportPromiseStore.shared.cancelled(dragIDs) }; dragIDs = []
        }
    }
    final class BrowserTableView: NSTableView {
        var onReturn: (() -> Void)?
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 36 || event.keyCode == 76 { onReturn?() } else { super.keyDown(with: event) }
        }
    }
}
