import XCTest
@testable import ClockifyWatcher

final class KeychainHelperTests: XCTestCase {
    let testService = "clockify-watcher-test"
    let testAccount = "api-key"

    override func setUp() {
        super.setUp()
        KeychainHelper.delete(service: testService, account: testAccount)
    }

    override func tearDown() {
        KeychainHelper.delete(service: testService, account: testAccount)
    }

    func testSaveAndLoad() {
        KeychainHelper.save("test-api-key-123", service: testService, account: testAccount)
        let loaded = KeychainHelper.load(service: testService, account: testAccount)
        XCTAssertEqual(loaded, "test-api-key-123")
    }

    func testLoadReturnsNilWhenAbsent() {
        let loaded = KeychainHelper.load(service: testService, account: testAccount)
        XCTAssertNil(loaded)
    }

    func testOverwrite() {
        KeychainHelper.save("first-key", service: testService, account: testAccount)
        KeychainHelper.save("second-key", service: testService, account: testAccount)
        let loaded = KeychainHelper.load(service: testService, account: testAccount)
        XCTAssertEqual(loaded, "second-key")
    }

    func testDelete() {
        KeychainHelper.save("test-key", service: testService, account: testAccount)
        KeychainHelper.delete(service: testService, account: testAccount)
        let loaded = KeychainHelper.load(service: testService, account: testAccount)
        XCTAssertNil(loaded)
    }
}
