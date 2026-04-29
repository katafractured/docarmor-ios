import Foundation

/// Mock data seeder for screenshot mode (--screenshots launch argument).
/// Provides sample documents (passport, ID, insurance, will) for fastlane snapshot CI.
///
/// Activate via launch arguments handled by ScreenshotMode.swift:
///   --screenshots               (master switch)
///   --mock-subscribed           (Sovereign cloud-sync entitlement active)
///   --mock-unsubscribed         (offline-only / paywall)
///   --seed-data preparedness    (seed enough docs to populate Preparedness panel)
///   --seed-data full-vault      (seed multi-category vault for vault frame)
///   --auto-open <doc-id>        (auto-open specific document on launch)
///
/// Tek wires this to the real DocumentStore / PreparednessChecker
/// when the 1.1.5 cloud-sync chunk lands. Until then this is a call-site
/// stub so XCUITests can launch with --screenshots and not crash when
/// ViewModels probe ScreenshotMode.
struct MockDataSeeder {
    static func seedDataIfNeeded() {
        guard CommandLine.arguments.contains("--screenshots") else { return }
        // TODO: wire to DocumentStore / PreparednessChecker / category seeds.
        print("MockDataSeeder: TODO — wire to DocArmor document/preparedness models")
    }
}
