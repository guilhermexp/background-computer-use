import CoreGraphics
import Foundation

enum VisualChangeAnalyzer {
    struct Result: Equatable, Sendable {
        let fullImageRatio: Double
        let targetRegionRatio: Double
    }

    static func compare(
        before: CGImage,
        after: CGImage,
        normalizedRegion: CGRect,
        sampleSize: Int = 128
    ) -> Result? {
        guard sampleSize > 0,
              let beforePixels = render(before, size: sampleSize),
              let afterPixels = render(after, size: sampleSize) else {
            return nil
        }

        let normalized = normalizedRegion.standardized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard normalized.isNull == false, normalized.isEmpty == false else { return nil }

        let minX = max(0, min(sampleSize - 1, Int(floor(normalized.minX * Double(sampleSize)))))
        let maxX = max(minX + 1, min(sampleSize, Int(ceil(normalized.maxX * Double(sampleSize)))))
        let minY = max(0, min(sampleSize - 1, Int(floor((1 - normalized.maxY) * Double(sampleSize)))))
        let maxY = max(minY + 1, min(sampleSize, Int(ceil((1 - normalized.minY) * Double(sampleSize)))))

        var fullChanged = 0
        var regionChanged = 0
        var regionSamples = 0
        for y in 0..<sampleSize {
            for x in 0..<sampleSize {
                let offset = (y * sampleSize + x) * 4
                let changed = pixelChanged(beforePixels, afterPixels, offset: offset)
                if changed {
                    fullChanged += 1
                }
                if x >= minX, x < maxX, y >= minY, y < maxY {
                    regionSamples += 1
                    if changed {
                        regionChanged += 1
                    }
                }
            }
        }

        return Result(
            fullImageRatio: Double(fullChanged) / Double(sampleSize * sampleSize),
            targetRegionRatio: Double(regionChanged) / Double(regionSamples)
        )
    }

    private static func render(_ image: CGImage, size: Int) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: size,
                height: size,
                bitsPerComponent: 8,
                bytesPerRow: size * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        return rendered ? pixels : nil
    }

    private static func pixelChanged(_ lhs: [UInt8], _ rhs: [UInt8], offset: Int) -> Bool {
        let red = abs(Int(lhs[offset]) - Int(rhs[offset]))
        let green = abs(Int(lhs[offset + 1]) - Int(rhs[offset + 1]))
        let blue = abs(Int(lhs[offset + 2]) - Int(rhs[offset + 2]))
        return max(red, green, blue) >= 16
    }
}
