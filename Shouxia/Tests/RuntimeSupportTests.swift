import Foundation
@main struct RuntimeSupportTests {
 static func main() async throws {
  let ready=RuntimeSupport.dependencySummary(["ffmpeg":"7","ffprobe":"7","yt-dlp":"2026","python3":"3","deno":"2","node":"未安装"])
  precondition(ready.contains("就绪") && !ready.contains("缺少"),"Deno alone satisfies JavaScript runtime")
  let missing=RuntimeSupport.dependencySummary(["ffmpeg":"7","ffprobe":"7","yt-dlp":"2026","python3":"3","deno":"未安装","node":"未安装"])
  precondition(missing.contains("JavaScript"),"missing both JS runtimes is actionable")
  let fixture=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at:fixture) }
  let local=fixture.appendingPathComponent(".local/bin"),brew=fixture.appendingPathComponent("brew/bin"),intel=fixture.appendingPathComponent("intel/bin")
  for directory in [local,brew,intel] { try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true) }
  func executable(_ directory:URL,_ mode:Int) throws {
   let file=directory.appendingPathComponent("docker")
   try Data("#!/bin/sh\nexit 0\n".utf8).write(to:file)
   try FileManager.default.setAttributes([.posixPermissions:mode],ofItemAtPath:file.path)
  }
  try executable(brew,0o755);try executable(intel,0o755)
  let resolved1=try LocalRuntimeExecutable.resolve("docker",home:fixture,searchDirectories:[brew,intel])
  precondition(resolved1 == brew.appendingPathComponent("docker").path,"Homebrew fallback order")
  try executable(local,0o755)
  let resolved2=try LocalRuntimeExecutable.resolve("docker",home:fixture,searchDirectories:[brew,intel])
  precondition(resolved2 == local.appendingPathComponent("docker").path,"local executable takes priority")
  try executable(local,0o644)
  let resolved3=try LocalRuntimeExecutable.resolve("docker",home:fixture,searchDirectories:[brew,intel])
  precondition(resolved3 == brew.appendingPathComponent("docker").path,"nonexecutable local file must be skipped")
  try FileManager.default.removeItem(at:brew.appendingPathComponent("docker"))
  let resolved4=try LocalRuntimeExecutable.resolve("docker",home:fixture,searchDirectories:[brew,intel])
  precondition(resolved4 == intel.appendingPathComponent("docker").path,"Intel Homebrew fallback")
  do { _ = try LocalRuntimeExecutable.resolve("colima",home:fixture,searchDirectories:[brew,intel]);fatalError("missing executable accepted") } catch {}
  let output=try await RuntimeSupport.raw("/bin/echo",["fixture"],timeout:2)
  precondition(String(decoding:output,as:UTF8.self)=="fixture\n","real child-process completion must not deadlock")
  do {_ = try await RuntimeSupport.raw("/bin/sleep",["10"],timeout:0.1);fatalError("unbounded subprocess") }catch{}
  let original: [String: Any] = ["Id":"original", "Name":"/metube", "Config":["Env":["SECRET=preserve", "ALLOW_YTDL_OPTIONS_OVERRIDES=false"], "WorkingDir":"/app"], "HostConfig":["NetworkMode":"default", "AutoRemove":false, "Binds":["/tmp/media:/downloads"], "PortBindings":["8081/tcp":[["HostIp":"127.0.0.1", "HostPort":"8081"]]]], "Mounts":[["Type":"bind"]]]
  let plan = try RuntimeSupport.creationPayload(original, snapshot:"snapshot")
  let config = plan["Env"] as! [String]
  precondition(config.contains("SECRET=preserve") && config.contains("ALLOW_YTDL_OPTIONS_OVERRIDES=true"))
  precondition(plan["WorkingDir"] as? String == "/app")
  precondition(NSDictionary(dictionary:plan["HostConfig"] as! [String:Any]).isEqual(to:original["HostConfig"] as! [String:Any]))
  var bad = original; var host = original["HostConfig"] as! [String:Any]; host["AutoRemove"] = true; bad["HostConfig"] = host
  do { _ = try RuntimeSupport.creationPayload(bad,snapshot:"x"); fatalError("accepted auto remove") } catch {}
  bad = original; bad["Mounts"] = [["Type":"volume"]]
  do { _ = try RuntimeSupport.creationPayload(bad,snapshot:"x"); fatalError("accepted implicit volume") } catch {}
  for change:[String:Any] in [["PublishAllPorts":true],["RestartPolicy":["Name":"always"]]] {
   bad=original;var h=original["HostConfig"] as! [String:Any];h.merge(change){_,new in new};bad["HostConfig"]=h
   do {_ = try RuntimeSupport.creationPayload(bad,snapshot:"x");fatalError("unsafe restart/publication accepted")} catch {}
  }
  let replacement:[String:Any] = ["Id":"new", "Config":["Labels":["com.shouxia.network-transaction":"token"]]]
  do {_ = try RuntimeSupport.recoveryCommands(original:nil,current:replacement,originalID:"original",backupName:"backup",token:"token");fatalError("must preserve replacement if backup missing")} catch {}
  let backup:[String:Any] = ["Id":"original","Name":"/backup"]
  let commands=try RuntimeSupport.recoveryCommands(original:backup,current:replacement,originalID:"original",backupName:"backup",token:"token")
  precondition(commands == [["rm","--force","new"],["rename","original","metube"],["start","original"]],"validated recovery sequence")
  do {_ = try RuntimeSupport.recoveryCommands(original:backup,current:["Id":"unrelated"],originalID:"original",backupName:"backup",token:"token");fatalError("must preserve unrelated replacement")} catch {}
  try RuntimeSupport.validateExposure(["NetworkSettings":["Ports":["8081/tcp":[["HostIp":"127.0.0.1","HostPort":"8081"]]]]])
  do {try RuntimeSupport.validateExposure(["NetworkSettings":["Ports":["8081/tcp":[["HostIp":"0.0.0.0","HostPort":"8081"]]]]]);fatalError("wildcard exposure accepted")}catch{}
  print("Runtime preservation and unsupported configuration checks passed")
 }
}
