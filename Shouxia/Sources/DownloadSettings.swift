import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct EngineSettings:View {
    @ObservedObject var store:DownloadStore
    @ObservedObject var updater:EngineUpdater
    @Environment(\.dismiss) private var dismiss
    @State private var draft=DownloadOptions()
    @State private var importError:String?
    @State private var confirmRemoval=false
    private var busy:Bool { store.isSubmitting || store.isConfiguring || updater.isUpdating || !store.items.isEmpty || !store.pending.isEmpty }
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            HStack { Text("下载设置").font(TypeStyle.heading(20)); Spacer(); Button("完成") { dismiss() }.buttonStyle(.plain).accessibilityLabel("关闭下载设置") }
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    Text("Cookie").font(TypeStyle.medium(15))
                    Text(store.hasCookies == true ? "已导入 · 不代表 Cookie 有效" : store.hasCookies == false ? "尚未导入 Cookie" : "Cookie 状态未知").foregroundStyle(Ink.muted)
                    Text("仅导入你自己导出的 Netscape Cookie 文件（最多 1 MB）。应用不会读取浏览器账户；网站仍可能要求重新登录。").font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
                    HStack {
                        Button("导入 Cookie 文件…",action:importCookies).accessibilityLabel("选择并导入 Cookie 文件")
                        Button("删除 Cookie") { confirmRemoval=true }.disabled(store.hasCookies != true).accessibilityLabel("删除已导入 Cookie")
                    }.disabled(busy)
                    if let importError { Text(importError).foregroundStyle(Ink.danger).textSelection(.enabled) }
                    Divider()
                    Text("格式与网络").font(TypeStyle.medium(15))
                    Picker("视频格式",selection:$draft.videoFormat) { Text("原始最佳格式").tag("any"); Text("MP4 源格式").tag("mp4") }.disabled(busy)
                    Text("MP4 仅选择源站提供的格式，不进行转码；部分视频可能无匹配格式。").font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
                    TextField("代理，如 http://127.0.0.1:7890",text:$draft.proxy).disabled(busy).accessibilityLabel("下载代理")
                    TextField("Referer（可选）",text:$draft.referer).disabled(busy).accessibilityLabel("请求来源 Referer")
                    TextField("User-Agent（可选）",text:$draft.userAgent).disabled(busy).accessibilityLabel("请求标识 User-Agent")
                    Text("支持无账号密码的 HTTP、HTTPS、SOCKS5 代理。本机地址会映射为 host.lima.internal；代理需允许虚拟机访问。保存网络参数可能备份并重启空闲后台，有任务时不能修改。").font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
                    Button(store.isConfiguring ? "正在配置…" : "保存格式与网络设置") { Task { if await store.saveOptions(draft) { draft=store.options } } }.buttonStyle(SoftButtonStyle(primary:true)).disabled(busy)
                    Text(store.networkEnabled ? "后台网络参数已启用" : "首次保存网络参数时启用后台支持").font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
                    if let message=store.settingsMessage { Text(message).font(TypeStyle.body(11)).textSelection(.enabled) }
                    Divider()
                    Text("引擎与后台").font(TypeStyle.medium(15))
                    Toggle("自动更新下载引擎",isOn:$updater.automaticEnabled).tint(Ink.mint).disabled(busy)
                    Text("每天检查；有下载时延后，退出应用后停止。").font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
                    Text("yt-dlp · \(updater.currentVersion)\n\(store.serviceVersion)").textSelection(.enabled)
                    Text(updater.status).font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
                    HStack {
                        Button("立即检查更新") { Task { await store.checkUpdates() } }.disabled(busy)
                        Button("检查后台依赖") { Task { await store.checkDiagnostics() } }.disabled(busy)
                    }
                    if !store.diagnostics.isEmpty { Text(store.diagnostics).font(TypeStyle.body(11)).textSelection(.enabled) }
                    Divider()
                    DestinationControl(store:store).disabled(busy)
                    Text("已有任务保留提交时的保存位置；手动重试保存使用当前文件夹。").font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
                    Button("打开运行日志") { FileActions.openLog() }.buttonStyle(.plain).accessibilityLabel("打开后台运行日志")
                }.font(TypeStyle.body(12)).textFieldStyle(.roundedBorder).padding(.vertical,3)
            }
        }.padding(26).frame(width:560).frame(maxHeight:700).foregroundStyle(Ink.dark).background(Ink.paper).preferredColorScheme(.dark)
            .task { draft=store.options; await store.refreshSettings() }
            .confirmationDialog("删除已导入的 Cookie？",isPresented:$confirmRemoval) { Button("删除 Cookie",role:.destructive) { Task { await store.removeCookies() } } }.dialogIcon(Image(systemName:"key"))
    }
    private func importCookies() {
        let panel=NSOpenPanel(); panel.allowedContentTypes=[.plainText,.text]; panel.allowsMultipleSelection=false; panel.canChooseDirectories=false
        guard panel.runModal() == .OK, let url=panel.url else { return }
        do {
            let values=try url.resourceValues(forKeys:[.fileSizeKey,.isRegularFileKey])
            guard values.isRegularFile == true, let size=values.fileSize, size <= 1_000_000 else { throw AppError.message("请选择不超过 1 MB 的 Cookie 文本文件。") }
            let data=try Data(contentsOf:url); importError=nil
            Task { await store.importCookies(data) }
        } catch { importError=error.localizedDescription }
    }
}
