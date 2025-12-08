extension ServiceAccountImpersonationProvider {

  /// Request body for generating an access token via the IAM Credentials API.
  struct GenerateAccessTokenRequest: Encodable {
    /// The list of scopes to include in the access token.
    let scope: [String]

    /// The lifetime of the access token in duration format (e.g., "3600s").
    let lifetime: String
  }

  /// Response from the IAM Credentials API when generating an access token.
  struct GenerateAccessTokenResponse: Decodable {
    /// The generated access token.
    let accessToken: String

    /// The time when the access token will expire, in ISO8601 format.
    let expireTime: String
  }
}
