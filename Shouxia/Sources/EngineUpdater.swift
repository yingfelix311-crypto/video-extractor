import Foundation
import Combine

/// Serialized maintenance. Callers must reject new downloads while isUpdating is true.
@MainActor final class EngineUpdater: ObservableObject {
    @Published private(set) var isUpdating = false
    @Published private(set) var status = "等待检查下载引擎"
    @Published private(set) var currentVersion = "读取中"
    @Published private(set) var lastChecked: Date?
    @Published var automaticEnabled: Bool {
        didSet { defaults.set(automaticEnabled, forKey: "engineAutomaticUpdates") }
    }
    private let defaults: UserDefaults
    private let backend = Backend()
    private var lastAttempt: Date?
    private var lastEligibility: Date?
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        automaticEnabled = defaults.object(forKey: "engineAutomaticUpdates") == nil || defaults.bool(forKey: "engineAutomaticUpdates")
        lastChecked = defaults.object(forKey: "engineLastChecked") as? Date
        lastAttempt = defaults.object(forKey: "engineLastAttempt") as? Date
    }
    func recoverIfNeeded() async {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }
        do { try await recoverInterrupted() }
        catch { status = "恢复尚未完成，请重新连接并查看日志"; Backend.log("Engine recovery: \(error)") }
    }
    func refreshVersion() async {
        guard !isUpdating else { return }
        if let version = try? await docker(["exec", "metube", "python3", "-c", "import yt_dlp.version; print(yt_dlp.version.__version__)"]) { currentVersion = version }
    }
    func checkIfNeeded(force: Bool = false) async {
        guard !isUpdating else { return }
        let now = Date()
        guard force || lastEligibility == nil || now.timeIntervalSince(lastEligibility!) >= 60 else { return }
        lastEligibility = now
        guard force || lastAttempt == nil || now.timeIntervalSince(lastAttempt!) >= 3600 else { return }
        guard force || (automaticEnabled && (lastChecked == nil || Date().timeIntervalSince(lastChecked!) >= 86400)) else { return }
        isUpdating = true
        defer { isUpdating = false }
        let previousAttempt = lastAttempt
        lastAttempt = Date(); defaults.set(lastAttempt, forKey: "engineLastAttempt")
        do {
            try await recoverInterrupted()
            let history = try await backend.history()
            guard history.queue.isEmpty && history.pending.isEmpty else {
                lastAttempt = previousAttempt; defaults.set(lastAttempt, forKey: "engineLastAttempt")
                status = "有下载任务，空闲后再检查"
                return
            }
            status = "正在检查下载引擎…"
            currentVersion = try await docker(["exec", "metube", "python3", "-c", "import yt_dlp.version; print(yt_dlp.version.__version__)"])
            // Stage only the engine wheel: existing browser, JS and media dependencies stay installed.
            let stageOutput = try await docker(["exec", "metube", "python3", "-c", Self.stageScript], timeout: 180)
            let stage = stageOutput.components(separatedBy: .newlines).last ?? ""
            guard stage.hasPrefix("READY ") else { throw AppError.message("引擎安装包验证失败") }
            let candidate = String(stage.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
            if candidate == currentVersion {
                recordCheck(); status = "已是最新版本"; return
            }
            let latest = try await backend.history()
            guard latest.queue.isEmpty && latest.pending.isEmpty else {
                lastAttempt = previousAttempt; defaults.set(lastAttempt, forKey: "engineLastAttempt")
                status = "有下载任务，更新已延后"; return
            }
            status = "正在更新下载引擎…"
            do {
                try await docker(["exec", "metube", "python3", "-c", Self.installScript])
                try await docker(["restart", "metube"], timeout: 45)
                try await waitForService()
                let installed = try await docker(["exec", "metube", "python3", "-c", "import yt_dlp.version; print(yt_dlp.version.__version__)"])
                guard installed == candidate else { throw AppError.message("更新后的版本验证失败") }
                currentVersion = installed
                try await finalize()
                recordCheck(); status = "已更新至 \(installed)"
            } catch {
                status = "更新失败，正在恢复原引擎…"
                do {
                    try await docker(["exec", "metube", "python3", "-c", Self.rollbackScript])
                    try await docker(["restart", "metube"], timeout: 45)
                    try await waitForService()
                    try await finalize()
                    status = "更新失败，已恢复原引擎；稍后可重试"
                } catch {
                    status = "恢复尚未完成，请重新连接服务并查看日志"
                }
                Backend.log("Engine update recovery: \(error)")
            }
        } catch {
            status = "检查失败，现有引擎保留；请查看日志，1 小时后自动重试"
            Backend.log("Engine update: \(error)")
        }
    }
    /// Recovery is allowed only when our persisted transaction marker exists.
    /// docker cp also works on a stopped container whose Python import cannot start.
    private func recoverInterrupted() async throws {
        let local = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: local) }
        let root = "metube:/tmp/shouxia-engine-update/"
        do { try await docker(["cp", root + "installing", local.appendingPathComponent("installing").path]) }
        catch { return } // No marker: normal checks never change an existing installation.
        status = "正在恢复上次未完成的引擎更新…"
        if let history = try? await backend.history(), !history.queue.isEmpty || !history.pending.isEmpty {
            throw AppError.message("恢复已延后，请先完成下载任务")
        }
        let running = try await docker(["inspect", "--format", "{{.State.Running}}", "metube"])
        if running != "true" {
            let journalURL = local.appendingPathComponent("transaction.json")
            try await docker(["cp", root + "transaction.json", journalURL.path])
            struct Journal: Decodable { let old: [String] }
            let journal = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: journalURL))
            // Restrict recovery destinations to this image's known Python installation.
            for path in journal.old {
                let file = URL(fileURLWithPath: path)
                guard file.deletingLastPathComponent().path == "/usr/local/lib/python3.14/site-packages",
                      file.lastPathComponent == "yt_dlp" || (file.lastPathComponent.hasPrefix("yt_dlp-") && file.lastPathComponent.hasSuffix(".dist-info")) else {
                    throw AppError.message("恢复记录路径异常，请查看日志")
                }
                try await docker(["cp", root + "backup/" + file.lastPathComponent, local.path])
                try await docker(["cp", local.appendingPathComponent(file.lastPathComponent).path, "metube:" + file.deletingLastPathComponent().path])
            }
            try await docker(["start", "metube"], timeout: 45)
        }
        try await docker(["exec", "metube", "python3", "-c", Self.rollbackScript])
        try await docker(["restart", "metube"], timeout: 45)
        try await waitForService()
        try await finalize()
    }
    private func finalize() async throws {
        try await docker(["exec", "metube", "python3", "-c", "from pathlib import Path; Path('/tmp/shouxia-engine-update/installing').unlink(missing_ok=True)"])
    }
    private func recordCheck() {
        lastChecked = Date()
        defaults.set(lastChecked, forKey: "engineLastChecked")
    }
    private func waitForService() async throws {
        for _ in 0..<30 {
            if (try? await backend.history()) != nil { return }
            try await Task.sleep(for: .seconds(1))
        }
        throw AppError.message("引擎重启后未能连接")
    }
    @discardableResult private func docker(_ arguments: [String], timeout: TimeInterval = 30) async throws -> String {
        try await EngineCommand.run(arguments: arguments, timeout: timeout)
    }
    // Staging never modifies the live engine. Recovery is a separate transaction
    // followed by a verified server restart before normal checks continue.
    static let stageScript = #"""
