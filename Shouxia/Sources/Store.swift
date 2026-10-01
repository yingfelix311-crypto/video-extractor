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
    private let backend = Backend()
    private var polling: Task<Void, Never>?
    private var reconnecting = false
    private var refreshing = false

    func start() {
        guard polling == nil else { return }
        polling = Task { [weak self] in
            await self?.reconnect()
            while !Task.isCancelled {
                let seconds = self?.items.isEmpty == false ? 2 : 5
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { break }
                await self?.refresh()
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
        guard connection == .ready else { message = "下载服务尚未连接，请先重新连接。"; return false }
        do {
            let url = try LinkParser.extract(text)
            isSubmitting = true
            submittingURL = url
            message = nil
            defer { isSubmitting = false; submittingURL = nil }
            try await backend.post("add", body: DownloadRequest.body(url: url, quality: quality, audioOnly: audioOnly))
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
    func clear(_ item: DownloadItem) async { await perform(.clear, item: item) }

    private func perform(_ action: DownloadAction, item: DownloadItem) async {
        message = nil
        do {
            let request = try ActionRequest(action, item: item)
            try await backend.post(request.route, body: request.body)
        } catch { report(error) }
        await refresh()
    }
    private func report(_ error: Error) {
        message = error.localizedDescription
        Backend.log(error.localizedDescription)
    }
}
