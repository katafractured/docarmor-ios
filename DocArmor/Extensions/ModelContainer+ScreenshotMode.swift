import SwiftData

extension ModelContainer {
    /// Seeds the model container with synthetic documents when ScreenshotMode is active.
    func seedScreenshotModeData() {
        guard ScreenshotMode.isEnabled else { return }

        let context = ModelContext(self)
        let seedDocs = ScreenshotMode.seedDocuments()

        for doc in seedDocs {
            context.insert(doc)
        }

        do {
            try context.save()
        } catch {
            print("⚠️  Failed to seed ScreenshotMode data: \(error)")
        }
    }
}
