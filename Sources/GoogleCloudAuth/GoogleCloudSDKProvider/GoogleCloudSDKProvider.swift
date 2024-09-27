import NIO
import Foundation
import AsyncHTTPClient
import NIOFoundationCompat

public actor GoogleCloudSDKProvider: Provider {

    let url: String
    let credentials: Credentials
    private var httpClient: HTTPClient?

    public init(credentials: Credentials) {
        self.init(url: "https://accounts.google.com/o/oauth2/token", credentials: credentials)
    }

    public init?() throws {
        guard let home = ProcessInfo.processInfo.environment["HOME"] else {
            return nil
        }
        let credentialsPath = home + "/.config/gcloud/application_default_credentials.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: credentialsPath)) else {
            return nil
        }
        let credentials = try JSONDecoder().decode(Credentials.self, from: data)
        self.init(credentials: credentials)
    }

    init(url: String, credentials: Credentials) {
        self.url = url
        self.credentials = credentials
    }

    public nonisolated func createSession(scopes: [Scope], eventLoopGroup: EventLoopGroup) async throws -> Session {
        let httpClient = try await getHTTPClient(eventLoopGroup: eventLoopGroup)
        
        var urlComponents = URLComponents(string: url)!
        urlComponents.queryItems = [
            .init(name: "client_id", value: credentials.clientID),
            .init(name: "client_secret", value: credentials.clientSecret),
            .init(name: "grant_type", value: "refresh_token"),
            .init(name: "refresh_token", value: credentials.refreshToken),
        ]
        var request = HTTPClientRequest(url: urlComponents.string!)
        request.method = .POST
        
        let response = try await httpClient.execute(request, timeout: .seconds(10))
        let body = try await response.body.collect(upTo: 1024 * 100) // 100 KB

        let token = try JSONDecoder().decode(Token.self, from: body)
        return Session(
            accessToken: token.accessToken,
            expiration: .absolute(Date().addingTimeInterval(TimeInterval(token.expiresIn)))
        )
    }

    private func getHTTPClient(eventLoopGroup: EventLoopGroup) async throws -> HTTPClient {
        if let httpClient {
            return httpClient
        }

        let client = HTTPClient(eventLoopGroupProvider: .shared(eventLoopGroup))
        self.httpClient = client
        return client
    }

    public nonisolated func shutdown() async throws {
        try await httpClient?.shutdown()
    }
}
