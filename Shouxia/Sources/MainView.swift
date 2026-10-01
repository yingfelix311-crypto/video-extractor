import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MainView: View {
    @ObservedObject var store: DownloadStore
    @ObservedObject var updater: EngineUpdater
    @Environment(\.openWindow) private var openWindow
    @State private var input = ""
    @AppStorage("downloadQuality") private var quality = "1080"
    @AppStorage("downloadAudioOnly") private var audioOnly = false
    @State private var dragOver = false
    @State private var filter = "全部"
    @State private var showSettings = false
    @State private var managingHistory = false
    @State private var selectedHistory = Set<String>()
    @FocusState private var inputFocused: Bool
    init(store:DownloadStore) { self.store=store; self.updater=store.updater }
    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            HStack {
                VStack(alignment:.leading,spacing:9) {
                    Text("Video Extractor").font(TypeStyle.heading(29)).tracking(-1.2)
                    Text("把喜欢的片段，带回来。").font(TypeStyle.body(13)).foregroundStyle(Ink.muted)
                }
                Spacer()
                Button { QuickWindow.shared.show(store:store) } label: { ReceiveMark(size:68) }.buttonStyle(.plain).help("打开快捷输入框").accessibilityLabel("快捷输入")
            }.padding(.top,37).padding(.bottom,26)
            HStack(spacing:12) {
                HStack(spacing:12) {
                    Image(systemName:"link").foregroundStyle(Ink.muted)
                    TextField("粘贴视频链接",text:$input).textFieldStyle(.plain).font(TypeStyle.body(15)).focused($inputFocused).onSubmit(submit).accessibilityLabel("视频链接")
                    Button("粘贴") { input=NSPasteboard.general.string(forType:.string) ?? ""; inputFocused=true }.buttonStyle(.plain).font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
                }.padding(.horizontal,16).frame(height:58).background(Ink.surface).clipShape(RoundedRectangle(cornerRadius:12))
                    .overlay(RoundedRectangle(cornerRadius:12).stroke(dragOver ? Ink.mint : Ink.line,lineWidth:1))
                    .onDrop(of:[.url,.plainText],isTargeted:$dragOver,perform:acceptDrop)
                Button(action:submit) { HStack(spacing:14) { Text(store.isSubmitting ? "解析中" : "提取"); Image(systemName:"arrow.up.right") }.frame(height:36) }
                    .buttonStyle(SoftButtonStyle(primary:true)).disabled(input.isEmpty || store.isSubmitting || updater.isUpdating || !store.connection.isReady)
            }
            HStack(spacing:20) {
                FormatControl(audioOnly:$audioOnly)
                QualityControl(quality:$quality).disabled(audioOnly)
                if audioOnly { Text("MP3").font(TypeStyle.body(11)).foregroundStyle(Ink.muted) }
                Spacer()
                Button("快捷输入") { QuickWindow.shared.show(store:store) }.buttonStyle(.plain).font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
            }.padding(.top,14)
            DestinationControl(store:store).padding(.top,15).padding(.bottom,23)
            if let message=store.message {
                HStack(alignment:.top) { Text(message).font(TypeStyle.body(12)).textSelection(.enabled); Spacer(); GlyphButton(symbol:"xmark",title:"关闭提示") { store.message=nil } }
                    .foregroundStyle(Ink.danger).padding(10).background(Ink.surface).clipShape(RoundedRectangle(cornerRadius:9)).padding(.bottom,12)
            }
            HStack {
                Text(audioOnly ? "音频任务" : "视频任务").font(TypeStyle.medium(13)); Text("/ \(visibleItems.count)").font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
                Spacer()
                ForEach(["全部","进行中","已完成"],id:\.self) { name in
                    Button(name) { filter=name }.buttonStyle(.plain).font(TypeStyle.body(11)).foregroundStyle(filter==name ? Ink.dark : Ink.muted)
                }
                Button(managingHistory ? "完成管理" : "管理记录") {
                    managingHistory.toggle(); selectedHistory.removeAll()
                }.buttonStyle(.plain).font(TypeStyle.body(11)).foregroundStyle(Ink.mint)
                    .disabled(!managingHistory && removableIDs.isEmpty)
            }.padding(.bottom,14)
            if managingHistory {
                HStack(spacing: 14) {
                    Button(!removableIDs.isEmpty && selectedHistory == removableIDs ? "取消全选" : "全选当前列表") {
                        selectedHistory = selectedHistory == removableIDs ? [] : removableIDs
                    }.disabled(removableIDs.isEmpty)
                    Text("仅移除记录，保留下载文件").foregroundStyle(Ink.muted)
                    Spacer()
                    Button("删除所选（\(selectedHistory.count)）") {
                        let ids = selectedHistory
                        Task { if await store.clearHistory(ids: ids) { selectedHistory.subtract(ids) } }
                    }.foregroundStyle(Ink.danger).disabled(selectedHistory.isEmpty || store.isSubmitting || updater.isUpdating)
                }.buttonStyle(.plain).font(TypeStyle.body(11)).padding(.bottom,12)
            }
            Rectangle().fill(Ink.line).frame(height:1)
            ScrollView {
                LazyVStack(spacing:0) {
                    ForEach(visibleItems) { item in
                        HStack(spacing: 12) {
                            if managingHistory {
                                if removableIDs.contains(item.url) {
                                    Button {
                                        if !selectedHistory.insert(item.url).inserted { selectedHistory.remove(item.url) }
                                    } label: {
                                        Image(systemName: selectedHistory.contains(item.url) ? "checkmark.square.fill" : "square")
                                            .foregroundStyle(selectedHistory.contains(item.url) ? Ink.mint : Ink.muted)
                                    }.buttonStyle(.plain).accessibilityLabel("选择记录：\(item.title)")
                                } else { Color.clear.frame(width: 14, height: 14) }
                            }
                            TaskRow(item:item,store:store,pending:store.pending.contains{$0.url==item.url})
                        }
                    }
                    if visibleItems.isEmpty {
                        VStack(spacing:12) { ReceiveMark(size:62); Text(filter == "进行中" ? "暂无进行中的\(audioOnly ? "音频" : "视频")任务" : filter == "已完成" ? "暂无已完成的\(audioOnly ? "音频" : "视频")任务" : "暂无\(audioOnly ? "音频" : "视频")任务，粘贴链接开始。").font(TypeStyle.body(13)).foregroundStyle(Ink.muted) }.frame(maxWidth:.infinity).padding(.vertical,35)
                    }
                }
            }.frame(maxHeight:.infinity)
            HStack(spacing:8) {
                Circle().fill(store.connection.isReady ? Ink.mint : Ink.muted).frame(width:5,height:5)
                Text(updater.isUpdating ? updater.status : store.connection.label).lineLimit(1)
                if !store.connection.isReady && !updater.isUpdating { Button("重新连接") { Task { await store.reconnect() } }.buttonStyle(.plain) }
                Spacer()
                GlyphButton(symbol:"folder",title:"打开保存文件夹") { FileActions.revealFolder(store.destinationPath) }
                GlyphButton(symbol:"arrow.clockwise",title:"刷新任务") { Task { await store.refresh() } }
                GlyphButton(symbol:"gearshape",title:"设置与更新") { showSettings=true }
            }.font(TypeStyle.body(11)).foregroundStyle(Ink.muted).padding(.vertical,12)
        }.padding(.horizontal,32).foregroundStyle(Ink.dark).background(Ink.paper)
            .frame(minWidth:740,minHeight:670)
            .sheet(isPresented:$showSettings) { EngineSettings(store:store,updater:updater) }
            .onAppear { inputFocused=true }
            .onChange(of: audioOnly) { _, _ in selectedHistory.removeAll() }
            .onChange(of: filter) { _, _ in selectedHistory.removeAll() }
            .onChange(of: removableIDs) { _, ids in selectedHistory.formIntersection(ids) }
            .onReceive(NotificationCenter.default.publisher(for:.showShouxiaWindow)) { _ in openWindow(id:"main"); NSApp.activate(ignoringOtherApps:true) }
    }
    private var visibleItems:[DownloadItem] {
        TaskList.visible(active: store.items, pending: store.pending, history: store.completed, audioOnly: audioOnly, filter: filter)
    }
    private var removableIDs: Set<String> {
        Set(visibleItems.filter { item in
            store.completed.contains { $0.url == item.url } && store.canRemoveHistory(item)
        }.map(\.url))
    }
    private func submit() {
        let captured=input
        Task { if await store.submit(captured,quality:quality,audioOnly:audioOnly), input==captured { input=""; filter="全部" } }
    }
    private func acceptDrop(_ providers:[NSItemProvider])->Bool {
        guard let provider=providers.first else {return false}
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            _=provider.loadObject(ofClass:URL.self) { url,_ in guard let url else{return}; Task{@MainActor in input=url.absoluteString; inputFocused=true} }; return true
        }
        if provider.canLoadObject(ofClass:NSString.self) {
            _=provider.loadObject(ofClass:NSString.self) { value,_ in guard let value=value as? String else{return}; Task{@MainActor in input=value; inputFocused=true} }; return true
        }
        return false
    }
}
struct FormatControl:View {
    @Binding var audioOnly:Bool
    var body:some View {
        HStack(spacing:4) {
            ForEach([false,true],id:\.self) { value in
                Button(value ? "音频" : "视频") { audioOnly=value }.buttonStyle(.plain).font(TypeStyle.medium(12)).foregroundStyle(audioOnly==value ? Ink.dark : Ink.muted).padding(.horizontal,15).padding(.vertical,7).background(audioOnly==value ? Ink.purple : .clear).clipShape(RoundedRectangle(cornerRadius:7))
            }
        }
    }
}
struct QualityControl:View {
    @Binding var quality:String
    @State private var expanded=false
    private var label:String { quality=="best" ? "最佳画质" : quality+"p" }
    var body:some View {
        Button { expanded.toggle() } label: { HStack(spacing:13) { Text(label); Image(systemName:"chevron.down").font(.system(size:9)) }.font(TypeStyle.body(12)).padding(7) }
            .buttonStyle(.plain).accessibilityLabel("画质：\(label)")
            .popover(isPresented:$expanded,arrowEdge:.bottom) {
                VStack(spacing:4) {
                    ForEach(["1080","720","480","best"],id:\.self) { value in
                        Button { quality=value; expanded=false } label: { HStack { Text(value=="best" ? "最佳画质" : value+"p"); Spacer(); if quality==value { Image(systemName:"checkmark").foregroundStyle(Ink.mint) } }.font(TypeStyle.body(13)).padding(10).background(quality==value ? Ink.purple : .clear).clipShape(RoundedRectangle(cornerRadius:6)) }.buttonStyle(.plain)
                    }
                }.padding(8).frame(width:165).foregroundStyle(Ink.dark).background(Ink.surface).preferredColorScheme(.dark)
            }
    }
}
struct DestinationControl:View {
    @ObservedObject var store:DownloadStore
    var compact=false
    var body:some View {
        HStack(spacing:9) {
            Text("保存到").foregroundStyle(Ink.muted)
            Button { FileActions.revealFolder(store.destinationPath) } label: { Text((store.destinationPath as NSString).abbreviatingWithTildeInPath).lineLimit(1).truncationMode(.middle) }.buttonStyle(.plain).help(store.destinationPath)
            if !compact { Spacer(minLength:0) }
            Button { FileActions.chooseFolder(store:store) } label: { Label(compact ? "更改" : "更改文件夹",systemImage:"folder") }.buttonStyle(.plain).foregroundStyle(Ink.muted).fixedSize()
        }.font(TypeStyle.body(11)).foregroundStyle(Ink.dark)
    }
}
struct QuickPanel:View {
    @ObservedObject var store:DownloadStore
    @ObservedObject var updater:EngineUpdater
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @State private var input=""
    @AppStorage("downloadQuality") private var quality="1080"
    @AppStorage("downloadAudioOnly") private var audioOnly=false
    @FocusState private var focused:Bool
    init(store:DownloadStore) { self.store=store; self.updater=store.updater }
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack(spacing:8) {
                TextField("粘贴视频链接",text:$input)
                    .textFieldStyle(.plain).font(TypeStyle.body(13)).focused($focused)
                    .onSubmit(submit).accessibilityLabel("快捷视频链接")
                    .padding(.horizontal,12).frame(height:38)
                    .background(Ink.surface).clipShape(RoundedRectangle(cornerRadius:10))
                Button(action:submit) {
                    Image(systemName:store.isSubmitting ? "hourglass" : "arrow.up.right").frame(width:12,height:16)
                }.buttonStyle(SoftButtonStyle(primary:true)).fixedSize()
                    .accessibilityLabel(store.isSubmitting ? "正在解析" : "提取")
                    .help("提取 · 回车 · 沿用主窗口的格式和画质")
                    .disabled(input.isEmpty || store.isSubmitting || updater.isUpdating || !store.connection.isReady)
            }
            HStack(spacing:8) {
                Image(systemName:"folder").foregroundStyle(Ink.muted)
                Button { FileActions.revealFolder(store.destinationPath) } label: {
                    Text(URL(fileURLWithPath:store.destinationPath).lastPathComponent).lineLimit(1).truncationMode(.middle)
                }.buttonStyle(.plain).help(store.destinationPath)
                Spacer(minLength:0)
                Button("更改") { FileActions.chooseFolder(store:store) }
                    .buttonStyle(.plain).foregroundStyle(Ink.muted).fixedSize()
            }.font(TypeStyle.body(11))
            if let message=store.message {
                Text(message).font(TypeStyle.body(11)).foregroundStyle(Ink.danger).fixedSize(horizontal:false,vertical:true)
            } else if !store.connection.isReady || updater.isUpdating {
                HStack {
                    Text(updater.isUpdating ? updater.status : store.connection.label)
                    if !store.connection.isReady && !updater.isUpdating {
                        Button("重新连接") { Task { await store.reconnect() } }.buttonStyle(.plain)
                    }
                }.font(TypeStyle.body(10)).foregroundStyle(Ink.muted)
            }
        }.padding(14).frame(width:320).foregroundStyle(Ink.dark).background(Ink.paper).preferredColorScheme(.dark)
            .onAppear { focused=true; store.start() }.onExitCommand { QuickWindow.shared.hide(); dismiss() }
            .onReceive(NotificationCenter.default.publisher(for:Notification.Name("focusQuickInput"))) { _ in
                focused=false
                DispatchQueue.main.async { focused=true }
            }
    }
    private func submit() {
        let captured=input
        Task { if await store.submit(captured,quality:quality,audioOnly:audioOnly),input==captured { input=""; QuickWindow.shared.hide(); dismiss() } }
    }
}
struct EngineSettings:View {
    @ObservedObject var store:DownloadStore
    @ObservedObject var updater:EngineUpdater
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            HStack { Text("设置与更新").font(TypeStyle.heading(20)); Spacer(); Button("完成") { dismiss() }.buttonStyle(.plain) }
            Toggle("自动更新下载引擎",isOn:$updater.automaticEnabled).tint(Ink.mint)
            Text("每天检查一次；有下载任务时延后。应用退出后停止检查，下次启动时补查。").font(TypeStyle.body(12)).foregroundStyle(Ink.muted)
            HStack { Text("yt-dlp"); Spacer(); Text(updater.currentVersion).textSelection(.enabled) }.font(TypeStyle.medium())
            Text(updater.status).font(TypeStyle.body(12)).foregroundStyle(Ink.muted)
            if let checked=updater.lastChecked { Text("上次检查：\(checked.formatted(date:.abbreviated,time:.shortened))").font(TypeStyle.body(11)).foregroundStyle(Ink.muted) }
            Button(updater.isUpdating ? "正在检查…" : "立即检查更新") { Task { await store.checkUpdates() } }.buttonStyle(SoftButtonStyle(primary:true)).disabled(updater.isUpdating || store.isSubmitting)
            Divider()
            DestinationControl(store:store)
            Text("自选目录的文件会在下载完成后保存。中转文件留在 Downloads/MeTube；已有任务自动保存到原位置，手动重试保存使用当前选择的文件夹。").font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
            Button("打开运行日志") { FileActions.openLog() }.buttonStyle(.plain).font(TypeStyle.body(12))
        }.padding(26).frame(width:480).foregroundStyle(Ink.dark).background(Ink.paper)
    }
}
@MainActor final class QuickWindow {
    static let shared=QuickWindow()
    private var panel:NSPanel?
    func show(store:DownloadStore) {
        if panel==nil {
            let panel=InputPanel(contentRect:NSRect(x:0,y:0,width:320,height:110),styleMask:[.titled,.closable,.fullSizeContentView],backing:.buffered,defer:false)
            panel.title="快捷提取"; panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent=true
            panel.isReleasedWhenClosed=false; panel.level = .floating; panel.isMovableByWindowBackground=true
            let content=NSHostingView(rootView:QuickPanel(store:store))
            content.sizingOptions = [.preferredContentSize]
            panel.contentView=content
            panel.setContentSize(content.fittingSize)
            panel.center(); self.panel=panel
        }
        NSApp.activate(ignoringOtherApps:true); panel?.center(); panel?.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { NotificationCenter.default.post(name:Notification.Name("focusQuickInput"),object:nil) }
    }
    func hide() { panel?.orderOut(nil) }
}
final class InputPanel:NSPanel { override var canBecomeKey:Bool {true}; override var canBecomeMain:Bool {true} }
