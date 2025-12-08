import Foundation
import NIO
import NIOHTTP1
import Testing

@testable import GoogleCloudAuth

@Suite struct ServiceAccountImpersonationProviderTests {

  @Test func createSessionShouldImpersonateServiceAccount() async throws {
    let (eventLoopGroup, url, mockedIAMCredentialsServer) = try await mockIAMCredentialsServer()
    let mockSourceProvider = MockProvider(accessToken: "source-token")

    let provider = ServiceAccountImpersonationProvider(
      sourceProvider: mockSourceProvider,
      targetServiceAccount: "target@project.iam.gserviceaccount.com",
      baseURL: url
    )

    let session = try await provider.createSession(
      scopes: ["https://www.googleapis.com/auth/bigquery"],
      eventLoopGroup: eventLoopGroup
    )

    #expect(session.accessToken == "impersonated-token-1")
    #expect(!session.isExpired)

    try await provider.shutdown()
    try await mockedIAMCredentialsServer.close()
  }

  @Test func createSessionShouldHandleMultipleRequests() async throws {
    let (eventLoopGroup, url, mockedIAMCredentialsServer) = try await mockIAMCredentialsServer()
    let mockSourceProvider = MockProvider(accessToken: "source-token")

    let provider = ServiceAccountImpersonationProvider(
      sourceProvider: mockSourceProvider,
      targetServiceAccount: "target@project.iam.gserviceaccount.com",
      baseURL: url
    )

    let session1 = try await provider.createSession(
      scopes: ["https://www.googleapis.com/auth/bigquery"],
      eventLoopGroup: eventLoopGroup
    )
    #expect(session1.accessToken == "impersonated-token-1")
    #expect(!session1.isExpired)

    let session2 = try await provider.createSession(
      scopes: ["https://www.googleapis.com/auth/bigquery"],
      eventLoopGroup: eventLoopGroup
    )
    #expect(session2.accessToken == "impersonated-token-2")
    #expect(!session2.isExpired)

    try await provider.shutdown()
    try await mockedIAMCredentialsServer.close()
    // if HTTP client wasn't reused, this will cause an assertion from the AsyncHTTPClient
  }

  @Test func createSessionShouldThrowForUnsuccessfulStatusCode() async throws {
    let (eventLoopGroup, url, mockedIAMCredentialsServer) = try await mockIAMCredentialsServer(
      statusCode: .forbidden,
      response: """
        {
            "error": {
                "code": 403,
                "message": "Permission denied"
            }
        }
        """
    )
    let mockSourceProvider = MockProvider(accessToken: "source-token")

    let provider = ServiceAccountImpersonationProvider(
      sourceProvider: mockSourceProvider,
      targetServiceAccount: "target@project.iam.gserviceaccount.com",
      baseURL: url
    )

    await #expect(throws: ServiceAccountImpersonationProvider.CreateSessionError.self) {
      try await provider.createSession(
        scopes: ["https://www.googleapis.com/auth/bigquery"],
        eventLoopGroup: eventLoopGroup
      )
    }

