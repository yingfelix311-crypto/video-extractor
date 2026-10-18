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
                    guideSection("1. 粘贴链接，选择视频或音频", "粘贴视频链接或整段分享文字，点提取。画质以源站实际提供为准；音频保存为 MP3。")
                    guideSection("2. 确认保存位置", "任务保留提交时的文件夹。保存完成后可打开文件或截取。")
                    DestinationControl(store:store).disabled(maintenance)
                    guideSection("3. 查看任务结果", "在主窗口查看进度或失败原因。保存失败时，更换可写入文件夹后点“重试保存”；提交未确认时，先停止并核对。")
                    Divider()
                    Text(store.connection.label).font(TypeStyle.body(12)).foregroundStyle(Ink.muted)
                    if store.connection == .offline {
                        HStack {
                            Button("重新连接") {Task {await store.reconnect()}}.disabled(maintenance)
                            Button("检查后台依赖") {Task {await store.checkDiagnostics()}}.disabled(store.isConfiguring)
                        }
                    }
                    Text(store.diagnostics.components(separatedBy:"\n").first ?? "").font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
                    DisclosureGroup("后台运行详情") {
                        Text("后台使用本机 Colima、Docker 与 MeTube；首次连接可能需要约一分钟。").font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
                        Text(store.diagnostics).font(TypeStyle.body(11)).textSelection(.enabled)
                    }
                    DisclosureGroup("网站访问辅助说明（可选）",isExpanded:$accessHelpExpanded) {
                        VStack(alignment:.leading,spacing:12) {
                    Text("公开链接可先直接尝试。需要时在设置中开启所选浏览器配置的网站 Cookie 读取；本机可读不代表网站接受会话或账号已登录。").font(TypeStyle.body(12)).foregroundStyle(Ink.muted)
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