import pathlib, tempfile, subprocess, zipfile, shutil, sysconfig, json
root=pathlib.Path('/tmp/shouxia-engine-update'); root.mkdir(exist_ok=True)
pkg=pathlib.Path(sysconfig.get_path('purelib'))/'yt_dlp'
if (root/'installing').exists(): raise RuntimeError('Recover interrupted update before staging')
work=pathlib.Path(tempfile.mkdtemp(prefix='stage-',dir=root))
subprocess.run(['python3','-m','pip','download','--pre','--no-deps','--only-binary=:all:','--index-url','https://pypi.org/simple','--dest',str(work),'yt-dlp'],check=True,stdout=subprocess.DEVNULL,timeout=150)
wheel=next(work.glob('yt_dlp-*.whl'))
with zipfile.ZipFile(wheel) as z:
 for n in z.namelist():
  p=pathlib.PurePosixPath(n)
  if p.is_absolute() or '..' in p.parts: raise RuntimeError('unsafe wheel')
 z.extractall(work/'unpacked')
# Refuse incompatible dependency requirements before replacing the working engine.
from email.parser import Parser
from importlib.metadata import version, PackageNotFoundError
try: from packaging.requirements import Requirement
except ImportError: from pip._vendor.packaging.requirements import Requirement
metadata=next((work/'unpacked').glob('*.dist-info/METADATA')).read_text()
for raw in Parser().parsestr(metadata).get_all('Requires-Dist', []):
 r=Requirement(raw)
 if r.marker and not any(r.marker.evaluate({'extra':e}) for e in ['', 'default', 'curl-cffi', 'deno']): continue
 try: installed=version(r.name)
 except PackageNotFoundError: raise RuntimeError('Required dependency missing: '+r.name)
 if r.specifier and not r.specifier.contains(installed,prereleases=True): raise RuntimeError('Required dependency incompatible: '+r.name)
