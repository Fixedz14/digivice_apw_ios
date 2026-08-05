import SwiftUI
import UIKit
import WatchKit

/// Shared geometry for the extracted 30×32 LCD.
///
/// `pixelAlignedSize` rounds the scale down to a whole number of physical
/// display pixels per source pixel. This keeps every source pixel the same
/// size on both 2× and 3× displays instead of producing uneven columns.
enum ClassicLCDGeometry {
    static let logicalWidth: CGFloat = 30
    static let logicalHeight: CGFloat = 32
    static let aspectRatio = logicalWidth / logicalHeight
    /// Lifecycle screens are fitted against `WKInterfaceDevice.screenBounds`
    /// instead of SwiftUI's smaller rounded safe-area. Keeping the final
    /// multiplier explicit prevents a later shell from shrinking the LCD.
    static let lifecycleFullscreenScale: CGFloat = 1.18

    static func pixelAlignedSize(
        fitting bounds: CGSize,
        displayScale: CGFloat
    ) -> CGSize {
        guard bounds.width > 0, bounds.height > 0 else {
            return .zero
        }

        let rawScale = min(
            bounds.width / logicalWidth,
            bounds.height / logicalHeight
        )
        let safeDisplayScale = max(1, displayScale)
        let alignedScale = floor(rawScale * safeDisplayScale)
            / safeDisplayScale
        let scale = alignedScale > 0 ? alignedScale : rawScale

        return CGSize(
            width: logicalWidth * scale,
            height: logicalHeight * scale
        )
    }

    static func fullscreenFittingBounds(_ bounds: CGSize) -> CGSize {
        let screenBounds = WKInterfaceDevice.current().screenBounds.size
        return CGSize(
            width: max(bounds.width, screenBounds.width),
            height: max(bounds.height, screenBounds.height)
        )
    }
}

/// The battle timeline redraws at up to 30 fps. Caching these tiny decoded
/// frames avoids reopening the PNG from the bundle for every SwiftUI update.
final class ClassicPixelAssetStore {
    static let shared = ClassicPixelAssetStore()

    private let cache = NSCache<NSString, UIImage>()
    private let lcdCellSize = 6
    private let lcdDotSize = 5

    private init() {
        cache.countLimit = 384
    }

    func image(resource: String, frame: Int) -> UIImage? {
        let name = "\(resource)_\(frame)"
        let key = name as NSString

        if let cached = cache.object(forKey: key) {
            return cached
        }

        guard let url = Bundle.main.url(
            forResource: name,
            withExtension: "png"
        ),
        let sourceImage = UIImage(contentsOfFile: url.path) else {
            return nil
        }

        let image = lcdDotImage(
            from: sourceImage,
            usesWhiteAsInkMask: resource == "spr_numbers"
        ) ?? sourceImage
        cache.setObject(image, forKey: key)
        return image
    }

