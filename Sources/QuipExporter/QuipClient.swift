import Foundation

actor QuipClient {
    private let token: String
    private let rateDelay: TimeInterval
    private let base: URL
    private let session = URLSession.shared

    init(token: String, rateDelay: TimeInterval, domain: QuipDomain = .quipApple) {
        self.token = token
        self.rateDelay = rateDelay
        self.base = domain.baseURL
    }

    private func authRequest(_ path: String) -> URLRequest {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return req
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try await Task.sleep(for: .seconds(rateDelay))
        let (data, resp) = try await session.data(for: authRequest(path))
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw MigrationError.api(statusCode: http.statusCode, path: path,
                                     body: String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func getData(_ path: String) async throws -> Data {
        try await Task.sleep(for: .seconds(rateDelay))
        let (data, resp) = try await session.data(for: authRequest(path))
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
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
        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw MigrationError.api(statusCode: http.statusCode, path: "/folders/add-members",
                                     body: String(data: data, encoding: .utf8) ?? "")
        }
    }
}
