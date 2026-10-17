import Foundation

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
        if has(["cancelled", "canceled", "取消"]) { return .init(kind: .cancelled, title: "下载已取消", message: "确认链接和参数后可重新提交。", actionTitle: "重试") }
        if has(["unsupported url", "unsupported link", "不支持的链接"]) { return .init(kind: .unsupportedLink, title: "链接暂不受支持", message: "请复制单个视频的分享链接，或更新下载引擎。", actionTitle: "检查链接") }
        if has(["cookie", "sign in", "login required", "log in", "登录"]) { return .init(kind: .cookies, title: "需要有效 Cookie", message: "请在设置中导入你自己的 Netscape Cookie 文件，再重试。", actionTitle: "管理 Cookie") }
        if has(["requested format", "format is not available", "no video formats", "格式不可用"]) { return .init(kind: .format, title: "所选格式不可用", message: "尝试原始最佳格式或降低清晰度。", actionTitle: "调整参数") }
        if has(["permission denied", "operation not permitted", "read-only file", "权限"]) { return .init(kind: .permission, title: "无法写入文件", message: "请重新选择可写入的保存目录。", actionTitle: "选择目录") }
        if has(["127.0.0.1:8081", "localhost:8081", "下载服务", "backend offline", "backend is offline", "metube offline", "metube is offline"]) { return .init(kind: .service, title: "下载服务不可用", message: "请检查设置中的后台依赖和服务状态。", actionTitle: "检查服务") }
        if has(["service unavailable", "403", "forbidden", "timed out", "timeout", "network", "proxy", "connection", "http error", "dns", "certificate"]) { return .init(kind: .network, title: "网络请求失败", message: "请检查网络、代理或请求头设置后重试。", actionTitle: "网络设置") }
        return .init(kind: .unknown, title: "下载失败", message: "查看原始错误，确认链接与参数后重试。", actionTitle: "重试")
    }
}
