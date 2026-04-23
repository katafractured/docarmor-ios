import XCTest

final class ScreenshotTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ScreenshotMode", "seedData"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    /// Screenshot 1: Hero scanner — camera viewfinder edge-outline
    func test_01_HeroScanner() throws {
        let scanButton = app.buttons["scanDocument"]
        XCTAssertTrue(scanButton.exists)
        scanButton.tap()

        sleep(1)
        snapshot("01_HeroScanner_iPhone17ProMax")
    }

    /// Screenshot 2: Vault list — 4-5 synthetic documents
    func test_02_VaultList() throws {
        let vaultTab = app.tabBars.buttons["vault"]
        XCTAssertTrue(vaultTab.exists)
        vaultTab.tap()

        sleep(1)
        snapshot("02_VaultList_iPhone17ProMax")
    }

    /// Screenshot 3: Document detail — OCR text + image + encryption shield
    func test_03_DocumentDetail() throws {
        let vaultTab = app.tabBars.buttons["vault"]
        vaultTab.tap()

        sleep(1)
        let firstDoc = app.cells.element(boundBy: 0)
        XCTAssertTrue(firstDoc.exists)
        firstDoc.tap()

        sleep(1)
        snapshot("03_DocumentDetail_iPhone17ProMax")
    }

    /// Screenshot 4: Paywall v2 — $12.99 unlock OR Sovereign state
    func test_04_PaywallV2() throws {
        let settingsTab = app.tabBars.buttons["settings"]
        XCTAssertTrue(settingsTab.exists)
        settingsTab.tap()

        sleep(1)
        let paywallButton = app.buttons["manageSubscription"]
        if paywallButton.exists {
            paywallButton.tap()
            sleep(1)
            snapshot("04_PaywallV2_iPhone17ProMax")
        } else {
            snapshot("04_PaywallV2_Sovereign_iPhone17ProMax")
        }
    }

    /// Screenshot 5: Settings — Face ID toggle, encryption, household switcher
    func test_05_Settings() throws {
        let settingsTab = app.tabBars.buttons["settings"]
        settingsTab.tap()

        sleep(1)
        snapshot("05_Settings_iPhone17ProMax")
    }

    /// Screenshot 6: Widget glance — recent scan
    func test_06_WidgetPreview() throws {
        let widgetButton = app.buttons["widgetPreview"]
        if widgetButton.exists {
            widgetButton.tap()
            sleep(1)
            snapshot("06_WidgetPreview_iPhone17ProMax")
        }
    }
}

// MARK: - iPad Pro 13-inch (M5) Variants

final class ScreenshotTests_iPad: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ScreenshotMode", "seedData"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    func test_iPad_01_VaultList() throws {
        let vaultTab = app.tabBars.buttons["vault"]
        XCTAssertTrue(vaultTab.exists)
        vaultTab.tap()

        sleep(1)
        snapshot("01_VaultList_iPad13ProM5")
    }

    func test_iPad_02_DocumentDetail() throws {
        let vaultTab = app.tabBars.buttons["vault"]
        vaultTab.tap()

        sleep(1)
        let firstDoc = app.cells.element(boundBy: 0)
        XCTAssertTrue(firstDoc.exists)
        firstDoc.tap()

        sleep(1)
        snapshot("02_DocumentDetail_iPad13ProM5")
    }

    func test_iPad_03_Settings() throws {
        let settingsTab = app.tabBars.buttons["settings"]
        settingsTab.tap()

        sleep(1)
        snapshot("03_Settings_iPad13ProM5")
    }
}

// MARK: - Snapshot Helper

func snapshot(_ name: String) {
    // Fastlane snapshot integration point — will be called by fastlane's snapshot() function
    // For local testing, this is a no-op; CI workflow uses FASTLANE_SNAPSHOT=1
    if ProcessInfo.processInfo.environment["FASTLANE_SNAPSHOT"] == "1" {
        // Fastlane will intercept this function call
        XCUIApplication().snapshot(name)
    }
}
