import Foundation

struct Backend: Sendable {
    private let base = URL(string: "http://127.0.0.1:8081")!
    private let session: URLSession
    init() {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 90
        session = URLSession(configuration: config)
    }
    func history() async throws -> History {
        try JSONDecoder().decode(History.self, from: await request("history"))
    }
    func post(_ route: String, body: Data) async throws {
        try APIResult.validate(await request(route, body: body))
    }
    private func request(_ route: String, body: Data? = nil) async throws -> Data {
        var request = URLRequest(url: base.appendingPathComponent(route), cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        request.timeoutInterval = body == nil ? 5 : 90
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw AppError.message("下载服务返回错误：" + String(decoding: data.prefix(1000), as: UTF8.self))
        }
        return data
    }
    static func boot() async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        try await run(executable: home + "/.local/bin/colima", arguments: ["start", "--profile", "metube"], timeout: 75)
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