    /// Rebuilds every source pixel as a slightly separated LCD cell.
    ///
    /// GameMaker's 30×32 source is a logical bitmap, while the physical
    /// D‑Tector display leaves a narrow gutter between adjacent cells. A
    /// normal nearest-neighbour scale joins black pixels into solid blocks.
    /// Expanding each logical pixel into a 5×5 dot inside a 6×6 transparent
    /// cell preserves the original square-pixel shape and exposes the LCD
    /// background through a narrow one-sixth-pixel gutter.
    private func lcdDotImage(
        from image: UIImage,
        usesWhiteAsInkMask: Bool
    ) -> UIImage? {
        guard let source = image.cgImage else { return nil }

        let width = source.width
        let height = source.height
        guard width > 0, height > 0 else { return nil }

        let sourceBytesPerRow = width * 4
        var sourceBytes = [UInt8](
            repeating: 0,
            count: sourceBytesPerRow * height
        )

        guard let sourceContext = CGContext(
            data: &sourceBytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: sourceBytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        sourceContext.interpolationQuality = .none
        sourceContext.draw(
            source,
            in: CGRect(x: 0, y: 0, width: width, height: height)
        )

        let outputWidth = width * lcdCellSize
        let outputHeight = height * lcdCellSize
        let outputBytesPerRow = outputWidth * 4
        var outputBytes = [UInt8](
            repeating: 0,
            count: outputBytesPerRow * outputHeight
        )

        for sourceY in 0..<height {
            for sourceX in 0..<width {
                let sourceOffset = sourceY * sourceBytesPerRow + sourceX * 4
                let alpha = sourceBytes[sourceOffset + 3]
                guard alpha > 0 else { continue }
                let red = sourceBytes[sourceOffset]
                let green = sourceBytes[sourceOffset + 1]
                let blue = sourceBytes[sourceOffset + 2]
                if usesWhiteAsInkMask {
                    let brightness = (
                        Int(red) + Int(green) + Int(blue)
                    ) / 3
                    guard brightness >= 128 else { continue }
                }

                for dotY in 0..<lcdDotSize {
                    let outputY = sourceY * lcdCellSize + dotY
                    for dotX in 0..<lcdDotSize {
                        let outputX = sourceX * lcdCellSize + dotX
                        let outputOffset = outputY * outputBytesPerRow
                            + outputX * 4
                        outputBytes[outputOffset] =
                            usesWhiteAsInkMask ? 0 : red
                        outputBytes[outputOffset + 1] =
                            usesWhiteAsInkMask ? 0 : green
                        outputBytes[outputOffset + 2] =
                            usesWhiteAsInkMask ? 0 : blue
                        outputBytes[outputOffset + 3] = alpha
                    }
                }
            }
        }

        guard let provider = CGDataProvider(
            data: Data(outputBytes) as CFData
        ),
        let output = CGImage(
            width: outputWidth,
            height: outputHeight,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: outputBytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
            ),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            return nil
        }

        return UIImage(
            cgImage: output,
            scale: image.scale,
            orientation: image.imageOrientation
        )
    }
}

struct ClassicPixelAsset: View {
    let resource: String
    var frame = 0

    private var image: UIImage? {
        ClassicPixelAssetStore.shared.image(
            resource: resource,
            frame: frame
        )
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
                    .antialiased(false)
            } else {
                Color.clear
            }
        }
        .accessibilityHidden(true)
    }
}

/// Displays one extracted D‑Tector LCD frame without smoothing or distortion.
///
/// The original game renders into a 30×32 logical viewport. Keeping that
/// aspect ratio here is important: stretching the image to the rectangular
/// Watch screen changes both the sprite proportions and the apparent battle
/// positions.
struct ClassicLCDSprite: View {
    let resource: String
    var frame = 0

