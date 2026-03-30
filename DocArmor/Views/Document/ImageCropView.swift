import SwiftUI

/// Interactive crop view with draggable corner handles.
///
/// The preview circle for each handle is lifted 52 pt **above** the touch point
/// so the user's finger never obscures what they're selecting — a critical
/// ergonomic detail for small card images (IDs, licences, etc.).
///
/// For document types that have a magnetic stripe (driver's license, state ID,
/// military ID, employee ID, green card), the initial crop rect automatically
/// excludes the bottom 15 % of the image and a yellow hint strip marks the zone.
struct ImageCropView: View {

    let image: UIImage
    let documentType: DocumentType?
    var onCrop: (UIImage) -> Void
    var onCancel: () -> Void

    // MARK: - Drag state

    @State private var topLeft: CGPoint = .zero
    @State private var bottomRight: CGPoint = .zero
    @State private var containerSize: CGSize = .zero
    @State private var isReady = false

    /// Which corner is currently being dragged, plus the live finger position.
    @State private var activeDrag: ActiveDrag? = nil

    struct ActiveDrag: Equatable {
        var corner: Corner
        var touchPosition: CGPoint
    }

    enum Corner: Equatable { case tl, tr, bl, br }

    // MARK: - Constants

    /// Minimum crop dimension in points.
    private let minSide: CGFloat = 64
    /// How far above the touch point the preview bubble floats.
    private let previewLift: CGFloat = 52
    /// Diameter of the corner bracket hit zone.
    private let hitZone: CGFloat = 48

    // MARK: - Magnetic stripe

    /// Bottom fraction of the image occupied by the magnetic stripe for card types.
    private var magneticFraction: CGFloat {
        switch documentType {
        case .driversLicense, .stateID, .militaryID, .employeeID, .greenCard:
            return 0.15
        default:
            return 0
        }
    }

    // MARK: - Geometry helpers

    /// Returns the CGRect where the image actually renders inside a container of `size`
    /// (replicating SwiftUI's .scaledToFit behaviour).
    private func displayRect(for size: CGSize) -> CGRect {
        let iw = image.size.width, ih = image.size.height
        guard iw > 0, ih > 0, size.width > 0, size.height > 0 else { return .zero }
        let aspect = iw / ih
        var w = size.width
        var h = w / aspect
        if h > size.height { h = size.height; w = h * aspect }
        return CGRect(
            x: (size.width - w) / 2,
            y: (size.height - h) / 2,
            width: w,
            height: h
        )
    }

