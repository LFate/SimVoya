import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var targeted = false
    @StateObject private var exportModel = ExportModel()
    @Environment(\.colorScheme) private var scheme
    private var accent: Color { TransferAppearance.accent(for: scheme) }
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 240)
            Divider()
            VStack(alignment: .leading, spacing: 16) {
                Picker("工作模式", selection: $model.workspace) { ForEach(WorkspaceMode.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden().frame(width: 160)
                if let error = model.deviceError {
                    Spacer()
                    emptyState(icon: "exclamationmark.triangle", title: "无法读取模拟器", text: "请确认 Xcode 已安装，并且开发工具可用。")
                    DisclosureGroup("错误详情") { ScrollView { Text(error).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 100) }
                    Button("重试") { Task { await model.refresh() } }
                    Spacer()
                } else if model.devices.isEmpty {
                    Spacer()
                    emptyState(icon: "iphone.gen3", title: "先启动一台模拟器", text: "启动后会自动出现在这里。")
                    HStack { Spacer(); Button("打开模拟器") { model.openSimulator() }.buttonStyle(.borderedProminent); Spacer() }
                    Spacer()
                } else if model.workspace == .exporting {
                    if model.selected != nil { ExportView(device: model.selected, model: exportModel) }
                    else { emptyState(icon: "cursorarrow.click", title: "选择目标设备", text: "从左侧选择一台运行中的模拟器。") }
                } else {
                    header
                    if model.selected != nil || model.importing {
                        importArea
                        history
                    } else {
                        Spacer()
                        emptyState(icon: "cursorarrow.click", title: "选择目标设备", text: model.notice ?? "从左侧选择一台运行中的模拟器。")
                        Spacer()
                    }
                }
                if let notice = model.notice, model.selected != nil {
                    Text(notice).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .tint(accent)
        .frame(minWidth: 940, minHeight: 680)
        .toolbar {
            ToolbarItemGroup {
                Button { model.openSimulator() } label: { Label("打开模拟器", systemImage: "iphone.gen3") }
                Button { Task { await model.refresh(); if model.workspace == .exporting { exportModel.refresh() } } } label: { Label("刷新", systemImage: "arrow.clockwise") }.keyboardShortcut("r").disabled(model.refreshing)
            }
        }
        .onChange(of: model.selectedID) { exportModel.setDevice(model.selected) }
        .task { while !Task.isCancelled { await model.refresh(); try? await Task.sleep(nanoseconds: 3_000_000_000) } }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("运行中的设备").font(.system(size: 12, weight: .medium))
                Text(model.devices.count.formatted()).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                if model.refreshing { ProgressView().controlSize(.mini) }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)

            List(selection: $model.selectedID) {
                ForEach(model.devices) { device in
                    HStack(spacing: 8) {
                        Image(systemName: device.name.lowercased().contains("ipad") ? "ipad" : "iphone.gen3")
                            .font(.system(size: 16)).frame(width: 20)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(device.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                            Text(device.runtime).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        Circle().fill(Color(nsColor: .systemGreen)).frame(width: 6, height: 6)
                            .accessibilityLabel("运行中")
                    }
                    .frame(minHeight: 36)
                    .tag(device.id)
                    .help("\(device.name) · \(device.runtime)\n\(device.id)")
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            if model.devices.isEmpty {
                Text("暂无运行中的设备").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16)
            }

            Label("设备列表自动刷新", systemImage: "arrow.clockwise")
                .font(.caption).foregroundStyle(.secondary).padding(16)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("导入到模拟器").font(.system(size: 24, weight: .medium))
            TransferRoute(device: model.selected, exporting: false)
        }
    }
    private var importArea: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("导入位置", selection: $model.mode) { ForEach(ImportMode.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).frame(width: 240).disabled(model.importing)
            HStack(spacing: 16) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(accent)
                    .frame(width: 44, height: 44)
                    .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)

                if model.importing {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("正在导入 \(min(model.completed + 1, model.total)) / \(model.total)")
                            .font(.system(size: 16, weight: .medium)).monospacedDigit()
                        ProgressView(value: Double(model.completed), total: Double(max(1, model.total)))
                            .frame(maxWidth: 240)
                        Text("到 \(model.batchDevice)").foregroundStyle(.secondary).font(.caption)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(targeted ? "松开以导入到 \(model.selected?.name ?? "模拟器")" : "拖入图片、视频或文件")
                            .font(.system(size: 16, weight: .medium)).lineLimit(2)
                        Text("也可以从 Mac 选择文件").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Button("选择文件…") { model.chooseFiles() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut("o")
                        .disabled(!model.canImport)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
            .background(targeted ? accent.opacity(0.12) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(targeted ? accent : Color.primary.opacity(0.14),
                                  style: StrokeStyle(lineWidth: targeted ? 2 : 1, dash: targeted ? [] : [4, 4]))
                    .allowsHitTesting(false)
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard model.canImport, !urls.isEmpty else { return false }; model.startImport(urls); return true
            } isTargeted: { targeted = $0 && model.canImport }
            HStack(alignment: .top) {
                Text(model.mode.hint).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("打开文件 App") { model.openFiles() }.font(.system(size: 11)).buttonStyle(.link).disabled(model.selected == nil || model.importing)
            }
        }
    }
    private var history: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("最近导入").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("清空") { model.records.removeAll(); model.summary = "" }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary).disabled(model.importing || model.records.isEmpty)
            }
            if model.records.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("暂无导入记录").font(.system(size: 13))
                    Text("原始文件保留在 Mac 上").font(.caption)
                }
                .foregroundStyle(.secondary)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.records) { record in
                            HStack(spacing: 10) {
                                if !record.finished { ProgressView().controlSize(.small).frame(width: 18) }
                                else { Image(systemName: record.error == nil ? "checkmark.circle.fill" : "exclamationmark.circle.fill").foregroundStyle(record.error == nil ? Color.green : Color.red).frame(width: 18) }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(record.name).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                                    Text(record.device).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                Text(record.error == nil ? (record.receipt?.message ?? "导入中…") : "导入失败 · 查看详情").font(.system(size: 11)).foregroundStyle(record.error == nil ? .secondary : Color.red).lineLimit(1)
                            }.padding(.vertical, 9)
                            .help(record.error ?? record.receipt?.detail ?? record.name)
                            if let error = record.error {
                                DisclosureGroup("错误详情 · 重新拖入即可重试") { Text(error).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.font(.system(size: 10)).padding(.bottom, 6)
                            }
                            Divider()
                        }
                    }
                }
            }
            if !model.summary.isEmpty { Text(model.summary).font(.system(size: 11)).foregroundStyle(.secondary) }
        }.frame(maxHeight: .infinity)
    }
    private func emptyState(icon: String, title: String, text: String) -> some View {
        VStack(spacing: 12) { Image(systemName: icon).font(.system(size: 32, weight: .light)).foregroundStyle(accent); Text(title).font(.title3.weight(.semibold)); Text(text).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center) }.frame(maxWidth: .infinity)
    }
}

enum TransferAppearance {
    static func accent(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.69, green: 0.72, blue: 0.97)
            : Color(red: 0.31, green: 0.30, blue: 0.65)
    }
}

struct TransferRoute: View {
    let device: SimulatorDevice?
    let exporting: Bool

    var body: some View {
        HStack(spacing: 8) {
            endpoint(isSimulator: exporting)
            Image(systemName: "arrow.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            endpoint(isSimulator: !exporting)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(exporting ? "从\(device?.name ?? "模拟器")传到 Mac" : "从 Mac 传到\(device?.name ?? "模拟器")")
    }

    private func endpoint(isSimulator: Bool) -> some View {
        Group {
            if isSimulator {
                Label(device.map { "\($0.name) · \($0.runtime)" } ?? "模拟器", systemImage: "iphone.gen3")
            } else {
                Label("Mac", systemImage: "laptopcomputer")
            }
        }
        .lineLimit(1)
    }
}
