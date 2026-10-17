import Foundation

func expect(_ condition:Bool,_ message:String) { precondition(condition,message) }

actor SessionReaderFixture: BrowserCookieReading {
    var reads = 0
    var delayed = false
    var fails = false
    var empty = false
    func configure(delayed:Bool = false, fails:Bool = false, empty:Bool = false) { self.delayed=delayed;self.fails=fails;self.empty=empty }
    func read(browser:BrowserKind,profile:String,scope:CookieScope) async throws -> [SessionCookie] {
        reads += 1
        expect(browser == .chrome && profile == "Default", "selected browser profile passed")
        if delayed { try await Task.sleep(for:.seconds(30)) }
        if fails { throw AppError.message("无法读取浏览器 Cookie，请检查钥匙串权限。") }
        return empty ? [] : [SessionCookie(domain:".douyin.com",name:"test",value:"synthetic-session",path:"/",expires:0,secure:true)]
    }
    func count()->Int { reads }
}
actor SessionBackendFixture:BackendServing {
    var queue:[DownloadItem]=[]
    var done:[DownloadItem]=[]
    var requests:[[String:Any]]=[]
    var cancels=0
    var unknown=false
    func history() async throws -> History { History(done:done,queue:queue,pending:[]) }
    func post(_ route:String,body:Data) async throws {
        guard route == "add" else {return}
        let payload=try JSONSerialization.jsonObject(with:body) as! [String:Any]; requests.append(payload)
        if unknown {throw URLError(.timedOut)}
        let data=try JSONSerialization.data(withJSONObject:["id":"test","url":payload["url"]!,"folder":payload["folder"]!,"title":"Fixture","status":"downloading"])
        queue.append(try JSONDecoder().decode(DownloadItem.self,from:data))
    }
    func finish() {done=queue;queue=[]}
    func last()->[String:String] {requests.last?["ytdl_options_overrides"] as? [String:String] ?? [:]}
    func count()->Int {requests.count}
    func markUnknown() {unknown=true}
    func cookieStatus() async throws -> Bool {false}
    func uploadCookies(_ data:Data) async throws {}
    func deleteCookies() async throws {}
    func cancelAdd() async throws {cancels += 1}
    func cancellationCount()->Int {cancels}
    func version() async throws -> BackendVersion {BackendVersion(version:"test",engine:"test")}
}
@main struct BrowserSessionTests {
    @MainActor static func main() async throws {
        let fm=FileManager.default
        let root=fm.temporaryDirectory.appendingPathComponent("session-tests-"+UUID().uuidString)
        try fm.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? fm.removeItem(at:root)}
        let files=TaskCookieFiles(downloadRoot:root,verifyRuntime:{})
        let scope=CookieScope.forURL("https://www.douyin.com/video/42")!
        let cookies=[SessionCookie(domain:".douyin.com",name:"fixture",value:"local-test",path:"/",expires:0,secure:true)]
        let id="VideoExtractor/"+UUID().uuidString
        let path=try await files.prepare(cookies,scope:scope,taskID:id)!
        expect(path.hasPrefix("/downloads/.video-extractor-sessions/"),"isolated fixed container path")
        let local=root.appendingPathComponent(String(path.dropFirst("/downloads/".count)))
        expect((try fm.attributesOfItem(atPath:local.path)[.posixPermissions] as? Int)==0o600,"cookie file private")
        expect((try fm.attributesOfItem(atPath:files.directory.path)[.posixPermissions] as? Int)==0o700,"cookie directory private")
        let payload=try DownloadRequest.body(url:"https://www.douyin.com/video/42",quality:"best",audioOnly:false,cookieFile:path)
        expect(!String(decoding:payload,as:UTF8.self).contains("local-test"),"request contains path, no cookie values")
        do {_ = try DownloadRequest.body(url:"https://example.com",quality:"best",audioOnly:false,cookieFile:"/etc/passwd");preconditionFailure("arbitrary paths rejected")} catch {}
        do {_ = try await files.prepare(cookies,scope:scope,taskID:"../bad");preconditionFailure("traversal rejected")} catch {}
        await files.cleanup(keeping:[id]);expect(fm.fileExists(atPath:local.path),"active task retains cookie")
        await files.cleanup(keeping:[]);expect(!fm.fileExists(atPath:local.path),"terminal cookies cleaned")
        expect(!fm.fileExists(atPath:local.deletingLastPathComponent().path),"late backend save cannot recreate removed session")
        try fm.removeItem(at:files.directory)
        let outside=root.appendingPathComponent("outside");try fm.createDirectory(at:outside,withIntermediateDirectories:true)
        try fm.createSymbolicLink(at:files.directory,withDestinationURL:outside)
        do {_ = try await files.prepare(cookies,scope:scope,taskID:id);preconditionFailure("symlink refused")} catch {}
        try fm.removeItem(at:files.directory)

