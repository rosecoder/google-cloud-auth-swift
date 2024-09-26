import NIO
import Foundation
import AsyncHTTPClient
import JWTKit

extension GoogleCloudSDKProvider {
    
    public struct Credentials {

        public let clientID: String
        public let clientSecret: String
        public let refreshToken: String
        public let tokenType: String

        public init(
            clientID: String,
            clientSecret: String,
            refreshToken: String,
            tokenType: String
        ) {
            self.clientID = clientID
            self.clientSecret = clientSecret
            self.refreshToken = refreshToken
            self.tokenType = tokenType
        }
    }
}

extension GoogleCloudSDKProvider.Credentials: Sendable {}

extension GoogleCloudSDKProvider.Credentials: Equatable {}

extension GoogleCloudSDKProvider.Credentials: Hashable {}

extension GoogleCloudSDKProvider.Credentials: Decodable {

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case clientSecret = "client_secret"
        case refreshToken = "refresh_token"
        case tokenType = "type"
    }
}