    private var cropRect: CGRect {
        CGRect(
            x: min(topLeft.x, bottomRight.x),
            y: min(topLeft.y, bottomRight.y),
            width: max(minSide, abs(bottomRight.x - topLeft.x)),
            height: max(minSide, abs(bottomRight.y - topLeft.y))
        )
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ZStack {
                    Color.black.ignoresSafeArea()

                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: proxy.size.width, height: proxy.size.height)

                    if isReady {
                        let disp = displayRect(for: proxy.size)

                        // Darkened region outside crop rect (uses even-odd fill rule)
                        Canvas { ctx, size in
                            var mask = Path(CGRect(origin: .zero, size: size))
                            mask.addRect(cropRect)
                            ctx.fill(mask, with: .color(.black.opacity(0.52)), style: FillStyle(eoFill: true))
                        }
                        .allowsHitTesting(false)

                        // Crop border
                        Rectangle()
                            .stroke(.white, lineWidth: 1.5)
                            .frame(width: cropRect.width, height: cropRect.height)
                            .position(x: cropRect.midX, y: cropRect.midY)
                            .allowsHitTesting(false)

                        // Rule-of-thirds grid inside crop
                        ruleOfThirdsOverlay
                            .allowsHitTesting(false)

                        // Magnetic stripe hint
                        if magneticFraction > 0 {
                            magneticStripeHint(imageRect: disp)
                                .allowsHitTesting(false)
                        }

                        // Corner handles (must be last so they sit on top)
                        cornerHandle(.tl, at: CGPoint(x: cropRect.minX, y: cropRect.minY), bounds: disp)
                        cornerHandle(.tr, at: CGPoint(x: cropRect.maxX, y: cropRect.minY), bounds: disp)
                        cornerHandle(.bl, at: CGPoint(x: cropRect.minX, y: cropRect.maxY), bounds: disp)
                        cornerHandle(.br, at: CGPoint(x: cropRect.maxX, y: cropRect.maxY), bounds: disp)
                    }
                }
                .coordinateSpace(name: "cropCanvas")
                .onAppear {
                    containerSize = proxy.size
                    guard !isReady else { return }
                    let disp = displayRect(for: proxy.size)
                    let stripH = disp.height * magneticFraction
                    topLeft = CGPoint(x: disp.minX, y: disp.minY)
                    bottomRight = CGPoint(x: disp.maxX, y: disp.maxY - stripH)
                    isReady = true
                }
                .onChange(of: proxy.size) { _, newSize in
                    // Re-initialise on rotation / resize
                    containerSize = newSize
                    let disp = displayRect(for: newSize)
                    let stripH = disp.height * magneticFraction
                    topLeft = CGPoint(x: disp.minX, y: disp.minY)
                    bottomRight = CGPoint(x: disp.maxX, y: disp.maxY - stripH)
                }
            }
            .navigationTitle("Adjust Crop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { performCrop() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Rule of thirds

    private var ruleOfThirdsOverlay: some View {
        Canvas { ctx, _ in
            let w3 = cropRect.width / 3
            let h3 = cropRect.height / 3
            var path = Path()
            for i in 1 ... 2 {
                let x = cropRect.minX + w3 * CGFloat(i)
                path.move(to: CGPoint(x: x, y: cropRect.minY))
                path.addLine(to: CGPoint(x: x, y: cropRect.maxY))
                let y = cropRect.minY + h3 * CGFloat(i)
                path.move(to: CGPoint(x: cropRect.minX, y: y))
                path.addLine(to: CGPoint(x: cropRect.maxX, y: y))
            }
            ctx.stroke(path, with: .color(.white.opacity(0.22)), lineWidth: 0.5)
        }
    }

    // MARK: - Magnetic stripe hint

    private func magneticStripeHint(imageRect: CGRect) -> some View {
        let stripH = imageRect.height * magneticFraction
        let stripY = imageRect.maxY - stripH
        return ZStack {
            Rectangle()
                .fill(.yellow.opacity(0.14))
                .frame(width: imageRect.width, height: stripH)
                .position(x: imageRect.midX, y: stripY + stripH / 2)
            Text("Magnetic Strip")
                .font(.caption2.bold())
                .foregroundStyle(.yellow)
                .position(x: imageRect.midX, y: stripY + stripH / 2)
        }
    }

    // MARK: - Corner handle

    @ViewBuilder
    private func cornerHandle(_ id: Corner, at position: CGPoint, bounds: CGRect) -> some View {
        let isActive = activeDrag?.corner == id
        let touchPos = activeDrag?.touchPosition ?? position

        ZStack {
            // Bracket decoration at the corner
            CornerBracketShape(corner: id)
                .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 22, height: 22)
                .position(position)

            // Transparent hit-target (much larger than the visible bracket)
            Rectangle()
                .fill(Color.white.opacity(0.001))
                .frame(width: hitZone, height: hitZone)
                .position(position)
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named("cropCanvas"))
                        .onChanged { value in
                            activeDrag = ActiveDrag(corner: id, touchPosition: value.location)
                            moveCorner(id, to: value.location, bounds: bounds)
                        }
                        .onEnded { _ in
                            activeDrag = nil
                        }
                )

            // Preview bubble lifted above the touch — visible only while dragging this corner.
            // This is the key offset so the user can see exactly where the handle lands
            // without their finger blocking the view.
            if isActive {
                ZStack {
                    Circle()
                        .fill(Color(uiColor: .systemBackground).opacity(0.92))
                        .frame(width: 36, height: 36)
                        .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 2)
                    Circle()
                        .stroke(Color.accentColor, lineWidth: 2.5)
                        .frame(width: 36, height: 36)
                    Image(systemName: "plus")
                        .font(.caption.bold())
                        .foregroundStyle(.accentColor)
                }
                .position(CGPoint(x: touchPos.x, y: touchPos.y - previewLift))
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Corner movement

    private func moveCorner(_ id: Corner, to point: CGPoint, bounds: CGRect) {
        let cx = max(bounds.minX, min(bounds.maxX, point.x))
        let cy = max(bounds.minY, min(bounds.maxY, point.y))

        switch id {
        case .tl:
            topLeft = CGPoint(
                x: min(cx, bottomRight.x - minSide),
                y: min(cy, bottomRight.y - minSide)
            )
        case .tr:
            bottomRight.x = max(cx, topLeft.x + minSide)
            topLeft.y     = min(cy, bottomRight.y - minSide)
        case .bl:
            topLeft.x     = min(cx, bottomRight.x - minSide)
            bottomRight.y = max(cy, topLeft.y + minSide)
        case .br:
            bottomRight = CGPoint(
                x: max(cx, topLeft.x + minSide),
                y: max(cy, topLeft.y + minSide)
            )
        }
    }

    // MARK: - Crop execution

    private func performCrop() {
        let disp = displayRect(for: containerSize)
        guard disp.width > 0, disp.height > 0 else { onCrop(image); return }

        let scaleX = image.size.width  / disp.width
        let scaleY = image.size.height / disp.height

        let imageCropRect = CGRect(
            x: (cropRect.minX - disp.minX) * scaleX,
            y: (cropRect.minY - disp.minY) * scaleY,
            width: cropRect.width  * scaleX,
            height: cropRect.height * scaleY
        )

        guard let cgCropped = image.cgImage?.cropping(to: imageCropRect) else {
            onCrop(image)
            return
        }
        onCrop(UIImage(cgImage: cgCropped, scale: image.scale, orientation: image.imageOrientation))
    }
}

// MARK: - Corner Bracket Shape

/// An L-shaped bracket drawn in the corner-appropriate orientation.
private struct CornerBracketShape: Shape {
    let corner: ImageCropView.Corner

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let s = min(rect.width, rect.height)
        switch corner {
        case .tl:
            p.move(to: CGPoint(x: rect.minX, y: rect.minY + s))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX + s, y: rect.minY))
        case .tr:
            p.move(to: CGPoint(x: rect.maxX - s, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + s))
        case .bl:
            p.move(to: CGPoint(x: rect.minX, y: rect.maxY - s))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX + s, y: rect.maxY))
        case .br:
            p.move(to: CGPoint(x: rect.maxX - s, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - s))
        }
        return p
    }
}

#Preview {
    ImageCropView(
        image: UIImage(systemName: "person.crop.rectangle.fill")!,
        documentType: .driversLicense,
        onCrop: { _ in },
        onCancel: {}
    )
}
