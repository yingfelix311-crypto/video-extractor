import Foundation

protocol BackendServing: Sendable {
    func history() async throws -> History
    func post(_ route: String, body: Data) async throws
    func cookieStatus() async throws -> Bool
    func uploadCookies(_ data: Data) async throws
    func deleteCookies() async throws
    func cancelAdd() async throws
    func version() async throws -> BackendVersion
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
                  Int64(fields[4]) != nil, !fields[5].isEmpty else {
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
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            let message = (try? JSONDecoder().decode(APIResult.self, from: data))?.msg
            throw AppError.message(message ?? "下载服务返回错误：" + String(decoding: data.prefix(1000), as: UTF8.self))
        }
        return data
    }
    static func boot() async throws {
        try await startVirtualMachine()
        try await startContainer()
    }
    static func startVirtualMachine() async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        try await run(executable: home + "/.local/bin/colima", arguments: ["start", "--profile", "metube"], timeout: 75)
    }
    static func startContainer() async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        try await run(executable: home + "/.local/bin/docker", arguments: ["--context", "colima-metube", "start", "metube"], timeout: 10)
    }
    private static func run(executable: String, arguments: [String], timeout: TimeInterval) async throws {
        try await Task.detached(priority: .utility) {
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
            process.standardOutput = output
            process.standardError = output
            try process.run()
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline { try await Task.sleep(for: .milliseconds(200)) }
            if process.isRunning {
                process.terminate()
                // Bound the wait even if a subprocess ignores SIGTERM.
                try await Task.sleep(for: .milliseconds(500))
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                throw AppError.message("启动下载服务超时，请查看日志后重新连接。")
            }
            guard process.terminationStatus == 0 else { throw AppError.message("下载服务启动失败，请查看日志后重试。") }
        }.value
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
