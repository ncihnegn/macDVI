import Foundation
import CoreGraphics
import AppKit
import CPostScript

final class NativePostScriptRenderer {
    static let shared = NativePostScriptRenderer()

    private let cache = NSCache<NSString, CGImage>()

    func renderPage(url: URL, pageIndex: Int, pixelWidth: UInt32, pixelHeight: UInt32) -> CGImage? {
        let cacheKey = "\(url.path):\(pageIndex):\(pixelWidth)x\(pixelHeight)" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        guard let data = try? Data(contentsOf: url) else { return nil }

        let image = data.withUnsafeBytes { rawBuffer -> CGImage? in
            guard let baseAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return nil
            }
            guard let handle = ps_document_open(baseAddress, rawBuffer.count) else {
                return nil
            }
            defer { ps_document_free(handle) }

            let byteCount = Int(pixelWidth * pixelHeight * 4)
            var pixelData = Data(count: byteCount)

            let success = pixelData.withUnsafeMutableBytes { outBuffer -> Bool in
                guard let outPtr = outBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return false
                }
                return ps_document_render_page_rgba(handle, pageIndex, pixelWidth, pixelHeight, outPtr) == 0
            }

            guard success else { return nil }

            guard let provider = CGDataProvider(data: pixelData as CFData) else { return nil }
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bitmapInfo: CGBitmapInfo = [
                CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                .byteOrder32Big
            ]

            return CGImage(
                width: Int(pixelWidth),
                height: Int(pixelHeight),
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: Int(pixelWidth * 4),
                space: colorSpace,
                bitmapInfo: bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
            )
        }

        if let image {
            cache.setObject(image, forKey: cacheKey)
        }
        return image
    }
}

enum NativePostScriptLoader {
    static func load(url: URL) throws -> DVIDocument {
        let data = try Data(contentsOf: url)

        return try data.withUnsafeBytes { rawBuffer -> DVIDocument in
            guard let baseAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                throw DVIError.malformed("could not read PostScript file data")
            }

            guard let handle = ps_document_open(baseAddress, rawBuffer.count) else {
                throw DVIError.malformed("could not initialize native PostScript interpreter")
            }
            defer { ps_document_free(handle) }

            let pageCount = ps_document_page_count(handle)
            guard pageCount > 0 else {
                throw DVIError.malformed("no renderable pages found in PostScript document")
            }

            var pages: [DVIPage] = []

            for pageIndex in 0..<pageCount {
                var width: Double = 612.0
                var height: Double = 792.0
                _ = ps_document_get_page_size(handle, pageIndex, &width, &height)

                let mediaBox = CGSize(width: width, height: height)
                let item = DVIPageItem.postScriptPage(
                    PostScriptPageItem(
                        pageIndex: pageIndex,
                        width: width,
                        height: height,
                        postScriptURL: url
                    )
                )

                let page = DVIPage(
                    number: pageIndex + 1,
                    counters: [Int64(pageIndex + 1)],
                    items: [item],
                    mediaBox: mediaBox
                )
                pages.pushOrAppend(page)
            }

            let preamble = DVIPreamble(
                id: 2,
                numerator: 25400000,
                denominator: 473628672,
                magnification: 1000,
                comment: "Native PostScript Document"
            )

            return DVIDocument(
                url: url,
                preamble: preamble,
                fonts: [:],
                pages: pages,
                warnings: []
            )
        }
    }
}

private extension Array {
    mutating func pushOrAppend(_ element: Element) {
        self.append(element)
    }
}