    try await provider.shutdown()
    try await mockedIAMCredentialsServer.close()
  }

  @Test func createSessionShouldParseExpireTime() async throws {
    let futureDate = Date().addingTimeInterval(1800)  // 30 minutes from now
    let formatter = ISO8601DateFormatter()
    let expireTimeString = formatter.string(from: futureDate)

    let (eventLoopGroup, url, mockedIAMCredentialsServer) = try await mockIAMCredentialsServer(
      response: """
        {
            "accessToken": "impersonated-token-#requestCounter",
            "expireTime": "\(expireTimeString)"
        }
        """
    )
    let mockSourceProvider = MockProvider(accessToken: "source-token")

    let provider = ServiceAccountImpersonationProvider(
      sourceProvider: mockSourceProvider,
      targetServiceAccount: "target@project.iam.gserviceaccount.com",
      baseURL: url
    )

    let session = try await provider.createSession(
      scopes: ["https://www.googleapis.com/auth/bigquery"],
      eventLoopGroup: eventLoopGroup
    )

    #expect(session.accessToken == "impersonated-token-1")
    #expect(!session.isExpired)

    // Verify the expiration is roughly correct (within 5 seconds)
    if case .absolute(let expirationDate) = session.expiration {
      let difference = abs(expirationDate.timeIntervalSince(futureDate))
      #expect(difference < 5, "Expiration date should be within 5 seconds of expected")
    } else {
      Issue.record("Expected absolute expiration")
    }

    try await provider.shutdown()
    try await mockedIAMCredentialsServer.close()
  }

  @Test func createSessionShouldFallbackToLifetimeOnInvalidExpireTime() async throws {
    let (eventLoopGroup, url, mockedIAMCredentialsServer) = try await mockIAMCredentialsServer(
      response: """
        {
            "accessToken": "impersonated-token-#requestCounter",
            "expireTime": "invalid-date"
        }
        """
    )
    let mockSourceProvider = MockProvider(accessToken: "source-token")
    let lifetime = 1800

    let provider = ServiceAccountImpersonationProvider(
      sourceProvider: mockSourceProvider,
      targetServiceAccount: "target@project.iam.gserviceaccount.com",
      lifetime: lifetime,
      baseURL: url
    )

    let beforeSession = Date()
    let session = try await provider.createSession(
      scopes: ["https://www.googleapis.com/auth/bigquery"],
      eventLoopGroup: eventLoopGroup
    )

    #expect(session.accessToken == "impersonated-token-1")
    #expect(!session.isExpired)

    // Verify fallback to lifetime-based expiration
    if case .absolute(let expirationDate) = session.expiration {
      let expectedExpiration = beforeSession.addingTimeInterval(TimeInterval(lifetime))
      let difference = abs(expirationDate.timeIntervalSince(expectedExpiration))
      #expect(difference < 5, "Expiration should fall back to lifetime-based calculation")
    } else {
      Issue.record("Expected absolute expiration")
    }

    try await provider.shutdown()
    try await mockedIAMCredentialsServer.close()
  }

  @Test func shutdownShouldShutdownSourceProvider() async throws {
    let mockSourceProvider = MockProvider(accessToken: "source-token")

    let provider = ServiceAccountImpersonationProvider(
      sourceProvider: mockSourceProvider,
      targetServiceAccount: "target@project.iam.gserviceaccount.com"
    )

    #expect(await mockSourceProvider.shutdownCalled == false)
    try await provider.shutdown()
    #expect(await mockSourceProvider.shutdownCalled == true)
  }

  // MARK: - Mock Provider

  private actor MockProvider: Provider {
    let accessToken: String
    var shutdownCalled = false

    init(accessToken: String) {
      self.accessToken = accessToken
    }

    nonisolated func createSession(scopes: [Scope], eventLoopGroup: EventLoopGroup) async throws
      -> Session
    {
      Session(
        accessToken: accessToken,
        expiration: .absolute(Date().addingTimeInterval(3600))
      )
    }

    func shutdown() async throws {
      shutdownCalled = true
    }
  }

  // MARK: - Mock Server

  private func mockIAMCredentialsServer(
    statusCode: HTTPResponseStatus = .ok,
    response: String = """
    {
        "accessToken": "impersonated-token-#requestCounter",
        "expireTime": "2099-12-31T23:59:59Z"
    }
    """
  ) async throws -> (eventLoopGroup: EventLoopGroup, url: String, channel: any Channel) {

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
      .serverChannelOption(
        ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1
      )
      .childChannelInitializer { channel in
        channel.pipeline.configureHTTPServerPipeline().flatMap { _ in
          requestCounter += 1
          return channel.pipeline.addHandler(
            HTTPHandler(
              statusCode: statusCode,
              response: response.replacingOccurrences(
                of: "#requestCounter", with: "\(requestCounter)")
            ))
        }
      }
      .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
      .childChannelOption(
        ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1
      )
      .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)

    let channel = try await bootstrap.bind(host: host, port: port).get()
    return (eventLoopGroup, "http://\(host):\(port)", channel)
  }
}
