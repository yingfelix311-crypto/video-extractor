import Foundation

enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

/// The response does not establish whether a mutating request was accepted.
struct UnconfirmedBackendResponse: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct DownloadItem: Codable, Identifiable, Sendable {
    let mediaID: String
    // Only this app's UUID folder namespace identifies one local occurrence.
    // Legacy backend folders can be empty or shared by unrelated URLs.
    var id: String {
        if let folder, folder.hasPrefix("VideoExtractor/"),
           UUID(uuidString: String(folder.dropFirst("VideoExtractor/".count))) != nil {
            return "task:" + folder
        }
        let components = [url, folder ?? "", mediaID, downloadType ?? format ?? "", filename ?? ""]
        return "legacy:" + components.map { "\($0.utf8.count):\($0)" }.joined()
    }
    var archived: Bool? = nil
    var isArchived: Bool { archived == true }
    enum CodingKeys: String, CodingKey {
        case mediaID = "id"
        case downloadType = "download_type"
        case format
        case storedOverrides = "ytdl_options_overrides"
        case archived
        case title, url, status, percent, speed, eta, size, filename, folder, error, msg, quality
    }
    let downloadType: String?
    let format: String?
    private let storedOverrides: StoredNetworkOverrides?
    var ytdlOptionsOverrides: [String:String]? { storedOverrides?.values }
    let title: String
    let url: String
    let status: String
    let percent: Double?
    let speed: Double?
    let eta: Double?
    let size: Double?
    let filename: String?
    let folder: String?
    let error: String?
    let msg: String?
    let quality: String?
    var isAudio: Bool {
        if let type = downloadType?.lowercased(), ["audio", "video"].contains(type) { return type == "audio" }
        let audioFormats = ["mp3", "m4a", "aac", "wav", "flac", "opus", "ogg", "oga", "alac", "aiff"]
        if let format, audioFormats.contains(format.lowercased()) { return true }
        return audioFormats.contains(URL(fileURLWithPath: filename ?? "").pathExtension.lowercased())
    }
    var isHistory: Bool { isComplete || isFailed }
    var isComplete: Bool { status == "finished" }
    var isFailed: Bool { status == "error" }
    var localFileURL: URL? {
        guard isComplete, let filename else { return nil }
        if let exported = ExportRegistry.file(for: url, folder: folder) { return exported }
        return SafeDownloadPath.resolve(filename: filename, folder: folder)
    }
    var platform: String {
        let host = URL(string: url)?.host?.lowercased() ?? ""
        if host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com") { return "YouTube" }
        if host == "douyin.com" || host.hasSuffix(".douyin.com") { return "抖音" }
        if host == "b23.tv" || host == "bilibili.com" || host.hasSuffix(".bilibili.com") { return "哔哩哔哩" }
        return host.replacingOccurrences(of: "www.", with: "")
    }
}

private struct StoredNetworkOverrides: Codable, Sendable {
    let values:[String:String]
    enum CodingKeys:String,CodingKey {case proxy,referer,user_agent}
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        for (key, value) in values { if let key = CodingKeys(rawValue: key) { try container.encode(value, forKey: key) } }
    }
    init(from decoder:Decoder)throws {
        let container=try decoder.container(keyedBy:CodingKeys.self)
        var known=[String:String]()
        for key in [CodingKeys.proxy,.referer,.user_agent] {
            if let value=try? container.decode(String.self,forKey:key) {known[key.rawValue]=value}
        }
        values=known
    }
}

struct History: Decodable, Sendable {
    let done: [DownloadItem]
    let queue: [DownloadItem]
    let pending: [DownloadItem]
}

struct ResolvedLink: Codable, Sendable {
    let originalURL: String
    let canonicalURL: String
    var wasNormalized: Bool { originalURL != canonicalURL }
}

enum LinkParser {
    static func extract(_ text: String) throws -> String { try resolve(text).canonicalURL }
    static func resolve(_ text: String) throws -> ResolvedLink {
        let regex = try NSRegularExpression(pattern: #"https?://[^\s<>\"“”]+"#, options: .caseInsensitive)
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard matches.count == 1, let range = Range(matches[0].range, in: text) else {
            throw AppError.message("请粘贴一个完整的 http 或 https 视频链接。")
        }
        let link = String(text[range]).trimmingCharacters(in: CharacterSet(charactersIn: "。，,！!？?；;）)]}"))
        guard let parts = URLComponents(string: link), let host = parts.host?.lowercased(),
              !host.isEmpty, parts.user == nil, parts.password == nil,
              let url = parts.url, url.host != nil else { throw AppError.message("链接格式不正确，请检查后重试。") }
        let h = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]."))
        let octets = h.split(separator: ".").compactMap { Int($0) }
        let privateIPv4 = octets.count == 4 && (octets[0] == 0 || octets[0] == 10 || octets[0] == 127 || octets[0] >= 224 || (octets[0] == 169 && octets[1] == 254) || (octets[0] == 172 && (16...31).contains(octets[1])) || (octets[0] == 192 && octets[1] == 168))
        guard h != "localhost", !h.hasSuffix(".localhost"), !h.hasSuffix(".local"), h.contains("."), !h.contains(":"), !privateIPv4 else {
            throw AppError.message("请使用公开视频网站链接，不能下载本机或局域网地址。")
        }
        var canonical = url.absoluteString
        if ["douyin.com", "www.douyin.com"].contains(host), ["", "/", "/jingxuan", "/jingxuan/"].contains(parts.path) {
            let ids = (parts.queryItems ?? []).filter { $0.name == "modal_id" }
            if !ids.isEmpty {
                guard ids.count == 1, let value = ids[0].value, (1...30).contains(value.count),
                      value.utf8.allSatisfy({ (48...57).contains($0) }) else {
                    throw AppError.message("抖音链接中的 modal_id 无效或重复，请复制单个视频的分享链接。")
                }
                canonical = "https://www.douyin.com/video/" + value
            }
        }
        return ResolvedLink(originalURL: link, canonicalURL: canonical)
    }
}

