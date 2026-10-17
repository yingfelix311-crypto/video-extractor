import Foundation

struct BrowserCookiePreferences: Codable, Equatable, Sendable {
    var enabled = false
    var browser: BrowserKind = .chrome
    var profile = "Default"
}

protocol TaskCookieServing: Sendable {
    func validateRuntime() async throws
    func prepare(_ cookies:[SessionCookie],scope:CookieScope,taskID:String) async throws -> String?
    func discard(taskID:String) async
    func cleanup(keeping taskIDs:Set<String>) async
}

/// One jar per request; the backend's manually imported cookie file is never replaced.
struct TaskCookieFiles: TaskCookieServing, Sendable {
    let downloadRoot:URL
    private let verifyRuntime:@Sendable () async throws -> Void
    var directory:URL { downloadRoot.appendingPathComponent(".video-extractor-sessions",isDirectory:true) }
    init(downloadRoot:URL = SafeDownloadPath.root,verifyRuntime:@escaping @Sendable () async throws -> Void = {try await RuntimeSupport.validateCookieMount()}) {
        self.downloadRoot=downloadRoot;self.verifyRuntime=verifyRuntime
    }
    func validateRuntime() async throws {try await verifyRuntime()}
    private func filename(_ taskID:String) throws -> String {
        let prefix="VideoExtractor/"
        guard taskID.hasPrefix(prefix),let id=UUID(uuidString:String(taskID.dropFirst(prefix.count))) else {throw AppError.message("Cookie 任务标识无效。")}
        return id.uuidString.lowercased()
    }
    private func checkedDirectory(create:Bool) throws -> Int32 {
        let fm=FileManager.default
        guard downloadRoot.standardizedFileURL.path == downloadRoot.resolvingSymlinksInPath().standardizedFileURL.path else {throw AppError.message("Cookie 缓存目录不能使用符号链接。")}
        if create && !fm.fileExists(atPath:directory.path) {
            try fm.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        }
        let fd=open(directory.path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
        guard fd >= 0 else {throw AppError.message("无法访问私有 Cookie 缓存目录，请检查下载目录权限。")}
        var info=stat()
        guard fstat(fd,&info)==0,info.st_uid==getuid(),fchmod(fd,0o700)==0 else {close(fd);throw AppError.message("Cookie 缓存目录的所有者或权限不正确。")}
        return fd
    }
    func prepare(_ cookies:[SessionCookie],scope:CookieScope,taskID:String) async throws -> String? {
        let name=try filename(taskID)
        let data=try BrowserCookieJar.netscape(cookies,scope:scope)
        // A valid jar with no rows must leave the backend's manual mode untouched.
        guard String(decoding:data,as:UTF8.self).split(whereSeparator:\.isNewline).contains(where:{!$0.hasPrefix("#") || $0.hasPrefix("#HttpOnly_")}) else {return nil}
        try CookieFile.validate(data)
        try Task.checkCancellation()
        try await validateRuntime()
        try Task.checkCancellation()
        let fd=try checkedDirectory(create:true);defer {close(fd)}
        guard mkdirat(fd,name,0o700)==0 else {throw AppError.message("无法创建此任务的私有 Cookie 目录。")}
        let taskDirectory=openat(fd,name,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
        guard taskDirectory >= 0 else {unlinkat(fd,name,AT_REMOVEDIR);throw AppError.message("无法访问此任务的私有 Cookie 目录。")}
        defer {close(taskDirectory)}
        let output=openat(taskDirectory,"cookies.txt",O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0o600)
        guard output >= 0 else {unlinkat(fd,name,AT_REMOVEDIR);throw AppError.message("无法创建此任务的私有 Cookie 文件。")}
        let handle=FileHandle(fileDescriptor:output,closeOnDealloc:true)
        do {
            try handle.write(contentsOf:data);try handle.synchronize();try handle.close()
            try Task.checkCancellation()
            return "/downloads/.video-extractor-sessions/"+name+"/cookies.txt"
        } catch {
            try? handle.close();unlinkat(taskDirectory,"cookies.txt",0);unlinkat(fd,name,AT_REMOVEDIR);throw error
        }
    }
    func discard(taskID:String) async {
        guard let name=try? filename(taskID),let fd=try? checkedDirectory(create:false) else {return}
        defer {close(fd)}
        remove(name,from:fd)
    }
    func cleanup(keeping taskIDs:Set<String>) async {
        guard let fd=try? checkedDirectory(create:false) else {return}
        defer {close(fd)}
        let names=Set(taskIDs.compactMap{try? filename($0)})
        guard let contents=try? FileManager.default.contentsOfDirectory(atPath:directory.path) else {return}
        for name in contents where UUID(uuidString:name) != nil && !names.contains(name) {
            remove(name,from:fd)
        }
    }
    private func remove(_ name:String,from fd:Int32) {
        let child=openat(fd,name,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
        guard child >= 0 else {return}
        defer {close(child)}
        _ = unlinkat(child,"cookies.txt",0)
        // Removing the parent also prevents a late yt-dlp save from recreating a jar.
        _ = unlinkat(fd,name,AT_REMOVEDIR)
    }
}
