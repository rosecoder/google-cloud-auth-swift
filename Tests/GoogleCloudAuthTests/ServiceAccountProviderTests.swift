import Testing
import Foundation
@testable import GoogleCloudAuth
import NIO
import NIOHTTP1

@Suite struct ServiceAccountProviderTests {

    private static var hasConfiguredServiceAccountLocally: Bool {
        let currentDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let serviceAccountPath = currentDirectory.appendingPathComponent("service-account.json").path
        return FileManager.default.fileExists(atPath: serviceAccountPath)
    }

    @Test(.enabled(
        if: ServiceAccountProviderTests.hasConfiguredServiceAccountLocally,
        "This test is using production Google Cloud Service Account JSON file. This file is ignored in Git and have to be placed in the same directory as this file, named `service-account.json`."
    )) func createSessionProduction() async throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let environmentVariableName = "GOOGLE_APPLICATION_CREDENTIALS_\(#fileID)_\(#line)"

        // Configure environment variable for service account
        let currentDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let serviceAccountPath = currentDirectory.appendingPathComponent("service-account.json").path
        setenv(environmentVariableName, serviceAccountPath, 1)
        
        // Create provider
        let provider = try #require(try ServiceAccountProvider(environmentVariableName: environmentVariableName))

        // Create session
        let session = try await provider.createSession(scopes: ["https://www.googleapis.com/auth/cloud-platform"], eventLoopGroup: eventLoopGroup)
        #expect(!session.isExpired)
        #expect(!session.accessToken.isEmpty)

        // Cleanup
        try await provider.shutdown()
    }

    @Test func createSessionShouldReturnNilForMissingEnvironmentVariable() async throws {
        let provider = try ServiceAccountProvider(environmentVariableName: "MISSING_ENV_VAR")
        #expect(provider == nil)
    }

    @Test func createSessionShouldHandleMultipleRequests() async throws {
        let (eventLoopGroup, tokenURI, mockedTokenServerChannel) = try await self.mockServiceAccountTokenServer()
        let credentials = createMockCredentials(tokenURI: tokenURI)
        let provider = try ServiceAccountProvider(credentials: credentials)

        let session1 = try await provider.createSession(scopes: ["https://www.googleapis.com/auth/cloud-platform"], eventLoopGroup: eventLoopGroup)
        #expect(session1.accessToken == "mocked-1")
        #expect(!session1.isExpired)

        let session2 = try await provider.createSession(scopes: ["https://www.googleapis.com/auth/cloud-platform"], eventLoopGroup: eventLoopGroup)
        #expect(session2.accessToken == "mocked-2")
        #expect(!session2.isExpired)

        try await provider.shutdown()
        try await mockedTokenServerChannel.close()
        // if HTTP client wasn't reused, this will cause a assertion from the AsyncHTTPClient
    }

    @Test func createSessionShouldHandleNoExpiration() async throws {
        let (eventLoopGroup, tokenURI, mockedTokenServerChannel) = try await self.mockServiceAccountTokenServer(response: """
        {
            "access_token": "mocked"
        }
        """)
        let credentials = createMockCredentials(tokenURI: tokenURI)
        let provider = try ServiceAccountProvider(credentials: credentials)

        let session = try await provider.createSession(scopes: ["https://www.googleapis.com/auth/cloud-platform"], eventLoopGroup: eventLoopGroup)
        #expect(session.accessToken == "mocked")
        #expect(!session.isExpired)
        #expect(session.expiration == .never)

        try await provider.shutdown()
        try await mockedTokenServerChannel.close()
    }

    @Test func createSessionShouldThrowForUnsuccessfulStatusCode() async throws {
        let (eventLoopGroup, tokenURI, mockedTokenServerChannel) = try await self.mockServiceAccountTokenServer(
            statusCode: .internalServerError,
            response: "Me not feeling well today"
        )
        let credentials = createMockCredentials(tokenURI: tokenURI)
        let provider = try ServiceAccountProvider(credentials: credentials)

        await #expect(throws: ServiceAccountProvider.CreateSessionError.self) {
            try await provider.createSession(scopes: ["https://www.googleapis.com/auth/cloud-platform"], eventLoopGroup: eventLoopGroup)
        }
        try await provider.shutdown()
        try await mockedTokenServerChannel.close()
    }

    private func createMockCredentials(tokenURI: String) -> ServiceAccountProvider.Credentials {
        ServiceAccountProvider.Credentials(
            credentialType: "service_account",
            projectID: "mock-project-id",
            privateKeyID: "mock-private-key-id",
            privateKey: mockedPrivateKey,
            clientEmail: "mock-service-account@mock-project-id.iam.gserviceaccount.com",
            clientID: "123456789012345678901",
            authURI: "https://accounts.google.com/o/oauth2/auth",
            tokenURI: tokenURI,
            authProviderX509CertURL: "https://www.googleapis.com/oauth2/v1/certs",
            clientX509CertURL: "https://www.googleapis.com/robot/v1/metadata/x509/mock-service-account%40mock-project-id.iam.gserviceaccount.com"
        )
    }

    private let mockedPrivateKey = """
    -----BEGIN RSA PRIVATE KEY-----
    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
    -----END RSA PRIVATE KEY-----
    """

    private func mockServiceAccountTokenServer(
        statusCode: HTTPResponseStatus = .ok,
        response: String = """
        {
            "access_token": "mocked-#requestCounter",
            "expires_in": 3600
        }
        """
    ) async throws -> (eventLoopGroup: EventLoopGroup, tokenURI: String, channel: any Channel) {

        final class HTTPHandler: ChannelInboundHandler {

            typealias InboundIn = HTTPServerRequestPart

            let statusCode: HTTPResponseStatus
            let response: String

            init(statusCode: HTTPResponseStatus, response: String) {
                self.statusCode = statusCode
                self.response = response
            }

            func channelRead(context: ChannelHandlerContext, data: NIOAny) {
                let reqPart = unwrapInboundIn(data)
                let channel = context.channel

                switch reqPart {
                case .head, .body:
                    break
                case .end:
                    var head = HTTPResponseHead(version: .http1_1, status: statusCode)
                    head.headers.add(name: "Content-Type", value: "application/json")
                    _ = channel.write(HTTPServerResponsePart.head(head))
                    var outputBuffer = channel.allocator.buffer(capacity: response.utf8.count)
                    outputBuffer.writeString(response)
                    _ = channel.write(HTTPServerResponsePart.body(.byteBuffer(outputBuffer)))
                    channel.writeAndFlush(HTTPServerResponsePart.end(nil)).whenComplete { _ in
                        channel.close(promise: nil)
                    }
                }
            }
        }

        nonisolated(unsafe) var requestCounter = 0

        let host = "127.0.0.1"
        let port = Int.random(in: 49152...65535)
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let bootstrap = ServerBootstrap(group: eventLoopGroup)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap { _ in
                    requestCounter += 1
                    return channel.pipeline.addHandler(HTTPHandler(
                        statusCode: statusCode,
                        response: response.replacingOccurrences(of: "#requestCounter", with: "\(requestCounter)")
                    ))
                }
            }
            .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
            .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)

        let channel = try await bootstrap.bind(host: host, port: port).get()
        return (eventLoopGroup, "http://\(host):\(port)/token", channel)
    }
}
