import Testing
import Foundation
@testable import GoogleCloudAuth

@Suite struct SessionTests {

    @Test func expiration() {
        let pastDate = Date().addingTimeInterval(-3600) // 1 hour ago
        let futureDate = Date().addingTimeInterval(3600) // 1 hour from now
        
        let expiredSession = Session(accessToken: "expired", expiration: .absolute(pastDate))
        #expect(expiredSession.isExpired == true)
        
        let validSession = Session(accessToken: "valid", expiration: .absolute(futureDate))
        #expect(validSession.isExpired == false)
        
        let neverExpiringSession = Session(accessToken: "never", expiration: .never)
        #expect(neverExpiringSession.isExpired == false)
    }
}