staged=work/'unpacked'/'yt_dlp'
v=subprocess.check_output(['python3','-c','import yt_dlp.version; from yt_dlp import YoutubeDL; print(yt_dlp.version.__version__)'],cwd=work/'unpacked',text=True).strip()
(root/'stage.json').write_text(json.dumps({'staged':str(staged),'package':str(pkg),'metadata':str(next((work/'unpacked').glob('*.dist-info')))}))
print('READY '+v)
"""#
    static let installScript = #"""
import pathlib,json,shutil,signal,fcntl
signal.alarm(20)
root=pathlib.Path('/tmp/shouxia-engine-update')
lock=open(root/'transaction.lock','a'); fcntl.flock(lock,fcntl.LOCK_EX)
state=json.loads((root/'stage.json').read_text())
pkg=pathlib.Path(state['package']); staged=pathlib.Path(state['staged']); meta=pathlib.Path(state['metadata'])
backup=root/'backup'
if (root/'installing').exists(): raise RuntimeError('Previous transaction not finalized')
if backup.exists(): shutil.rmtree(backup)
backup.mkdir()
old=[pkg]+list(pkg.parent.glob('yt_dlp-*.dist-info'))
# Complete all backups before modifying the live installation.
for path in old: shutil.copytree(path,backup/path.name)
journal={'old':[str(p) for p in old],'new':[str(pkg),str(pkg.parent/meta.name)]}
(root/'transaction.json').write_text(json.dumps(journal))
(root/'installing').touch()
for path in old: shutil.rmtree(path)
shutil.copytree(staged,pkg)
shutil.copytree(meta,pkg.parent/meta.name)
"""#
    static let rollbackScript = #"""
import pathlib,json,shutil,signal,fcntl
signal.alarm(20)
root=pathlib.Path('/tmp/shouxia-engine-update')
lock=open(root/'transaction.lock','a'); fcntl.flock(lock,fcntl.LOCK_EX)
if (root/'installing').exists():
 journal=json.loads((root/'transaction.json').read_text())
 backup=root/'backup'
 for name in set(journal['old']+journal['new']):
  path=pathlib.Path(name)
  if path.exists(): shutil.rmtree(path)
 for name in journal['old']:
  path=pathlib.Path(name); shutil.copytree(backup/path.name,path)
# The marker remains until Swift confirms restart and service health.
"""#
    static var recoveryScript: String {
        rollbackScript + "\nprint('RECOVERED' if (root/'installing').exists() else 'CLEAN')"
    }

}

enum EngineCommand {
    static func run(arguments: [String], timeout: TimeInterval) async throws -> String {
        try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/docker")
            process.arguments = ["--context", "colima-metube"] + arguments
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            FileManager.default.createFile(atPath: url.path, contents: nil)
            let file = try FileHandle(forWritingTo: url)
            defer { try? file.close(); try? FileManager.default.removeItem(at: url) }
            process.standardOutput = file; process.standardError = file
            try process.run()
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline {
                try await Task.sleep(for: .milliseconds(200))
            }
            if process.isRunning {
                process.terminate()
                try await Task.sleep(for: .milliseconds(500))
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                throw AppError.message("引擎维护超时")
            }
            let reader = try FileHandle(forReadingFrom: url)
            defer { try? reader.close() }
            let size = try reader.seekToEnd()
            try reader.seek(toOffset: size > 8192 ? size - 8192 : 0)
            let result = String(decoding: try reader.read(upToCount: 8192) ?? Data(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard process.terminationStatus == 0 else { Backend.log(result); throw AppError.message("引擎维护失败") }
            return result
        }.value
    }
}
