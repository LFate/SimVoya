import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var targeted = false
    @Environment(\.colorScheme) private var scheme
    private var accent: Color { scheme == .dark ? Color(red: 0.65, green: 0.70, blue: 0.99) : Color(red: 0.31, green: 0.27, blue: 0.90) }
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 228)
            Divider()
            VStack(alignment: .leading, spacing: 20) {
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
            .padding(28).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .tint(accent)
        .frame(minWidth: 760, minHeight: 580)
        .toolbar {
            ToolbarItemGroup {
                Button { model.openSimulator() } label: { Label("打开模拟器", systemImage: "iphone.gen3") }
                Button { Task { await model.refresh() } } label: { Label("刷新", systemImage: "arrow.clockwise") }.keyboardShortcut("r").disabled(model.refreshing)
            }
        }
        .task { while !Task.isCancelled { await model.refresh(); try? await Task.sleep(nanoseconds: 3_000_000_000) } }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("正在运行").font(.system(size: 12, weight: .semibold)); Text("\(model.devices.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary); Spacer(); if model.refreshing { ProgressView().controlSize(.mini) } }.padding(.horizontal, 16).padding(.top, 24)
            List(selection: $model.selectedID) {
                ForEach(model.devices) { device in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: device.name.lowercased().contains("ipad") ? "ipad" : "iphone.gen3").font(.system(size: 23, weight: .light)).frame(width: 26).padding(.top, 2)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(device.name).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                            Text(device.runtime).font(.caption).foregroundStyle(.secondary)
                            Label("运行中", systemImage: "circle.fill").font(.system(size: 10)).foregroundStyle(.green)
                        }
                    }.padding(.vertical, 8).tag(device.id).help("\(device.name) · \(device.runtime)\n\(device.id)")
                }
            }.listStyle(.sidebar)
            if model.devices.isEmpty { Text("暂无运行中的设备").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16) }
            Spacer(minLength: 0)
            Label("每 3 秒自动更新", systemImage: "arrow.triangle.2.circlepath").font(.system(size: 11)).foregroundStyle(.secondary).padding(16)
        }.background(Color(nsColor: .underPageBackgroundColor))
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("把文件送进模拟器").font(.system(size: 24, weight: .semibold))
            HStack(spacing: 6) {
                Text("目标设备").foregroundStyle(.secondary)
                if let device = model.selected { Text(device.name).fontWeight(.medium).lineLimit(1); Text("· \(device.runtime)").foregroundStyle(.secondary).lineLimit(1) }
                else { Text("尚未选择").foregroundStyle(.secondary) }
            }.font(.system(size: 12))
        }
    }
    private var importArea: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("导入位置", selection: $model.mode) { ForEach(ImportMode.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).frame(width: 240).disabled(model.importing)
            VStack(spacing: 14) {
                if model.importing {
                    ProgressView(value: Double(model.completed), total: Double(max(1, model.total))).frame(width: 200)
                    Text("正在导入 \(min(model.completed + 1, model.total)) / \(model.total)").font(.system(size: 17, weight: .semibold))
                    Text("到 \(model.batchDevice)").foregroundStyle(.secondary).font(.caption)
                } else {
                    Image(systemName: "tray.and.arrow.down").font(.system(size: 34, weight: .light)).foregroundStyle(accent)
                    Text(targeted ? "松开以导入到 \(model.selected?.name ?? "模拟器")" : "拖入图片、视频或文件").font(.system(size: 17, weight: .semibold)).lineLimit(2).multilineTextAlignment(.center)
                    Button("选择文件…") { model.chooseFiles() }.keyboardShortcut("o").disabled(!model.canImport)
                }
            }
            .frame(maxWidth: .infinity).frame(height: 190)
            .background(accent.opacity(targeted ? 0.10 : 0.035), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(accent.opacity(targeted ? 0.9 : 0.30), style: StrokeStyle(lineWidth: targeted ? 2 : 1, dash: targeted ? [] : [6, 5])))
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
                VStack(spacing: 6) { Text("还没有导入记录").font(.system(size: 12)); Text("文件会保留在 Mac 上，不会被移动或删除。").font(.system(size: 11)) }.foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
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
        VStack(spacing: 14) { Image(systemName: icon).font(.system(size: 42, weight: .ultraLight)).foregroundStyle(accent); Text(title).font(.title3.weight(.semibold)); Text(text).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center) }.frame(maxWidth: .infinity)
    }
}
