import XCTest

@MainActor
class ScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--screenshots"]
        setupSnapshot(app)
        app.launch()
    }

    /// Vault: document grid with categories + recently added
    func testVault() throws {
        let app = XCUIApplication()
        snapshot("01-vault")
    }

    /// Document detail: passport with multi-page preview
    func testDocumentDetail() throws {
        let app = XCUIApplication()
        snapshot("02-document-detail")
    }

    /// Preparedness Checklist: gaps + ready states
    func testPreparedness() throws {
        let app = XCUIApplication()
        snapshot("03-preparedness")
    }

    /// Scan: capture sheet + auto-detect overlay
    func testScan() throws {
        let app = XCUIApplication()
        snapshot("04-scan")
    }

    /// Settings: cloud sync + entitlement status
    func testSettings() throws {
        let app = XCUIApplication()
        snapshot("05-settings")
    }
}
