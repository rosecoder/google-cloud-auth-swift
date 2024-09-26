import NIO
import Foundation
import AsyncHTTPClient
import JWTKit

extension ServiceAccountProvider {
    
    public struct Credentials {

        public let credentialType: String
        public let projectID: String
        public let privateKeyID: String
        public let privateKey: String
        public let clientEmail: String
        public let clientID: String
        public let authURI: String
        public let tokenURI: String
        public let authProviderX509CertURL: String
        public let clientX509CertURL: String

        public init(
            credentialType: String,
            projectID: String,
            privateKeyID: String,
            privateKey: String,
            clientEmail: String,
            clientID: String,
            authURI: String,
            tokenURI: String,
            authProviderX509CertURL: String,
            clientX509CertURL: String
        ) {
            self.credentialType = credentialType
            self.projectID = projectID
            self.privateKeyID = privateKeyID
            self.privateKey = privateKey
            self.clientEmail = clientEmail
            self.clientID = clientID
            self.authURI = authURI
            self.tokenURI = tokenURI
            self.authProviderX509CertURL = authProviderX509CertURL
            self.clientX509CertURL = clientX509CertURL
        }
    }
}

extension ServiceAccountProvider.Credentials: Sendable {}

extension ServiceAccountProvider.Credentials: Equatable {}

extension ServiceAccountProvider.Credentials: Hashable {}

extension ServiceAccountProvider.Credentials: Decodable {

    enum CodingKeys: String, CodingKey {
        case credentialType = "type"
        case projectID = "project_id"
        case privateKeyID = "private_key_id"
        case privateKey = "private_key"
        case clientEmail = "client_email"
        case clientID = "client_id"
        case authURI = "auth_uri"
        case tokenURI = "token_uri"
        case authProviderX509CertURL = "auth_provider_x509_cert_url"
        case clientX509CertURL = "client_x509_cert_url"
    }
}
