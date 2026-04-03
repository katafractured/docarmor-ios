import PDFKit
import UIKit
import UniformTypeIdentifiers

nonisolated struct NormalizedDocumentImport: Sendable {
    let images: [UIImage]
    let suggestedName: String?
}

enum DocumentImportNormalizationService {
    enum ImportError: LocalizedError {
        case unsupportedType(String)
        case unreadableFile
        case emptyDocument

        var errorDescription: String? {
            switch self {
            case .unsupportedType(let name):
                return "\"\(name)\" is not a supported image or PDF."
            case .unreadableFile:
                return "The selected file could not be read."
            case .emptyDocument:
                return "The selected file did not contain any importable pages."
            }
        }
    }

    static func normalize(urls: [URL]) throws -> NormalizedDocumentImport {
        var images: [UIImage] = []
        var suggestedName: String?

        for (index, url) in urls.enumerated() {
            let fileImages = try withScopedAccess(to: url) {
                try normalize(url: url)
            }
            images.append(contentsOf: fileImages)

            if index == 0 {
                suggestedName = readableName(for: url)
            }
        }

        guard !images.isEmpty else {
            throw ImportError.emptyDocument
        }

        return NormalizedDocumentImport(images: images, suggestedName: suggestedName)
    }

    static func normalize(url: URL) throws -> [UIImage] {
        let type = inferredType(for: url)

        if type?.conforms(to: .pdf) == true {
            return try renderPDF(at: url)
        }

        if type?.conforms(to: .image) == true {
            guard let image = UIImage(contentsOfFile: url.path(percentEncoded: false)) else {
                throw ImportError.unreadableFile
            }
            return [image]
        }

        throw ImportError.unsupportedType(url.lastPathComponent)
    }

    static func previewImage(for url: URL) -> UIImage? {
        (try? withScopedAccess(to: url) {
            try normalize(url: url)
        })?.first
    }

    nonisolated private static func inferredType(for url: URL) -> UTType? {
        if let values = try? url.resourceValues(forKeys: [.contentTypeKey]), let type = values.contentType {
            return type
        }

        return UTType(filenameExtension: url.pathExtension)
    }

    private static func renderPDF(at url: URL) throws -> [UIImage] {
        guard let document = PDFDocument(url: url), document.pageCount > 0 else {
            throw ImportError.unreadableFile
        }

        var images: [UIImage] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            images.append(render(page: page))
        }

        guard !images.isEmpty else {
            throw ImportError.emptyDocument
        }

        return images
    }

    private static func render(page: PDFPage) -> UIImage {
        let bounds = page.bounds(for: .mediaBox)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 2

        return UIGraphicsImageRenderer(size: bounds.size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: bounds.size))

            context.cgContext.translateBy(x: 0, y: bounds.height)
            context.cgContext.scaleBy(x: 1, y: -1)
            page.draw(with: .mediaBox, to: context.cgContext)
        }
    }

    nonisolated private static func readableName(for url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func withScopedAccess<T>(to url: URL, perform: () throws -> T) throws -> T {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try perform()
    }
}
