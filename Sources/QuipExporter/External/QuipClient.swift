import Foundation

actor QuipClient {
    private let token: String
    private let rateDelay: TimeInterval
    private let base: URL
    private let session = URLSession.shared
    private let cacheDir: URL
    private let cacheTTL: TimeInterval = 24 * 60 * 60

    init(token: String, rateDelay: TimeInterval, domain: QuipDomain = .quipApple) {
        self.token = token
        self.rateDelay = rateDelay
        self.base = domain.baseURL
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.cacheDir = support.appendingPathComponent("QuipExporter/APICache")
    }

    private func authRequest(_ path: String) -> URLRequest {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return req
    }

    // Quip signals its rate limit two ways: a 429, or a 503 whose body reads
    // {"error_code":503,"error_description":"Over Rate Limit..."} — both get the same
    // Retry-After-aware backoff instead of failing the whole run outright.
    private let maxRetries = 5

    private func send(_ req: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var attempt = 0
        while true {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                throw MigrationError.api(statusCode: -1, path: req.url?.path ?? "", body: "")
            }
            let isRateLimited = http.statusCode == 429
                || (http.statusCode == 503 && String(data: data, encoding: .utf8)?.contains("Rate Limit") == true)
            if isRateLimited, attempt < maxRetries {
                try await Task.sleep(for: .seconds(retryDelay(after: http, attempt: attempt)))
                attempt += 1
                continue
            }
            return (data, http)
        }
    }

    private func retryDelay(after http: HTTPURLResponse, attempt: Int) -> TimeInterval {
        if let header = http.value(forHTTPHeaderField: "Retry-After"), let seconds = TimeInterval(header) {
            return seconds
        }
        return min(pow(2, Double(attempt)), 30)
    }

    // GET responses (folders/threads/current user) are cached to disk for up to a day —
    // repeated scans/runs over the same account otherwise refetch identical data and eat
    // into Quip's rate limit for no benefit. Cached at the raw-Data level (keyed by path)
    // so the decoded response types don't need Encodable conformance.
    private func cacheFile(for path: String) -> URL {
        let safe = path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).replacingOccurrences(of: "/", with: "_")
        return cacheDir.appendingPathComponent(safe + ".json")
    }

    private func readCache(_ path: String) -> Data? {
        let file = cacheFile(for: path)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
              let modified = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < cacheTTL
        else { return nil }
        return try? Data(contentsOf: file)
    }

    private func writeCache(_ path: String, _ data: Data) {
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try? data.write(to: cacheFile(for: path))
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        if let cached = readCache(path) {
            return try JSONDecoder().decode(T.self, from: cached)
        }
        try await Task.sleep(for: .seconds(rateDelay))
        let (data, http) = try await send(authRequest(path))
        if http.statusCode != 200 {
            throw MigrationError.api(statusCode: http.statusCode, path: path,
                                     body: String(data: data, encoding: .utf8) ?? "")
        }
        writeCache(path, data)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func getData(_ path: String) async throws -> Data {
        try await Task.sleep(for: .seconds(rateDelay))
        let (data, http) = try await send(authRequest(path))
        if http.statusCode != 200 {
            throw MigrationError.api(statusCode: http.statusCode, path: path,
                                     body: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    func getCurrentUser() async throws -> QuipCurrentUserResponse {
        try await get("/users/current")
    }

    func getFolder(_ id: String) async throws -> QuipFolderResponse {
        try await get("/folders/\(id)")
    }

    func getThread(_ id: String) async throws -> QuipThreadResponse {
        try await get("/threads/\(id)")
    }

    func getBlob(threadId: String, blobHash: String) async throws -> Data {
        try await getData("/threads/\(threadId)/blob/\(blobHash)")
    }

    func trashThread(_ threadId: String, trashFolderId: String) async throws {
        try await Task.sleep(for: .seconds(rateDelay))
        var req = URLRequest(url: base.appendingPathComponent("/folders/add-members"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = "folder_id=\(trashFolderId)&member_ids=\(threadId)".data(using: .utf8)
        let (data, http) = try await send(req)
        if http.statusCode != 200 {
            throw MigrationError.api(statusCode: http.statusCode, path: "/folders/add-members",
                                     body: String(data: data, encoding: .utf8) ?? "")
        }
    }
}
