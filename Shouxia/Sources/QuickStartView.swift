import SwiftUI

struct QuickStartView: View {
    @ObservedObject var store: DownloadStore
    @ObservedObject var updater: EngineUpdater
    @Environment(\.dismiss) private var dismiss
    @State private var accessHelpExpanded=false
    private var maintenance: Bool { store.isConfiguring || store.isSubmitting || updater.isUpdating }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("快速上手").font(TypeStyle.heading(22))
                Spacer()
                Button("开始使用") { dismiss() }.keyboardShortcut(.defaultAction)
                    .accessibilityLabel("关闭快速上手，返回下载")
            }
            Text("粘贴链接，确认保存位置，下载后即可打开或截取。").font(TypeStyle.body(13)).foregroundStyle(Ink.muted)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    guideSection("先确认后台就绪", "本版本依赖已配置的本机 Colima（metube 配置）、Docker（colima-metube 上下文）和 MeTube（metube 容器），不会自动安装这些依赖。首次连接可能需要约一分钟。")
                    HStack {
                        Text(store.connection.label).foregroundStyle(Ink.muted)
                        Button("检查后台依赖") { Task { await store.checkDiagnostics() } }.disabled(store.isConfiguring)
                        Button("重新连接") { Task { await store.reconnect() } }.disabled(maintenance)
                    }
                    if !store.diagnostics.isEmpty {
                        Text(store.diagnostics).font(TypeStyle.body(11)).foregroundStyle(Ink.muted).textSelection(.enabled)
                    }
                    if let message = store.message {
                        Text(message).font(TypeStyle.body(11)).foregroundStyle(Ink.danger).textSelection(.enabled)
                    }
                    Divider()
                    guideSection("粘贴链接，选择视频或音频", "复制视频链接或整段分享文字，粘贴或拖入主窗口后点提取。视频建议先选最佳画质；音频会提取为 MP3。MP4 源格式只选择源站提供的格式，不会转码，也不保证源站提供所有画质。")
                    guideSection("确认保存位置", "提交前选择文件夹。任务保留提交时的位置；下载后软件会将文件保存到该位置，保存完成才可打开或截取。")
                    DestinationControl(store: store).disabled(maintenance)
                    Divider()
                    guideSection("失败时看简短原因", "按提示检查链接、网络或格式后重试。提交结果未确认时，先停止并核对，避免重复下载。")
                    Text("如果下载成功但保存失败，选择可写入的文件夹，再点“重试保存”；它会使用当前文件夹，通常无需重新下载。").font(TypeStyle.body(12)).foregroundStyle(Ink.muted)
                    guideSection("截取本地视频", "保存完成后点击剪刀，或使用菜单“截取本地视频…”。默认跟随原视频尺寸；也可选横屏、竖屏、方形等常用尺寸。拖动“预览大小”可放大缩小显示；导出按所选画面尺寸，等比完整显示。导出新的 MP4，保留源文件。")
                    Divider()
                    DisclosureGroup("网站访问辅助说明（可选）",isExpanded:$accessHelpExpanded) {
                        VStack(alignment:.leading,spacing:12) {
                    guideSection("网站访问辅助按需尝试", "先直接尝试下载。仅在实际错误与本机读取相关，或你希望尝试网站会话时，在下载设置中主动开启；软件才会读取所选浏览器配置的网站 Cookie。Cookie 可能来自访客会话，读取成功不能证明账号登录。")
                    Text("链接可从任意浏览器复制；会话来源由软件中保存的浏览器与配置决定，与复制来源及系统默认浏览器分开。会话经本机下载服务发送给对应网站，不上传到开发者服务器。").font(TypeStyle.body(12)).foregroundStyle(Ink.muted)
                    Text("只有本机读取确实失败时，才需检查对应访问权限；也可选择本次不读取浏览器信息重试。此操作不改变持久开关，手动导入文件仍可能使用。网站解析错误本身不能证明需要登录或会话。").font(TypeStyle.body(12)).foregroundStyle(Ink.muted)
                    Button("打开下载设置") {
                        store.quickStartOpenSettings = true
                        dismiss()
                    }.accessibilityHint("关闭快速上手后打开下载设置，可选择网站会话、格式和高级网络参数")
                        }.padding(.top,10)
                    }
                    Text("关闭主窗口后，软件仍在菜单栏运行。退出软件不会中断已提交的后台下载；重新打开后可继续查看结果。随时从帮助菜单重开本指南。").font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
                }.padding(.vertical, 4)
            }
        }
        .padding(26).frame(width: 590).frame(maxHeight: 700)
        .foregroundStyle(Ink.dark).background(Ink.paper).preferredColorScheme(.dark)
    }

    private func guideSection(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(TypeStyle.medium(15)).accessibilityAddTraits(.isHeader)
            Text(detail).font(TypeStyle.body(12)).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
}
