import SwiftUI
import AppKit

struct TaskRow: View {
    let item: DownloadItem
    @ObservedObject var store: DownloadStore
    var pending = false
    @State private var hovered = false
    @State private var editingRetry = false

    private var exportError: String? {
        store.exportErrors[ExportRegistry.recordKey(for: item.url, folder: item.folder)]
    }

    private var fileExists: Bool {
        guard let url = item.localFileURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private var percentage: Double { min(100, max(0, item.percent ?? 0)) }
    private var detail: String {
        if item.isFailed { return DownloadFailure.classify(item.error ?? item.msg ?? "").title }
        if item.isComplete {
            let size = ByteCountFormatter.string(fromByteCount: Int64(item.size ?? 0), countStyle: .file)
            return "\(item.platform)  ·  \(item.filename.map { URL(fileURLWithPath: $0).pathExtension.uppercased() } ?? "视频")  ·  \(size)" + (fileExists ? "" : "  ·  未找到本地文件")
        }
        if pending { return "等待开始" }
        if let speed = item.speed, speed > 0 {
            let rate = ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file)
            let eta = item.eta.map { " · 约 \(Int($0)) 秒" } ?? ""
            return "\(rate)/s\(eta)"
        }
        return percentage >= 100 ? "正在合并音视频…" : "正在连接视频源…"
    }
    var body: some View {
        HStack(alignment: .center, spacing: 15) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Ink.surface)
                Image(systemName: item.isFailed ? "exclamationmark" : (item.isComplete ? (item.isAudio ? "waveform" : "play.rectangle") : "arrow.down"))
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(item.isFailed ? Ink.danger : Ink.mint)
            }.frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title).font(.custom("Sora-Medium",size:15)).lineLimit(2)
                    .help(item.title).textSelection(.enabled)
                if !item.isFailed {
                    Text(detail).font(TypeStyle.body(11)).foregroundStyle(Ink.muted).monospacedDigit()
                }
                if !item.isComplete && !item.isFailed && !pending {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Ink.line)
                            Capsule().fill(Ink.mint).frame(width: max(3, g.size.width * percentage / 100))
                        }
                    }.frame(height: 3).padding(.top, 3)
                }
                if let exportError {
                    Text(exportError.contains("缓存文件") || exportError.contains("未返回文件名") ? "下载文件不完整" : "文件保存失败")
                        .font(TypeStyle.body(11)).foregroundStyle(Ink.danger)
                }
                if item.isFailed {
                    FailureDetails(raw:item.error ?? item.msg ?? "视频源未返回可下载内容。",store:store)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if exportError != nil {
                VStack(alignment: .trailing, spacing: 10) {
                    Button("重试保存") { Task { await store.retryExport(item) } }
                    Button("选择文件夹并重试") {
                        if FileActions.chooseFolder(store: store) {
                            Task { await store.retryExport(item) }
                        }
                    }
                }.buttonStyle(.plain).font(TypeStyle.body(11)).foregroundStyle(Ink.danger)
                    .disabled(store.isSubmitting || store.exporting.contains(item.url))
            } else if store.exporting.contains(item.url) {
                Text("保存中…").font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
            } else if item.isComplete {
                HStack(spacing: 2) {
                    if !item.isAudio {
                        GlyphButton(symbol: "scissors", title: "截取片段") { ClipWindow.shared.show(item.localFileURL) }
                    }
                    GlyphButton(symbol: "play.fill", title: "打开文件") { FileActions.open(item) }.disabled(!fileExists)
                    GlyphButton(symbol: "folder", title: "在 Finder 中显示") { FileActions.reveal(item) }.disabled(!fileExists)
                }
            } else if item.isFailed {
                VStack(spacing:12) {
                    Button("重试") { Task { await store.retry(item) } }
                    Button("修正后重试") { editingRetry=true }
                }.buttonStyle(.plain).font(TypeStyle.body(11)).foregroundStyle(Ink.mint).disabled(store.isSubmitting || store.isConfiguring || store.updater.isUpdating)
            } else if pending {
                GlyphButton(symbol: "play.fill", title: "开始下载") { Task { await store.startPending(item) } }
                GlyphButton(symbol: "xmark", title: "取消等待") { Task { await store.cancel(item) } }
            } else {
                Text("\(Int(percentage))%").font(TypeStyle.heading(18)).foregroundStyle(Ink.mint)
                    .frame(width: 38, alignment: .trailing)
                GlyphButton(symbol: "xmark", title: "取消下载") { Task { await store.cancel(item) } }
            }
            Menu {
                if let url = URL(string: store.originalURL(for:item)), ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                    Button("打开原网页") { NSWorkspace.shared.open(url) }
                }
                if item.isComplete && !item.isAudio {
                    Button("截取片段…") { ClipWindow.shared.show(item.localFileURL) }
                }
                Button("复制原链接") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(store.originalURL(for:item), forType: .string)
                }
                if store.originalURL(for:item) != item.url {
                    Button("复制规范链接") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(item.url,forType:.string) }
                }
                if store.canRemoveHistory(item) {
                    Divider()
                    Button("移除记录（保留文件）") { Task { await store.clear(item) } }
                }
            } label: { Image(systemName: "ellipsis").frame(width: 22, height: 28) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("更多操作")
            .accessibilityLabel("更多操作")
        }
        .padding(.vertical, 22).padding(.horizontal, 0)
        .background(hovered ? Ink.surface.opacity(0.5) : .clear)
        .overlay(alignment:.bottom) { Rectangle().fill(Ink.line).frame(height:1) }

        .sheet(isPresented:$editingRetry) { RetryEditor(item:item,store:store) }
        .onHover { hovered = $0 }
        .onDrag {
            if fileExists, let url = item.localFileURL, let provider = NSItemProvider(contentsOf: url) { return provider }
            return NSItemProvider(object: item.url as NSString)
        }
    }
}
