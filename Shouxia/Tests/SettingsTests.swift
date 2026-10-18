import Foundation
actor SettingsBackend: BackendServing {
    var done:[DownloadItem]=[]
    func setDone(_ items:[DownloadItem]) {done=items}
    func history() async throws -> History {History(done:done,queue:[],pending:[])}
    func post(_ route:String,body:Data) async throws {}
    func cookieStatus() async throws -> Bool {false}
    func uploadCookies(_ data:Data) async throws {}
    func deleteCookies() async throws {}
    func cancelAdd() async throws {}
    func version() async throws -> BackendVersion {BackendVersion(version:"fixture",engine:"fixture")}
}
actor SuspendedCookieCleanup: TaskCookieServing {
    var started=false
    var finished=false
    var calls=0
    var resume:CheckedContinuation<Void,Never>?
    func validateRuntime() async throws {}
    func prepare(_ cookies:[SessionCookie],scope:CookieScope,taskID:String) async throws -> String? {nil}
    func discard(taskID:String) async {
        calls += 1
        started=true
        await withCheckedContinuation {resume=$0}
        finished=true
    }
    func cleanup(keeping taskIDs:Set<String>) async {preconditionFailure("refresh must not sweep newly submitted sessions")}
    func release() {resume?.resume();resume=nil}
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
        let backend=SettingsBackend(), cookies=SuspendedCookieCleanup()
        let terminal=try JSONDecoder().decode(DownloadItem.self,from:JSONSerialization.data(withJSONObject:["id":"fixture","url":"https://example.com/fixture","title":"Fixture","status":"finished","folder":"VideoExtractor/"+UUID().uuidString]))
        await backend.setDone([terminal])
        let pendingCleanup=DownloadStore(backend:backend,defaults:defaults,cookieFiles:cookies)
        var reconnected=false
        let reconnect=Task {await pendingCleanup.reconnect();reconnected=true}
        for _ in 0..<100 where !(await cookies.started) {try await Task.sleep(for:.milliseconds(5))}
        let cleanupStarted=await cookies.started
        precondition(cleanupStarted,"confirmed terminal cleanup scheduled")
        for _ in 0..<20 where !reconnected {try await Task.sleep(for:.milliseconds(5))}
        precondition(reconnected,"suspended cookie filesystem cleanup must not hold reconnect or readiness")
        let savedWhileCleaning=await pendingCleanup.saveSettings(options:originalOptions,browser:originalBrowser,automaticUpdates:automatic)
        precondition(savedWhileCleaning,"ready idle settings save must work while terminal cleanup waits for local permission")
        await pendingCleanup.refresh()
        await cookies.release()
        await reconnect.value
        for _ in 0..<20 where !(await cookies.finished) {try await Task.sleep(for:.milliseconds(5))}
        let finished=await cookies.finished
        precondition(finished,"confirmed terminal cleanup still completes after permission resumes")
        let cleanupCalls=await cookies.calls
        precondition(cleanupCalls==1,"polling deduplicates cleanup while the same terminal ID is suspended")
        print("Settings tests passed")
    }
}
