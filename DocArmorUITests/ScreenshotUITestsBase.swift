import XCTest

open class ScreenshotUITestsBase: XCTestCase {
    var app: XCUIApplication!

    override open func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()

        // Enable ScreenshotMode seed data if running via fastlane or explicit CI flag
        if ProcessInfo.processInfo.environment["FASTLANE_SNAPSHOT"] == "1" ||
           ProcessInfo.processInfo.environment["SCREENSHOT_MODE"] == "1" {
            app.launchArguments = ["-ScreenshotMode", "seedData"]
        }

        app.launch()
    }

    override open func tearDownWithError() throws {
        app.terminate()
    }

    /// Helper to safely wait for element and verify visibility
    func waitForElement(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "exists == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
