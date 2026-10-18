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
    @State private var advancedExpanded=false
    @State private var sessionExpanded=false
    @State private var privacyExpanded=false
    @State private var automaticDraft=true
    @State private var saving=false
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
            HStack { Text("下载设置").font(TypeStyle.heading(20)); Spacer(); Button("取消") { dismiss() }.buttonStyle(.plain).keyboardShortcut(.cancelAction).disabled(saving || store.isConfiguring) }
            if let message=store.settingsMessage { Text(message).font(TypeStyle.body(11)).textSelection(.enabled).fixedSize(horizontal:false,vertical:true) }
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    Text("保存位置（立即生效）").font(TypeStyle.medium(15))
                    DestinationControl(store:store).disabled(busy)
                    Text("已有任务保留提交时的保存位置；手动重试保存使用当前文件夹。").font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
                    Divider()
                    Text("视频格式").font(TypeStyle.medium(15))
                    Picker("视频格式",selection:$draft.videoFormat) { Text("原始最佳格式").tag("any"); Text("MP4 源格式").tag("mp4") }.disabled(busy)
                    Text("MP4 仅选择源站提供的格式，不进行转码；部分视频可能无匹配格式。画质与视频/音频在主窗口选择。").font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
                    Divider()
                    DisclosureGroup("网站访问辅助（可选）",isExpanded:$sessionExpanded) {
                        browserCookieSettings.padding(.top,10)
                    }
                    Divider()
                    DisclosureGroup("高级设置：手动 Cookie 与网络",isExpanded:$advancedExpanded) {
                        VStack(alignment:.leading,spacing:12) {
                            Text("手动 Cookie（操作立即生效）").font(TypeStyle.medium(15))
                            Text(store.hasCookies == true ? "已导入 · 有效性及账号登录未验证" : store.hasCookies == false ? "尚未导入 Cookie" : "Cookie 状态未知").foregroundStyle(Ink.muted)
                            Text("导入自己的 Netscape Cookie 文件（最多 1 MB）。与浏览器读取分开管理，关闭浏览器读取不会移除此文件。下载服务会将匹配的网站会话信息发送给对应网站。").font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
                            HStack {
                                Button("导入 Cookie 文件…",action:importCookies).accessibilityLabel("选择并导入 Cookie 文件")
                                Button("立即删除已导入文件") { confirmRemoval=true }.disabled(store.hasCookies != true).accessibilityLabel("删除已导入 Cookie")
                            }.disabled(busy)
                            if let importError { Text(importError).foregroundStyle(Ink.danger).textSelection(.enabled) }
                            Divider()
                            TextField("代理，如 http://127.0.0.1:7890",text:$draft.proxy).disabled(busy).accessibilityLabel("下载代理")
                            TextField("Referer（可选）",text:$draft.referer).disabled(busy).accessibilityLabel("请求来源 Referer")
                            TextField("User-Agent（可选）",text:$draft.userAgent).disabled(busy).accessibilityLabel("请求标识 User-Agent")
                            Text("支持无账号密码的 HTTP、HTTPS、SOCKS5 代理。本机地址会映射为 host.lima.internal；代理需允许虚拟机访问。保存网络参数可能备份并重启空闲后台，有任务时不能修改。").font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
                            Text(store.networkEnabled ? "后台网络参数已启用" : "首次保存网络参数时启用后台支持").font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
                        }.padding(.top,10)
                    }
                    Divider()
                    Text("引擎与后台").font(TypeStyle.medium(15))
                    Toggle("自动更新下载引擎",isOn:$automaticDraft).tint(Ink.mint).disabled(busy)
                    Text("每天检查；有下载时延后，退出应用后停止。").font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
                    Text(store.serviceVersion).textSelection(.enabled)
                    Text(updater.status).font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
                    HStack {
                        Button("立即检查并更新引擎") { Task { await store.checkUpdates() } }.disabled(busy)
                        Button("立即检查后台依赖") { Task { await store.checkDiagnostics() } }.disabled(store.isConfiguring)
                    }
                    if !store.diagnostics.isEmpty {
                        Text(store.diagnostics.components(separatedBy:"\n").first ?? "").font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
                        DisclosureGroup("后台依赖详情") {Text(store.diagnostics).font(TypeStyle.body(11)).textSelection(.enabled)}
                    }
                    Divider()
                    Text("原生安装包会准备本机 Colima 与下载后台。首次连接可能需要约一分钟；依赖缺失时可重新运行安装包修复。").font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
                    Button("打开运行日志") { FileActions.openLog() }.buttonStyle(.plain).accessibilityLabel("打开后台运行日志")
                }.font(TypeStyle.body(12)).textFieldStyle(.roundedBorder).padding(.vertical,3).disabled(saving)
            }
            HStack {
                Text("格式、会话与自动更新将在保存后生效。").font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
                Spacer()
                Button(saving ? "正在保存…" : "保存并关闭") {
                    saving=true
                    Task {
                        let saved=await store.saveSettings(options:draft,browser:browserDraft,automaticUpdates:automaticDraft)
                        saving=false
                        if saved {dismiss()}
                    }
                }.buttonStyle(SoftButtonStyle(primary:true)).keyboardShortcut(.defaultAction)
                    .disabled(busy || saving || !browserDraftReady || (browserDraft.enabled && (loadingProfiles || !selectedProfileAvailable)))
            }
        }.padding(26).frame(width:560).frame(maxHeight:700).foregroundStyle(Ink.dark).background(Ink.paper).preferredColorScheme(.dark)
            .interactiveDismissDisabled(saving || store.isConfiguring)
            .task {
                draft=store.options; browserDraft=store.browserCookies; automaticDraft=updater.automaticEnabled
                sessionExpanded=store.browserCookies.enabled
                profileSelections[browserDraft.browser]=browserDraft.profile; browserDraftReady=true
                await store.refreshSettings()
            }
            .task(id: "\(browserDraftReady):\(sessionExpanded):\(browserDraft.browser.rawValue):\(profileReload)") {
                guard browserDraftReady,sessionExpanded else { return }
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
            Text("网站会话（可选）").font(TypeStyle.medium(15))
            Toggle("使用浏览器网站会话（可选）",isOn:$browserDraft.enabled).tint(Ink.mint).disabled(busy)
            Text("默认关闭，公开链接可先直接尝试。开启后仅读取所选配置的网站 Cookie；读取成功不代表账号已登录。").font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
            if browserDraft.browser == .safari {
                Text("Safari 读取被系统拒绝时，可为本应用开启完全磁盘访问；也可在失败任务中点“跳过浏览器重试”，仅跳过本次读取。").font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
            } else if browserDraft.browser == .chrome || browserDraft.browser == .edge {
                Text("读取加密会话时，macOS 可能请求钥匙串访问授权。").font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
            }
            Picker("会话来源浏览器",selection:browserSelection) {
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
                    Text("未找到标准配置。请先打开所选浏览器，再刷新配置；也可保持关闭并尝试公开链接。").font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
                } else if !selectedProfileAvailable {
                    Text("之前选择的配置已不可用。请重新选择你要使用的配置并保存。").font(TypeStyle.body(11)).foregroundStyle(Ink.danger)
                }
            }
            HStack {
                Button("打开所选浏览器") { store.openBrowserLogin(browserDraft.browser) }
                Button("刷新配置") { loadedBrowser=nil; profileReload += 1 }.disabled(loadingProfiles)
                if browserDraft.browser == .safari { Button("Safari 访问权限") { openPrivacySettings() } }
            }.buttonStyle(.plain).foregroundStyle(Ink.mint)
            Text("链接可从任意浏览器复制；会话只来自上方所选配置，与默认浏览器无关。").font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
            if browserDraft != store.browserCookies {
                Text("选择尚未保存，当前任务仍使用已保存的设置。").font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
            }
            Button("立即检查已保存配置的读取权限") { Task { await store.checkBrowserAccess() } }
                .disabled(busy || !store.browserCookies.enabled || browserDraft != store.browserCookies)
                .accessibilityHint("使用已保存的设置检查对应网站会话是否可读取，不验证账号登录")
            Text("检查使用已保存的配置；不验证账号登录。").font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
            Text("最近状态：\(store.browserCookieStatus)").font(TypeStyle.body(11)).foregroundStyle(Ink.muted).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
            DisclosureGroup("隐私与会话清理",isExpanded:$privacyExpanded) {
                Text("不读取密码或历史记录。会话经本机服务发送给对应网站，不上传到开发者服务器。Safari 使用默认存储；Firefox 不读取容器或分区会话。").font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
            Button("立即清理闲置自动会话文件") { Task { await store.clearIdleBrowserCookies() } }.buttonStyle(.plain).foregroundStyle(Ink.mint).disabled(busy)
            Text("活动任务文件保留到后台确认结束；不影响手动导入文件。").font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
            }
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
