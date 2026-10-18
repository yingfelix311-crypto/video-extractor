import Foundation
import Combine
import AppKit

enum ConnectionState: Equatable {
    case connecting, starting, ready, offline
    var label: String {
        switch self {
        case .connecting: "连接中"
        case .starting: "正在启动下载服务"
        case .ready: "下载服务已就绪"
        case .offline: "下载服务未连接"
        }
    }
    var isReady: Bool { self == .ready }
}

@MainActor final class DownloadStore: ObservableObject {
    @Published var items: [DownloadItem] = []
    @Published var completed: [DownloadItem] = []
    @Published var pending: [DownloadItem] = []
    @Published var connection: ConnectionState = .connecting
    @Published var message: String? { didSet { if message != nil { notice = nil } } }
    @Published var isSubmitting = false
    @Published var submittingURL: String?
    @Published var notice: String?
    @Published var showSettings = false
    @Published var showQuickStart = false
    @Published var quickStartOpenSettings = false
    @Published private(set) var isConfiguring = false
    @Published private(set) var hasCookies: Bool?
    @Published private(set) var serviceVersion = "未检查"
    @Published var settingsMessage: String?
    @Published var diagnostics = "点击检查，查看后台和下载依赖状态。"
    @Published var networkEnabled = false
    @Published var browserCookies:BrowserCookiePreferences {
        didSet {if let data=try? JSONEncoder().encode(browserCookies) {defaults.set(data,forKey:"browserCookiePreferencesV1")}}
    }
    @Published private(set) var browserProfiles:[BrowserProfile]=[]
    @Published private(set) var browserCookieStatus="尚未读取浏览器网站会话；账号登录未验证。"
    @Published private(set) var browserLoginURL=URL(string:"https://www.douyin.com/")!
    @Published private(set) var isLoadingBrowserProfiles=false
    @Published private(set) var runtimeRecoveryPending = false
    @Published var options: DownloadOptions {
        didSet { if let data=try? JSONEncoder().encode(options) { defaults.set(data,forKey:"downloadOptionsV2") } }
    }
    @Published private(set) var submissions: [SubmissionIntent] {
        didSet { if let data=try? JSONEncoder().encode(submissions) { defaults.set(data,forKey:"submissionIntentsV2") } }
    }
    @Published var destinationPath = UserDefaults.standard.string(forKey: "downloadDestination") ?? SafeDownloadPath.root.path
    @Published var exportErrors: [String: String] = [:]
    @Published private(set) var exporting: Set<String> = []
    let updater = EngineUpdater()
    private var maintenanceChecked = Date.distantPast
    private let backend: any BackendServing
    private let defaults: UserDefaults
    private var submissionTask: Task<Void, Error>?
    private var cookieSyncTask:Task<String?,Error>?
    private let cookieReader:any BrowserCookieReading
    private let cookieFiles:any TaskCookieServing
    private var cancellationRequested = false
    private var lastAcceptedURL: String?
    private var polling: Task<Void, Never>?
    private var reconnecting = false
    private let archive: DownloadArchive
    private var refreshing = false
    private var lastRecoveryAttempt = Date.distantPast
    private var browserProfileLoadID=UUID()

    init(backend: any BackendServing = Backend(), defaults: UserDefaults = .standard, cookieReader:any BrowserCookieReading = NativeBrowserCookieReader(), cookieFiles:any TaskCookieServing = TaskCookieFiles()) {
        self.backend=backend; self.defaults=defaults
        self.archive = DownloadArchive(defaults: defaults)
        completed = archive.records.map { var item = $0; item.archived = true; return item }
        self.cookieReader=cookieReader;self.cookieFiles=cookieFiles
        browserCookies=defaults.data(forKey:"browserCookiePreferencesV1").flatMap {try? JSONDecoder().decode(BrowserCookiePreferences.self,from:$0)} ?? BrowserCookiePreferences()
        options=defaults.data(forKey:"downloadOptionsV2").flatMap { try? JSONDecoder().decode(DownloadOptions.self,from:$0) } ?? DownloadOptions()
        submissions=(defaults.data(forKey:"submissionIntentsV2").flatMap { try? JSONDecoder().decode([SubmissionIntent].self,from:$0) } ?? []).map {
            var intent=$0
            if intent.state == .syncing || intent.state == .cancellingCookies {intent.state = .failed;intent.error="上次浏览器 Cookie 同步已中断，尚未提交后台；可安全重试。"}
            if intent.state == .parsing || intent.state == .cancelling { intent.state = .uncertain }
            return intent
        }
    }

