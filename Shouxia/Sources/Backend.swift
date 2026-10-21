import Foundation

enum LocalRuntimeExecutable {
    static func resolve(_ name:String, home:URL=FileManager.default.homeDirectoryForCurrentUser, searchDirectories:[URL]?=nil) throws -> String {
        guard ["docker","colima"].contains(name) else { throw AppError.message("不支持的后台程序：\(name)") }
        let directories=[home.appendingPathComponent(".local/bin")] + (searchDirectories ?? [URL(fileURLWithPath:"/opt/homebrew/bin"),URL(fileURLWithPath:"/usr/local/bin")])
        for directory in directories {
            let path=directory.appendingPathComponent(name).path
            var isDirectory:ObjCBool=false
            if FileManager.default.fileExists(atPath:path,isDirectory:&isDirectory), !isDirectory.boolValue, FileManager.default.isExecutableFile(atPath:path) { return path }
        }
        throw AppError.message("未找到可执行的 \(name)；请检查本机后台依赖安装。")
    }
}

protocol BackendServing: Sendable {
    func history() async throws -> History
    func post(_ route: String, body: Data) async throws
    func cookieStatus() async throws -> Bool
    func uploadCookies(_ data: Data) async throws
    func deleteCookies() async throws
    func cancelAdd() async throws
    func version() async throws -> BackendVersion
}

protocol BackendPreparing: Sendable {
    var usesInstaller: Bool { get }
    func prepare(progress: @escaping @Sendable (String) async -> Void) async throws
}

struct LocalBackendPreparation: BackendPreparing {
    var usesInstaller: Bool { Backend.hasBundledInstaller }
    func prepare(progress: @escaping @Sendable (String) async -> Void) async throws {
        try await Backend.ensureService(progress: progress)
    }
}

struct BackendVersion: Decodable, Sendable {
    let version: String
    let engine: String
    enum CodingKeys: String, CodingKey { case version; case engine = "yt-dlp" }
}

enum CookieFile {
    static func validate(_ data: Data) throws {
        guard !data.isEmpty, data.count <= 1_000_000 else { throw AppError.message("Cookie 文件为空或超过 1 MB，请重新导出。") }
        guard let text = String(data: data, encoding: .utf8),
              text.hasPrefix("# Netscape HTTP Cookie File") || text.hasPrefix("# HTTP Cookie File") else {
            throw AppError.message("请选择 Netscape 格式的 cookies.txt 文件，不支持 JSON 或网页文件。")
        }
        var count = 0
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            if line.hasPrefix("#") && !line.hasPrefix("#HttpOnly_") { continue }
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 7, !fields[0].isEmpty, ["TRUE", "FALSE"].contains(String(fields[1])),
                  fields[2].hasPrefix("/"), ["TRUE", "FALSE"].contains(String(fields[3])),
                  Int64(fields[4]) != nil, (!fields[5].isEmpty || !fields[6].isEmpty) else {
                throw AppError.message("Cookie 文件内容不完整，请按 Netscape 格式重新导出。")
            }
            count += 1
        }
        guard count > 0 else { throw AppError.message("Cookie 文件没有可导入的条目。") }
    }
}

