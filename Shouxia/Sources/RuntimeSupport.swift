import Foundation

/// Called only while downloads, cookie writes and engine updates are excluded by Store.
enum RuntimeSupport {
    private static let docker = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/docker").path
    private static var journalURL: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Shouxia/network-transaction.json") }
    static var recoveryRequired: Bool { FileManager.default.fileExists(atPath:journalURL.path) }
    private struct Journal: Codable { let original: String; let backup: String; let snapshot: String; let token: String }
    private static func fail(_ text: String) -> AppError { .message(text) }

    static func creationPayload(_ inspect: [String: Any], snapshot: String) throws -> [String: Any] {
        guard inspect["Name"] as? String == "/metube", var config = inspect["Config"] as? [String: Any],
              let host = inspect["HostConfig"] as? [String: Any], host["AutoRemove"] as? Bool != true,
              host["PublishAllPorts"] as? Bool != true,
              ((host["RestartPolicy"] as? [String:Any])?["Name"] as? String) != "always",
              ["default", "bridge"].contains(host["NetworkMode"] as? String ?? ""),
              (host["Links"] as? [Any] ?? []).isEmpty,
              (host["VolumesFrom"] as? [Any] ?? []).isEmpty,
              let bindings = host["PortBindings"] as? [String: [[String: Any]]], bindings.count == 1,
              let port = bindings["8081/tcp"], port.count == 1,
              port[0]["HostIp"] as? String == "127.0.0.1", port[0]["HostPort"] as? String == "8081",
              let mounts = inspect["Mounts"] as? [[String: Any]], mounts.allSatisfy({ $0["Type"] as? String == "bind" }) else {
            throw fail("后台运行配置不支持安全迁移；现有容器已保留")
        }
        if let settings = inspect["NetworkSettings"] as? [String: Any],
           let networks = settings["Networks"] as? [String: Any],
           Set(networks.keys) != Set(["bridge"]) {
            throw fail("后台连接了额外网络，无法安全迁移")
        }
        // Bind mounts are fully retained in HostConfig. Anonymous/named volumes are
        // deliberately rejected, as image VOLUME declarations can otherwise fork data.
        if let volumes = config["Volumes"] as? [String: Any], !volumes.isEmpty {
            let destinations = Set(mounts.compactMap { $0["Destination"] as? String })
            guard Set(volumes.keys).isSubset(of: destinations) else { throw fail("后台存在未绑定的数据卷，无法安全迁移") }
        }
        var env = config["Env"] as? [String] ?? []
        env.removeAll { $0.hasPrefix("ALLOW_YTDL_OPTIONS_OVERRIDES=") }
        env.append("ALLOW_YTDL_OPTIONS_OVERRIDES=true")
        config["Env"] = env; config["Image"] = snapshot; config["HostConfig"] = host
        return config
    }
    static func validateExposure(_ inspect:[String:Any]) throws {
        guard let settings=inspect["NetworkSettings"] as? [String:Any],let ports=settings["Ports"] as? [String:Any] else {throw fail("无法验证后台监听端口")}
        let published=ports.filter { ($0.value as? [Any])?.isEmpty == false }
        guard published.count==1,let bindings=published["8081/tcp"] as? [[String:String]],bindings.count==1,
              bindings[0]["HostIp"]=="127.0.0.1",bindings[0]["HostPort"]=="8081" else {throw fail("后台端口不是仅本机监听，配置已停止")}
    }
    static func recoveryCommands(original:[String:Any]?,current:[String:Any]?,originalID:String,backupName:String,token:String) throws -> [[String]] {
        // Validate the recoverable original before planning any removal of the replacement.
        guard let original,original["Id"] as? String==originalID,
              let name=original["Name"] as? String,["/metube","/"+backupName].contains(name) else {throw fail("原后台不存在或身份变化，保留现有容器并停止恢复")}
        var commands=[[String]]()
        if let current,current["Id"] as? String != originalID {
            let labels=(current["Config"] as? [String:Any])?["Labels"] as? [String:String]
            guard labels?["com.shouxia.network-transaction"]==token,let id=current["Id"] as? String else {throw fail("后台身份变化，恢复已停止")}
            commands.append(["rm","--force",id])
        }
        if name != "/metube" {commands.append(["rename",originalID,"metube"])}
        commands.append(["start",originalID])
        return commands
    }
    private static func command(_ args: [String], timeout: TimeInterval = 30) async throws -> Data {
        try await raw(docker, ["--context", "colima-metube"] + args, timeout: timeout)
    }
    /// File-backed output avoids deadlocks and the small maintenance runner's truncation.
    static func raw(_ executable: String, _ args: [String], timeout: TimeInterval) async throws -> Data {
        try await Task.detached {
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            FileManager.default.createFile(atPath:fileURL.path, contents:nil, attributes:[.posixPermissions:0o600])
            let handle = try FileHandle(forWritingTo:fileURL)
            defer { try? handle.close(); try? FileManager.default.removeItem(at:fileURL) }
            let process = Process(); process.executableURL = URL(fileURLWithPath:executable); process.arguments = args
            process.standardOutput = handle; process.standardError = FileHandle.nullDevice
            try process.run()
            let deadline = Date().addingTimeInterval(timeout)
            do {
                while process.isRunning && Date() < deadline { try await Task.sleep(for:.milliseconds(100)) }
                if process.isRunning { throw fail("后台维护超时") }
            } catch {
                if process.isRunning { process.terminate(); try? await Task.sleep(for:.milliseconds(300)); if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
                throw error
            }
            guard process.terminationStatus == 0 else { throw fail("后台维护命令失败；现有备份已保留") }
            let data = try Data(contentsOf:fileURL)
            guard data.count < 8 * 1024 * 1024 else { throw fail("后台配置过大") }
            return data
        }.value
    }
    private static func inspect(_ name: String) async throws -> [String: Any] {
        guard let value = (try JSONSerialization.jsonObject(with: await command(["inspect", name]))) as? [[String: Any]], let first = value.first else { throw fail("无法读取后台配置") }
        return first
    }
    static func networkEnabled() async throws -> Bool {
        let value = try await inspect("metube")
        try validateExposure(value)
        return ((value["Config"] as? [String: Any])?["Env"] as? [String] ?? []).contains("ALLOW_YTDL_OPTIONS_OVERRIDES=true")
    }
    static func validateCookieMount() async throws {
        let value=try await inspect("metube")
        try validateExposure(value)
        guard let mounts=value["Mounts"] as? [[String:Any]],
              let mount=mounts.first(where:{$0["Destination"] as? String == "/downloads"}),
              mount["Type"] as? String == "bind",mount["RW"] as? Bool == true,
              let source=mount["Source"] as? String,
              URL(fileURLWithPath:source).standardizedFileURL.path == SafeDownloadPath.root.standardizedFileURL.path else {throw fail("Cookie 同步需要本机下载目录的可写绑定；请检查后台配置。")}
    }
    private static func healthy() async -> Bool { (try? await Backend().history()) != nil }
    private static func waitHealthy() async throws {
        for _ in 0..<30 { if await healthy() { return }; try await Task.sleep(for:.seconds(1)) }
        throw fail("后台重启后未恢复连接")
    }
    private static func save(_ journal: Journal) throws {
        try FileManager.default.createDirectory(at:journalURL.deletingLastPathComponent(), withIntermediateDirectories:true)
        try JSONEncoder().encode(journal).write(to:journalURL, options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600], ofItemAtPath:journalURL.path)
    }
    static func enableNetworkOptions() async throws {
        try await recoverIfNeeded()
        if try await networkEnabled() { return }
        let original = try await inspect("metube")
        _ = try creationPayload(original, snapshot:"validation")
        guard let id = original["Id"] as? String else { throw fail("后台身份无法验证") }
        let token = UUID().uuidString.lowercased()
        let journal = Journal(original:id, backup:"metube-shouxia-backup-" + token, snapshot:"shouxia-metube-network:" + token, token:token)
        // Resolve socket before any mutation. Only a local Unix Docker context is supported.
        let context = try await command(["context", "inspect", "colima-metube"])
        guard let contexts = try JSONSerialization.jsonObject(with:context) as? [[String:Any]],
              let endpoints = contexts.first?["Endpoints"] as? [String:Any], let endpoint = endpoints["docker"] as? [String:Any],
              let host = endpoint["Host"] as? String, host.hasPrefix("unix://") else { throw fail("后台不是本机 Docker，无法安全迁移") }
        try save(journal)
        do {
            _ = try await command(["stop", "--time", "20", id], timeout:40)
            _ = try await command(["commit", id, journal.snapshot], timeout:90)
            var payload = try creationPayload(original, snapshot:journal.snapshot)
            var labels = payload["Labels"] as? [String:String] ?? [:]; labels["com.shouxia.network-transaction"] = token; payload["Labels"] = labels
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            FileManager.default.createFile(atPath:file.path, contents:try JSONSerialization.data(withJSONObject:payload), attributes:[.posixPermissions:0o600])
            defer { try? FileManager.default.removeItem(at:file) }
            _ = try await command(["rename", id, journal.backup])
            _ = try await raw("/usr/bin/curl", ["--silent", "--show-error", "--fail", "--max-time", "30", "--unix-socket", String(host.dropFirst(7)), "-H", "Content-Type: application/json", "--data-binary", "@" + file.path, "http://localhost/containers/create?name=metube"], timeout:35)
            _ = try await command(["start", "metube"], timeout:40)
            try validateExposure(await inspect("metube"))
            try await waitHealthy()
            guard try await networkEnabled() else { throw fail("网络参数开关验证失败") }
            try FileManager.default.removeItem(at:journalURL)
        } catch {
            do { try await rollback(journal) } catch { throw fail("后台迁移恢复尚未完成；请保留备份并重试恢复") }
            throw error
        }
    }
    private static func rollback(_ journal: Journal) async throws {
        let original = try await inspect(journal.original)
        let current=try? await inspect("metube")
        for args in try recoveryCommands(original:original,current:current,originalID:journal.original,backupName:journal.backup,token:journal.token) {
            _ = try await command(args,timeout:40)
        }
        try await waitHealthy()
        try FileManager.default.removeItem(at:journalURL)
    }
    static func recoverIfNeeded() async throws {
        guard FileManager.default.fileExists(atPath:journalURL.path) else { return }
        let journal = try JSONDecoder().decode(Journal.self, from:Data(contentsOf:journalURL))
        if let current = try? await inspect("metube"), let config = current["Config"] as? [String:Any],
           (config["Labels"] as? [String:String])?["com.shouxia.network-transaction"] == journal.token,
           (config["Env"] as? [String] ?? []).contains("ALLOW_YTDL_OPTIONS_OVERRIDES=true"),
           (try? validateExposure(current)) != nil,await healthy() {
            try FileManager.default.removeItem(at:journalURL)
        } else { try await rollback(journal) }
    }
    static func diagnostics() async throws -> String {
        let fm = FileManager.default
        var lines = ["Docker：" + (fm.isExecutableFile(atPath:docker) ? "已安装" : "未找到")]
        let colima = fm.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/colima").path
        lines.append("Colima：" + (fm.isExecutableFile(atPath:colima) || fm.isExecutableFile(atPath:"/opt/homebrew/bin/colima") ? "已安装" : "未找到"))
        let script = "import json,subprocess,shutil; names=['ffmpeg','ffprobe','node','deno','python3']; out={n:(subprocess.run([n,'--version'] if n not in ['ffmpeg','ffprobe'] else [n,'-version'],capture_output=True,text=True,timeout=5).stdout.splitlines() or ['已安装'])[0][:180] if shutil.which(n) else '未安装' for n in names}; import yt_dlp.version; out['yt-dlp']=yt_dlp.version.__version__; print(json.dumps(out))"
        do {
            let data = try await command(["exec", "metube", "python3", "-c", script], timeout:40)
            if let versions = try JSONSerialization.jsonObject(with:data) as? [String:String] { for name in versions.keys.sorted() { lines.append(name + "：" + (versions[name] ?? "未知")) } }
            lines.append("网络参数：" + ((try await networkEnabled()) ? "已启用" : "尚未启用"))
        } catch { lines.append("后台依赖：无法连接，请确认本机服务已启动") }
        return lines.joined(separator:"\n")
    }
}
