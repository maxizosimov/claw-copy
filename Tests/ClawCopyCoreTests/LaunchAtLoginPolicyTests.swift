import XCTest
@testable import ClawCopyCore

final class LaunchAtLoginPolicyTests: XCTestCase {
    func testEnabledByDefaultOnFirstLaunch() {
        XCTAssertTrue(LaunchAtLoginPolicy.shouldEnableOnLaunch(defaultApplied: false, state: .disabled))
    }

    func testUserChoiceIsRespectedAfterFirstLaunch() {
        // The user turned it off: later launches must not turn it back on.
        XCTAssertFalse(LaunchAtLoginPolicy.shouldEnableOnLaunch(defaultApplied: true, state: .disabled))
    }

    func testNothingToDoWhenAlreadyRegisteredOrUnavailable() {
        for state in [LoginItemState.enabled, .requiresApproval, .unavailable] {
            XCTAssertFalse(LaunchAtLoginPolicy.shouldEnableOnLaunch(defaultApplied: false, state: state), "\(state)")
        }
    }

    func testMenuCheckmark() {
        XCTAssertTrue(LaunchAtLoginPolicy.isOn(.enabled))
        XCTAssertTrue(LaunchAtLoginPolicy.isOn(.requiresApproval))
        XCTAssertFalse(LaunchAtLoginPolicy.isOn(.disabled))
        XCTAssertFalse(LaunchAtLoginPolicy.isOn(.unavailable))
    }
}
