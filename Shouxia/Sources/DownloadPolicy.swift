import Foundation

enum DownloadQuality {
    static let values = ["best", "2160", "1440", "1080", "720", "480"]
    static func label(for value: String) -> String {
        switch value {
        case "best": return "最佳画质"
        case "2160": return "4K · 2160p"
        case "1440": return "2K · 1440p"
        default: return value + "p"
        }
    }
    static func validate(_ value: String) throws {
        guard values.contains(value) else { throw AppError.message("请选择有效的清晰度。") }
    }
}

struct DownloadOptions: Codable, Equatable, Sendable {
    var videoFormat: String = "any"
    var proxy: String = ""
    var referer: String = ""
    var userAgent: String = ""

    func validated() throws -> DownloadOptions {
        var result = self
        guard ["any", "mp4"].contains(videoFormat) else { throw AppError.message("请选择原始最佳格式或兼容 MP4。") }
        guard ![proxy, referer, userAgent].contains(where: { $0.unicodeScalars.contains(where: { $0.value == 13 || $0.value == 10 }) }) else {
            throw AppError.message("网络参数不能包含换行。")
        }
        result.proxy = proxy.trimmingCharacters(in: .whitespaces)
        result.referer = referer.trimmingCharacters(in: .whitespaces)
        result.userAgent = userAgent.trimmingCharacters(in: .whitespaces)
        if !result.proxy.isEmpty {
            guard var parts = URLComponents(string: result.proxy), let scheme = parts.scheme?.lowercased(),
                  ["http", "https", "socks5", "socks5h"].contains(scheme), let host = parts.host, !host.isEmpty,
                  parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
                  parts.path.isEmpty || parts.path == "/", parts.url != nil,
                  parts.port == nil || (1...65535).contains(parts.port!) else {
                throw AppError.message("代理须为不含账号密码、查询参数或片段的 HTTP、HTTPS 或 SOCKS5 地址。")
            }
            if ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host.lowercased()) { parts.host = "host.lima.internal" }
            result.proxy = parts.string!
        }
        if !result.referer.isEmpty {
            let link = try LinkParser.resolve(result.referer)
            guard link.originalURL == result.referer else { throw AppError.message("Referer 必须是完整的公开 HTTP 或 HTTPS 地址。") }
            result.referer = link.originalURL
        }
        return result
    }

    var ytdlOverrides: [String: String] {
        var values: [String: String] = [:]
        if !proxy.isEmpty { values["proxy"] = proxy }
        if !referer.isEmpty { values["referer"] = referer }
        if !userAgent.isEmpty { values["user_agent"] = userAgent }
        return values
    }
}

struct DownloadFailure: Sendable, Equatable {
    enum Kind: String, Codable, Sendable { case unsupportedLink, cookies, network, format, permission, service, cancelled, unknown }
    let kind: Kind
    let title: String
    let message: String
    let actionTitle: String

