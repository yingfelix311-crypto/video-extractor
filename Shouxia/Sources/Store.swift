import Foundation
import Combine

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
    @Published var message: String?
    @Published var isSubmitting = false
    @Published var submittingURL: String?
    @Published var notice: String?
    @Published var showSettings = false
    @Published private(set) var isConfiguring = false
    @Published private(set) var hasCookies: Bool?
    @Published private(set) var serviceVersion = "未检查"
    @Published var settingsMessage: String?
    @Published var diagnostics = "点击检查，查看后台和下载依赖状态。"
    @Published var networkEnabled = false
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
    private var cancellationRequested = false
    private var lastAcceptedURL: String?
    private var polling: Task<Void, Never>?
    private var reconnecting = false
    private var refreshing = false
    private var lastRecoveryAttempt = Date.distantPast

    init(backend: any BackendServing = Backend(), defaults: UserDefaults = .standard) {
        self.backend=backend; self.defaults=defaults
        options=defaults.data(forKey:"downloadOptionsV2").flatMap { try? JSONDecoder().decode(DownloadOptions.self,from:$0) } ?? DownloadOptions()
        submissions=(defaults.data(forKey:"submissionIntentsV2").flatMap { try? JSONDecoder().decode([SubmissionIntent].self,from:$0) } ?? []).map {
            var intent=$0
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
            completed = history.done.reversed()
            pending = history.pending
            connection = .ready
            let folders=Set((items+completed+pending).compactMap(\.folder))
            submissions.removeAll { folders.contains($0.id) && $0.state != .cancelling }
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

    func submit(_ text: String, quality: String, audioOnly: Bool, options selectedOptions: DownloadOptions? = nil, destination: String? = nil) async -> Bool {
        guard !isSubmitting else { return false }
        guard !isConfiguring else { message = "后台设置正在保存，请稍后提取。"; return false }
        guard !reconnecting else {message="下载服务正在连接，请稍后提取。";return false}
        guard !runtimeRecoveryPending else {message="后台恢复尚未完成，请先重新连接。";return false}
        guard !submissions.contains(where:{$0.state == .uncertain || $0.state == .cancelling}) else {message="请先停止并核对未决任务，再提交新链接。";return false}
        guard !updater.isUpdating else { message = "下载引擎正在更新，完成后即可提取。"; return false }
        guard connection == .ready else { message = "下载服务尚未连接，请先重新连接。"; return false }
        do {
            let link = try LinkParser.resolve(text)
            let url = link.canonicalURL
            let requestOptions = try (selectedOptions ?? options).validated()
            guard requestOptions.ytdlOverrides.isEmpty || networkEnabled else { message="请先在设置中启用并保存网络参数。";showSettings=true;return false }
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
            submissions.append(SubmissionIntent(id:taskFolder,link:link,quality:quality,audioOnly:audioOnly,options:requestOptions,destination:selectedDestination,createdAt:Date(),state:.parsing))
            defer { isSubmitting = false; submittingURL = nil; submissionTask=nil }
            // Persist intent before the request: a timeout or app exit must not lose
            // the destination of a task the server already accepted.
            var records = ExportRegistry.records
            records[taskFolder] = ExportRecord(destination: selectedDestination,originalURL:link.originalURL,canonicalURL:link.canonicalURL,quality:quality,audioOnly:audioOnly,options:requestOptions)
            ExportRegistry.records = records
            exportErrors[taskFolder] = nil
            let body=try DownloadRequest.body(url:url,quality:quality,audioOnly:audioOnly,folder:taskFolder,options:requestOptions)
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
                let unresolved=(error is URLError || error is CancellationError || !connection.isReady)
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
            _ = await clearHistory(ids:[item.url])
        }
        return accepted
    }
    func retrySubmission(_ intent: SubmissionIntent) async {
        guard intent.state == .failed else { return }
        _ = await submit(intent.link.originalURL,quality:intent.quality,audioOnly:intent.audioOnly,options:intent.options,destination:intent.destination)
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
        let target=id.flatMap { key in submissions.first(where:{$0.id==key}) } ?? submissions.first(where:{$0.state == .parsing || $0.state == .uncertain})
        guard let target else {return}
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
            notice=accepted.isEmpty ? "已停止解析并核对后台；已完成的文件仍会保留。" : "已停止解析并取消刚创建的下载任务。"
            await refresh()
        } catch { setSubmission(target.id,state:.uncertain,error:"停止或核对未完成：\(error.localizedDescription)");report(error) }
    }
    func startPending(_ item: DownloadItem) async { await perform(.start, item: item) }
    func canRemoveHistory(_ item: DownloadItem) -> Bool {
        item.isHistory && !exporting.contains(item.url)
    }
    func clear(_ item: DownloadItem) async { _ = await clearHistory(ids: [item.url]) }
    func clearHistory(ids: Set<String>) async -> Bool {
        guard !updater.isUpdating, !isSubmitting, !isConfiguring, !reconnecting, !runtimeRecoveryPending else { return false }
        let selected = completed.filter { ids.contains($0.url) && canRemoveHistory($0) }
        guard !selected.isEmpty else { return false }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await backend.post("delete", body: HistoryRemoval.body(items: selected))
            var records = ExportRegistry.records
            for item in selected {
                let key = ExportRegistry.recordKey(for: item.url, folder: item.folder)
                records.removeValue(forKey: key)
                exportErrors[key] = nil
            }
            ExportRegistry.records = records
            let removed = Set(selected.map(\.url))
            completed.removeAll { removed.contains($0.url) }
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
        message = error.localizedDescription
        Backend.log(error.localizedDescription)
    }
}
