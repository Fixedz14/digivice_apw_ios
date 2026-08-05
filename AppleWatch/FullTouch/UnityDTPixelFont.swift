import SwiftUI
import UIKit

enum UnityDTPixelFontStyle: String {
    case small
    case regular
    case big

    var atlasName: String {
        "font_\(rawValue)"
    }

    var settingsName: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }

    var defaultHeight: Int {
        self == .big ? 7 : 5
    }

    var defaultAdvance: Int {
        self == .big ? 6 : 5
    }
}

struct UnityDTPixelGlyph {
    let width: Int
    let height: Int
    let advance: Int
    let pixels: [CGPoint]
}

struct UnityDTPixelFont {
    let glyphs: [Int: UnityDTPixelGlyph]
    let lineHeight: Int
    let defaultAdvance: Int
}

final class UnityDTPixelFontCache {
    static let shared = UnityDTPixelFontCache()

    private var cache: [UnityDTPixelFontStyle: UnityDTPixelFont] = [:]
    private let lock = NSLock()

    func font(_ style: UnityDTPixelFontStyle) -> UnityDTPixelFont {
        lock.lock()
        defer { lock.unlock() }

        if let cached = cache[style] {
            return cached
        }

        let loaded = load(style)
        cache[style] = loaded
        return loaded
    }

    private func load(_ style: UnityDTPixelFontStyle) -> UnityDTPixelFont {
        guard let imageURL = Bundle.main.url(
            forResource: style.atlasName,
            withExtension: "png"
        ),
        let settingsURL = Bundle.main.url(
            forResource: style.settingsName,
            withExtension: "fontsettings"
        ),
        let image = UIImage(contentsOfFile: imageURL.path),
        let cgImage = image.cgImage,
        let settings = try? String(contentsOf: settingsURL),
        let atlas = atlasPixels(cgImage) else {
            return UnityDTPixelFont(
                glyphs: [:],
                lineHeight: style.defaultHeight + 1,
                defaultAdvance: style.defaultAdvance
            )
        }

        var glyphs: [Int: UnityDTPixelGlyph] = [:]
        var index: Int?
        var uvX = 0.0
        var uvY = 0.0
        var uvWidth = 0.0
        var uvHeight = 0.0
        var insideUV = false

        for rawLine in settings.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ) {
            let line = rawLine.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            if line.hasPrefix("index:") {
                index = Int(value(afterColonIn: line))
            } else if line == "uv:" {
                insideUV = true
            } else if line == "vert:" {
                insideUV = false
            } else if insideUV, line.hasPrefix("x:") {
                uvX = Double(value(afterColonIn: line)) ?? 0
            } else if insideUV, line.hasPrefix("y:") {
                uvY = Double(value(afterColonIn: line)) ?? 0
            } else if insideUV, line.hasPrefix("width:") {
                uvWidth = Double(value(afterColonIn: line)) ?? 0
            } else if insideUV, line.hasPrefix("height:") {
                uvHeight = Double(value(afterColonIn: line)) ?? 0
            } else if line.hasPrefix("advance:"),
                      let glyphIndex = index {
                let advanceValue =
                    Double(value(afterColonIn: line)) ?? 120
                let glyph = buildGlyph(
                    atlas: atlas,
                    atlasWidth: cgImage.width,
                    atlasHeight: cgImage.height,
                    uvX: uvX,
                    uvY: uvY,
                    uvWidth: uvWidth,
                    uvHeight: uvHeight,
                    advance: advanceValue
                )
                glyphs[glyphIndex] = glyph
                index = nil
            }
        }

        return UnityDTPixelFont(
            glyphs: glyphs,
            lineHeight: style.defaultHeight + 1,
            defaultAdvance: style.defaultAdvance
        )
    }

    private func value(afterColonIn line: String) -> String {
        guard let colon = line.firstIndex(of: ":") else {
            return ""
        }
        return String(line[line.index(after: colon)...])
            .trimmingCharacters(in: .whitespaces)
    }

    private func atlasPixels(
        _ image: CGImage
    ) -> (bytes: [UInt8], width: Int, height: Int)? {
        let width = image.width
        let height = image.height
        var bytes = [UInt8](
            repeating: 0,
            count: width * height * 4
        )
        guard let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: width, height: height)
        )
        return (bytes, width, height)
    }

    private func buildGlyph(
        atlas: (bytes: [UInt8], width: Int, height: Int),
        atlasWidth: Int,
        atlasHeight: Int,
        uvX: Double,
        uvY: Double,
        uvWidth: Double,
        uvHeight: Double,
        advance: Double
    ) -> UnityDTPixelGlyph {
        let sourceX = Int(round(uvX * Double(atlasWidth)))
        let width = max(1, Int(round(uvWidth * Double(atlasWidth))))
        let height = max(
            1,
            Int(round(uvHeight * Double(atlasHeight)))
        )
        let sourceY = atlasHeight - Int(
            round((uvY + uvHeight) * Double(atlasHeight))
        )
        var pixels: [CGPoint] = []

        for y in 0..<height {
            for x in 0..<width {
                let atlasX = sourceX + x
                let atlasY = sourceY + y
                guard atlasX >= 0,
                      atlasX < atlas.width,
                      atlasY >= 0,
                      atlasY < atlas.height else {
                    continue
                }
                let offset = (atlasY * atlas.width + atlasX) * 4
                if atlas.bytes[offset + 3] > 32 {
                    pixels.append(CGPoint(x: x, y: y))
                }
            }
        }

        return UnityDTPixelGlyph(
            width: width,
            height: height,
            advance: max(1, Int(round(advance / 24.0))),
            pixels: pixels
        )
    }
}
