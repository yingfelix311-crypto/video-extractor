import Foundation
import SQLite3
import CommonCrypto
import CryptoKit

@main struct BrowserCookieTests {
 static func expectFailure(_ body: () throws -> Void) { do { try body(); fatalError("Expected rejection") } catch {} }
 static func expectReadFailure(_ body: () async throws -> [SessionCookie]) async { do { _ = try await body(); fatalError("Expected read rejection") } catch {} }
 static func sql(_ url: URL, _ text: String) throws {
  try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
  var db: OpaquePointer?; precondition(sqlite3_open(url.path, &db) == SQLITE_OK); defer { sqlite3_close(db) }
  precondition(sqlite3_exec(db, text, nil, nil, nil) == SQLITE_OK)
 }
 static func hex(_ data: Data) -> String { data.map { String(format:"%02x", $0) }.joined() }
 static func encrypted(_ value: Data) -> Data {
  let password = Array("fixture-password".utf8), salt = Array("saltysalt".utf8)
  var key = [UInt8](repeating:0,count:16)
  let status = password.withUnsafeBytes { p in salt.withUnsafeBytes { s in CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), p.baseAddress!.assumingMemoryBound(to:Int8.self), password.count, s.baseAddress!.assumingMemoryBound(to:UInt8.self),salt.count,CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),1003,&key,key.count) } }
  precondition(status == kCCSuccess)
  let iv = [UInt8](repeating:32,count:16); var out = [UInt8](repeating:0,count:value.count+16);var written=0
  let encryptedStatus = value.withUnsafeBytes { p in CCCrypt(CCOperation(kCCEncrypt),CCAlgorithm(kCCAlgorithmAES),CCOptions(kCCOptionPKCS7Padding),key,16,iv,p.baseAddress,value.count,&out,out.count,&written) }
  precondition(encryptedStatus == kCCSuccess)
  return Data("v10".utf8) + Data(out.prefix(written))
 }
 static func safariFixture() -> Data {
  func le(_ n: UInt32) -> Data { var v=n.littleEndian;return withUnsafeBytes(of:&v){Data($0)} }
  func be(_ n: UInt32) -> Data { var v=n.bigEndian;return withUnsafeBytes(of:&v){Data($0)} }
  func double(_ n: Double) -> Data { var v=n.bitPattern.littleEndian;return withUnsafeBytes(of:&v){Data($0)} }
  let strings=[".youtube.com","sid","/","safari-fixture"]
  var offsets=[UInt32]();var payload=Data();for s in strings { offsets.append(UInt32(56+payload.count));payload.append(Data(s.utf8));payload.append(0) }
  var record=le(UInt32(56+payload.count))+le(0)+le(5)+le(0)
  for offset in offsets {record.append(le(offset))};record.append(Data(repeating:0,count:8));record.append(double(2_000_000_000-978_307_200));record.append(double(0));record.append(payload)
  let page=Data([0,0,1,0])+le(1)+le(16)+le(0)+record
  return Data("cook".utf8)+be(1)+be(UInt32(page.count))+page
 }
 static func main() async throws {
  let root=FileManager.default.temporaryDirectory.appendingPathComponent("browser-fixture-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
  let scope=CookieScope.forURL("https://youtu.be/fixture")!
  precondition(scope.contains(domain:".YouTube.Com") && scope.contains(domain:"www.youtube.com"))
  precondition(!scope.contains(domain:"evilyoutube.com") && !scope.contains(domain:"youtube.com.evil.test"))
  precondition(!scope.contains(domain:"..youtube.com") && !scope.contains(domain:"bad..youtube.com"))
  precondition(CookieScope.forURL("https://youtube.com.evil.test/")==nil && CookieScope.forURL("file:///youtube.com")==nil)
  for url in ["https://v.douyin.com/abc","https://b23.tv/abc","https://www.tiktok.com/a","https://instagram.com/a","https://x.com/a","https://xhslink.com/a","https://v.kuaishou.com/a"] {precondition(CookieScope.forURL(url) != nil)}
  let live=SessionCookie(domain:".youtube.com",name:"sid",value:"fixture",path:"/",expires:2_000_000_000,secure:true,httpOnly:true)
  let expired=SessionCookie(domain:"youtube.com",name:"old",value:"x",path:"/",expires:50,secure:false)
  let foreign=SessionCookie(domain:"evil.test",name:"other",value:"x",path:"/",expires:0,secure:false)
  let jar=String(decoding:try BrowserCookieJar.netscape([live,expired,foreign],scope:scope,now:100),as:UTF8.self)
  precondition(jar.contains("#HttpOnly_.youtube.com\tTRUE\t/\tTRUE\t2000000000\tsid\tfixture") && !jar.contains("old") && !jar.contains("evil.test"))
  let emptyJar = try BrowserCookieJar.netscape([],scope:scope,now:100)
  precondition(String(decoding:emptyJar,as:UTF8.self).hasPrefix("# Netscape HTTP Cookie File"))
  for value in ["x\ny","x\ty","x\ry","x\0y"] {expectFailure {_ = try BrowserCookieJar.netscape([SessionCookie(domain:"youtube.com",name:"sid",value:value,path:"/",expires:0,secure:false)],scope:scope,now:100)}}
  let ff=root.appendingPathComponent("Library/Application Support/Firefox/Profiles/test.default")
  try sql(ff.appendingPathComponent("cookies.sqlite"),"""
   CREATE TABLE moz_cookies (host TEXT,name TEXT,value TEXT,path TEXT,expiry INTEGER,isSecure INTEGER,isHttpOnly INTEGER,originAttributes TEXT);
   INSERT INTO moz_cookies VALUES('.youtube.com','sid','firefox','/',2000000000,1,1,'');
   INSERT INTO moz_cookies VALUES('.youtube.com','container','no','/',2000000000,0,0,'^userContextId=1');
   INSERT INTO moz_cookies VALUES('.youtube.com','partition','no','/',2000000000,0,0,'^partitionKey=%28https%2Cexample.com%29');
   INSERT INTO moz_cookies VALUES('.youtube.com','expired','no','/',1,0,0,'');
   INSERT INTO moz_cookies VALUES('evilyoutube.com','foreign','no','/',2000000000,0,0,'');
   """)
  let reader=NativeBrowserCookieReader(home:root,keyProvider:{_ in Data("fixture-password".utf8)})
  let profiles=try NativeBrowserCookieReader.profiles(for:.firefox,home:root);precondition(profiles.count==1 && profiles[0].directory=="test.default")
  let firefox=try await reader.read(browser:.firefox,profile:"test.default",scope:scope);precondition(firefox.count==1 && firefox[0].value=="firefox" && firefox[0].httpOnly)
  await expectReadFailure {try await reader.read(browser:.firefox,profile:"../test.default",scope:scope)}
  let symlink=ff.deletingLastPathComponent().appendingPathComponent("symlink.default");try FileManager.default.createSymbolicLink(at:symlink,withDestinationURL:ff)
  await expectReadFailure {try await reader.read(browser:.firefox,profile:"symlink.default",scope:scope)}
  let chrome=root.appendingPathComponent("Library/Application Support/Google/Chrome/Default/Cookies")
  let digest=Data(SHA256.hash(data:Data(".youtube.com".utf8)))
  try sql(chrome,"""
   CREATE TABLE meta (key TEXT,value TEXT); INSERT INTO meta VALUES('version','24');
   CREATE TABLE cookies (host_key TEXT,name TEXT,value TEXT,encrypted_value BLOB,path TEXT,expires_utc INTEGER,is_secure INTEGER,is_httponly INTEGER);
   INSERT INTO cookies VALUES('.youtube.com','sid','',X'\(hex(encrypted(digest+Data("chrome-fixture".utf8))))','/',0,1,1);
   INSERT INTO cookies VALUES('evil.test','foreign','',X'763131626164','/',0,0,0);
   """)
  let chromeRows=try await reader.read(browser:.chrome,profile:"Default",scope:scope);precondition(chromeRows.count==1 && chromeRows[0].value=="chrome-fixture")
  let wrongKey=NativeBrowserCookieReader(home:root,keyProvider:{_ in Data("wrong-password".utf8)})
  await expectReadFailure {try await wrongKey.read(browser:.chrome,profile:"Default",scope:scope)}
  let edge=root.appendingPathComponent("Library/Application Support/Microsoft Edge/Profile 1/Network/Cookies")
  try FileManager.default.createDirectory(at:edge.deletingLastPathComponent(),withIntermediateDirectories:true)
  try FileManager.default.copyItem(at:chrome,to:edge)
  let edgeRows=try await reader.read(browser:.edge,profile:"Profile 1",scope:scope);precondition(edgeRows.count==1 && edgeRows[0].value=="chrome-fixture")
  try sql(chrome,"UPDATE meta SET value='23'; UPDATE cookies SET encrypted_value=X'\(hex(encrypted(Data("legacy-fixture".utf8))))' WHERE name='sid'")
  let legacyRows=try await reader.read(browser:.chrome,profile:"Default",scope:scope);precondition(legacyRows.first?.value=="legacy-fixture")
  try sql(chrome,"UPDATE meta SET value='24'")
  try sql(chrome,"UPDATE cookies SET encrypted_value=X'\(hex(encrypted(Data(repeating:0,count:32)+Data("bad-host".utf8))))' WHERE name='sid'")
  await expectReadFailure {try await reader.read(browser:.chrome,profile:"Default",scope:scope)}
  try sql(chrome,"UPDATE cookies SET encrypted_value=X'763131626164' WHERE name='sid'")
  await expectReadFailure {try await reader.read(browser:.chrome,profile:"Default",scope:scope)}
  try sql(chrome,"DELETE FROM cookies WHERE name='sid'")
  let noKey=NativeBrowserCookieReader(home:root,keyProvider:{_ in fatalError("Keychain must be lazy and scoped")})
  let noCookies = try await noKey.read(browser:.chrome,profile:"Default",scope:scope)
  precondition(noCookies.isEmpty)
  try sql(chrome,"INSERT INTO cookies VALUES('.youtube.com','expired','',X'763131626164','/',1,0,0)")
  let expiredOnly=try await noKey.read(browser:.chrome,profile:"Default",scope:scope);precondition(expiredOnly.isEmpty)
  let wal=URL(fileURLWithPath:chrome.path+"-wal");try FileManager.default.createSymbolicLink(at:wal,withDestinationURL:ff.appendingPathComponent("cookies.sqlite"))
  await expectReadFailure {try await noKey.read(browser:.chrome,profile:"Default",scope:scope)}
  try FileManager.default.removeItem(at:wal)
  let fileLink=ff.appendingPathComponent("cookies.sqlite");try FileManager.default.removeItem(at:fileLink);try FileManager.default.createSymbolicLink(at:fileLink,withDestinationURL:chrome)
  await expectReadFailure {try await reader.read(browser:.firefox,profile:"test.default",scope:scope)}
  let safari=root.appendingPathComponent("Library/Cookies/Cookies.binarycookies");try FileManager.default.createDirectory(at:safari.deletingLastPathComponent(),withIntermediateDirectories:true)
  try safariFixture().write(to:safari)
  let safariRows=try await reader.read(browser:.safari,profile:"Default",scope:scope);precondition(safariRows.count==1 && safariRows[0].value=="safari-fixture" && safariRows[0].httpOnly)
  for length in [0,7,15,25,safariFixture().count-1] {try safariFixture().prefix(length).write(to:safari);await expectReadFailure {try await reader.read(browser:.safari,profile:"Default",scope:scope)}}
  for position in [4,8,20,28,44] {var malformed=safariFixture();malformed.replaceSubrange(position..<position+4,with:[255,255,255,255]);try malformed.write(to:safari);await expectReadFailure {try await reader.read(browser:.safari,profile:"Default",scope:scope)}}
  try FileManager.default.removeItem(at:safari)
  try FileManager.default.createDirectory(at:safari,withIntermediateDirectories:false)
  do {_ = try await reader.read(browser:.safari,profile:"Default",scope:scope);fatalError("Directory is not a Cookie store")}
  catch {precondition(error.localizedDescription.contains("损坏") || error.localizedDescription.contains("不受支持"), "Nonregular stores must fail as invalid input")}
  print("Browser cookie scope, private profile, Firefox isolation, Chromium v10/digest and Safari bounds tests passed")
 }
}
