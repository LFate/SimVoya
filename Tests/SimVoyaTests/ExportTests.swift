import XCTest
import AppKit
import UniformTypeIdentifiers
@testable import SimVoya

final class ExportTests: XCTestCase {
    func fixture() throws -> (URL, URL, URL) {
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent("simvoya-export-test-\(UUID().uuidString)", isDirectory: true)
        let data = workspace.appendingPathComponent("device/data", isDirectory: true), output = workspace.appendingPathComponent("output", isDirectory: true)
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        return (workspace, data, output)
    }
    func testDiscoveryIncludesAllAppsAndDeduplicatesGroups() throws {
        let (workspace, data, _) = try fixture(); defer { try? FileManager.default.removeItem(at: workspace) }
        let apps: [String: Any] = [
            "test.user": ["CFBundleDisplayName": "Demo", "DataContainer": data.appendingPathComponent("app").absoluteString, "GroupContainers": ["group.shared": data.appendingPathComponent("group").absoluteString]],
            "com.apple.DocumentsApp": ["CFBundleName": "Files", "DataContainer": data.appendingPathComponent("files").absoluteString, "GroupContainers": ["group.com.apple.FileProvider.LocalStorage": data.appendingPathComponent("local").absoluteString, "group.shared": data.appendingPathComponent("group").absoluteString]],
            "test.no-data": ["CFBundleName": "No Data"]
        ]
        let roots = try FileBrowserService.roots(from: JSONSerialization.data(withJSONObject: apps), dataRoot: data)
        XCTAssertEqual(roots.filter { $0.kind == .applications }.count, 3)
        XCTAssertEqual(roots.filter { $0.kind == .sharedGroups }.count, 2)
        XCTAssertEqual(roots.first { $0.kind == .localFiles }?.url?.lastPathComponent, "File Provider Storage")
        XCTAssertEqual(roots.first { $0.kind == .deviceData }?.url, data)
        XCTAssertNotNil(FileBrowserService.rootEntry(roots.first { $0.id == "app:test.no-data" }!).unavailableReason)
    }
    func testNavigationMetadataHiddenAndSymlinkBoundaries() throws {
        let (workspace, data, _) = try fixture(); defer { try? FileManager.default.removeItem(at: workspace) }
        let file = data.appendingPathComponent("空文件.txt"), hidden = data.appendingPathComponent(".hidden")
        try Data().write(to: file); try Data("hidden".utf8).write(to: hidden)
        let link = data.appendingPathComponent("escape")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: workspace)
        let root = BrowserRoot(id: "test", kind: .deviceData, name: "Device", subtitle: "", url: data, dataRoot: data)
        let visible = try FileBrowserService.list(data, root: root, showHidden: false)
        XCTAssertEqual(visible.count, 2)
        XCTAssertEqual(visible.first { $0.name == "空文件.txt" }?.byteCount, 0)
        XCTAssertFalse(visible.first { $0.name == "escape" }!.canExport)
        XCTAssertEqual(try FileBrowserService.list(data, root: root, showHidden: true).count, 3)
        XCTAssertThrowsError(try FileBrowserService.validate(link, root: data, dataRoot: data))
        XCTAssertThrowsError(try FileBrowserService.list(workspace, root: root, showHidden: true))
        XCTAssertFalse(FileBrowserService.isWithin(URL(fileURLWithPath: data.path + "-other"), root: data))
    }
    func testFolderCopyPreservesNestedEmptyAndHiddenContentsAndDuplicates() async throws {
        let (workspace, data, output) = try fixture(); defer { try? FileManager.default.removeItem(at: workspace) }
        let source = data.appendingPathComponent("中文 文件夹", isDirectory: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("nested/empty-directory"), withIntermediateDirectories: true)
        try Data().write(to: source.appendingPathComponent("nested/empty.txt"))
        try Data("payload".utf8).write(to: source.appendingPathComponent(".hidden"))
        let snapshot = ExportSnapshot(source: source, sourceRoot: data, dataRoot: data, isDirectory: true)
        async let first = ExportService().export(snapshot, toDirectory: output)
        async let second = ExportService().export(snapshot, toDirectory: output)
        let destinations = try await [first, second]
        XCTAssertEqual(Set(destinations.map(\.lastPathComponent)), ["中文 文件夹", "中文 文件夹 (2)"])
        for destination in destinations { XCTAssertNoThrow(try ImportService.verify(source, destination)) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        let remaining = try FileManager.default.contentsOfDirectory(atPath: output.path)
        XCTAssertFalse(remaining.contains { $0.hasPrefix(".simvoya") })
    }
    func testRejectsConflictsAndTargetsWithinSimulatorWithoutChangingEither() async throws {
        let (workspace, data, output) = try fixture(); defer { try? FileManager.default.removeItem(at: workspace) }
        let source = data.appendingPathComponent("encrypted.zip"), target = output.appendingPathComponent("encrypted.zip")
        try Data([0x50, 0x4b, 0x03, 0x04, 0xff]).write(to: source); try Data("existing".utf8).write(to: target)
        let snapshot = ExportSnapshot(source: source, sourceRoot: data, dataRoot: data, isDirectory: false)
        do { _ = try await ExportService().fulfillPromise(snapshot, exactDestination: target); XCTFail("Must not overwrite") } catch {}
        XCTAssertEqual(try Data(contentsOf: target), Data("existing".utf8))
        do { _ = try await ExportService().fulfillPromise(snapshot, exactDestination: data.appendingPathComponent("another.zip")); XCTFail("Must not export into simulator") } catch {}
        XCTAssertEqual(try Data(contentsOf: source), Data([0x50, 0x4b, 0x03, 0x04, 0xff]))
    }
    func testPromiseDelegateWritesExactFileAndDirectoryAndReportsConflict() async throws {
        let (workspace, data, output) = try fixture(); defer { try? FileManager.default.removeItem(at: workspace) }
        let file = data.appendingPathComponent("密文.zip"), directory = data.appendingPathComponent("folder")
        try Data([0x50, 0x4b, 0x03, 0x04, 0, 1, 2]).write(to: file)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("child"), withIntermediateDirectories: true)
        try Data("data".utf8).write(to: directory.appendingPathComponent("child/data.txt"))
        for source in [file, directory] {
            let isDirectory = source == directory
            let snapshot = ExportSnapshot(source: source, sourceRoot: data, dataRoot: data, isDirectory: isDirectory)
            let delegate = ExportPromiseDelegate(snapshot: snapshot)
            let provider = NSFilePromiseProvider(fileType: isDirectory ? UTType.folder.identifier : UTType.zip.identifier, delegate: delegate)
            let promisedName = await delegate.filePromiseProvider(provider, fileNameForType: provider.fileType)
            XCTAssertEqual(promisedName, source.lastPathComponent)
            let destination = output.appendingPathComponent(isDirectory ? "Finder chosen folder (2)" : "Finder chosen archive (2).zip")
            let complete = expectation(description: "promise \(source.lastPathComponent)"); complete.assertForOverFulfill = true
            delegate.filePromiseProvider(provider, writePromiseTo: destination) { error in XCTAssertNil(error); complete.fulfill() }
            await fulfillment(of: [complete], timeout: 10)
            XCTAssertNoThrow(try ImportService.verify(source, destination))
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathComponent(source.lastPathComponent).path))
            let conflictDelegate = ExportPromiseDelegate(snapshot: snapshot)
            let conflictProvider = NSFilePromiseProvider(fileType: provider.fileType, delegate: conflictDelegate)
            let rejected = expectation(description: "conflict rejected"); rejected.assertForOverFulfill = true
            conflictDelegate.filePromiseProvider(conflictProvider, writePromiseTo: destination) { error in XCTAssertNotNil(error); rejected.fulfill() }
            await fulfillment(of: [rejected], timeout: 10)
            XCTAssertNoThrow(try ImportService.verify(source, destination))
        }
    }
    func testLiveSimulatorExportWhenRequested() async throws {
        guard let id = ProcessInfo.processInfo.environment["SIMVOYA_LIVE_EXPORT_DEVICE"] else { throw XCTSkip("Set SIMVOYA_LIVE_EXPORT_DEVICE for explicit simulator smoke test") }
        guard let device = try await SimulatorService().devices().first(where: { $0.id == id }) else { throw AppError("Live simulator is not booted") }
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent("simvoya-live-export-\(UUID().uuidString)", isDirectory: true)
        let input = workspace.appendingPathComponent("Export Demo", isDirectory: true), output = workspace.appendingPathComponent("Mac Export", isDirectory: true)
        try FileManager.default.createDirectory(at: input.appendingPathComponent("中文 文件夹/nested/empty-directory"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try Data("SimVoya export demo only\n".utf8).write(to: input.appendingPathComponent("Welcome.txt"))
        try Data("Nested export demo\n".utf8).write(to: input.appendingPathComponent("中文 文件夹/nested/说明.txt"))
        try Data().write(to: input.appendingPathComponent("中文 文件夹/nested/empty.txt"))
        let archive = input.appendingPathComponent("Encrypted Demo.zip")
        _ = try await ProcessRunner.shared.run("/usr/bin/zip", ["-j", "-P", "simvoya-fixture-only", archive.path, input.appendingPathComponent("Welcome.txt").path])
        let receipt = try await ImportService().importItem(input, to: device, mode: .files)
        let imported = try XCTUnwrap(receipt.destination)
        let roots = try await FileBrowserService().discover(device)
        let local = try XCTUnwrap(roots.first { $0.kind == .localFiles })
        let rows = try FileBrowserService.list(imported, root: local, showHidden: true)
        XCTAssertEqual(rows.count, 3)
        for row in rows {
            let snapshot = try ExportSnapshot(device: device, root: local, entry: row)
            let destination = try await ExportService().export(snapshot, toDirectory: output)
            XCTAssertNoThrow(try ImportService.verify(try XCTUnwrap(row.url), destination))
            print("LIVE EXPORT PASS \(row.name) => \(destination.path)")
        }
        // Actually navigate an installed app's Documents and one of its descendants.
        var navigated = false
        for appRoot in roots.filter({ $0.kind == .applications }) {
            guard let rootURL = appRoot.url else { continue }
            let docs = rootURL.appendingPathComponent("Documents", isDirectory: true)
            guard let children = try? FileBrowserService.list(docs, root: appRoot, showHidden: true) else { continue }
            if let child = children.first(where: { $0.isDirectory && $0.canExport }), let childURL = child.url {
                _ = try FileBrowserService.list(childURL, root: appRoot, showHidden: true); navigated = true; print("LIVE APP DOCUMENTS NAVIGATION PASS"); break
            }
        }
        XCTAssertTrue(navigated, "At least one installed App Documents subfolder must be browsable")
        print("LIVE SIMULATOR FIXTURE: \(imported.path)")
        print("LIVE MAC OUTPUT: \(output.path)")
        print("LIVE ARCHIVE MANIFEST: \(try ImportService.manifest(archive))")
    }
}
