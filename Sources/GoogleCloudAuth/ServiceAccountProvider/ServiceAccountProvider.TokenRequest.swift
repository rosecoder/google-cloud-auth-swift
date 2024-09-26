import JWTKit

extension ServiceAccountProvider {
    
    struct TokenRequestBody: Encodable {

        let grantType = "urn:ietf:params:oauth:grant-type:jwt-bearer"
        let assertion: String

        enum CodingKeys: String, CodingKey {
            case grantType = "grant_type"
            case assertion
        }
    }

    struct TokenRequestAssertionPayload: JWTPayload {
        
        let issuer: String
        let audience: String
        let scope: String
        let issuedAt: Int
        let expiration: Int

        enum CodingKeys: String, CodingKey {
            case issuer = "iss"
            case audience = "aud"
            case scope = "scope"
            case issuedAt = "iat"
            case expiration = "exp"
        }

        func verify(using algorithm: some JWTKit.JWTAlgorithm) async throws {}
    }
}