    static func classify(_ raw: String) -> DownloadFailure {
        let text = raw.lowercased()
        func has(_ terms: [String]) -> Bool { terms.contains(where: text.contains) }
        if text.contains("启用后台自动同步支持") {return .init(kind:.cookies,title:"网站访问辅助尚未配置",message:"",actionTitle:"网站访问辅助")}
        if text.contains("启用并保存网络参数") {return .init(kind:.service,title:"网络设置尚未配置",message:"",actionTitle:"网络设置")}
        if has(["请粘贴一个完整", "链接格式不正确", "modal_id 无效"]) { return .init(kind:.unsupportedLink,title:"链接格式不正确",message:"",actionTitle:"检查链接") }
        if has(["本机或局域网地址"]) { return .init(kind:.unsupportedLink,title:"不支持本机或局域网链接",message:"",actionTitle:"检查链接") }
        if has(["已有任务正在处理"]) { return .init(kind:.unknown,title:"这个链接正在处理中",message:"",actionTitle:"查看任务") }
        if has(["正在连接，请稍后", "服务尚未连接"]) { return .init(kind:.service,title:"下载服务正在连接",message:"",actionTitle:"重新连接") }
        if has(["后台设置正在保存", "后台正在配置", "后台恢复尚未完成"]) { return .init(kind:.service,title:"后台正在准备，请稍后重试",message:"",actionTitle:"重试") }
        if has(["引擎正在更新"]) { return .init(kind:.service,title:"下载引擎正在更新",message:"",actionTitle:"稍后重试") }
        if has(["未决任务", "尚未确认任务", "提交结果未确认"]) { return .init(kind:.unknown,title:"提交结果待确认，请先核对任务",message:"",actionTitle:"核对任务") }
        if has(["cancelled", "canceled", "取消"]) { return .init(kind: .cancelled, title: "下载已取消", message: "确认链接和参数后可重新提交。", actionTitle: "重试") }
        if has(["unsupported url", "unsupported link", "不支持的链接"]) { return .init(kind: .unsupportedLink, title: "链接暂不受支持", message: "请复制单个视频的分享链接，或更新下载引擎。", actionTitle: "检查链接") }
        if text.contains("无法读取 safari cookie"),text.contains("完全磁盘访问权限") {
            return .init(kind:.cookies,title:"Safari 访问权限不足",message:"macOS 尚未允许本应用读取 Safari Cookie。请为 Video Extractor 开启完全磁盘访问权限，退出并重新打开软件后重试。",actionTitle:"管理 Cookie")
        }
        if text.contains("fresh cookies") {
            return .init(kind:.unknown,title:"暂时无法解析这个视频",message:"",actionTitle:"重试")
        }
        if has(["浏览器 cookie", "浏览器配置", "浏览器会话", "本机网站会话", "会话存储", "钥匙串"]) || (text.contains("无法读取") && text.contains("cookie")) { return .init(kind:.cookies,title:"浏览器信息读取失败",message:"",actionTitle:"网站访问辅助") }
        if has(["sign in", "login required", "log in", "需要登录", "请登录", "登录后"]) { return .init(kind:.cookies,title:"网站要求登录后访问",message:"",actionTitle:"网站访问辅助") }
        if has(["cookie", "网站会话"]) { return .init(kind:.cookies,title:"网站暂时无法访问",message:"",actionTitle:"网站访问辅助") }
        if has(["http error 404", "404: not found", "status code 404", "http error 410", "410: gone", "status code 410"]) { return .init(kind:.unsupportedLink,title:"视频不存在或已删除",message:"请检查原始链接是否仍可访问。",actionTitle:"检查链接") }
        if has(["no video formats", "no formats found", "no formats available"]) { return .init(kind:.format,title:"网站未返回可下载的视频",message:"可稍后重试或更新下载引擎。",actionTitle:"重试") }
        if has(["requested format", "format is not available", "格式不可用"]) { return .init(kind: .format, title: "所选格式不可用", message: "尝试原始最佳格式或降低清晰度。", actionTitle: "调整参数") }
        if has(["permission denied", "operation not permitted", "read-only file", "权限"]) { return .init(kind: .permission, title: "无法写入文件", message: "请重新选择可写入的保存目录。", actionTitle: "选择目录") }
        if has(["127.0.0.1:8081", "localhost:8081", "下载服务", "backend offline", "backend is offline", "metube offline", "metube is offline"]) { return .init(kind: .service, title: "下载服务不可用", message: "请检查设置中的后台依赖和服务状态。", actionTitle: "检查服务") }
        if has(["http error 403", "403: forbidden", "status code 403"]) { return .init(kind:.network,title:"网站暂时拒绝访问",message:"",actionTitle:"重试") }
        if has(["service unavailable", "403", "forbidden", "timed out", "timeout", "network", "proxy", "connection", "http error", "dns", "certificate"]) { return .init(kind: .network, title: "网络请求失败", message: "请检查网络、代理或请求头设置后重试。", actionTitle: "网络设置") }
        return .init(kind: .unknown, title: "暂时无法解析这个视频", message: "", actionTitle: "重试")
    }
}
