import Foundation
import CoreGraphics
import AppKit
import CPostScript

final class NativePostScriptRenderer {
    static let shared = NativePostScriptRenderer()

    private let cache = NSCache<NSString, CGImage>()

    static func isPostScript(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ext == "ps" || ext == "eps" {
            return true
        }

        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            return false
        }

        let prefix = Array(data.prefix(1024))
        var start = 0
        if prefix.starts(with: [0xEF, 0xBB, 0xBF]) {
            start = 3
        }
        while start < prefix.count, prefix[start] == 0x09 || prefix[start] == 0x0A ||
                prefix[start] == 0x0C || prefix[start] == 0x0D || prefix[start] == 0x20 {
            start += 1
        }
        return prefix.dropFirst(start).starts(with: [0x25, 0x21])
    }

    func renderPage(
        url: URL,
        pageIndex: Int,
        pixelWidth: UInt32,
        pixelHeight: UInt32,
        boundingBox: CGRect? = nil
    ) -> CGImage? {
        let boundingBoxKey = boundingBox.map {
            ":\($0.minX),\($0.minY),\($0.width),\($0.height)"
        } ?? ""
        let cacheKey = "\(url.path):\(pageIndex):\(pixelWidth)x\(pixelHeight)\(boundingBoxKey)" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        guard let data = try? Data(contentsOf: url) else { return nil }
        let renderData = boundingBox.map { normalizedGraphicData(data, boundingBox: $0) } ?? data

        let image = renderData.withUnsafeBytes { rawBuffer -> CGImage? in
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

    private func normalizedGraphicData(_ data: Data, boundingBox: CGRect) -> Data {
        let width = max(boundingBox.width, 1.0)
        let height = max(boundingBox.height, 1.0)
        let scaleX = 612.0 / width
        let scaleY = 792.0 / height

        let sourceText = String(decoding: data, as: UTF8.self)
        var fontAliases = Set<String>()
        for line in sourceText.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 2, fields[0] == "%*Font:" else { continue }
            fontAliases.insert(String(fields[1]))
        }

        let aliases = fontAliases.sorted().map {
            "/\($0) /\($0.uppercased()) def\n"
        }.joined()
        let setup = """
        /fshow { exch dup type /nametype ne { cvn } if findfont exch scalefont setfont show } bind def
        \(aliases)\(scaleX) \(scaleY) scale
        \(-boundingBox.minX) \(-boundingBox.minY) translate\n
        """

        let pageMarker = Data("%%Page:".utf8)
        guard let pageOffset = data.range(of: pageMarker)?.lowerBound else {
            var result = Data(setup.utf8)
            result.append(data)
            return result
        }

        var result = Data()
        result.append(data.prefix(upTo: pageOffset))
        result.append(Data(setup.utf8))
        result.append(data.suffix(from: pageOffset))
        return result
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