    func start() {
        guard polling == nil else { return }
        polling = Task { [weak self] in
            await self?.reconnect()
            if let self,self.connection.isReady,!self.runtimeRecoveryPending {
                await self.updater.recoverIfNeeded()
                await self.updater.refreshVersion()
                await self.refreshSettings()
            }
            while !Task.isCancelled {
                let seconds = self?.items.isEmpty == false ? 2 : 5
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { break }
                if let self,self.runtimeRecoveryPending {
                    if Date().timeIntervalSince(self.lastRecoveryAttempt)>30 {await self.reconnect()}
                    continue
                }
                await self?.refresh()
                if let self,self.connection.isReady,!self.reconnecting, !self.isSubmitting, !self.isConfiguring, !self.submissions.contains(where: { $0.state == .uncertain }), Date().timeIntervalSince(self.maintenanceChecked) > 60 {
                    self.maintenanceChecked = Date()
                    await self.updater.recoverIfNeeded()
                    await self.updater.checkIfNeeded()
                }
            }
        }
    }

    func refresh() async {
        guard !refreshing, !isConfiguring else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            let history = try await backend.history()
            items = history.queue
            completed = archive.merge(history.done, current: history.done + history.queue + history.pending)
            pending = history.pending
            connection = .ready
            let folders=Set((items+completed+pending).compactMap(\.folder))
            submissions.removeAll { folders.contains($0.id) && $0.state != .cancelling }
            // Only confirmed terminal IDs are cleaned here. A broad orphan sweep
            // could race a new synchronization that starts while history is fetched.
            for item in history.done {if let folder=item.folder {await cookieFiles.discard(taskID:folder)}}
            let active=Set((history.queue+history.pending).compactMap(\.folder))
            for intent in submissions where intent.state == .failed && !active.contains(intent.id) {await cookieFiles.discard(taskID:intent.id)}
            if canConfigure {
                // Exclude new local submissions while sweeping confirmed idle files.
                // In-flight/uncertain intents make canConfigure false.
                isConfiguring=true
                await cookieFiles.cleanup(keeping:active)
                isConfiguring=false
            }
            await exportFinished()
        } catch {
            if connection != .starting { connection = .offline }
            // Retain the last successful snapshot during a transient outage.
            Backend.log("History: \(error.localizedDescription)")
        }
    }

    func reconnect() async {
        guard !reconnecting, !isConfiguring, !isSubmitting, !updater.isUpdating else { return }
        reconnecting = true
        defer { reconnecting = false }
        connection = .connecting
        message = nil
        lastRecoveryAttempt=Date()
        do {try await RuntimeSupport.recoverIfNeeded();runtimeRecoveryPending=false}
        catch {runtimeRecoveryPending=true;message="后台恢复待重试：\(error.localizedDescription)"}
        if !runtimeRecoveryPending {await refresh();if connection == .ready {return}}
        connection = .starting
        do {
            try await Backend.startVirtualMachine()
            try await RuntimeSupport.recoverIfNeeded()
            runtimeRecoveryPending=false
            try await Backend.startContainer()
            for _ in 0..<3 {
                await refresh()
                if connection == .ready { return }
                try await Task.sleep(for: .seconds(1))
            }
            throw AppError.message("服务尚未就绪，请稍后重新连接。")
        } catch {
            runtimeRecoveryPending=RuntimeSupport.recoveryRequired
            connection = .offline
            report(error)
        }
    }

    func submit(_ text: String, quality: String, audioOnly: Bool, options selectedOptions: DownloadOptions? = nil, destination: String? = nil, useBrowserSession: Bool? = nil) async -> Bool {
        guard !isSubmitting else { return false }
        guard !isConfiguring else { message = "后台设置正在保存，请稍后提取。"; return false }
        guard !reconnecting else {message="下载服务正在连接，请稍后提取。";return false}
        guard !runtimeRecoveryPending else {message="后台恢复尚未完成，请先重新连接。";return false}
        notice = nil
        guard !submissions.contains(where:{$0.state == .uncertain || $0.state == .cancelling}) else {message="请先停止并核对未决任务，再提交新链接。";return false}
        guard !updater.isUpdating else { message = "下载引擎正在更新，完成后即可提取。"; return false }
        guard connection == .ready else { message = "下载服务尚未连接，请先重新连接。"; return false }
        do {
            try DownloadQuality.validate(quality)
            let link = try LinkParser.resolve(text)
            let url = link.canonicalURL
            let requestOptions = try (selectedOptions ?? options).validated()
            let syncCookies=browserCookies.enabled && (useBrowserSession ?? true) && CookieScope.forURL(url) != nil
            guard !syncCookies || networkEnabled else {message="请在 Cookie 设置中保存浏览器选择，启用后台自动同步支持。";return false}
            guard requestOptions.ytdlOverrides.isEmpty || networkEnabled else { message="请先在设置中启用并保存网络参数。";return false }
            guard !submissions.contains(where: { $0.link.canonicalURL == url && $0.state != .failed }),
                  !exporting.contains(url), !items.contains(where: { $0.url == url }), !pending.contains(where: { $0.url == url }) else {
                message = "这个链接已有任务正在处理，请等待完成。"; return false
            }
            let selectedDestination = destination ?? destinationPath
            let taskFolder = "VideoExtractor/" + UUID().uuidString
            isSubmitting = true
            submittingURL = url
            message = nil
            notice = nil
            cancellationRequested = false
            lastAcceptedURL = nil
            submissions.removeAll { $0.link.canonicalURL == url && $0.state == .failed }
            submissions.append(SubmissionIntent(id:taskFolder,link:link,quality:quality,audioOnly:audioOnly,options:requestOptions,destination:selectedDestination,createdAt:Date(),state:syncCookies ? .syncing : .parsing,browserSessionRequested:useBrowserSession))
            defer { isSubmitting = false; submittingURL = nil; submissionTask=nil;cookieSyncTask=nil }
            // Persist intent before the request: a timeout or app exit must not lose
            // the destination of a task the server already accepted.
            var records = ExportRegistry.records
            records[taskFolder] = ExportRecord(destination: selectedDestination,originalURL:link.originalURL,canonicalURL:link.canonicalURL,quality:quality,audioOnly:audioOnly,options:requestOptions)
            ExportRegistry.records = records
            exportErrors[taskFolder] = nil
            var cookieFile:String?
            if let domain=CookieScope.forURL(url)?.domains.first,let inspectionURL=URL(string:"https://"+domain+"/") {browserLoginURL=inspectionURL}
            if syncCookies {
                let preferences=browserCookies
                let sync=BrowserSessionSync(reader:cookieReader,files:cookieFiles)
                let cookieTask=Task<String?,Error> {
                    let result=try await sync.prepare(preferences:preferences,url:url,taskID:taskFolder)
                    self.browserCookieStatus=result.status
                    return result.cookieFile
                }
                cookieSyncTask=cookieTask
                do {cookieFile=try await cookieTask.value}
                catch {
                    await cookieFiles.discard(taskID:taskFolder)
                    if cancellationRequested || error is CancellationError {
                        submissions.removeAll {$0.id==taskFolder};notice="已停止浏览器 Cookie 同步，未提交下载任务。"
                    } else {
                        setSubmission(taskFolder,state:.failed,error:error.localizedDescription)
                        browserCookieStatus=error.localizedDescription;report(error)
                    }
                    return false
                }
                if cancellationRequested {
                    await cookieFiles.discard(taskID:taskFolder);submissions.removeAll {$0.id==taskFolder};return false
                }
                setSubmission(taskFolder,state:.parsing)
            } else {
                browserCookieStatus="本次未读取浏览器网站会话；已导入的手动会话文件（如有）仍可能使用。账号登录未验证。"
            }
            let body=try DownloadRequest.body(url:url,quality:quality,audioOnly:audioOnly,folder:taskFolder,options:requestOptions,cookieFile:cookieFile)
            let task=Task { try await backend.post("add",body:body) }
            submissionTask=task
            do {
                try await task.value
                await refresh()
                guard !cancellationRequested else { return false }
                if submissions.contains(where: { $0.id == taskFolder }) {
                    setSubmission(taskFolder,state:.uncertain,error:"后台已响应，尚未确认任务。请先核对，不要重复提交。")
                    return false
                }
                lastAcceptedURL=(items+pending+completed).first(where:{$0.folder==taskFolder})?.url
                notice=link.wasNormalized ? "已转换抖音页面链接，并创建下载任务。" : "下载任务已创建，可在下方查看进度。"
                return true
            } catch {
                await refresh()
                // The cancellation owner removes the intent only after successful reconciliation.
                if cancellationRequested { return false }
                // Only an explicit backend rejection establishes that retrying is safe.
                let unresolved = !(error is AppError) || !connection.isReady
                setSubmission(taskFolder,state:unresolved ? .uncertain : .failed,error:error.localizedDescription)
                report(error)
                return false
            }
        } catch {
            report(error)
            await refresh()
            return false
        }
    }

    func cancel(_ item: DownloadItem) async { await perform(.cancel, item: item) }
    func originalURL(for item: DownloadItem) -> String {
        ExportRegistry.records[ExportRegistry.recordKey(for:item.url,folder:item.folder)]?.originalURL ?? item.url
    }
    func retryOptions(for item:DownloadItem) -> DownloadOptions {
        if let saved=ExportRegistry.records[ExportRegistry.recordKey(for:item.url,folder:item.folder)]?.options {return saved}
        let network=item.ytdlOptionsOverrides ?? [:]
        return DownloadOptions(videoFormat:["mp4","any"].contains(item.format ?? "") ? item.format! : "any",proxy:network["proxy"] ?? "",referer:network["referer"] ?? "",userAgent:network["user_agent"] ?? "")
    }
    @discardableResult func retry(_ item: DownloadItem, link: String? = nil, quality: String? = nil, audioOnly: Bool? = nil, options selected: DownloadOptions? = nil) async -> Bool {
        let record=ExportRegistry.records[ExportRegistry.recordKey(for:item.url,folder:item.folder)]
        let selectedOptions=selected ?? retryOptions(for:item)
        let accepted=await submit(link ?? originalURL(for:item),quality:quality ?? record?.quality ?? item.quality ?? "best",audioOnly:audioOnly ?? record?.audioOnly ?? item.isAudio,options:selectedOptions,destination:record?.destination ?? destinationPath)
        // Same-URL add can already have completed by now. Never delete that new done record.
        if accepted, let newURL=lastAcceptedURL, newURL != item.url {
            _ = await clearHistory(ids:[item.id])
        }
        return accepted
    }
    func retrySubmission(_ intent: SubmissionIntent) async {
        guard intent.state == .failed else { return }
        _ = await submit(intent.link.originalURL,quality:intent.quality,audioOnly:intent.audioOnly,options:intent.options,destination:intent.destination,useBrowserSession:intent.browserSessionRequested == false ? false : nil)
    }
    func retrySubmissionWithoutBrowser(_ intent:SubmissionIntent) async {
        guard intent.state == .failed else {return}
        _ = await submit(intent.link.originalURL,quality:intent.quality,audioOnly:intent.audioOnly,options:intent.options,destination:intent.destination,useBrowserSession:false)
    }
    func dismissSubmission(_ id:String) {
        submissions.removeAll { $0.id==id && $0.state == .failed }
    }
    private func setSubmission(_ id:String,state:SubmissionState,error:String?=nil) {
        guard let index=submissions.firstIndex(where:{$0.id==id}) else {return}
        submissions[index].state=state;submissions[index].error=error
    }
    func cancelSubmission(_ id:String? = nil) async {
        guard !isConfiguring, !reconnecting, !runtimeRecoveryPending else { return }
        let target=id.flatMap { key in submissions.first(where:{$0.id==key}) } ?? submissions.first(where:{$0.state == .syncing || $0.state == .parsing || $0.state == .uncertain})
        guard let target else {return}
        if target.state == .syncing || target.state == .cancellingCookies {
            cancellationRequested=true;setSubmission(target.id,state:.cancellingCookies)
            cookieSyncTask?.cancel()
            notice="已请求停止同步；如有系统授权窗口，请在该窗口取消。"
            return
        }
        setSubmission(target.id,state:.cancelling)
        if submittingURL == target.link.canonicalURL {cancellationRequested=true}
        do {
            // cancel-add invalidates in-flight extraction on the server, unlike cancelling only HTTP.
            try await backend.cancelAdd()
            if submittingURL == target.link.canonicalURL {
                submissionTask?.cancel()
            }
            let history=try await backend.history()
            let accepted=(history.queue+history.pending).filter {$0.folder==target.id}
            for item in accepted { let request=try ActionRequest(.cancel,item:item);try await backend.post(request.route,body:request.body) }
            submissions.removeAll {$0.id==target.id}
            await cookieFiles.discard(taskID:target.id)
            notice=accepted.isEmpty ? "已停止解析并核对后台；已完成的文件仍会保留。" : "已停止解析并取消刚创建的下载任务。"
            await refresh()
        } catch { setSubmission(target.id,state:.uncertain,error:"停止或核对未完成：\(error.localizedDescription)");report(error) }
    }
    func startPending(_ item: DownloadItem) async { await perform(.start, item: item) }
    func canRemoveHistory(_ item: DownloadItem) -> Bool {
        item.isHistory && !exporting.contains(item.url)
    }
    func clear(_ item: DownloadItem) async { _ = await clearHistory(ids: [item.id]) }
    func clearHistory(ids: Set<String>) async -> Bool {
        guard !updater.isUpdating, !isSubmitting, !isConfiguring, !reconnecting, !runtimeRecoveryPending else { return false }
        let selected = completed.filter { ids.contains($0.id) && canRemoveHistory($0) }
        guard !selected.isEmpty else { return false }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            notice = nil
            message = nil
            let backendItems = selected.filter { !$0.isArchived }
            if !backendItems.isEmpty { try await backend.post("delete", body: HistoryRemoval.body(items: backendItems)) }
            archive.remove(ids: Set(selected.map(\.id)))
            var records = ExportRegistry.records
            for item in selected {
                let key = ExportRegistry.recordKey(for: item.url, folder: item.folder)
                records.removeValue(forKey: key)
                exportErrors[key] = nil
            }
            ExportRegistry.records = records
            let removed = Set(selected.map(\.id))
            completed.removeAll { removed.contains($0.id) }
            await refresh()
            return true
        } catch {
            report(error)
            return false
        }
    }

    private func perform(_ action: DownloadAction, item: DownloadItem) async {
        if updater.isUpdating { message = "引擎更新中，请稍后重试。"; return }
        guard !isConfiguring, !reconnecting, !runtimeRecoveryPending else {message="后台正在配置或恢复，请稍后操作。";return}
        guard !isSubmitting else { message = "正在提交任务，请稍后重试。"; return }
        isSubmitting = true
        defer { isSubmitting = false }
        message = nil
        do {
            let request = try ActionRequest(action, item: item)
            try await backend.post(request.route, body: request.body)
        } catch { report(error) }
        await refresh()
    }
    func setDestination(_ url: URL) {
        destinationPath = url.path
        UserDefaults.standard.set(destinationPath, forKey: "downloadDestination")
    }
    func checkUpdates() async {
        guard !isSubmitting, !isConfiguring, !reconnecting, !runtimeRecoveryPending, !submissions.contains(where:{$0.state == .uncertain}) else { message = "请先完成提交、恢复或核对未决任务，再检查更新。"; return }
        await updater.checkIfNeeded(force: true)
        await refresh()
    }
    private var canConfigure: Bool {
        connection.isReady && !reconnecting && !isSubmitting && !isConfiguring && !runtimeRecoveryPending && !updater.isUpdating && items.isEmpty && pending.isEmpty && !submissions.contains(where: { $0.state == .uncertain || $0.state == .parsing || $0.state == .cancelling })
    }
    func reloadBrowserProfiles(_ browser:BrowserKind) async {
        let loadID=UUID();browserProfileLoadID=loadID
        isLoadingBrowserProfiles=true
        defer {if browserProfileLoadID==loadID {isLoadingBrowserProfiles=false}}
        do {
            let profiles=try await Task.detached {try NativeBrowserCookieReader.profiles(for:browser)}.value
            guard browserProfileLoadID==loadID,!Task.isCancelled else {return}
            browserProfiles=profiles
            if browserProfiles.isEmpty {browserCookieStatus="没有找到 \(browser.title) 的标准用户配置。请先打开该浏览器，或继续使用 Cookie 文件导入。"}
        } catch {if browserProfileLoadID==loadID {browserProfiles=[];browserCookieStatus=error.localizedDescription}}
    }
    @discardableResult func saveBrowserCookies(_ candidate:BrowserCookiePreferences) async -> Bool {
        guard canConfigure else {settingsMessage="请先完成下载、解析或引擎维护，再保存浏览器 Cookie 设置。";return false}
        isConfiguring=true;settingsMessage=nil
        defer {isConfiguring=false}
        do {
            if candidate.enabled {
                let profiles=try await Task.detached {try NativeBrowserCookieReader.profiles(for:candidate.browser)}.value
                guard profiles.contains(where:{$0.directory==candidate.profile}) else {throw AppError.message("未找到所选浏览器配置，请重新选择或先打开浏览器。")}
                if !networkEnabled {try await RuntimeSupport.enableNetworkOptions();networkEnabled=try await RuntimeSupport.networkEnabled()}
                try await RuntimeSupport.validateCookieMount()
            }
            browserCookies=candidate
            browserCookieStatus=candidate.enabled ? "已开启：下次从 \(candidate.browser.title) 读取对应网站会话，首次可能出现系统授权。设置保存不代表账号已登录。" : "浏览器读取已关闭；手动导入的会话文件（如有）仍可使用。"
            settingsMessage="网站会话来源已保存；账号登录未验证。"
            return true
        } catch {settingsMessage=error.localizedDescription;return false}
    }
    func checkBrowserAccess() async {
        guard canConfigure else {settingsMessage="请先完成任务或后台维护，再检查读取权限。";return}
        guard browserCookies.enabled else {settingsMessage="请先选择浏览器并主动开启、保存网站会话读取。";return}
        isConfiguring=true;settingsMessage=nil
        defer {isConfiguring=false}
        do {
            let sync=BrowserSessionSync(reader:cookieReader,files:cookieFiles)
            browserCookieStatus=try await sync.inspect(preferences:browserCookies,url:browserLoginURL.absoluteString)
            settingsMessage="本机读取检查完成。未向网站发起登录验证，也未创建下载任务。"
        } catch {browserCookieStatus=error.localizedDescription;settingsMessage=error.localizedDescription}
    }
    func clearIdleBrowserCookies() async {
        guard canConfigure else {settingsMessage="请先完成任务或核对未决提交，再清理会话文件。";return}
        isConfiguring=true;defer {isConfiguring=false}
        do {
            let history=try await backend.history()
            let keep=Set((history.queue+history.pending).compactMap(\.folder)+submissions.filter{$0.state != .failed}.map(\.id))
            await cookieFiles.cleanup(keeping:keep);settingsMessage="已清理闲置自动会话文件，手动导入文件仍保留。"
        } catch {settingsMessage="清理前无法核对后台，请恢复连接后再试。"}
    }
    func openBrowserLogin(_ browser:BrowserKind) {
        let ids:[BrowserKind:String]=[.chrome:"com.google.Chrome",.edge:"com.microsoft.edgemac",.firefox:"org.mozilla.firefox",.safari:"com.apple.Safari"]
        if let id=ids[browser],let app=NSWorkspace.shared.urlForApplication(withBundleIdentifier:id) {
            NSWorkspace.shared.open([browserLoginURL],withApplicationAt:app,configuration:NSWorkspace.OpenConfiguration())
        } else {settingsMessage="没有找到 \(browser.title)，请先安装或打开该浏览器。"}
    }
    func refreshSettings() async {
        do {
            hasCookies=try await backend.cookieStatus()
            let version=try await backend.version()
            serviceVersion="MeTube \(version.version) · yt-dlp \(version.engine)"
            networkEnabled=(try? await RuntimeSupport.networkEnabled()) ?? false
        } catch { settingsMessage="状态读取失败：\(error.localizedDescription)";hasCookies=nil }
    }
    func importCookies(_ data:Data) async {
        guard canConfigure else { settingsMessage="请先完成下载、解析或引擎维护，再更改 Cookie。";return }
        isConfiguring=true;settingsMessage=nil
        defer {isConfiguring=false}
        do {
            try await backend.uploadCookies(data)
            hasCookies=try await backend.cookieStatus()
            settingsMessage="Cookie 已导入到本机下载服务；有效性由视频网站决定。"
        } catch {settingsMessage=error.localizedDescription}
    }
    func removeCookies() async {
        guard canConfigure else {settingsMessage="请先完成下载、解析或引擎维护，再移除 Cookie。";return}
        isConfiguring=true;settingsMessage=nil
        defer {isConfiguring=false}
        do {try await backend.deleteCookies();hasCookies=try await backend.cookieStatus();settingsMessage="Cookie 已从下载服务移除。"}
        catch {settingsMessage=error.localizedDescription}
    }
    @discardableResult func saveOptions(_ candidate:DownloadOptions) async -> Bool {
        guard canConfigure else {settingsMessage="请先完成下载、解析或引擎维护，再保存设置。";return false}
        isConfiguring=true;settingsMessage=nil
        defer {isConfiguring=false}
        do {
            let validated=try candidate.validated()
            if !validated.ytdlOverrides.isEmpty && !networkEnabled {
                settingsMessage="正在备份并配置本机下载服务…"
                try await RuntimeSupport.enableNetworkOptions()
                networkEnabled=try await RuntimeSupport.networkEnabled()
            }
            options=validated
            settingsMessage="设置已保存；新任务使用这些参数，已有任务保持原参数。"
            await refresh()
            return true
        } catch {settingsMessage=error.localizedDescription;await refresh();return false}
    }
    func checkDiagnostics() async {
        guard !isConfiguring else {return}
        diagnostics="正在检查后台和依赖…"
        do {diagnostics=try await RuntimeSupport.diagnostics();await refreshSettings()}
        catch {diagnostics="检查未完成：\(error.localizedDescription)"}
    }
    func retryExport(_ item: DownloadItem) async {
        guard !isSubmitting, !exporting.contains(item.url), item.isComplete else { return }
        let key = ExportRegistry.recordKey(for: item.url, folder: item.folder)
        var records = ExportRegistry.records
        guard var record = records[key], record.exportedPath == nil else { return }
        record.destination = destinationPath
        record.generation = UUID().uuidString
        records[key] = record
        ExportRegistry.records = records
        exportErrors[key] = nil
        await exportFinished(only: item.url)
    }
    private func exportFinished(only url: String? = nil) async {
        for item in completed where item.isComplete && (url == nil || item.url == url) {
            // Do not start copying while a history deletion is in flight.
            guard !isSubmitting else { return }
            let recordKey = ExportRegistry.recordKey(for: item.url, folder: item.folder)
            guard let record = ExportRegistry.records[recordKey], record.exportedPath == nil,
                  !items.contains(where: { $0.url == item.url }), !pending.contains(where: { $0.url == item.url }),
                  !exporting.contains(item.url), exportErrors[recordKey] == nil else { continue }
            guard let filename = item.filename else {
                exportErrors[recordKey] = "下载服务未返回文件名，请重新下载或移除记录。"; continue
            }
            guard let source = SafeDownloadPath.resolve(filename: filename, folder: item.folder) else {
                exportErrors[recordKey] = "找不到下载缓存文件，请重新下载；也可以移除记录。"; continue
            }
            exporting.insert(item.url)
            do {
                let destination = URL(fileURLWithPath: record.destination, isDirectory: true)
                let result = try await Task.detached(priority: .utility) { try ExportFiles.copy(source, into: destination) }.value
                var records = ExportRegistry.records
                if records[recordKey]?.generation == record.generation {
                    records[recordKey]?.exportedPath = result.path
                    ExportRegistry.records = records
                }
            } catch {
                let detail = "保存失败：\(error.localizedDescription)\n原保存位置：\(record.destination)\n请选择可写入的文件夹，再重试保存。"
                exportErrors[recordKey] = detail
                Backend.log(detail)
            }
            exporting.remove(item.url)
        }
    }
    private func report(_ error: Error) {
        notice = nil
        message = error.localizedDescription
        Backend.log(error.localizedDescription)
    }
}
