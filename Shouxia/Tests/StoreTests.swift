import Foundation

actor SetupFixture: BackendPreparing {
    nonisolated var usesInstaller: Bool { true }
    var attempts = 0
    var failNext = true
    func prepare(progress: @escaping @Sendable (String) async -> Void) async throws {
        attempts += 1
        await progress("正在下载测试后台")
        if failNext { failNext = false; throw AppError.message("安装停止：网络已中断") }
    }
}

actor HealthySetupBackend: BackendServing {
    var posts = 0
    func history() async throws -> History { History(done: [], queue: [], pending: []) }
    func post(_ route: String, body: Data) async throws { posts += 1 }
    func cookieStatus() async throws -> Bool { false }
    func uploadCookies(_ data: Data) async throws {}
    func deleteCookies() async throws {}
    func cancelAdd() async throws {}
    func version() async throws -> BackendVersion { BackendVersion(version: "fixture", engine: "fixture") }
}

@main struct StoreTests {
    @MainActor static func main() async throws {
        let setupDefaultsName = "VideoExtractor.SetupTests." + UUID().uuidString
        let setupDefaults = UserDefaults(suiteName: setupDefaultsName)!
        defer { setupDefaults.removePersistentDomain(forName: setupDefaultsName) }
        let setup = SetupFixture()
        let setupBackend = HealthySetupBackend()
        let firstLaunch = DownloadStore(backend: setupBackend, defaults: setupDefaults, preparation: setup)
        await firstLaunch.reconnect()
        precondition(firstLaunch.connection == .offline, "HTTP health alone must not bypass unfinished installation")
        precondition(firstLaunch.backendProgress == "正在下载测试后台", "first-run stage is visible")
        precondition(firstLaunch.message?.contains("网络已中断") == true, "setup failure retains its cause")
        await firstLaunch.refresh()
        precondition(firstLaunch.connection != .ready, "polling cannot turn a partial installation into ready")
        let accepted = await firstLaunch.submit("https://example.com/video", quality: "best", audioOnly: false)
        let postCount = await setupBackend.posts
        precondition(!accepted && postCount == 0, "unfinished setup must never submit a download")
        await firstLaunch.reconnect()
        let attempts = await setup.attempts
        precondition(firstLaunch.connection == .ready && attempts == 2, "reconnect resumes setup and only then becomes ready")
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
