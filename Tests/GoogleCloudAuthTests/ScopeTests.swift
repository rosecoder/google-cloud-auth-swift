import Testing
import Foundation
@testable import GoogleCloudAuth

@Suite struct ScopeTests {

    @Test func expressibleByStringLiteral() {
        let scope: Scope = "https://www.googleapis.com/auth/cloud-platform"
        #expect(scope.rawValue == "https://www.googleapis.com/auth/cloud-platform")
        
        let customScope: Scope = "custom.scope"
        #expect(customScope.rawValue == "custom.scope")
    }
}
