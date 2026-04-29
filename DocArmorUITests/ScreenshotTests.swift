import XCTest

@MainActor
class ScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Frame 01: Vault — document grid with categories

    func testVault() {
        _ = launch(flags: defaultFlags)
        sleep(3)
        snapshot("01-vault")
    }

    // MARK: - Frame 02: Document detail (auto-open passport)

    func testDocumentDetail() {
        _ = launch(flags: defaultFlags + ["--auto-open", "passport"])
        sleep(3)
        snapshot("02-document-detail")
    }

    // MARK: - Frame 03: Preparedness Checklist (gaps + ready states)

    func testPreparedness() {
        let app = launch(flags: defaultFlags + ["--seed-data", "preparedness"])
        sleep(3)
        let prepTab = app.buttons.matching(identifier: "preparedness-tab").firstMatch
        if prepTab.waitForExistence(timeout: 4) {
            prepTab.tap()
            sleep(2)
        }
        snapshot("03-preparedness")
    }

    // MARK: - Frame 04: Scan capture sheet

    func testScan() {
        let app = launch(flags: defaultFlags)
        sleep(3)
        let scanButton = app.buttons.matching(identifier: "scan-button").firstMatch
        if scanButton.waitForExistence(timeout: 4) {
            scanButton.tap()
            sleep(2)
        }
        snapshot("04-scan")
    }

    // MARK: - Frame 05: Settings (cloud sync + entitlement)

    func testSettings() {
        let app = launch(flags: defaultFlags)
        sleep(3)
        let settingsTab = app.buttons.matching(identifier: "settings-tab").firstMatch
        if settingsTab.waitForExistence(timeout: 4) {
            settingsTab.tap()
            sleep(2)
        }
        snapshot("05-settings")
    }

    // MARK: - Helpers

    private var defaultFlags: [String] {
        [
            "--screenshots",
            "--skip-onboarding",
            "--mock-subscribed",
            "--seed-data", "full-vault",
        ]
    }

    private func launch(flags: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launchArguments += flags
        app.launch()
        return app
    }
}