struct Backend: BackendServing, Sendable {
    private let base: URL
    private let session: URLSession
    init(baseURL: URL = URL(string: "http://127.0.0.1:8081")!, session: URLSession? = nil) {
        base = baseURL
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 90
        self.session = session ?? URLSession(configuration: config)
    }
    func history() async throws -> History {
        try JSONDecoder().decode(History.self, from: await request("history"))
    }
    func post(_ route: String, body: Data) async throws {
        try APIResult.validate(await request(route, body: body))
    }
    func version() async throws -> BackendVersion {
        try JSONDecoder().decode(BackendVersion.self, from: await request("version"))
    }
    func cookieStatus() async throws -> Bool {
        struct Status: Decodable { let has_cookies: Bool }
        return try JSONDecoder().decode(Status.self, from: await request("cookie-status")).has_cookies
    }
    func uploadCookies(_ data: Data) async throws {
        try CookieFile.validate(data)
        let boundary = "VideoExtractor-" + UUID().uuidString
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"cookies\"; filename=\"cookies.txt\"\r\nContent-Type: text/plain\r\n\r\n".utf8)
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        try APIResult.validate(await request("upload-cookies", body: body, contentType: "multipart/form-data; boundary=\(boundary)"))
    }
    func deleteCookies() async throws { try await post("delete-cookies", body: Data("{}".utf8)) }
    func cancelAdd() async throws { try await post("cancel-add", body: Data("{}".utf8)) }

    private func request(_ route: String, body: Data? = nil, contentType: String = "application/json") async throws -> Data {
        var request = URLRequest(url: base.appendingPathComponent(route), cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        request.timeoutInterval = body == nil ? 5 : 90
        if body != nil { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw UnconfirmedBackendResponse(message: "下载服务未返回有效 HTTP 响应，请先核对任务状态。")
        }
        guard (200..<300).contains(response.statusCode) else {
            if let result = try? JSONDecoder().decode(APIResult.self, from: data), result.status == "error" {
                throw AppError.message(result.msg ?? "下载服务未能完成操作。")
            }
            throw UnconfirmedBackendResponse(message: "下载服务返回 HTTP \(response.statusCode)，请先核对任务状态。")
        }
        return data
    }
    static func boot() async throws {
        try await ensureService()
    }
    static var installerURL: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("BackendInstaller/安装原版.command")
    }
    static var hasBundledInstaller: Bool {
        installerURL.map { FileManager.default.isExecutableFile(atPath: $0.path) || FileManager.default.fileExists(atPath: $0.path) } ?? false
    }
    /// A copied app must be able to finish first-run setup without a separate terminal installer.
    static func ensureService(progress: @escaping @Sendable (String) async -> Void = { _ in }) async throws {
        if let installer = installerURL, hasBundledInstaller {
            await progress("正在检查下载环境")
            do {
                try await run(executable: "/bin/bash", arguments: [installer.path, "--check"], timeout: 60)
                return
            } catch is CancellationError { throw CancellationError() }
            catch { log("Backend setup/check: \(error.localizedDescription)") }
            try await run(executable: "/bin/bash", arguments: [installer.path, "--backend-only"], timeout: 1200, progress: progress)
        } else {
            await progress("正在启动下载服务")
            try await startVirtualMachine()
            try await startContainer()
        }
    }
    static func startVirtualMachine() async throws {
        try await run(executable: LocalRuntimeExecutable.resolve("colima"), arguments: ["start", "--profile", "metube"], timeout: 180)
    }
    static func startContainer() async throws {
        try await run(executable: LocalRuntimeExecutable.resolve("docker"), arguments: ["--context", "colima-metube", "start", "metube"], timeout: 10)
    }
    static func setupFailure(_ output: String, timedOut: Bool = false) -> String {
        if timedOut { return "准备下载服务超时；检查网络后点“重新连接”继续，已下载的组件会保留。" }
        if let reason = output.components(separatedBy: .newlines).first(where: { $0.hasPrefix("安装停止：") }) { return reason }
        if output.contains("Virtualization is not available") { return "系统未允许启动虚拟机。请在本机正常打开应用后重试，或查看后台日志。" }
        return "下载服务准备失败。请检查网络后重新连接；可在设置中打开后台日志查看原因。"
    }
    static func setupProgress(_ output: String) -> String? {
        output.components(separatedBy: .newlines).last(where: { $0.hasPrefix("进度：") }).map { String($0.dropFirst(3)) }
    }
    private static func run(executable: String, arguments: [String], timeout: TimeInterval,
                            progress: @escaping @Sendable (String) async -> Void = { _ in }) async throws {
        let task = Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = FileManager.default.homeDirectoryForCurrentUser.path + "/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            process.environment = env
            let logURL = Backend.logURL
            if !FileManager.default.fileExists(atPath: logURL.path) { FileManager.default.createFile(atPath: logURL.path, contents: nil) }
            let output = try FileHandle(forWritingTo: logURL)
            defer { try? output.close() }
            try output.seekToEnd()
            let startOffset = try output.offset()
            process.standardOutput = output
            process.standardError = output
            try process.run()
            defer {
                if process.isRunning { process.terminate() }
            }
            let deadline = Date().addingTimeInterval(timeout)
            let reader = try FileHandle(forReadingFrom: logURL)
            defer { try? reader.close() }
            try reader.seek(toOffset: startOffset)
            var captured = Data()
            var lastProgress: String?
            func readOutput() throws -> String {
                captured.append(try reader.readToEnd() ?? Data())
                if captured.count > 128 * 1024 { captured = Data(captured.suffix(128 * 1024)) }
                return String(decoding: captured, as: UTF8.self)
            }
            do {
                while process.isRunning && Date() < deadline {
                    try Task.checkCancellation()
                    if let text = setupProgress(try readOutput()), text != lastProgress {
                        lastProgress = text
                        await progress(text)
                    }
                    try await Task.sleep(for: .milliseconds(500))
                }
            } catch {
                process.terminate()
                try? await Task.sleep(for: .milliseconds(500))
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                throw error
            }
            if process.isRunning {
                process.terminate()
                // Bound the wait even if a subprocess ignores SIGTERM.
                try await Task.sleep(for: .milliseconds(500))
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                throw AppError.message(setupFailure(try readOutput(), timedOut: true))
            }
            guard process.terminationStatus == 0 else { throw AppError.message(setupFailure(try readOutput())) }
        }
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
    static var logURL: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Shouxia")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("backend.log")
    }
    static func log(_ text: String) {
        let url = logURL
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        if let file = try? FileHandle(forWritingTo: url) {
            defer { try? file.close() }
            _ = try? file.seekToEnd()
            try? file.write(contentsOf: Data("\(Date()): \(text)\n".utf8))
        }
    }
}
