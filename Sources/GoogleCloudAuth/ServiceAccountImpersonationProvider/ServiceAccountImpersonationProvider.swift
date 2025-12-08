import AsyncHTTPClient
import Foundation
import NIO
import NIOFoundationCompat

/// A provider that impersonates a service account by obtaining an access token on its behalf.
///
/// This provider uses another provider to authenticate, then calls the IAM Credentials API
/// to generate an access token for the target service account.
public actor ServiceAccountImpersonationProvider: Provider {

  /// The source provider used to obtain the initial access token.
  public nonisolated let sourceProvider: Provider

  /// The email address of the service account to impersonate.
  public nonisolated let targetServiceAccount: String

  /// The lifetime of the generated access token in seconds. Defaults to 3600 (1 hour).
  public nonisolated let lifetime: Int

  /// The base URL for the IAM Credentials API. Used for testing.
  nonisolated let baseURL: String

  private var httpClient: HTTPClient?

  /// Creates a new service account impersonation provider.
  ///
  /// - Parameters:
  ///   - sourceProvider: The provider used to obtain the initial access token for authentication.
  ///   - targetServiceAccount: The email address of the service account to impersonate.
  ///   - lifetime: The lifetime of the generated access token in seconds. Defaults to 3600 (1 hour).
  ///               Must be between 0 and 43200 (12 hours).
  public init(
    sourceProvider: Provider,
    targetServiceAccount: String,
    lifetime: Int = 3600
  ) {
    self.sourceProvider = sourceProvider
    self.targetServiceAccount = targetServiceAccount
    self.lifetime = lifetime
    self.baseURL = "https://iamcredentials.googleapis.com"
  }

  /// Internal initializer that allows overriding the base URL for testing.
  init(
    sourceProvider: Provider,
    targetServiceAccount: String,
    lifetime: Int = 3600,
    baseURL: String
  ) {
    self.sourceProvider = sourceProvider
    self.targetServiceAccount = targetServiceAccount
    self.lifetime = lifetime
    self.baseURL = baseURL
  }

  public enum CreateSessionError: Error {
    case unsuccessfulStatusCode(UInt, debugDescription: String)
  }

  public nonisolated func createSession(scopes: [Scope], eventLoopGroup: EventLoopGroup)
    async throws -> Session
  {
    // First, get an access token from the source provider
    // We need cloud-platform scope to call the IAM Credentials API
    let sourceSession = try await sourceProvider.createSession(
      scopes: ["https://www.googleapis.com/auth/cloud-platform"],
      eventLoopGroup: eventLoopGroup
    )

    let httpClient = try await getHTTPClient(eventLoopGroup: eventLoopGroup)

    let url =
      "\(baseURL)/v1/projects/-/serviceAccounts/\(targetServiceAccount):generateAccessToken"

    var request = HTTPClientRequest(url: url)
    request.method = .POST
    request.headers.add(name: "Authorization", value: "Bearer \(sourceSession.accessToken)")
    request.headers.add(name: "Content-Type", value: "application/json")

    let requestBody = GenerateAccessTokenRequest(
      scope: scopes.map(\.rawValue),
      lifetime: "\(lifetime)s"
    )
    request.body = .bytes(try JSONEncoder().encode(requestBody))

    let response = try await httpClient.execute(request, timeout: .seconds(30))
    let body = try await response.body.collect(upTo: 1024 * 100)  // 100 KB

    guard (200..<300).contains(response.status.code) else {
      let debugDescription = String(buffer: body)
      throw CreateSessionError.unsuccessfulStatusCode(
        response.status.code, debugDescription: debugDescription)
    }

    let tokenResponse = try JSONDecoder().decode(GenerateAccessTokenResponse.self, from: body)

    // Parse the expireTime from ISO8601 format
    let expiration: Session.Expiration
    if let expireDate = ISO8601DateFormatter().date(from: tokenResponse.expireTime) {
      expiration = .absolute(expireDate)
    } else {
      // Fallback to using the lifetime if parsing fails
      expiration = .absolute(Date().addingTimeInterval(TimeInterval(lifetime)))
    }

    return Session(accessToken: tokenResponse.accessToken, expiration: expiration)
  }

  private func getHTTPClient(eventLoopGroup: EventLoopGroup) async throws -> HTTPClient {
    if let httpClient {
      return httpClient
    }

    let client = HTTPClient(eventLoopGroupProvider: .shared(eventLoopGroup))
    self.httpClient = client
    return client
  }

  public nonisolated func shutdown() async throws {
    try await httpClient?.shutdown()
    try await sourceProvider.shutdown()
  }
}