        let suite="BrowserSession.Tests."+UUID().uuidString
        let defaults=UserDefaults(suiteName:suite)!
        defer {defaults.removePersistentDomain(forName:suite)}
        let exports=ExportRegistry.records;defer {ExportRegistry.records=exports}
        let backend=SessionBackendFixture(), reader=SessionReaderFixture()
        let store=DownloadStore(backend:backend,defaults:defaults,cookieReader:reader,cookieFiles:files)
        store.connection = .ready;store.networkEnabled=true
        expect(await store.submit("https://www.douyin.com/video/1",quality:"best",audioOnly:false),"disabled reading preserves downloads")
        expect(await reader.count()==0,"disabled means zero reads")
        defaults.set(try JSONEncoder().encode(BrowserCookiePreferences(enabled:true,browser:.chrome,profile:"Default")),forKey:"browserCookiePreferencesV1")
        let enabled=DownloadStore(backend:backend,defaults:defaults,cookieReader:reader,cookieFiles:files)
        enabled.connection = .ready;enabled.networkEnabled=true
        expect(await enabled.submit("https://example.com/public.mp4",quality:"best",audioOnly:false),"unknown platform proceeds normally")
        expect(await reader.count()==0,"unknown site cannot trigger cookie read")
        expect(await enabled.submit("https://www.douyin.com/video/2",quality:"best",audioOnly:false),"enabled auto sync adds task")
        let opts=await backend.last();expect(opts["cookiefile"]?.hasPrefix("/downloads/.video-extractor-sessions/")==true,"per-task cookie path")
        expect(await reader.count()==1,"one fresh read")
        await reader.configure(empty:true)
        expect(await enabled.submit("https://www.douyin.com/video/3",quality:"best",audioOnly:false),"missing cookies allows public access")
        expect(await backend.last()["cookiefile"]==nil,"missing cookies never reuses old automatic file")
        await reader.configure(fails:true)
        let before=await backend.count()
        expect(!(await enabled.submit("https://www.douyin.com/video/4",quality:"best",audioOnly:false)),"permission error is actionable")
        expect(await backend.count()==before,"no add after permission failure")
        expect(enabled.message?.contains("Cookie")==true,"permission recovery shown")
        await reader.configure(delayed:true)
        let cancelling=Task {await enabled.submit("https://www.douyin.com/video/5",quality:"best",audioOnly:false)}
        while await reader.count()<4 {await Task.yield()}
        expect(enabled.submissions.contains(where:{$0.state == .syncing}),"visible sync stage")
        let restored=DownloadStore(backend:backend,defaults:defaults,cookieReader:reader,cookieFiles:files)
        expect(restored.submissions.filter{$0.link.canonicalURL.hasSuffix("/5")}.first?.state == .failed,"interrupted local sync is safe retry")
        await enabled.cancelSubmission()
        expect(!(await cancelling.value),"sync cancelled")
        expect(await backend.cancellationCount()==0,"local sync cancellation never calls global backend cancellation")
        expect(await backend.count()==before,"cancelled sync makes zero adds")
        await reader.configure();await backend.markUnknown()
        expect(!(await enabled.submit("https://www.douyin.com/video/6",quality:"best",audioOnly:false)),"unknown add remains unresolved")
        let unknownPath=await backend.last()["cookiefile"]!
        let unknownFile=root.appendingPathComponent(String(unknownPath.dropFirst("/downloads/".count)))
        await enabled.refresh()
        expect(fm.fileExists(atPath:unknownFile.path),"uncertain server result retains required cookie file")
        print("PASS: isolated private cookies, domain gating, persisted consent, cancellation, restart and uncertain result retention")
    }
}
