import Foundation
import UniformTypeIdentifiers

struct SimulatorDevice: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let runtime: String
}
enum ImportMode: String, CaseIterable, Identifiable, Sendable {
    case automatic = "自动", photos = "照片", files = "文件"
    var id: String { rawValue }
    var hint: String {
        switch self {
        case .automatic: return "图片和视频 → 照片 · 其他文件和文件夹 → 文件 App / SimVoya"
        case .photos: return "图片和视频 → 模拟器的照片图库"
        case .files: return "所有内容 → 文件 App / 我的 iPhone 或 iPad / SimVoya"
        }
    }
    func usesPhotos(_ url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        // Common types also work when LaunchServices has not initialized its type database.
        let knownMedia: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "gif", "tif", "tiff", "bmp", "webp", "avif", "mov", "mp4", "m4v", "3gp", "avi"]
        let media = knownMedia.contains(url.pathExtension.lowercased()) || (UTType(filenameExtension: url.pathExtension).map { $0.conforms(to: .image) || $0.conforms(to: .movie) } ?? false)
        if self == .photos {
            guard values.isDirectory != true, media else { throw AppError("照片模式仅支持图片和视频；其他内容请选择「文件」模式。") }
            return true
        }
        return self == .automatic && values.isDirectory != true && media
    }
}
struct AppError: LocalizedError, Sendable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
struct ImportReceipt: Sendable {
    let message: String
    let detail: String
    let destination: URL?
}
struct ImportRecord: Identifiable {
    let id = UUID()
    let name: String
    let device: String
    var receipt: ImportReceipt?
    var error: String?
    var finished: Bool { receipt != nil || error != nil }
}
