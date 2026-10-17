import SwiftUI
import AppKit

struct FailureDetails:View {
    let raw:String
    @ObservedObject var store:DownloadStore
    private var failure:DownloadFailure { DownloadFailure.classify(raw) }
    var body:some View {
        VStack(alignment:.leading,spacing:7) {
            Text(failure.title).foregroundStyle(Ink.danger)
            Text(failure.message).foregroundStyle(Ink.muted)
            if [.cookies,.network,.service].contains(failure.kind) {
                Button(failure.actionTitle) { NotificationCenter.default.post(name:.showShouxiaWindow,object:nil); store.showSettings=true }.buttonStyle(.plain).foregroundStyle(Ink.mint).accessibilityLabel(failure.actionTitle)
            }
            DisclosureGroup("原始错误") {
                Text(raw).font(TypeStyle.body(10)).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
                Button("复制错误") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(raw,forType:.string) }.buttonStyle(.plain).accessibilityLabel("复制原始错误")
            }.foregroundStyle(Ink.muted)
        }.font(TypeStyle.body(11))
    }
}
struct SubmissionRow:View {
    let intent:SubmissionIntent
    @ObservedObject var store:DownloadStore
    private var progressing:Bool { [.syncing,.cancellingCookies,.parsing,.cancelling].contains(intent.state) }
    private var stopping:Bool { [.cancellingCookies,.cancelling].contains(intent.state) }
    private var title:String {
        switch intent.state {
        case .syncing: return "正在读取浏览器网站会话…"
        case .cancellingCookies: return "正在停止会话读取…"
        case .parsing: return "正在解析链接…"
        case .cancelling: return "正在停止并核对…"
        case .uncertain: return "提交结果尚未确认"
        case .failed: return "未能提交下载"
        }
    }
    private var cancelTitle:String { intent.state == .uncertain ? "停止并核对" : intent.state == .syncing || intent.state == .cancellingCookies ? "取消同步" : "取消解析" }
    var body:some View {
        HStack(alignment:.top,spacing:15) {
            if progressing { ProgressView().controlSize(.small).frame(width:46,height:46).accessibilityLabel(title) }
            else { Image(systemName:"exclamationmark.circle").foregroundStyle(Ink.danger).frame(width:46,height:46) }
            VStack(alignment:.leading,spacing:7) {
                Text(title).font(TypeStyle.medium(13))
                if intent.state == .syncing || intent.state == .cancellingCookies { Text("仅读取当前网站的会话信息，尚未提交下载；不代表账号已登录。").foregroundStyle(Ink.muted) }
                Text(intent.summary).foregroundStyle(Ink.muted)
                Text(intent.link.originalURL).lineLimit(2).textSelection(.enabled)
                if intent.link.wasNormalized { Text("已转换为：\(intent.link.canonicalURL)").foregroundStyle(Ink.muted).textSelection(.enabled) }
                if let error=intent.error { FailureDetails(raw:error,store:store) }
                if intent.state == .uncertain { Text("请先停止并核对后台任务，避免重复下载。").foregroundStyle(Ink.muted) }
            }.font(TypeStyle.body(11)).frame(maxWidth:.infinity,alignment:.leading)
            if intent.state == .failed {
                VStack(spacing:12) {
                    Button("重试") { Task { await store.retrySubmission(intent) } }.accessibilityLabel("重试失败的提交").disabled(store.isSubmitting || store.isConfiguring)
                    if store.browserCookies.enabled, intent.browserSessionRequested != false, DownloadFailure.classify(intent.error ?? "").kind == .cookies {
                        Button("本次不读取浏览器重试") {Task {await store.retrySubmissionWithoutBrowser(intent)}}.accessibilityLabel("本次不读取浏览器信息并重试").disabled(store.isSubmitting || store.isConfiguring)
                    }
                    Button("移除") { store.dismissSubmission(intent.id) }.accessibilityLabel("移除失败的提交")
                }.buttonStyle(.plain).foregroundStyle(Ink.mint)
            } else {
                Button(cancelTitle) { Task { await store.cancelSubmission(intent.id) } }.buttonStyle(.plain).foregroundStyle(Ink.mint).disabled(stopping).accessibilityLabel(cancelTitle)
            }
        }.padding(.vertical,20).overlay(alignment:.bottom) { Rectangle().fill(Ink.line).frame(height:1) }
    }
}
