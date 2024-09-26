import Foundation

extension ServiceAccountProvider {
    
    struct Token {

        let accessToken: String
        let expiresIn: Int?
    }
}

extension ServiceAccountProvider.Token: Decodable {

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
    }
}
