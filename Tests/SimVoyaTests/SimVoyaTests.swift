import XCTest
@testable import SimVoya

final class SimVoyaTests: XCTestCase {
    func testOnlyAvailableBootedDevicesAreListed() throws {
        let json = #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-27-2":[{"udid":"b","name":"Z","state":"Booted","isAvailable":true},{"udid":"a","name":"A","state":"Shutdown","isAvailable":true},{"udid":"c","name":"C","state":"Booted","isAvailable":false}]}}"#
        let devices = try SimulatorService.parse(Data(json.utf8))
        XCTAssertEqual(devices.map(\.id), ["b"])
        XCTAssertEqual(devices.first?.runtime, "iOS 27.2")
        XCTAssertThrowsError(try SimulatorService.parse(Data("invalid".utf8)))
    }
    func testContainerParsingRequiresExactGroup() {
        XCTAssertNil(ImportService.localContainer("Usage: simctl get_app_container"))
        XCTAssertNil(ImportService.localContainer("group.com.apple.FileProvider.LocalStorage.other\t/tmp/wrong"))
        XCTAssertEqual(ImportService.localContainer("group.com.apple.tipsnext\t/tmp/wrong\ngroup.com.apple.FileProvider.LocalStorage\t/tmp/right\n")?.path, "/tmp/right")
    }
    func testRoutingDuplicateNamesAndContentVerification() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("中文 sample.txt")
        try Data("测试 abc".utf8).write(to: file)
        XCTAssertFalse(try ImportMode.automatic.usesPhotos(file))
        XCTAssertThrowsError(try ImportMode.photos.usesPhotos(file))
        XCTAssertEqual(ImportService.uniqueDestination(source: file, folder: folder).lastPathComponent, "中文 sample (2).txt")
        let image = folder.appendingPathComponent("image.png")
        try Data().write(to: image)
        XCTAssertTrue(try ImportMode.automatic.usesPhotos(image))
        XCTAssertFalse(try ImportMode.files.usesPhotos(image))
        XCTAssertFalse(try ImportMode.automatic.usesPhotos(folder))
        XCTAssertThrowsError(try ImportMode.photos.usesPhotos(folder))
        let copy = folder.appendingPathComponent("copy.txt")
        try Data("测试 abc".utf8).write(to: copy)
        XCTAssertNoThrow(try ImportService.verify(file, copy))
        try Data("测试 abd".utf8).write(to: copy)
        XCTAssertThrowsError(try ImportService.verify(file, copy))
        let link = folder.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        XCTAssertThrowsError(try ImportService.validateTree(folder))
    }
    func testCommandFailureAndTimeout() async throws {
        let result = try await ProcessRunner.shared.run("/usr/bin/printf", ["a b 中文"])
        XCTAssertEqual(result.stdout, "a b 中文")
        do { _ = try await ProcessRunner.shared.run("/usr/bin/false", []); XCTFail("Expected failure") } catch {}
        let start = Date()
        do { _ = try await ProcessRunner.shared.run("/bin/sleep", ["10"], timeout: 0.1); XCTFail("Expected timeout") }
        catch { XCTAssertTrue(error.localizedDescription.contains("超时")) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }
}