    private var image: UIImage? {
        ClassicPixelAssetStore.shared.image(
            resource: resource,
            frame: frame
        )
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
                    .antialiased(false)
                    .scaledToFit()
            } else {
                Color.clear
                    .overlay {
                        Image(systemName: "questionmark")
                            .foregroundStyle(DetectorPalette.ink)
                    }
            }
        }
        .aspectRatio(ClassicLCDGeometry.aspectRatio, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

struct ClassicLCDNumber: View {
    let value: Int
    var white = true
    var scale: CGFloat

    static func logicalWidth(for value: Int) -> CGFloat {
        let count = max(1, String(max(0, value)).count)
        return CGFloat(count * 5 - 1)
    }

    /// GameMaker's `draw_number_with_sprite` receives the x position of the
    /// least-significant digit. Earlier digits are placed five pixels to its
    /// left (four pixels of glyph plus the original one-pixel gap).
    static func logicalCenter(for value: Int, leastSignificantX: CGFloat) -> CGFloat {
        leastSignificantX + 4 - logicalWidth(for: value) / 2
    }

    private var digits: [Int] {
        String(max(0, value)).compactMap { $0.wholeNumberValue }
    }

    var body: some View {
        HStack(spacing: scale) {
            ForEach(Array(digits.enumerated()), id: \.offset) { _, digit in
                ClassicPixelAsset(
                    resource: white ? "spr_numbers_white" : "spr_numbers",
                    frame: digit
                )
                .frame(width: 4 * scale, height: 5 * scale)
            }
        }
        .accessibilityLabel("\(value)")
    }
}

/// Square-cornered LCD viewport used by strict original-presentation screens.
struct ClassicLCDViewport<Content: View>: View {
    @ViewBuilder let content: Content
    var showGrid = false
    var borderOutset: CGFloat = 0

    var body: some View {
        ZStack {
            DetectorPalette.screen

            if showGrid {
                PixelGrid()
                    .opacity(0.36)
            }

            content
        }
        .aspectRatio(ClassicLCDGeometry.aspectRatio, contentMode: .fit)
        .clipped()
        .overlay {
            Rectangle()
                .inset(by: -borderOutset)
                .stroke(DetectorPalette.ink, lineWidth: 2)
        }
        .background(Color.black)
        .accessibilityElement(children: .contain)
    }
}

/// Invisible LCD hit zones for the small Watch screen.
///
/// The display is split into left / center / right regions. Menus use the
/// center region as the selected item's icon/text hit target, while left and
/// right remain navigation zones. Cancel is an exclusive long-press, so
/// releasing a hold cannot also fire the regional tap underneath it.
struct ClassicDetectorTouchZones: View {
    var leftEnabled = true
    var centerEnabled = true
    var rightEnabled = true
    var cancelEnabled = true
    var onLeft: () -> Void
    var onCenter: () -> Void
    var onRight: () -> Void
    var onCancel: () -> Void

    private let longPressDuration: TimeInterval = 0.48

    var body: some View {
        GeometryReader { geometry in
            Color.clear
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
            .highPriorityGesture(
                LongPressGesture(minimumDuration: longPressDuration)
                    .exclusively(before: SpatialTapGesture())
                    .onEnded { result in
                        switch result {
                        case .first:
                            guard cancelEnabled else { return }
                            onCancel()
                        case .second(let tap):
                            performTap(
                                x: tap.location.x,
                                width: geometry.size.width
                            )
                        }
                    }
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAction(named: "Left") {
            guard leftEnabled else { return }
            onLeft()
        }
        .accessibilityAction(named: "Select") {
            guard centerEnabled else { return }
            onCenter()
        }
        .accessibilityAction(named: "Right") {
            guard rightEnabled else { return }
            onRight()
        }
        .accessibilityAction(named: "Cancel") {
            guard cancelEnabled else { return }
            onCancel()
        }
    }

    private func performTap(x: CGFloat, width: CGFloat) {
        let sideWidth = max(1, width * 0.30)

        if x < sideWidth {
            guard leftEnabled else { return }
            onLeft()
        } else if x > width - sideWidth {
            guard rightEnabled else { return }
            onRight()
        } else {
            guard centerEnabled else { return }
            onCenter()
        }
    }
}

/// Compatibility wrapper for older screens that still ask for the original
/// three detector controls. It intentionally draws no visible circles.
struct ClassicDetectorControls: View {
    var leftEnabled = true
    var cancelEnabled = true
    var acceptEnabled = true
    var visualDiameter: CGFloat = 34
    var hitDiameter: CGFloat = 38
    var spacing: CGFloat = 14
    var onLeft: () -> Void
    var onCancel: () -> Void
    var onAccept: () -> Void

    private var safeHitDiameter: CGFloat {
        max(28, hitDiameter)
    }

    var body: some View {
        ClassicDetectorTouchZones(
            leftEnabled: leftEnabled,
            centerEnabled: acceptEnabled,
            rightEnabled: acceptEnabled,
            cancelEnabled: cancelEnabled,
            onLeft: onLeft,
            onCenter: onAccept,
            onRight: onAccept,
            onCancel: onCancel
        )
        .frame(maxWidth: .infinity, minHeight: safeHitDiameter)
    }
}
