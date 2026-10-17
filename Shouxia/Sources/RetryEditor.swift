import SwiftUI

struct RetryEditor:View {
    let item:DownloadItem
    @ObservedObject var store:DownloadStore
    @Environment(\.dismiss) private var dismiss
    @State private var link=""
    @State private var quality="best"
    @State private var audioOnly=false
    @State private var options=DownloadOptions()
    @State private var working=false
    @State private var showNetworkSettings=false
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            HStack { Text("修正后重试").font(TypeStyle.heading(20)); Spacer(); Button("取消") { dismiss() } }
            TextField("视频链接",text:$link).textFieldStyle(.roundedBorder).accessibilityLabel("重试原始链接")
            HStack { FormatControl(audioOnly:$audioOnly); QualityControl(quality:$quality).disabled(audioOnly) }
            Picker("视频格式",selection:$options.videoFormat) { Text("原始最佳格式").tag("any"); Text("MP4 源格式").tag("mp4") }.disabled(audioOnly)
            Text(store.browserCookies.enabled ? "保留此任务提交时的网络参数和保存目录。支持的平台会重新读取所选浏览器的最新 Cookie。" : "保留此任务提交时的网络参数和保存目录。Cookie 使用当前手动导入的文件；可在设置中开启浏览器自动同步。").font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
            HStack {
                Button("Cookie 与网络设置") { showNetworkSettings=true }
                Button("使用当前网络设置") {
                    let format=options.videoFormat
                    options=store.options;options.videoFormat=format
                }
            }.buttonStyle(.plain).foregroundStyle(Ink.mint)
            Text(options.ytdlOverrides.isEmpty ? "本次重试：不附加网络参数" : "本次重试：附加 \(options.ytdlOverrides.keys.sorted().joined(separator: "、"))")
                .font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
            if let message=store.message { FailureDetails(raw:message,store:store) }
            Button(working ? "正在提交…" : "提交重试") {
                working=true
                Task { let accepted=await store.retry(item,link:link,quality:quality,audioOnly:audioOnly,options:options); working=false; if accepted { dismiss() } }
            }.buttonStyle(SoftButtonStyle(primary:true)).disabled(working || store.isSubmitting || store.isConfiguring || store.updater.isUpdating).accessibilityLabel("使用修正参数重试下载")
        }.padding(26).frame(width:510).foregroundStyle(Ink.dark).background(Ink.paper).preferredColorScheme(.dark)
            .sheet(isPresented:$showNetworkSettings) { EngineSettings(store:store,updater:store.updater) }
            .onAppear {
                let record=ExportRegistry.records[ExportRegistry.recordKey(for:item.url,folder:item.folder)]
                link=store.originalURL(for:item); quality=record?.quality ?? item.quality ?? "best"; audioOnly=record?.audioOnly ?? item.isAudio
                options=store.retryOptions(for:item)
            }
    }
}
