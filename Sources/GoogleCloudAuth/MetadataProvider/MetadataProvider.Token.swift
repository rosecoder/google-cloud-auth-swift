import Foundation

extension MetadataProvider {
    
    struct Token {

        let accessToken: String
        let expiresIn: Int?
    }
}

extension MetadataProvider.Token: Decodable {

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
    }
}
