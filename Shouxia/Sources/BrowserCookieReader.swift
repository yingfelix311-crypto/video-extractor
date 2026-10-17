import Foundation
import SQLite3
import Security
import CommonCrypto
import CryptoKit

struct NativeBrowserCookieReader: BrowserCookieReading {
    typealias KeyProvider = @Sendable (BrowserKind) throws -> Data
    let home: URL
    private let keyProvider: KeyProvider

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser, keyProvider: @escaping KeyProvider = { try NativeBrowserCookieReader.safeStoragePassword($0) }) {
        self.home = home
        self.keyProvider = keyProvider
    }

    static func profiles(for browser: BrowserKind, home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> [BrowserProfile] {
        let root = base(for: browser, home: home)
        try guardPath(root, home: home)
        if browser == .safari {
            // Safari has one supported default store. Access permission is checked only on explicit reading.
            return [BrowserProfile(browser: browser, directory: "Default", name: "默认配置")]
        }
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let directories: [URL]
        do { directories = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) }
        catch { throw BrowserCookieError.denied(browser) }
        var names: [String: String] = [:]
        if browser == .chrome || browser == .edge {
            let state = root.appendingPathComponent("Local State")
            try guardPath(state, home: home)
            if let data = try? boundedData(state, limit: 16 * 1024 * 1024),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let profile = json["profile"] as? [String: Any], let cache = profile["info_cache"] as? [String: [String: Any]] {
                for (directory, info) in cache { names[directory] = info["name"] as? String }
            }
        }
        return directories.compactMap { directory -> BrowserProfile? in
            let component = directory.lastPathComponent
            guard validProfile(component, browser: browser),
                  let values = try? directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]), values.isDirectory == true, values.isSymbolicLink != true,
                  (try? guardPath(directory, home: home)) != nil else { return nil }
            return BrowserProfile(browser: browser, directory: component, name: names[component] ?? (component == "Default" ? "默认配置" : component))
        }.sorted { $0.directory.localizedStandardCompare($1.directory) == .orderedAscending }
    }

    func read(browser: BrowserKind, profile: String, scope: CookieScope) async throws -> [SessionCookie] {
        try Task.checkCancellation()
        guard Self.validProfile(profile, browser: browser) else { throw BrowserCookieError.invalidProfile }
        let root = Self.base(for: browser, home: home)
        try Self.guardPath(root, home: home)
        if browser == .safari {
            let stores = [root.appendingPathComponent("Cookies.binarycookies"), home.appendingPathComponent("Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies")]
            for store in stores {
                try Self.guardPath(store, home: home)
                do { return try safari(Self.boundedData(store, limit: 64 * 1024 * 1024), scope: scope) }
                catch let error as BrowserCookieError { throw error }
                catch let error as CocoaError where error.code == .fileReadNoSuchFile { continue }
                catch { throw BrowserCookieError.denied(.safari) }
            }
            throw BrowserCookieError.missingStore
        }
        let directory = root.appendingPathComponent(profile, isDirectory: true)
        try Self.guardPath(directory, home: home)
        let filenames = browser == .firefox ? ["cookies.sqlite"] : ["Cookies", "Network/Cookies"]
        for filename in filenames {
            let file = directory.appendingPathComponent(filename)
            try Self.guardPath(file, home: home)
            // SQLite can also read WAL/SHM; do not follow attacker-controlled sidecar links.
            for suffix in ["-wal", "-shm", "-journal"] { try Self.guardPath(URL(fileURLWithPath: file.path + suffix), home: home) }
            if FileManager.default.fileExists(atPath: file.path) {
                return try database(file, browser: browser, scope: scope)
            }
        }
        throw BrowserCookieError.missingStore
    }

    private static func base(for browser: BrowserKind, home: URL) -> URL {
        let relative: String
        switch browser {
        case .chrome: relative = "Library/Application Support/Google/Chrome"
        case .edge: relative = "Library/Application Support/Microsoft Edge"
        case .firefox: relative = "Library/Application Support/Firefox/Profiles"
        case .safari: relative = "Library/Cookies"
        }
        return home.appendingPathComponent(relative, isDirectory: true)
    }

    private static func validProfile(_ profile: String, browser: BrowserKind) -> Bool {
        guard !profile.isEmpty, profile != ".", profile != "..", !profile.contains("/"), !profile.contains("\\"), !profile.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else { return false }
        switch browser {
        case .safari: return profile == "Default"
        case .chrome, .edge: return profile == "Default" || profile.range(of: "^Profile [0-9]+$", options: .regularExpression) != nil
        case .firefox: return true
        }
    }

    private static func guardPath(_ url: URL, home: URL) throws {
        let homePath = home.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path == homePath || path.hasPrefix(homePath + "/") else { throw BrowserCookieError.unsafePath }
        var cursor = URL(fileURLWithPath: homePath, isDirectory: true)
        let relative = path.dropFirst(homePath.count).split(separator: "/")
        for component in [""] + relative.map(String.init) {
            if !component.isEmpty { cursor.appendPathComponent(component) }
            if let attributes = try? FileManager.default.attributesOfItem(atPath: cursor.path), attributes[.type] as? FileAttributeType == .typeSymbolicLink {
                throw BrowserCookieError.unsafePath
            }
        }
    }

    private static func boundedData(_ url: URL, limit: Int) throws -> Data {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber, size.int64Value <= Int64(limit) else { throw BrowserCookieError.corrupt }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw BrowserCookieError.corrupt }
        return data
    }

    static func safeStoragePassword(_ browser: BrowserKind) throws -> Data {
        let account: String, service: String
        switch browser {
        case .chrome: account = "Chrome"; service = "Chrome Safe Storage"
        case .edge: account = "Microsoft Edge"; service = "Microsoft Edge Safe Storage"
        default: throw BrowserCookieError.keychain(browser)
        }
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrAccount: account,
                                    kSecAttrService: service, kSecMatchLimit: kSecMatchLimitOne, kSecReturnData: true]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, !data.isEmpty else { throw BrowserCookieError.keychain(browser) }
        return data
    }

    private func database(_ file: URL, browser: BrowserKind, scope: CookieScope) throws -> [SessionCookie] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(file.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            throw BrowserCookieError.database
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 1000)
        let firefox = browser == .firefox
        let hostColumn = firefox ? "host" : "host_key"
        // Bound equality/suffix clauses select only this platform; values never enter SQL source.
        let clauses = scope.domains.map { _ in "(lower(\(hostColumn)) = ? OR lower(\(hostColumn)) = ? OR lower(\(hostColumn)) LIKE ? ESCAPE '\\')" }.joined(separator: " OR ")
        let columns = firefox ? "host,name,value,path,expiry,isSecure,isHttpOnly" : "host_key,name,value,path,expires_utc,is_secure,is_httponly,encrypted_value"
        let sql = "SELECT \(columns) FROM \(firefox ? "moz_cookies" : "cookies") WHERE (\(clauses))" + (firefox ? " AND originAttributes = ''" : "")
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw BrowserCookieError.database }
        defer { sqlite3_finalize(statement) }
        var parameter: Int32 = 1
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for domain in scope.domains {
            let escaped = domain.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
            for value in [domain, "." + domain, "%." + escaped] {
                guard sqlite3_bind_text(statement, parameter, value, -1, transient) == SQLITE_OK else { throw BrowserCookieError.database }
                parameter += 1
            }
        }
        var version = 0
        if !firefox {
            var meta: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT value FROM meta WHERE key = 'version' LIMIT 1", -1, &meta, nil) == SQLITE_OK, let meta else { throw BrowserCookieError.database }
            defer { sqlite3_finalize(meta) }
            let state = sqlite3_step(meta)
            guard state == SQLITE_ROW || state == SQLITE_DONE else { throw BrowserCookieError.database }
            if state == SQLITE_ROW {
                guard let number = Int(try Self.string(meta, 0)), number >= 0 else { throw BrowserCookieError.corrupt }
                version = number
            }
        }
        var cookies: [SessionCookie] = [], key: Data?
        let now = Int64(Date().timeIntervalSince1970)
        while true {
            try Task.checkCancellation()
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW else { throw BrowserCookieError.database }
            let domain = try Self.string(statement, 0)
            guard scope.contains(domain: domain) else { continue }
            let rawExpiry = sqlite3_column_int64(statement, 4)
            let expiry = firefox ? rawExpiry : (rawExpiry == 0 ? 0 : rawExpiry / 1_000_000 - 11_644_473_600)
            guard expiry == 0 || expiry > now else { continue }
            var value = try Self.string(statement, 2)
            if !firefox {
                let size = Int(sqlite3_column_bytes(statement, 7))
                guard size <= 1024 * 1024 else { throw BrowserCookieError.corrupt }
                if size > 0 {
                    guard let bytes = sqlite3_column_blob(statement, 7) else { throw BrowserCookieError.corrupt }
                    let encrypted = Data(bytes: bytes, count: size)
                    guard encrypted.starts(with: Data("v10".utf8)) else { throw BrowserCookieError.unsupportedEncryption }
                    if key == nil { key = try Self.deriveKey(keyProvider(browser)) }
                    value = try Self.decrypt(encrypted, key: key!, host: domain, verifyHost: version >= 24)
                }
            }
            cookies.append(SessionCookie(domain: domain, name: try Self.string(statement, 1), value: value,
                                         path: try Self.string(statement, 3), expires: expiry,
                                         secure: sqlite3_column_int(statement, 5) != 0, httpOnly: sqlite3_column_int(statement, 6) != 0))
            guard cookies.count <= 100_000 else { throw BrowserCookieError.corrupt }
        }
        return cookies
    }

    private static func string(_ statement: OpaquePointer, _ column: Int32) throws -> String {
        let count = Int(sqlite3_column_bytes(statement, column))
        guard count <= 1024 * 1024 else { throw BrowserCookieError.corrupt }
        guard let bytes = sqlite3_column_text(statement, column) else {
            if sqlite3_column_type(statement, column) == SQLITE_NULL { return "" }
            throw BrowserCookieError.corrupt
        }
        guard let string = String(data: Data(bytes: bytes, count: count), encoding: .utf8) else { throw BrowserCookieError.corrupt }
        return string
    }

    private static func deriveKey(_ password: Data) throws -> Data {
        let salt = Array("saltysalt".utf8)
        var key = [UInt8](repeating: 0, count: 16)
        let status = password.withUnsafeBytes { p in
            salt.withUnsafeBytes { s in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), p.baseAddress?.assumingMemoryBound(to: Int8.self), password.count,
                                    s.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003, &key, 16)
            }
        }
        guard status == kCCSuccess else { throw BrowserCookieError.decryption }
        return Data(key)
    }

    private static func decrypt(_ encrypted: Data, key: Data, host: String, verifyHost: Bool) throws -> String {
        let ciphertext = Data(encrypted.dropFirst(3))
        guard !ciphertext.isEmpty, ciphertext.count % 16 == 0 else { throw BrowserCookieError.decryption }
        let iv = [UInt8](repeating: 32, count: 16)
        var output = [UInt8](repeating: 0, count: ciphertext.count + 16), count = 0
        let status = key.withUnsafeBytes { k in ciphertext.withUnsafeBytes { c in
            CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding), k.baseAddress, key.count, iv,
                    c.baseAddress, ciphertext.count, &output, output.count, &count)
        } }
        guard status == kCCSuccess else { throw BrowserCookieError.decryption }
        var plaintext = Data(output.prefix(count))
        if verifyHost {
            let digest = Data(SHA256.hash(data: Data(host.utf8)))
            guard plaintext.count >= 32, plaintext.prefix(32) == digest else { throw BrowserCookieError.decryption }
            plaintext.removeFirst(32)
        }
        guard let value = String(data: plaintext, encoding: .utf8) else { throw BrowserCookieError.decryption }
        return value
    }

    private func safari(_ data: Data, scope: CookieScope) throws -> [SessionCookie] {
        let bytes = [UInt8](data)
        func uint(_ offset: Int, end: Int, big: Bool = false) throws -> Int {
            guard offset >= 0, end <= bytes.count, offset <= end - 4 else { throw BrowserCookieError.corrupt }
            let b = bytes[offset..<offset + 4]
            return big ? b.reduce(0) { ($0 << 8) | Int($1) } : b.reversed().reduce(0) { ($0 << 8) | Int($1) }
        }
        guard bytes.count >= 8, bytes.prefix(4) == Array("cook".utf8)[...] else { throw BrowserCookieError.corrupt }
        let pageCount = try uint(4, end: bytes.count, big: true)
        guard pageCount <= 100_000, pageCount <= (bytes.count - 8) / 4 else { throw BrowserCookieError.corrupt }
        var pageStart = 8 + pageCount * 4, cookies: [SessionCookie] = []
        let now = Int64(Date().timeIntervalSince1970)
        for pageIndex in 0..<pageCount {
            try Task.checkCancellation()
            let pageSize = try uint(8 + pageIndex * 4, end: bytes.count, big: true)
            guard pageSize >= 8, pageSize <= bytes.count - pageStart else { throw BrowserCookieError.corrupt }
            let pageEnd = pageStart + pageSize
            guard Array(bytes[pageStart..<pageStart + 4]) == [0, 0, 1, 0] else { throw BrowserCookieError.corrupt }
            let count = try uint(pageStart + 4, end: pageEnd)
            guard count <= 100_000, count <= (pageSize - 8) / 4 else { throw BrowserCookieError.corrupt }
            let headerSize = 8 + count * 4
            var previousRecordEnd = pageStart + headerSize
            for index in 0..<count {
                let relative = try uint(pageStart + 8 + index * 4, end: pageEnd)
                guard relative >= headerSize, relative <= pageSize - 4 else { throw BrowserCookieError.corrupt }
                let start = pageStart + relative
                let size = try uint(start, end: pageEnd)
                guard size >= 56, size <= pageEnd - start else { throw BrowserCookieError.corrupt }
                let end = start + size
                guard start >= previousRecordEnd else { throw BrowserCookieError.corrupt }
                previousRecordEnd = end
                func string(_ at: Int) throws -> String {
                    let offset = try uint(start + at, end: end)
                    guard offset >= 56, offset < size else { throw BrowserCookieError.corrupt }
                    let from = start + offset
                    guard let zero = bytes[from..<end].firstIndex(of: 0), let result = String(bytes: bytes[from..<zero], encoding: .utf8) else { throw BrowserCookieError.corrupt }
                    return result
                }
                let domain = try string(16)
                guard scope.contains(domain: domain) else { continue }
                let bits = bytes[start + 40..<start + 48].reversed().reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
                let seconds = Double(bitPattern: bits)
                let unix = seconds + 978_307_200
                guard seconds.isFinite, unix >= 0, unix < Double(Int64.max) else { throw BrowserCookieError.corrupt }
                let expiry = Int64(unix)
                guard expiry > now else { continue }
                let flags = try uint(start + 8, end: end)
                cookies.append(SessionCookie(domain: domain, name: try string(20), value: try string(28), path: try string(24), expires: expiry,
                                             secure: flags & 1 != 0, httpOnly: flags & 4 != 0))
                guard cookies.count <= 100_000 else { throw BrowserCookieError.corrupt }
            }
            pageStart = pageEnd
        }
        return cookies
    }
}
