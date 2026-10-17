import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct EngineSettings:View {
    @ObservedObject var store:DownloadStore
    @ObservedObject var updater:EngineUpdater
    @Environment(\.dismiss) private var dismiss
    @State private var draft=DownloadOptions()
    @State private var browserDraft=BrowserCookiePreferences()
    @State private var browserDraftReady=false
    @State private var loadedBrowser:BrowserKind?
    @State private var profileSelections:[BrowserKind:String]=[:]
    @State private var profileReload=0
    @State private var importError:String?
    @State private var confirmRemoval=false
    private var busy:Bool { !store.connection.isReady || store.runtimeRecoveryPending || store.isSubmitting || store.isConfiguring || updater.isUpdating || !store.items.isEmpty || !store.pending.isEmpty || store.submissions.contains { $0.state != .failed } }
    private var profiles:[BrowserProfile] { loadedBrowser == browserDraft.browser ? store.browserProfiles.filter { $0.browser == browserDraft.browser } : [] }
    private var loadingProfiles:Bool { loadedBrowser != browserDraft.browser || store.isLoadingBrowserProfiles }
    private var selectedProfileAvailable:Bool { profiles.contains { $0.directory == browserDraft.profile } }
    private var browserSelection:Binding<BrowserKind> {
        Binding(get:{ browserDraft.browser },set:{ browser in
            profileSelections[browserDraft.browser]=browserDraft.profile
            browserDraft.browser=browser
            browserDraft.profile=profileSelections[browser] ?? ""
            loadedBrowser=nil
        })
    }
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            HStack { Text("下载设置").font(TypeStyle.heading(20)); Spacer(); Button("完成") { dismiss() }.buttonStyle(.plain).accessibilityLabel("关闭下载设置") }
            if let message=store.settingsMessage { Text(message).font(TypeStyle.body(11)).textSelection(.enabled).fixedSize(horizontal:false,vertical:true) }
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    browserCookieSettings
                    Divider()
                    Text("手动导入 Cookie").font(TypeStyle.medium(15))
                    Text(store.hasCookies == true ? "已导入 · 不代表 Cookie 有效" : store.hasCookies == false ? "尚未导入 Cookie" : "Cookie 状态未知").foregroundStyle(Ink.muted)
                    Text("导入你自己导出的 Netscape Cookie 文件（最多 1 MB）。与自动同步分开管理；网站仍可能要求重新登录。").font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
                    HStack {
                        Button("导入 Cookie 文件…",action:importCookies).accessibilityLabel("选择并导入 Cookie 文件")
                        Button("删除已导入文件") { confirmRemoval=true }.disabled(store.hasCookies != true).accessibilityLabel("删除已导入 Cookie")
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
                    Divider()
                    Text("引擎与后台").font(TypeStyle.medium(15))
                    Toggle("自动更新下载引擎",isOn:$updater.automaticEnabled).tint(Ink.mint).disabled(busy)
                    Text("每天检查；有下载时延后，退出应用后停止。").font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
                    Text("yt-dlp · \(updater.currentVersion)\n\(store.serviceVersion)").textSelection(.enabled)
                    Text(updater.status).font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
                    HStack {
                        Button("立即检查更新") { Task { await store.checkUpdates() } }.disabled(busy)
                        Button("检查后台依赖") { Task { await store.checkDiagnostics() } }.disabled(store.isConfiguring)
                    }
                    if !store.diagnostics.isEmpty { Text(store.diagnostics).font(TypeStyle.body(11)).textSelection(.enabled) }
                    Divider()
                    DestinationControl(store:store).disabled(busy)
                    Text("已有任务保留提交时的保存位置；手动重试保存使用当前文件夹。").font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
                    Button("打开运行日志") { FileActions.openLog() }.buttonStyle(.plain).accessibilityLabel("打开后台运行日志")
                }.font(TypeStyle.body(12)).textFieldStyle(.roundedBorder).padding(.vertical,3)
            }
        }.padding(26).frame(width:560).frame(maxHeight:700).foregroundStyle(Ink.dark).background(Ink.paper).preferredColorScheme(.dark)
            .task {
                draft=store.options; browserDraft=store.browserCookies
                profileSelections[browserDraft.browser]=browserDraft.profile; browserDraftReady=true
                await store.refreshSettings()
            }
            .task(id: "\(browserDraftReady):\(browserDraft.browser.rawValue):\(profileReload)") {
                guard browserDraftReady else { return }
                let browser=browserDraft.browser
                await store.reloadBrowserProfiles(browser)
                guard !Task.isCancelled, browserDraft.browser == browser else { return }
                loadedBrowser=browser
                // A new browser gets its first available profile. Keep an existing
                // choice visible if it disappears, rather than silently switching accounts.
                if browserDraft.profile.isEmpty, let first=profiles.first {
                    browserDraft.profile=first.directory
                    profileSelections[browser]=first.directory
                }
            }
            .confirmationDialog("删除已导入的 Cookie？",isPresented:$confirmRemoval) { Button("删除 Cookie",role:.destructive) { Task { await store.removeCookies() } } }.dialogIcon(Image(systemName:"key"))
    }
    private var browserCookieSettings:some View {
        VStack(alignment:.leading,spacing:12) {
            Text("浏览器登录状态").font(TypeStyle.medium(15))
            Toggle("自动同步浏览器 Cookie",isOn:$browserDraft.enabled).tint(Ink.mint).disabled(busy)
            Text("默认关闭。选择你自己的浏览器配置并保存后，每次提交或重试时只读取对应平台的 Cookie；首次可能出现 macOS 钥匙串或完全磁盘访问权限提示。").font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
            Picker("浏览器",selection:browserSelection) {
                ForEach(BrowserKind.allCases) { browser in Text(browser.title).tag(browser) }
            }.disabled(busy || !browserDraftReady)
            if loadingProfiles {
                HStack(spacing:8) { ProgressView().controlSize(.small); Text("正在查找本机浏览器配置…").foregroundStyle(Ink.muted) }
            } else {
                Picker("用户配置",selection:$browserDraft.profile) {
                    if !selectedProfileAvailable {
                        Text(browserDraft.profile.isEmpty ? "未找到可用配置" : "不可用：\(browserDraft.profile)").tag(browserDraft.profile)
                    }
                    ForEach(profiles) { profile in Text(profile.name).tag(profile.directory) }
                }.disabled(busy || profiles.isEmpty)
                if profiles.isEmpty {
                    Text("未找到标准配置。请先打开所选浏览器并登录网站，再刷新配置；也可关闭自动同步，使用手动导入。").font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
                } else if !selectedProfileAvailable {
                    Text("之前选择的配置已不可用。请重新选择用户配置，确认账户后保存。").font(TypeStyle.body(11)).foregroundStyle(Ink.danger)
                }
            }
            HStack {
                Button("打开所选浏览器") { store.openBrowserLogin(browserDraft.browser) }
                Button("刷新配置") { loadedBrowser=nil; profileReload += 1 }.disabled(loadingProfiles)
                Button("系统访问权限") { openPrivacySettings() }
            }.buttonStyle(.plain).foregroundStyle(Ink.mint)
            Text("打开浏览器后，请切换到上方所选配置登录。Safari 使用默认存储；Firefox 不读取容器或分区会话。").font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
            Text("适用：抖音、YouTube、Bilibili、TikTok、Instagram、X、小红书、快手。仅本机处理，不读取密码或历史记录。Cookie 是否有效由网站决定。").font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
            Button(store.isConfiguring ? "正在保存…" : "保存浏览器 Cookie 设置") {
                let candidate=browserDraft
                Task { if await store.saveBrowserCookies(candidate) { browserDraft=store.browserCookies } }
            }.buttonStyle(SoftButtonStyle(primary:true)).disabled(busy || !browserDraftReady || (browserDraft.enabled && (loadingProfiles || !selectedProfileAvailable)))
            if browserDraft != store.browserCookies {
                Text("选择尚未保存，当前任务仍使用已保存的设置。").font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
            }
            Text("最近状态：\(store.browserCookieStatus)").font(TypeStyle.body(11)).foregroundStyle(Ink.muted).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
            Button("清理闲置自动会话文件") { Task { await store.clearIdleBrowserCookies() } }.buttonStyle(.plain).foregroundStyle(Ink.mint).disabled(busy)
            Text("活动任务的会话文件保留到后台确认结束；清理不影响手动导入文件。").font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
        }
    }
    private func openPrivacySettings() {
        guard let url=URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
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
