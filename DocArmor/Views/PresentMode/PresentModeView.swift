import SwiftUI
import UIKit

/// Full-screen document display for showing to airport agents, hotel staff, etc.
/// - Max brightness
/// - Landscape orientation forced
/// - No navigation/tab chrome
/// - Screenshot prevention disabled (user is intentionally showing the doc)
struct PresentModeView: View {
    let images: [UIImage]
    let initialIndex: Int
    let documentName: String

    @Environment(\.dismiss) private var dismiss
    @Environment(EntitlementService.self) private var entitlementService
    @State private var currentIndex: Int
    @State private var showingDismissConfirm = false
    @State private var showingPaywall = false
    @State private var previousBrightness: CGFloat = 0.5

    /// Returns the screen associated with the app's first active window scene.
    /// Avoids the deprecated `UIScreen.main` on iOS 26+.
    private var activeScreen: UIScreen? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?.screen
    }

    init(images: [UIImage], initialIndex: Int = 0, documentName: String) {
        self.images = images
        self.initialIndex = initialIndex
        self.documentName = documentName
        _currentIndex = State(initialValue: initialIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack {
                TabView(selection: $currentIndex) {
                    ForEach(images.indices, id: \.self) { i in
                        Image(uiImage: images[i])
                            .resizable()
                            .scaledToFit()
                            .padding(16)
                            .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .always : .never))
                .ignoresSafeArea()

            }

            // Dismiss button (top trailing)
            VStack {
                HStack {
                    Spacer()
                    Button(action: { showingDismissConfirm = true }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(20)
                    }
                }
                Spacer()
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            // Premium gate: one-time unlock OR Sovereign bundle unlocks this.
            guard entitlementService.canUsePresentMode else {
                showingPaywall = true
                return
            }
            if let screen = activeScreen {
                previousBrightness = screen.brightness
                screen.brightness = 1.0
            }
            forceOrientation(.landscapeRight)
        }
        .onDisappear {
            activeScreen?.brightness = previousBrightness
            forceOrientation(.portrait)
        }
        .confirmationDialog("Exit Present Mode?", isPresented: $showingDismissConfirm, titleVisibility: .visible) {
            Button("Exit Present Mode", role: .destructive) { dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The document will no longer be displayed.")
        }
        .sheet(isPresented: $showingPaywall, onDismiss: { dismiss() }) {
            PaywallView(
                reason: .presentMode,
                entitlementService: entitlementService,
                dismiss: { showingPaywall = false }
            )
        }
    }

    // MARK: - Orientation

    private func forceOrientation(_ orientation: UIInterfaceOrientation) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        let mask: UIInterfaceOrientationMask = orientation == .landscapeRight ? .landscapeRight : .portrait
        windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
    }
}

#Preview {
    PresentModeView(
        images: [UIImage(systemName: "person.crop.rectangle")!],
        documentName: "Driver's License"
    )
}