enum SafeDownloadPath {
    static var root: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/MeTube", isDirectory: true) }
    static func resolve(filename: String, folder: String?, root: URL = root) -> URL? {
        guard !filename.isEmpty, !filename.hasPrefix("/"), !(folder ?? "").hasPrefix("/") else { return nil }
        let base = root.resolvingSymlinksInPath().standardizedFileURL
        let target = base.appendingPathComponent(folder ?? "").appendingPathComponent(filename).resolvingSymlinksInPath().standardizedFileURL
        guard target.path.hasPrefix(base.path + "/"), FileManager.default.fileExists(atPath: target.path) else { return nil }
        return target
    }
}

struct APIResult: Decodable {
    let status: String
    let msg: String?
    static func validate(_ data: Data) throws {
        let result: APIResult
        do { result = try JSONDecoder().decode(APIResult.self, from: data) }
        catch { throw UnconfirmedBackendResponse(message: "下载服务响应格式不完整，请先核对任务状态。") }
        switch result.status {
        case "ok": return
        case "error": throw AppError.message(result.msg ?? "下载服务未能完成操作。")
        default: throw UnconfirmedBackendResponse(message: "下载服务返回未知状态，请先核对任务状态。")
        }
    }
}


enum DownloadRequest {
    static func body(url: String, quality: String, audioOnly: Bool, folder: String? = nil, options: DownloadOptions = DownloadOptions(), cookieFile: String? = nil) throws -> Data {
        let options = try options.validated()
        let isDirectMedia = ["mp4", "webm", "mov", "m4v"].contains(URL(string: url)?.pathExtension.lowercased() ?? "")
        try DownloadQuality.validate(quality)
        let selectedQuality = isDirectMedia ? "best" : quality
        var payload: [String: Any] = ["url": url, "download_type": audioOnly ? "audio" : "video", "quality": audioOnly ? "best" : selectedQuality, "codec": "auto", "format": audioOnly ? "mp3" : options.videoFormat, "auto_start": true, "playlist_item_limit": 1]
        if let folder { payload["folder"] = folder }
        var overrides=options.ytdlOverrides
        if let cookieFile {
            let prefix="/downloads/.video-extractor-sessions/"
            let components=String(cookieFile.dropFirst(prefix.count)).split(separator:"/",omittingEmptySubsequences:false)
            guard cookieFile.hasPrefix(prefix),components.count==2,UUID(uuidString:String(components[0])) != nil,components[1]=="cookies.txt" else {throw AppError.message("Cookie 任务路径无效。")}
            overrides["cookiefile"]=cookieFile
        }
        if !overrides.isEmpty { payload["ytdl_options_overrides"] = overrides }
        return try JSONSerialization.data(withJSONObject: payload)
    }
}


enum DownloadAction: CaseIterable { case cancel, retry, start, clear }

struct ActionRequest {
    let route: String
    let body: Data
    init(_ action: DownloadAction, item: DownloadItem) throws {
        let payload: [String: Any]
        switch action {
        case .cancel, .clear:
            route = "delete"
            payload = ["ids": [item.url], "where": action == .clear ? "done" : "queue", "delete_files": false]
        case .retry:
            route = "retry"
            payload = ["id": item.url]
        case .start:
            route = "start"
            payload = ["ids": [item.url]]
        }
        body = try JSONSerialization.data(withJSONObject: payload)
    }
}


enum TaskList {
    static func visible(active: [DownloadItem], pending: [DownloadItem], history: [DownloadItem], audioOnly: Bool? = nil, filter: String) -> [DownloadItem] {
        let candidates = filter == "进行中" ? active + pending : filter == "已完成" ? history.filter(\.isComplete) : filter == "失败" ? history.filter(\.isFailed) : active + pending + history
        var seen = Set<String>()
        return candidates.filter { (audioOnly == nil || $0.isAudio == audioOnly!) && seen.insert($0.id).inserted }
    }
}

enum HistoryRemoval {
    static func body(items: [DownloadItem]) throws -> Data {
        let ids = Array(Set(items.filter { $0.isHistory && !$0.isArchived }.map(\.url))).sorted()
        return try JSONSerialization.data(withJSONObject: ["ids": ids, "where": "done", "delete_files": false])
    }
}

/// Stores terminal snapshots locally before the URL-keyed backend replaces them.
/// Uses the same injected preferences store as submission recovery.
struct DownloadArchive {
    private let defaults: UserDefaults
    private let key = "downloadTerminalArchiveV1"
    init(defaults: UserDefaults) { self.defaults = defaults }
    var records: [DownloadItem] {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([DownloadItem].self, from: $0) } ?? []
    }
    func merge(_ terminal: [DownloadItem], current: [DownloadItem]) -> [DownloadItem] {
        var saved = records
        for item in terminal where item.isHistory {
            saved.removeAll { $0.id == item.id }
            saved.insert(item, at: 0)
        }
        persist(saved)
        let currentIDs = Set(current.map(\.id))
        return terminal.reversed() + saved.filter { !currentIDs.contains($0.id) }.map {
            var item = $0; item.archived = true; return item
        }
    }
    func remove(ids: Set<String>) { persist(records.filter { !ids.contains($0.id) }) }
    private func persist(_ records: [DownloadItem]) {
        if let data = try? JSONEncoder().encode(records) { defaults.set(data, forKey: key) }
    }
}
