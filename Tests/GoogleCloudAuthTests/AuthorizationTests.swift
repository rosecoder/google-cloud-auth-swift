import Testing
import NIO
import Foundation
@testable import GoogleCloudAuth

@Suite struct AuthorizationTests {

    @Test func getAccessTokenNotExpiredTwice() async throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let mockProvider = MockProvider(expiration: .absolute(Date().addingTimeInterval(3600)))
        let authorization = Authorization(scopes: ["https://www.googleapis.com/auth/cloud-platform"], provider: mockProvider, eventLoopGroup: eventLoopGroup)

        let token1 = try await authorization.accessToken()
        #expect(token1 == "token1")
        await #expect(mockProvider.createSessionCallCount == 1)

        let token2 = try await authorization.accessToken()
        #expect(token2 == "token1")
        await #expect(mockProvider.createSessionCallCount == 1)

        try await authorization.shutdown()
        await #expect(mockProvider.shutdownCallCount == 1)
    }

    @Test func getAccessTokenExpiredTwice() async throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let mockProvider = MockProvider(expiration: .always)
        let authorization = Authorization(scopes: ["https://www.googleapis.com/auth/cloud-platform"], provider: mockProvider, eventLoopGroup: eventLoopGroup)

        let token1 = try await authorization.accessToken()
        #expect(token1 == "token1")
        await #expect(mockProvider.createSessionCallCount == 1)

        let token2 = try await authorization.accessToken()
        #expect(token2 == "token2")
        await #expect(mockProvider.createSessionCallCount == 2)

        try await authorization.shutdown()
        await #expect(mockProvider.shutdownCallCount == 1)
    }

    private actor MockProvider: Provider {

        var createSessionCallCount = 0
        var shutdownCallCount = 0
        var currentSession: Session?

        let expiration: Session.Expiration

        init(expiration: Session.Expiration) {
            self.expiration = expiration
        }

        func createSession(scopes: [Scope], eventLoopGroup: EventLoopGroup) async throws -> Session {
            createSessionCallCount += 1
            return Session(
                accessToken: "token\(createSessionCallCount)",
                expiration: expiration
            )
        }

        func shutdown() async throws {
            shutdownCallCount += 1
        }
    }
}
