import Testing
import Foundation
@testable import GoogleCloudAuth
import NIO
import NIOHTTP1

@Suite struct MetadataProviderTests {

    @Test(.disabled("This test requires running in a GCP environment."))
    func createSessionProduction() async throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)

        // Create provider
        let provider = MetadataProvider()

        // Create session
        let session = try await provider.createSession(scopes: ["https://www.googleapis.com/auth/cloud-platform"], eventLoopGroup: eventLoopGroup)
        #expect(!session.isExpired)
        #expect(!session.accessToken.isEmpty)

        // Cleanup
        try await provider.shutdown()
    }

    @Test func createSessionShouldThrowRunningInNonGCPEnvironment() async throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let provider = MetadataProvider(timeout: .milliseconds(10))
        await #expect(throws: MetadataProvider.NotInGCPEnvironmentError.self) {
            try await provider.createSession(scopes: ["https://www.googleapis.com/auth/cloud-platform"], eventLoopGroup: eventLoopGroup)
        }
        try await provider.shutdown()
    }

    @Test func createSessionShouldHandleMultipleRequests() async throws {
        let (eventLoopGroup, url, mockedTokenServerChannel) = try await self.mockMetadataServer()
        let provider = MetadataProvider(url: url)

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
        let (eventLoopGroup, url, mockedTokenServerChannel) = try await self.mockMetadataServer(response: """
        {
            "access_token": "mocked"
        }
        """)
        let provider = MetadataProvider(url: url)

        let session = try await provider.createSession(scopes: ["https://www.googleapis.com/auth/cloud-platform"], eventLoopGroup: eventLoopGroup)
        #expect(session.accessToken == "mocked")
        #expect(!session.isExpired)
        #expect(session.expiration == .never)

        try await provider.shutdown()
        try await mockedTokenServerChannel.close()
    }

    private func mockMetadataServer(
        response: String = """
        {
            "access_token": "mocked-#requestCounter",
            "expires_in": 3600
        }
        """
    ) async throws -> (eventLoopGroup: EventLoopGroup, tokenURI: String, channel: any Channel) {

        final class HTTPHandler: ChannelInboundHandler {

            typealias InboundIn = HTTPServerRequestPart

            let response: String

            init(response: String) {
                self.response = response
            }

            func channelRead(context: ChannelHandlerContext, data: NIOAny) {
                let reqPart = unwrapInboundIn(data)
                let channel = context.channel

                switch reqPart {
                case .head, .body:
                    break
                case .end:
                    var head = HTTPResponseHead(version: .http1_1, status: .ok)
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
                        response: response.replacingOccurrences(of: "#requestCounter", with: "\(requestCounter)")
                    ))
                }
            }
            .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
            .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)

        let channel = try await bootstrap.bind(host: host, port: port).get()
        return (eventLoopGroup, "http://\(host):\(port)/computeMetadata/v1/instance/service-accounts/default/token", channel)
    }
}
