// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import OnyxKit

final class SmokeTests: XCTestCase {
    func testVersion() { XCTAssertFalse(OnyxKitInfo.version.isEmpty) }
}
