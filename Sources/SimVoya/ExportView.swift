import SwiftUI
import AppKit

struct ExportView: View {
    let device: SimulatorDevice?
    @ObservedObject var model: ExportModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("从模拟器导出").font(.system(size: 24, weight: .medium))
                TransferRoute(device: device, exporting: true)
            }
            HStack(spacing: 12) {
                Picker("来源", selection: $model.source) { ForEach(ExportSourceKind.allCases) { Text($0.rawValue).tag($0) } }.frame(maxWidth: 310)
                Spacer(minLength: 8)
                TextField(model.directory == nil ? "搜索名称或标识" : "搜索当前文件夹", text: $model.search).textFieldStyle(.roundedBorder).frame(maxWidth: 230)
            }
            HStack(spacing: 8) {
                Button { model.up() } label: { Image(systemName: "arrow.up") }.disabled(!model.canGoUp).help("返回上一级").accessibilityLabel("返回上一级")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button(model.currentRoot?.name ?? model.source.rawValue) {
                            if let root = model.currentRoot, let url = root.url { model.navigate(url, root: root) } else { model.chooseSource() }
                        }.buttonStyle(.link)
                        ForEach(breadcrumbs, id: \.path) { url in
                            Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(.secondary)
                            Button(url.lastPathComponent) { if let root = model.currentRoot { model.navigate(url, root: root) } }.buttonStyle(.link)
                        }
                    }.font(.system(size: 12)).lineLimit(1)
                }
                Toggle("显示隐藏文件", isOn: $model.showHidden).toggleStyle(.checkbox).font(.caption).help("显示点开头的隐藏文件")
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }.disabled(model.loading).help("刷新文件列表").accessibilityLabel("刷新文件列表")
            }
            ZStack {
                ExportFileTable(model: model)
                if model.loading {
                    VStack(spacing: 10) { ProgressView(); Text("正在读取文件…").font(.caption) }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(nsColor: .textBackgroundColor).opacity(0.95))
                } else if let error = model.error {
                    VStack(spacing: 10) { Image(systemName: "exclamationmark.triangle"); Text("无法读取此位置").font(.headline); ScrollView { Text(error).font(.caption).textSelection(.enabled).multilineTextAlignment(.center) }.frame(maxHeight: 80); Button("重试") { model.refresh() } }.padding(25).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(nsColor: .textBackgroundColor))
                } else if model.filtered.isEmpty {
                    Text(model.search.isEmpty ? "这个位置没有可显示的条目" : "没有匹配的文件").font(.callout).foregroundStyle(.secondary).allowsHitTesting(false)
                }
            }
            .frame(minHeight: 180)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(0.10))
                    .allowsHitTesting(false)
            }
            HStack {
                Text("\(model.filtered.count) 项 · 已选 \(model.selected.count) 项").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                if model.selected.count == 1, let entry = model.filtered.first(where: { model.selected.contains($0.id) }) { Button("查看信息") { model.info = entry }.buttonStyle(.link).font(.caption) }
                Spacer()
                Button("导出所选…") { model.chooseDestination() }.buttonStyle(.borderedProminent).keyboardShortcut("e", modifiers: [.command, .shift]).disabled(model.loading || model.chosen.isEmpty || model.activeExports > 0)
            }
            Text("拖到 Finder 以复制，原文件保留。加密压缩包无需密码" + (model.showHidden ? "" : " · 已隐藏点开头文件"))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if model.activeExports > 0 { HStack { ProgressView().controlSize(.small); Text("正在导出 \(model.activeExports) 项，复制并校验内容…").font(.caption) } }
            if !model.records.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text("最近导出").font(.caption.weight(.semibold)); Spacer(); Button("清空记录") { model.records.removeAll() }.buttonStyle(.link).font(.caption).disabled(model.activeExports > 0) }
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(model.records) { record in
                                HStack(alignment: .top, spacing: 8) {
                                    if !record.finished { ProgressView().controlSize(.mini) }
                                    else { Image(systemName: record.error == nil ? "checkmark.circle.fill" : "exclamationmark.circle.fill").foregroundStyle(record.error == nil ? .green : .red) }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(record.name).lineLimit(1).truncationMode(.middle)
                                        if let error = record.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                                        else if record.finished { Text("已导出 · \(record.destination?.lastPathComponent ?? record.name)").foregroundStyle(.secondary) }
                                    }
                                    Spacer()
                                    if let destination = record.destination { Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([destination]) }.buttonStyle(.link) }
                                }.font(.system(size: 11))
                            }
                        }
                    }.frame(maxHeight: 90)
                }.padding(12).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .onChange(of: model.source) { model.chooseSource() }
        .onChange(of: model.showHidden) { model.refresh() }
        .onChange(of: device?.id) { model.setDevice(device) }
        .onAppear { model.setDevice(device) }
        .sheet(item: $model.info) { entry in
            VStack(alignment: .leading, spacing: 12) {
                Text(entry.name).font(.headline)
                Text("类型：\(entry.typeDescription)\n大小：\(entry.isDirectory ? "文件夹（未递归计算）" : entry.byteCount.map { "\($0) bytes" } ?? "未知")\n修改时间：\(entry.dateText)\n创建时间：\(entry.created?.formatted() ?? "未知")\n来源：\(model.currentRoot?.name ?? model.source.rawValue)\n路径：\(entry.url?.path ?? entry.subtitle)\n状态：\(entry.unavailableReason ?? "可读取")").font(.callout).textSelection(.enabled)
                HStack { Spacer(); Button("完成") { model.info = nil }.keyboardShortcut(.defaultAction) }
            }.padding(24).frame(width: 520)
        }
    }
    private var breadcrumbs: [URL] {
        guard let directory = model.directory, let root = model.currentRoot?.url else { return [] }
        var result: [URL] = [], current = root
        for part in directory.standardizedFileURL.pathComponents.dropFirst(root.standardizedFileURL.pathComponents.count) { current.appendPathComponent(part); result.append(current) }
        return result
    }
}
