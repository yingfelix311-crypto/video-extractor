import Foundation
@main struct RuntimeSupportTests {
 static func main() async throws {
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
