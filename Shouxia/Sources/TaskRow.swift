import SwiftUI
import AppKit

struct TaskRow: View {
    let item: DownloadItem
    @ObservedObject var store: DownloadStore
    var pending = false
    @State private var showError = false
    @State private var hovered = false

    private var fileExists: Bool {
        guard let url = item.localFileURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
    private var isAudio: Bool { ["mp3", "m4a", "wav", "flac", "opus", "ogg"].contains(URL(fileURLWithPath: item.filename ?? "").pathExtension.lowercased()) }
    private var percentage: Double { min(100, max(0, item.percent ?? 0)) }
    private var detail: String {
        if item.isFailed { return "未能下载 · 查看原因或重试" }
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
                Image(systemName: item.isFailed ? "exclamationmark" : (item.isComplete ? (isAudio ? "waveform" : "play.rectangle") : "arrow.down"))
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(item.isFailed ? Ink.danger : Ink.mint)
            }.frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title).font(.custom("Sora-Medium",size:15)).lineLimit(2)
                    .help(item.title).textSelection(.enabled)
                Text(detail).font(TypeStyle.body(11)).foregroundStyle(item.isFailed ? Ink.danger : Ink.muted)
                    .monospacedDigit()
                if !item.isComplete && !item.isFailed && !pending {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Ink.line)
                            Capsule().fill(Ink.mint).frame(width: max(3, g.size.width * percentage / 100))
                        }
                    }.frame(height: 3).padding(.top, 3)
                }
                if showError {
                    Text(item.error ?? item.msg ?? "视频源未返回可下载内容。可打开原网页确认链接是否可访问。")
                        .font(TypeStyle.body(11)).foregroundStyle(Ink.danger)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if let exportError = store.exportErrors[ExportRegistry.recordKey(for: item.url, folder: item.folder)] {
                Button("重试保存") { Task { await store.retryExport(item) } }.buttonStyle(.plain).font(TypeStyle.body(11)).foregroundStyle(Ink.danger).help(exportError)
            } else if store.exporting.contains(item.url) {
                Text("保存中…").font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
            } else if item.isComplete {
                HStack(spacing: 2) {
                    GlyphButton(symbol: "play.fill", title: "打开文件") { FileActions.open(item) }.disabled(!fileExists)
                    GlyphButton(symbol: "folder", title: "在 Finder 中显示") { FileActions.reveal(item) }.disabled(!fileExists)
                }
            } else if item.isFailed {
                GlyphButton(symbol: "info.circle", title: "查看失败原因") { showError.toggle() }
                GlyphButton(symbol: "arrow.clockwise", title: "重试下载") { Task { await store.retry(item) } }
            } else if pending {
                GlyphButton(symbol: "play.fill", title: "开始下载") { Task { await store.startPending(item) } }
                GlyphButton(symbol: "xmark", title: "取消等待") { Task { await store.cancel(item) } }
            } else {
                Text("\(Int(percentage))%").font(TypeStyle.heading(18)).foregroundStyle(Ink.mint)
                    .frame(width: 38, alignment: .trailing)
                GlyphButton(symbol: "xmark", title: "取消下载") { Task { await store.cancel(item) } }
            }
            Menu {
                if let url = URL(string: item.url), ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                    Button("打开原网页") { NSWorkspace.shared.open(url) }
                }
                Button("复制原链接") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.url, forType: .string)
                }
                if item.isComplete || item.isFailed {
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

        .onHover { hovered = $0 }
        .onDrag {
            if fileExists, let url = item.localFileURL, let provider = NSItemProvider(contentsOf: url) { return provider }
            return NSItemProvider(object: item.url as NSString)
        }
    }
}
