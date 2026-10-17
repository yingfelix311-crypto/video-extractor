import Foundation

struct BrowserSessionResult: Sendable {
    let cookieFile:String?
    let status:String
}

struct BrowserSessionSync: Sendable {
    let reader:any BrowserCookieReading
    let files:any TaskCookieServing
    func prepare(preferences:BrowserCookiePreferences,url:String,taskID:String) async throws -> BrowserSessionResult {
        guard preferences.enabled,let scope=CookieScope.forURL(url) else {return .init(cookieFile:nil,status:"未对这个链接读取浏览器登录状态。")}
        let cookies=try await reader.read(browser:preferences.browser,profile:preferences.profile,scope:scope)
        try Task.checkCancellation()
        let path=try await files.prepare(cookies,scope:scope,taskID:taskID)
        try Task.checkCancellation()
        return .init(cookieFile:path,status:path == nil ? "\(scope.name)：未找到可用 Cookie，将尝试公开访问；需要登录时请在所选浏览器打开网站。" : "\(scope.name)：已从 \(preferences.browser.title) 同步 Cookie；是否有效由网站决定。")
    }
}
