import NIO
import Foundation
import AsyncHTTPClient
import NIOFoundationCompat

public actor MetadataProvider: Provider {

    let url: String
    let timeout: TimeAmount

    private var httpClient: HTTPClient?

    public init(
        url: String = "http://metadata/computeMetadata/v1/instance/service-accounts/default/token",
        timeout: TimeAmount = .seconds(5)
    ) {
        self.url = url
        self.timeout = timeout
    }

    public struct NotInGCPEnvironmentError: Error, CustomStringConvertible {

        public var description: String {
            "The application is not running in a Google Cloud Platform environment. Unable to retrieve metadata from the GCP metadata server. If you are running this application locally, set the `GOOGLE_APPLICATION_CREDENTIALS` environment variable to the path of your service account key file."
        }
    }

    public nonisolated func createSession(scopes: [Scope], eventLoopGroup: EventLoopGroup) async throws -> Session {
        let httpClient = try await getHTTPClient(eventLoopGroup: eventLoopGroup)
        
        var request = HTTPClientRequest(url: url)
        request.method = .GET
        request.headers.add(name: "Metadata-Flavor", value: "Google")
        
        let response: HTTPClientResponse
        do {
            response = try await httpClient.execute(request, timeout: timeout)
        } catch let error as NIOConnectionError where error.dnsAAAAError != nil {
            throw NotInGCPEnvironmentError()
        }
        let body = try await response.body.collect(upTo: 1024 * 100) // 100 KB

        let token = try JSONDecoder().decode(Token.self, from: body)
        
        let expiration: Session.Expiration
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

    public nonisolated func shutdown() async throws {
        try await httpClient?.shutdown()
    }
}
