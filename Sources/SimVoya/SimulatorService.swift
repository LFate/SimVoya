import Foundation

struct SimulatorService: Sendable {
    struct DeviceList: Decodable { let devices: [String: [Device]] }
    struct Device: Decodable { let udid: String; let name: String; let state: String; let isAvailable: Bool?; let dataPath: String? }
    static func parse(_ data: Data) throws -> [SimulatorDevice] {
        let list = try JSONDecoder().decode(DeviceList.self, from: data)
        return list.devices.flatMap { runtime, devices in
            devices.filter { $0.state == "Booted" && $0.isAvailable != false }.map {
                SimulatorDevice(id: $0.udid, name: $0.name, runtime: runtime.replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "").replacingOccurrences(of: "-", with: ".").replacingOccurrences(of: "iOS.", with: "iOS ").replacingOccurrences(of: "iPadOS.", with: "iPadOS "), dataPath: $0.dataPath)
            }
        }.sorted { ($0.name, $0.id) < ($1.name, $1.id) }
    }
    func devices() async throws -> [SimulatorDevice] {
        let output = try await ProcessRunner.shared.simctl(["list", "devices", "booted", "-j"])
        return try Self.parse(Data(output.stdout.utf8))
    }
    func requireBooted(_ device: SimulatorDevice) async throws {
        guard try await devices().contains(where: { $0.id == device.id }) else { throw AppError("目标模拟器已关闭，请重新启动后导入。") }
    }
    func openFiles(_ device: SimulatorDevice) async throws {
        try await requireBooted(device)
        _ = try await ProcessRunner.shared.simctl(["launch", device.id, "com.apple.DocumentsApp"])
    }
}
