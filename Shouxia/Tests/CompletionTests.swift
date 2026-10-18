import Foundation

actor CompletionBackend: BackendServing {
    var snapshot = History(done:[],queue:[],pending:[])
    var deletes = 0
    var latestAudio: Bool?
    var deletedURLs: [String] = []
    func set(_ done:[DownloadItem], queue:[DownloadItem] = []) {snapshot=History(done:done,queue:queue,pending:[])}
    func history() async throws -> History {snapshot}
    func post(_ route:String,body:Data) async throws {
        if route == "delete" {
            deletes += 1
            let payload=try JSONSerialization.jsonObject(with:body) as! [String:Any]
            let ids=payload["ids"] as! [String]
            deletedURLs += ids
            snapshot=History(done:snapshot.done.filter { !ids.contains($0.url) },queue:snapshot.queue,pending:snapshot.pending)
        }
        if route == "add" {
            let payload=try JSONSerialization.jsonObject(with:body) as! [String:Any]
            latestAudio = payload["download_type"] as? String == "audio"
            let data=try JSONSerialization.data(withJSONObject:["id":"same","title":"Fixture","url":payload["url"]!,"status":"downloading","folder":payload["folder"]!,"download_type":payload["download_type"]!])
            snapshot=History(done:[],queue:[try JSONDecoder().decode(DownloadItem.self,from:data)],pending:[])
        }
    }
    func cookieStatus() async throws -> Bool {false}
    func uploadCookies(_ data:Data) async throws {}
    func deleteCookies() async throws {}
    func cancelAdd() async throws {}
    func version() async throws -> BackendVersion {BackendVersion(version:"fixture",engine:"fixture")}
}
@main struct CompletionTests {
    @MainActor static func main() async throws {
        let suite="CompletionTests."+UUID().uuidString
        let defaults=UserDefaults(suiteName:suite)!
        defer {defaults.removePersistentDomain(forName:suite)}
        let exports=ExportRegistry.records
        defer {ExportRegistry.records=exports}
        func item(_ folder:String,_ type:String, url:String = "https://example.com/fixture") throws -> DownloadItem {
            try JSONDecoder().decode(DownloadItem.self,from:JSONSerialization.data(withJSONObject:["id":"same","title":"Fixture","url":url,"status":"finished","folder":folder,"download_type":type]))
        }
        for folder in ["", "shared-downloads", "VideoExtractor/not-a-uuid"] {
            let first=try item(folder,"video",url:"https://example.com/first")
            let second=try item(folder,"video",url:"https://example.com/second")
            precondition(first.id != second.id,"shared legacy folder must not collide across URLs")
            let legacyBackend=CompletionBackend()
            await legacyBackend.set([first,second])
            let legacyDefaults=UserDefaults(suiteName:suite+folder)!
            defer {legacyDefaults.removePersistentDomain(forName:suite+folder)}
            let legacy=DownloadStore(backend:legacyBackend,defaults:legacyDefaults)
            await legacy.refresh()
            precondition(TaskList.visible(active:[],pending:[],history:legacy.completed,filter:"全部").count==2,"legacy shared-folder rows both visible")
            let reloaded=DownloadStore(backend:legacyBackend,defaults:legacyDefaults)
            precondition(reloaded.completed.count==2,"legacy shared-folder rows both persist")
            await reloaded.refresh()
            let cleared=await reloaded.clearHistory(ids:[first.id])
            precondition(cleared && reloaded.completed.count==1 && reloaded.completed[0].id==second.id,"selected legacy deletion preserves other row")
            let deletedURLs=await legacyBackend.deletedURLs
            precondition(deletedURLs==[first.url],"only selected backend URL is deleted")
            let backendHistory=try await legacyBackend.history()
            precondition(backendHistory.done.map(\.url)==[second.url],"unselected backend history survives")
            let afterClear=DownloadStore(backend:legacyBackend,defaults:legacyDefaults)
            precondition(afterClear.completed.map(\.id)==[second.id],"selected removal persists without dropping unselected record")
        }
        let video=try item("VideoExtractor/"+UUID().uuidString,"video"),audio=try item("VideoExtractor/"+UUID().uuidString,"audio")
        precondition(video.id != audio.id && video.id.hasPrefix("task:"),"local UUID folders distinguish repeated same URL occurrences")
        let backend=CompletionBackend()
        let store=DownloadStore(backend:backend,defaults:defaults)
        await backend.set([video]);await store.refresh()
        await backend.set([audio]);await store.refresh()
        precondition(store.completed.count==2,"same URL video and audio retained")
        let restored=DownloadStore(backend:backend,defaults:defaults)
        precondition(restored.completed.count==2,"archive restores before network refresh")
        await restored.refresh()
        precondition(restored.completed.count==2,"both occurrences survive reload")
        precondition(TaskList.visible(active:[],pending:[],history:restored.completed,filter:"全部").count==2,"task list retains both")
        let old=restored.completed.first(where:{$0.id==video.id})!
        restored.notice="stale success"
        let removed=await restored.clearHistory(ids:[old.id])
        precondition(removed,"archive removed")
        let deletes=await backend.deletes
        precondition(deletes==0,"archive removal never deletes newer backend item")
        precondition(restored.completed.count==1 && restored.completed[0].id==audio.id,"latest remains")
        precondition(restored.notice==nil,"removal clears stale notice")
        let retried=await restored.retry(restored.completed[0])
        precondition(retried,"latest task retry accepted")
        let latestAudio=await backend.latestAudio
        precondition(latestAudio==true,"latest same URL retry preserves audio mode")
        let audioSnapshot=restored.completed.first(where:{$0.id==audio.id})!
        precondition(audioSnapshot.isArchived,"overwritten terminal task becomes local archive")
        let removedAudio=await restored.clearHistory(ids:[audioSnapshot.id])
        precondition(removedAudio,"archive can be removed while newer URL task runs")
        let deletesAfterRetry=await backend.deletes
        precondition(deletesAfterRetry==0,"archive removal preserves active newer backend task")
        let again=DownloadStore(backend:backend,defaults:defaults)
        await again.refresh()
        precondition(!again.completed.contains(where:{$0.id==video.id}),"removed archive stays removed")
        again.notice="previous success"
        again.message="new failure"
        precondition(again.notice==nil,"errors replace previous success notice")
        print("PASS: durable occurrences, safe removal, latest retry, notice lifecycle")
    }
}
