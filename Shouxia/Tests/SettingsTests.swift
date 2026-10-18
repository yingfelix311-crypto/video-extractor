import Foundation
actor SettingsBackend: BackendServing {
    func history() async throws -> History {History(done:[],queue:[],pending:[])}
    func post(_ route:String,body:Data) async throws {}
    func cookieStatus() async throws -> Bool {false}
    func uploadCookies(_ data:Data) async throws {}
    func deleteCookies() async throws {}
    func cancelAdd() async throws {}
    func version() async throws -> BackendVersion {BackendVersion(version:"fixture",engine:"fixture")}
}
@main struct SettingsTests {
    @MainActor static func main() async throws {
        let suite="SettingsTests."+UUID().uuidString
        let defaults=UserDefaults(suiteName:suite)!
        defer {defaults.removePersistentDomain(forName:suite)}
        let store=DownloadStore(backend:SettingsBackend(),defaults:defaults)
        store.connection = .ready
        let originalOptions=store.options, originalBrowser=store.browserCookies
        let automatic=store.updater.automaticEnabled
        defer {store.updater.automaticEnabled=automatic}
        var bad=originalOptions;bad.proxy="invalid-proxy"
        var browser=originalBrowser;browser.enabled=false;browser.profile="draft"
        let invalidOptions=await store.saveSettings(options:bad,browser:browser,automaticUpdates:!automatic)
        precondition(!invalidOptions && store.options==originalOptions && store.browserCookies==originalBrowser && store.updater.automaticEnabled==automatic,"invalid options must leave every preference unchanged")
        browser.enabled=true;browser.profile="missing-profile-"+UUID().uuidString
        var changed=originalOptions;changed.videoFormat="mp4"
        let invalidProfile=await store.saveSettings(options:changed,browser:browser,automaticUpdates:!automatic)
        precondition(!invalidProfile && store.options==originalOptions && store.browserCookies==originalBrowser && store.updater.automaticEnabled==automatic,"missing selected profile must not partially save options or automatic updates")
        browser.enabled=false
        let saved=await store.saveSettings(options:changed,browser:browser,automaticUpdates:!automatic)
        precondition(saved && store.options==changed && store.browserCookies==browser && store.updater.automaticEnabled == !automatic,"valid drafts save together")
        print("Settings tests passed")
    }
}
