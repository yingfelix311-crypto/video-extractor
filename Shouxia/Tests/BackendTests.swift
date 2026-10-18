import Foundation

final class StubProtocol: URLProtocol, @unchecked Sendable {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@main struct BackendTests {
    static func main() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let backend = Backend(baseURL: URL(string: "http://127.0.0.1:8081")!, session: URLSession(configuration: config))
        StubProtocol.handler = { request in
            precondition(request.url!.path == "/cookie-status" && request.httpMethod == "GET")
            return (200, Data(#"{"status":"ok","has_cookies":true}"#.utf8))
        }
        let hasCookies = try await backend.cookieStatus()
        precondition(hasCookies, "cookie status decoded")
        let cookies = Data("# Netscape HTTP Cookie File\n.douyin.com\tTRUE\t/\tTRUE\t0\ttest\tfictional-test-only\n".utf8)
        try CookieFile.validate(cookies)
        for data in [Data(), Data("{\"cookies\":[]}".utf8), Data(repeating: 65, count: 1_000_001), Data("# Netscape HTTP Cookie File\ninvalid\n".utf8)] {
            do { try CookieFile.validate(data); fatalError("must reject invalid cookie file") } catch {}
        }
        try CookieFile.validate(Data("# Netscape HTTP Cookie File\n#HttpOnly_.example.com\tTRUE\t/\tFALSE\t0\tsession\tfixture\n".utf8))
        StubProtocol.handler = { request in
            precondition(request.url!.path == "/upload-cookies" && request.httpMethod == "POST")
            precondition(request.value(forHTTPHeaderField: "Content-Type")!.hasPrefix("multipart/form-data; boundary="))
            let body = request.httpBody ?? { () -> Data in
                let stream = request.httpBodyStream!; stream.open(); defer { stream.close() }
                var data=Data(); var bytes=[UInt8](repeating:0,count:4096)
                while stream.hasBytesAvailable { let count=stream.read(&bytes,maxLength:bytes.count); if count<=0 {break};data.append(contentsOf:bytes.prefix(count)) }
                return data
            }()
            let text=String(decoding:body,as:UTF8.self)
            precondition(text.contains("name=\"cookies\"") && text.contains("fictional-test-only"))
            return (200,Data(#"{"status":"ok"}"#.utf8))
        }
        try await backend.uploadCookies(cookies)
        StubProtocol.handler = { request in
            precondition(request.url!.path == "/delete-cookies" && request.httpMethod == "POST")
            return (200,Data(#"{"status":"ok"}"#.utf8))
        }
        try await backend.deleteCookies()
        StubProtocol.handler = { request in
            precondition(request.url!.path == "/cancel-add")
            return (200,Data(#"{"status":"ok"}"#.utf8))
        }
        try await backend.cancelAdd()
        StubProtocol.handler = { _ in (400,Data(#"{"status":"error","msg":"Cookie file too large"}"#.utf8)) }
        do { try await backend.post("add",body:Data());fatalError("HTTP error must propagate") }
        catch { precondition(error is AppError && error.localizedDescription.contains("Cookie file too large"),"structured backend rejection is definite") }
        for (status,response) in [(200,"{malformed"),(200,#"{"status":"unexpected","msg":"unknown outcome"}"#),(200,#"{"msg":"missing status"}"#),(500,"gateway failed"),(500,#"{"status":"ok"}"#)] {
            StubProtocol.handler = { _ in (status,Data(response.utf8)) }
            do {try await backend.post("add",body:Data());fatalError("unconfirmed response must throw")}
            catch {precondition(!(error is AppError),"HTTP/protocol failure cannot imply definite rejection")}
        }
        StubProtocol.handler = { _ in (200,Data(#"{"status":"error","msg":"Fresh cookies are needed"}"#.utf8)) }
        do {try await backend.post("add",body:Data());fatalError("explicit rejection must throw")}
        catch {precondition(error is AppError,"explicit protocol rejection remains definite")}
        print("PASS: Cookie validation, multipart upload, status/delete, cancel-add, HTTP errors")
    }
}
