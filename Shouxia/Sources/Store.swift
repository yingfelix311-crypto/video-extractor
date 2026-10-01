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
    @Published var destinationPath = UserDefaults.standard.string(forKey: "downloadDestination") ?? SafeDownloadPath.root.path
    @Published var exportErrors: [String: String] = [:]
    @Published private(set) var exporting: Set<String> = []
    let updater = EngineUpdater()
    private var maintenanceChecked = Date.distantPast
    private let backend = Backend()
    private var polling: Task<Void, Never>?
    private var reconnecting = false
    private var refreshing = false

    func start() {
        guard polling == nil else { return }
        polling = Task { [weak self] in
            await self?.updater.recoverIfNeeded()
            await self?.reconnect()
            await self?.updater.refreshVersion()
            while !Task.isCancelled {
                let seconds = self?.items.isEmpty == false ? 2 : 5
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { break }
                await self?.refresh()
                if let self, !self.isSubmitting, Date().timeIntervalSince(self.maintenanceChecked) > 60 {
                    self.maintenanceChecked = Date()
                    await self.updater.recoverIfNeeded()
                    await self.updater.checkIfNeeded()
                }
            }
        }
    }

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            let history = try await backend.history()
            items = history.queue
            completed = history.done.reversed()
            pending = history.pending
            connection = .ready
            await exportFinished()
        } catch {
            if connection != .starting { connection = .offline }
            // Retain the last successful snapshot during a transient outage.
            Backend.log("History: \(error.localizedDescription)")
        }
    }

    func reconnect() async {
        guard !reconnecting else { return }
        reconnecting = true
        defer { reconnecting = false }
        connection = .connecting
        message = nil
        await refresh()
        guard connection != .ready else { return }
        connection = .starting
        do {
            try await Backend.boot()
            for _ in 0..<3 {
                await refresh()
                if connection == .ready { return }
                try await Task.sleep(for: .seconds(1))
            }
            throw AppError.message("服务尚未就绪，请稍后重新连接。")
        } catch {
            connection = .offline
            report(error)
        }
    }

    func submit(_ text: String, quality: String, audioOnly: Bool) async -> Bool {
        guard !isSubmitting else { return false }
        guard !updater.isUpdating else { message = "下载引擎正在更新，完成后即可提取。"; return false }
        guard connection == .ready else { message = "下载服务尚未连接，请先重新连接。"; return false }
        do {
            let url = try LinkParser.extract(text)
            guard !exporting.contains(url), !items.contains(where: { $0.url == url }), !pending.contains(where: { $0.url == url }) else {
                message = "这个链接已有任务正在处理，请等待完成。"; return false
            }
            let selectedDestination = destinationPath
            let taskFolder = "VideoExtractor/" + UUID().uuidString
            isSubmitting = true
            submittingURL = url
            message = nil
            defer { isSubmitting = false; submittingURL = nil }
            // Persist intent before the request: a timeout or app exit must not lose
            // the destination of a task the server already accepted.
            var records = ExportRegistry.records
            records[taskFolder] = ExportRecord(destination: selectedDestination)
            ExportRegistry.records = records
            exportErrors[taskFolder] = nil
            try await backend.post("add", body: DownloadRequest.body(url: url, quality: quality, audioOnly: audioOnly, folder: taskFolder))
            await refresh()
            return true
        } catch {
            report(error)
            await refresh()
            return false
        }
    }

    func cancel(_ item: DownloadItem) async { await perform(.cancel, item: item) }
    func retry(_ item: DownloadItem) async { await perform(.retry, item: item) }
    func startPending(_ item: DownloadItem) async { await perform(.start, item: item) }
    func canRemoveHistory(_ item: DownloadItem) -> Bool {
        guard item.isHistory, !exporting.contains(item.url) else { return false }
        // Keep records needed for an unfinished or failed export so saving can be retried.
        let record = ExportRegistry.records[ExportRegistry.recordKey(for: item.url, folder: item.folder)]
        return !item.isComplete || record == nil || record?.exportedPath != nil
    }
    func clear(_ item: DownloadItem) async { _ = await clearHistory(ids: [item.url]) }
    func clearHistory(ids: Set<String>) async -> Bool {
        guard !updater.isUpdating, !isSubmitting else { return false }
        let selected = completed.filter { ids.contains($0.url) && canRemoveHistory($0) }
        guard !selected.isEmpty else { return false }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await backend.post("delete", body: HistoryRemoval.body(items: selected))
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
        guard !isSubmitting else { message = "正在提交任务，稍后检查更新。"; return }
        await updater.checkIfNeeded(force: true)
        await refresh()
    }
    func retryExport(_ item: DownloadItem) async {
        exportErrors[ExportRegistry.recordKey(for: item.url, folder: item.folder)] = nil
        await exportFinished()
    }
    private func exportFinished() async {
        for item in completed where item.isComplete {
            let recordKey = ExportRegistry.recordKey(for: item.url, folder: item.folder)
            guard let record = ExportRegistry.records[recordKey], record.exportedPath == nil,
                  !items.contains(where: { $0.url == item.url }), !pending.contains(where: { $0.url == item.url }),
                  !exporting.contains(item.url), exportErrors[recordKey] == nil,
                  let filename = item.filename else { continue }
            guard let source = SafeDownloadPath.resolve(filename: filename, folder: item.folder) else {
                exportErrors[recordKey] = "下载文件尚未找到，请刷新后重试保存。"; continue
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
            } catch { exportErrors[recordKey] = "保存失败：\(error.localizedDescription)" }
            exporting.remove(item.url)
        }
    }
    private func report(_ error: Error) {
        message = error.localizedDescription
        Backend.log(error.localizedDescription)
    }
}
