import Foundation

@main struct StoreTests {
    @MainActor static func main() async throws {
        let fm = FileManager.default
        let folder = "VideoExtractor/test-" + UUID().uuidString
        let sourceDir = SafeDownloadPath.root.appendingPathComponent(folder)
        let target = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: sourceDir); try? fm.removeItem(at: target) }
        let source = sourceDir.appendingPathComponent("test.mp4")
        try Data("video-bytes".utf8).write(to: source)
        let data = try JSONSerialization.data(withJSONObject: ["id": "test", "title": "Test", "url": "https://example.com/test", "status": "finished", "folder": folder, "filename": "test.mp4"])
        let item = try JSONDecoder().decode(DownloadItem.self, from: data)
        let store = DownloadStore()
        store.completed = [item]
        ExportRegistry.records = [folder: ExportRecord(destination: target.appendingPathComponent("missing").path)]
        store.exportErrors[folder] = "保存文件夹不存在"
        var failures = [String]()
        if !store.canRemoveHistory(item) { failures.append("failed exports must allow history removal") }
        store.destinationPath = target.path
        await store.retryExport(item)
        if ExportRegistry.records[folder]?.destination != target.path { failures.append("retry must adopt current destination") }
        if ExportRegistry.records[folder]?.exportedPath == nil { failures.append("retry must save successfully to current destination") }
        if store.exportErrors[folder] != nil { failures.append("successful retry must clear error") }
        if (try? Data(contentsOf: target.appendingPathComponent("test.mp4"))) != Data("video-bytes".utf8) { failures.append("exported bytes must match") }
        precondition(fm.fileExists(atPath: source.path), "source retained")
        // Repeated retries must not duplicate an already exported file.
        await store.retryExport(item)
        if fm.fileExists(atPath: target.appendingPathComponent("test (1).mp4").path) { failures.append("repeated retry must not duplicate export") }
        ExportRegistry.records = [folder: ExportRecord(destination: target.path)]
        store.destinationPath = target.appendingPathComponent("missing").path
        await store.retryExport(item)
        if store.exportErrors[folder]?.contains("保存文件夹不存在") != true { failures.append("missing destination must explain the cause") }
        if store.exportErrors[folder]?.contains(store.destinationPath) != true { failures.append("error must identify the failed destination") }
        if !store.canRemoveHistory(item) { failures.append("a new save error must not block removal") }
        try fm.removeItem(at: source)
        store.destinationPath = target.path
        await store.retryExport(item)
        if store.exportErrors[folder]?.contains("找不到下载缓存文件") != true { failures.append("missing source must explain recovery") }
        ExportRegistry.records = [:]
        if !failures.isEmpty { print("FAIL: " + failures.joined(separator: "; ")); exit(1) }
        print("PASS: failed history removal and retry to current destination")
    }
}
