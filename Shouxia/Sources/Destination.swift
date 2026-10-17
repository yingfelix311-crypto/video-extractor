import Foundation

enum ExportFiles {
    static func copy(_ source: URL, into directory: URL) throws -> URL {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw AppError.message("保存文件夹不存在，请重新选择。")
        }
        let source = source.resolvingSymlinksInPath().standardizedFileURL
        let directory = directory.resolvingSymlinksInPath().standardizedFileURL
        if source.deletingLastPathComponent() == directory { return source }
        let temporary = directory.appendingPathComponent(".video-extractor-\(UUID().uuidString).tmp")
        defer { try? fm.removeItem(at: temporary) }
        // Avoid APFS clonefile: Docker-shared files can stall in clonefileat.
        // Stream into our private temporary file, then rename only when complete.
        guard fm.createFile(atPath: temporary.path, contents: nil) else { throw AppError.message("无法写入保存文件夹。") }
        let reader = try FileHandle(forReadingFrom: source)
        let writer = try FileHandle(forWritingTo: temporary)
        do {
            while let bytes = try reader.read(upToCount: 4 * 1024 * 1024), !bytes.isEmpty { try writer.write(contentsOf: bytes) }
            try writer.synchronize()
            try reader.close(); try writer.close()
        } catch {
            try? reader.close(); try? writer.close(); throw error
        }
        let ext = source.pathExtension
        let stem = source.deletingPathExtension().lastPathComponent
        for index in 0..<10000 {
            let name = index == 0 ? source.lastPathComponent : "\(stem) (\(index))" + (ext.isEmpty ? "" : ".\(ext)")
            let target = directory.appendingPathComponent(name)
            if fm.fileExists(atPath: target.path) { continue }
            do { try fm.moveItem(at: temporary, to: target); return target }
            catch { if fm.fileExists(atPath: target.path) { continue }; throw error }
        }
        throw AppError.message("同名文件太多，请选择其他文件夹。")
    }
}

struct ExportRecord: Codable {
    var destination: String
    var exportedPath: String?
    var generation: String? = UUID().uuidString
    var originalURL: String?
    var canonicalURL: String?
    var quality: String?
    var audioOnly: Bool?
    var options: DownloadOptions?
}

enum ExportRegistry {
    private static let key = "videoExtractorExportsV1"
    static var records: [String: ExportRecord] {
        get {
            guard let data = UserDefaults.standard.data(forKey: key) else { return [:] }
            return (try? JSONDecoder().decode([String: ExportRecord].self, from: data)) ?? [:]
        }
        set { if let data = try? JSONEncoder().encode(newValue) { UserDefaults.standard.set(data, forKey: key) } }
    }
    static func recordKey(for url: String, folder: String?) -> String {
        folder.flatMap { records[$0] != nil ? $0 : nil } ?? url
    }
    static func file(for url: String, folder: String? = nil) -> URL? {
        guard let path = (folder.flatMap { records[$0] } ?? records[url])?.exportedPath, FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }
}
