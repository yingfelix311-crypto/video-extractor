import Foundation

actor FlowBackend: BackendServing {
    var delay = false
    var fail = false
    var recorded: [[String: Any]] = []
    var queued: [DownloadItem] = []
    var done: [DownloadItem] = []
    var cancellationCount = 0
    var failHistoryOnCancel = false
    var historyFailure = false
    func configure(delay: Bool = false, fail: Bool = false) { self.delay=delay;self.fail=fail }
    func history() async throws -> History {
        if historyFailure {throw URLError(.cannotConnectToHost)}
        return History(done:done,queue:queued,pending:[])
    }
    func post(_ route: String, body: Data) async throws {
        if route != "add" { return }
        let payload=try JSONSerialization.jsonObject(with:body) as! [String:Any]
        recorded.append(payload)
        if delay { try await Task.sleep(for:.seconds(30)) }
        let data=try JSONSerialization.data(withJSONObject:["id":"fixture","title":"Fixture","url":payload["url"]!,"status":fail ? "error" : "downloading","folder":payload["folder"]!,"format":payload["format"]!,"download_type":payload["download_type"]!])
        let item=try JSONDecoder().decode(DownloadItem.self,from:data)
        if fail { done=[item];throw AppError.message("Fresh cookies are needed") }
        queued=[item]
    }
    func cookieStatus() async throws -> Bool { false }
    func uploadCookies(_ data:Data) async throws {}
    func deleteCookies() async throws {}
    func cancelAdd() async throws { cancellationCount += 1;if failHistoryOnCancel {historyFailure=true} }
    func historyFailsAfterCancel(_ enabled:Bool) {failHistoryOnCancel=enabled;historyFailure=false}
    func version() async throws -> BackendVersion { BackendVersion(version:"fixture",engine:"fixture") }
    func requestCount()->Int { recorded.count }
    func lastURL()->String? { recorded.last?["url"] as? String }
    func clear() { queued=[];done=[] }
}

@main struct SubmissionTests {
    @MainActor static func main() async throws {
        let suite="VideoExtractor.Tests."+UUID().uuidString
        let defaults=UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let originalExports=ExportRegistry.records
        defer { ExportRegistry.records=originalExports }
        let backend=FlowBackend()
        let store=DownloadStore(backend:backend,defaults:defaults)
        store.connection = .ready
        await backend.configure(delay:true)
        let submission=Task { await store.submit("https://www.douyin.com/jingxuan?modal_id=42",quality:"720",audioOnly:false) }
        while await backend.requestCount()==0 { await Task.yield() }
        precondition(store.submissions.count==1 && store.isSubmitting, "intent visible before server response")
        let restored=DownloadStore(backend:backend,defaults:defaults)
        precondition(restored.submissions.count==1 && restored.submissions[0].state == .uncertain,"interrupted request restored as unresolved")
        await store.cancelSubmission()
        let accepted=await submission.value
        precondition(!accepted && !store.isSubmitting && store.submissions.isEmpty,"cancel-add confirmed and request stopped")
        let cancelled=await backend.cancellationCount
        precondition(cancelled==1,"cancel-add sent once")
        await backend.historyFailsAfterCancel(true)
        let interrupted=Task {await store.submit("https://example.com/ambiguous",quality:"best",audioOnly:false)}
        while await backend.requestCount()<2 {await Task.yield()}
        await store.cancelSubmission()
        _ = await interrupted.value
        precondition(store.submissions.count==1 && store.submissions[0].state == .uncertain,"failed cancellation reconciliation must retain durable blocker")
        let countBefore=await backend.requestCount()
        let duplicate=await store.submit("https://example.com/another",quality:"best",audioOnly:false)
        let countAfter=await backend.requestCount()
        precondition(!duplicate && countBefore==countAfter,"unresolved cancellation blocks other adds")
        await backend.historyFailsAfterCancel(false)
        await store.cancelSubmission()
        store.connection = .ready
        await backend.configure()
        let added=await store.submit("https://www.douyin.com/jingxuan?modal_id=42",quality:"720",audioOnly:false)
        let url=await backend.lastURL()
        precondition(added && url=="https://www.douyin.com/video/42","canonical URL submitted")
        precondition(store.submissions.isEmpty,"server history reconciles optimistic intent")
        let source=store.originalURL(for:store.items[0])
        precondition(source.contains("modal_id=42"),"original source survives backend normalization")
        await backend.clear();await store.refresh()
        await backend.configure(fail:true)
        let failed=await store.submit("https://www.douyin.com/video/43",quality:"best",audioOnly:false)
        precondition(!failed && store.completed.count==1 && store.submissions.isEmpty,"failed server record replaces pending row")
        precondition(store.message?.lowercased().contains("cookie")==true,"raw error retained for classification")
        await backend.configure();await backend.clear();await store.refresh()
        store.options=DownloadOptions(videoFormat:"mp4")
        let reloaded=DownloadStore(backend:backend,defaults:defaults)
        precondition(reloaded.options.videoFormat=="mp4","download options persist")
        print("PASS: immediate/persisted intent, cancellation, canonicalization, failure reconciliation, options")
    }
}
