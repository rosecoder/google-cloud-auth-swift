import Foundation

extension GoogleCloudSDKProvider {
    
    struct Token {

        let accessToken: String
        let expiresIn: Int
    }
}

extension GoogleCloudSDKProvider.Token: Decodable {

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
    }
}
