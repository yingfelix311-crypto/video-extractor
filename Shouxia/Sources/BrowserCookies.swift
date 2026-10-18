import Foundation

enum BrowserKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case chrome, edge, firefox, safari
    var id: String { rawValue }
    var title: String {
        switch self {
        case .chrome: return "Google Chrome"
        case .edge: return "Microsoft Edge"
        case .firefox: return "Firefox"
        case .safari: return "Safari"
        }
    }
}

struct BrowserProfile: Identifiable, Equatable, Sendable {
    let browser: BrowserKind
    let directory: String
    let name: String
    var id: String { "\(browser.rawValue):\(directory)" }
    init(browser: BrowserKind, directory: String, name: String) {
        self.browser = browser; self.directory = directory; self.name = name
    }
}

struct CookieScope: Equatable, Sendable {
    let name: String
    let domains: [String]

    func contains(domain: String) -> Bool {
        var host = domain.lowercased()
        if host.hasPrefix(".") { host.removeFirst() }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard host.utf8.count <= 253, labels.allSatisfy({ label in
            !label.isEmpty && label.utf8.count <= 63 && label.first != "-" && label.last != "-" &&
            label.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
        }) else { return false }
        return domains.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    static func forURL(_ text: String) -> CookieScope? {
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme), let host = url.host?.lowercased() else { return nil }
        return supported.first { $0.contains(domain: host) }
    }

    private static let supported = [
        CookieScope(name: "抖音", domains: ["douyin.com", "iesdouyin.com"]),
        CookieScope(name: "YouTube", domains: ["youtube.com", "youtu.be", "youtube-nocookie.com", "googlevideo.com"]),
        CookieScope(name: "Bilibili", domains: ["bilibili.com", "b23.tv"]),
        CookieScope(name: "TikTok", domains: ["tiktok.com"]),
        CookieScope(name: "Instagram", domains: ["instagram.com"]),
        CookieScope(name: "X", domains: ["x.com", "twitter.com", "t.co"]),
        CookieScope(name: "小红书", domains: ["xiaohongshu.com", "xhslink.com"]),
        CookieScope(name: "快手", domains: ["kuaishou.com", "gifshow.com"])
    ]
}

struct SessionCookie: Equatable, Sendable {
    let domain: String
    let name: String
    let value: String
    let path: String
    let expires: Int64
    let secure: Bool
    let httpOnly: Bool

    init(domain: String, name: String, value: String, path: String, expires: Int64, secure: Bool, httpOnly: Bool = false) {
        self.domain = domain; self.name = name; self.value = value; self.path = path
        self.expires = expires; self.secure = secure; self.httpOnly = httpOnly
    }
}

protocol BrowserCookieReading: Sendable {
    func read(browser: BrowserKind, profile: String, scope: CookieScope) async throws -> [SessionCookie]
}

enum BrowserCookieError: LocalizedError {
    case invalidProfile, unsafePath, missingStore, denied(BrowserKind), database, corrupt, keychain(BrowserKind), decryption, unsupportedEncryption, invalidCookie
    case invalidField(field: String, rule: String)
    var errorDescription: String? {
        switch self {
        case .invalidProfile: return "浏览器配置无效。请在设置中重新选择标准浏览器配置。"
        case .unsafePath: return "浏览器配置路径包含符号链接或不安全位置。请选择浏览器的标准本机配置。"
        case .missingStore: return "找不到所选浏览器的网站会话存储。请先打开该浏览器配置后重试；没有存储不能证明账号未登录，也可本次不读取浏览器信息。"
        case .denied(.safari): return "无法读取 Safari Cookie。请在系统设置 → 隐私与安全性 → 完全磁盘访问权限中允许本应用，重新打开应用后重试，或关闭自动读取。"
        case .denied(let browser): return "无法读取 \(browser.title) Cookie。请检查此配置的文件权限，或在设置中关闭自动读取。"
        case .database: return "浏览器 Cookie 数据库正在使用、不可读或格式不兼容。请关闭浏览器后重试，或关闭自动读取并手动导入。"
        case .corrupt: return "浏览器 Cookie 存储格式损坏或不受支持。可本次不读取浏览器信息重试，或检查所选浏览器配置。此错误不能证明账号未登录。"
        case .keychain(let browser): return "无法获得 \(browser.title) Safe Storage 钥匙串授权。请允许系统授权后重试，或在设置中关闭自动读取。"
        case .decryption: return "浏览器 Cookie 解密或主机校验失败。可本次不读取浏览器信息重试；请检查读取兼容性，此错误不能证明账号未登录。"
        case .unsupportedEncryption: return "此浏览器 Cookie 使用不受支持的加密版本。请更新本应用，或关闭自动读取并手动导入。"
        case .invalidCookie: return "本机网站会话的格式无法安全读取。可本次不读取浏览器信息重试；账号登录未验证。"
        case .invalidField(let field, let rule): return "本机网站会话格式不兼容（字段：\(field)；规则：\(rule)）。未提交下载，账号登录未验证。可本次不读取浏览器信息重试。"
        }
    }
}

enum BrowserCookieJar {
    static func netscape(_ cookies: [SessionCookie], scope: CookieScope, now: Int64 = Int64(Date().timeIntervalSince1970)) throws -> Data {
        var lines = ["# Netscape HTTP Cookie File", "# Generated for a single local download request.", ""]
        for cookie in cookies where scope.contains(domain: cookie.domain) && (cookie.expires == 0 || cookie.expires > now) {
            for (field, value) in [("domain",cookie.domain),("name",cookie.name),("value",cookie.value),("path",cookie.path)] {
                guard !value.unicodeScalars.contains(where:{$0.value < 32 || $0.value == 127}) else {
                    throw BrowserCookieError.invalidField(field:field,rule:"controlCharacter")
                }
            }
            guard !cookie.domain.isEmpty, cookie.domain.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: ".-0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ").contains($0) }) else {throw BrowserCookieError.invalidField(field:"domain",rule:"invalidDomain")}
            // Netscape and Python cookiejar represent a nameless browser cookie
            // with an empty name column and its original value. Preserve it.
            guard !cookie.name.isEmpty || !cookie.value.isEmpty else {throw BrowserCookieError.invalidField(field:"name",rule:"emptyNameAndValue")}
            guard !cookie.name.contains("="), !cookie.name.contains(";") else {throw BrowserCookieError.invalidField(field:"name",rule:"nameSeparator")}
            guard cookie.path.hasPrefix("/") else {throw BrowserCookieError.invalidField(field:"path",rule:"invalidPath")}
            guard cookie.expires >= 0 else {throw BrowserCookieError.invalidField(field:"expires",rule:"negativeExpiry")}
            let domain = (cookie.httpOnly ? "#HttpOnly_" : "") + cookie.domain
            lines.append([domain, cookie.domain.hasPrefix(".") ? "TRUE" : "FALSE", cookie.path, cookie.secure ? "TRUE" : "FALSE", String(cookie.expires), cookie.name, cookie.value].joined(separator: "\t"))
        }
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }
}
