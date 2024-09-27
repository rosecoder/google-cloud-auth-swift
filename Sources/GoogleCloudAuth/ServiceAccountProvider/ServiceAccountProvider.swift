import NIO
import Foundation
import AsyncHTTPClient
import JWTKit
import NIOFoundationCompat

public actor ServiceAccountProvider: Provider {

    public nonisolated let credentials: Credentials

    private nonisolated let keysTask: Task<JWTKeyCollection, Error>
    private var httpClient: HTTPClient?

    public init(credentials: Credentials) throws {
        self.credentials = credentials

        let privateKey = try Insecure.RSA.PrivateKey(pem: credentials.privateKey)
        keysTask = Task {
            let keys = JWTKeyCollection()
            await keys.add(rsa: privateKey, digestAlgorithm: .sha256, kid: .init(string: credentials.privateKeyID))
            return keys
        }
    }

    public init(credentialsURL url: URL) throws {
        let credentialsData = try Data(contentsOf: url)
        let credentials = try JSONDecoder().decode(Credentials.self, from: credentialsData)
        try self.init(credentials: credentials)
    }

    public init?(environmentVariableName: String = "GOOGLE_APPLICATION_CREDENTIALS") throws {
        guard let urlString = ProcessInfo.processInfo.environment[environmentVariableName] else {
            return nil
        }
        try self.init(credentialsURL: URL(fileURLWithPath: urlString))
    }

    public enum CreateSessionError: Error {
        case unsuccessfulStatusCode(UInt, debugDescription: String)
    }

    public nonisolated func createSession(scopes: [Scope], eventLoopGroup: EventLoopGroup) async throws -> Session {
        let requestBody = TokenRequestBody(assertion: try await createAssertion(scopes: scopes))
        let httpClient = try await getHTTPClient(eventLoopGroup: eventLoopGroup)
        
        var request = HTTPClientRequest(url: credentials.tokenURI)
        request.method = .POST
        request.headers.add(name: "Content-Type", value: "application/json")
        request.body = .bytes(try JSONEncoder().encode(requestBody))
        
        let response = try await httpClient.execute(request, timeout: .seconds(10))
        let body = try await response.body.collect(upTo: 1024 * 100) // 100 KB

        guard (200..<300).contains(response.status.code) else {
            let debugDescription = String(buffer: body)
            throw CreateSessionError.unsuccessfulStatusCode(response.status.code, debugDescription: debugDescription)
        }

        let token = try JSONDecoder().decode(Token.self, from: body)
        
        let  expiration: Session.Expiration
        if let expiresIn = token.expiresIn {
            expiration = .absolute(Date().addingTimeInterval(TimeInterval(expiresIn)))
        } else {
            expiration = .never
        }
        return Session(accessToken: token.accessToken, expiration: expiration)
    }

    private func getHTTPClient(eventLoopGroup: EventLoopGroup) async throws -> HTTPClient {
        if let httpClient {
            return httpClient
        }

        let client = HTTPClient(eventLoopGroupProvider: .shared(eventLoopGroup))
        self.httpClient = client
        return client
    }

    private nonisolated func createAssertion(scopes: [Scope]) async throws -> String {
        let keys = try await keysTask.value
        
        let issuedAt = Date()
        let expiration = issuedAt.addingTimeInterval(3600)

        let payload = TokenRequestAssertionPayload(
            issuer: credentials.clientEmail,
            audience: credentials.tokenURI,
            scope: scopes.map(\.rawValue).joined(separator: " "),
            issuedAt: Int(issuedAt.timeIntervalSince1970),
            expiration: Int(expiration.timeIntervalSince1970)
        )

        let header: JWTHeader = ["typ": "JWT", "alg": "RS256"]

        return try await keys.sign(payload, kid: .init(string: credentials.privateKeyID), header: header)
    }

    public nonisolated func shutdown() async throws {
        try await httpClient?.shutdown()
    }
}
