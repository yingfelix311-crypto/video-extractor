import Foundation

struct BrowserSessionResult: Sendable {
    let cookieFile:String?
    let status:String
}

struct BrowserSessionSync: Sendable {
    let reader:any BrowserCookieReading
    let files:any TaskCookieServing
    func prepare(preferences:BrowserCookiePreferences,url:String,taskID:String) async throws -> BrowserSessionResult {
        guard preferences.enabled,let scope=CookieScope.forURL(url) else {return .init(cookieFile:nil,status:"本次未读取浏览器网站会话；账号登录未验证。")}
        try Task.checkCancellation()
        try await files.validateRuntime()
        try Task.checkCancellation()
        let cookies=try await reader.read(browser:preferences.browser,profile:preferences.profile,scope:scope)
        try Task.checkCancellation()
        let path=try await files.prepare(cookies,scope:scope,taskID:taskID)
        try Task.checkCancellation()
        return .init(cookieFile:path,status:Self.readStatus(browser:preferences.browser,scope:scope,hasData:path != nil))
    }
    func inspect(preferences:BrowserCookiePreferences,url:String) async throws -> String {
        guard preferences.enabled,let scope=CookieScope.forURL(url) else {return "未启用浏览器网站会话；未读取任何浏览器信息。"}
        try Task.checkCancellation()
        try await files.validateRuntime()
        try Task.checkCancellation()
        let cookies=try await reader.read(browser:preferences.browser,profile:preferences.profile,scope:scope)
        try Task.checkCancellation()
        let data=try BrowserCookieJar.netscape(cookies,scope:scope)
        let hasData=String(decoding:data,as:UTF8.self).split(whereSeparator:\.isNewline).contains(where:{!$0.hasPrefix("#") || $0.hasPrefix("#HttpOnly_")})
        return Self.readStatus(browser:preferences.browser,scope:scope,hasData:hasData)
    }
    private static func readStatus(browser:BrowserKind,scope:CookieScope,hasData:Bool)->String {
        hasData ? "\(scope.name)：已读取 \(browser.title) 的网站会话信息，可能包含访客状态。账号登录未验证。" : "\(scope.name)：未找到可用的网站会话信息，将尝试不读取浏览器的方式。账号登录未验证。"
    }
}
