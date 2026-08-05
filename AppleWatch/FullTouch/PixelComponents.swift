import SwiftUI
import UIKit

enum DetectorPalette {
    static let ink = Color(red: 0.15, green: 0.15, blue: 0.15)
    static let screen = Color(red: 0.65, green: 0.67, blue: 0.66)
    static let screenBright = Color(red: 0.86, green: 0.86, blue: 0.86)
    static let accent = Color(red: 0.66, green: 0.14, blue: 0.15)
    static let danger = Color(red: 0.66, green: 0.14, blue: 0.15)

    static func accent(for index: Int) -> Color {
        switch index {
        case 1: Color(red: 0.11, green: 0.15, blue: 0.36)
        case 2: Color(red: 0.90, green: 0.70, blue: 0.18)
        case 3: Color(red: 0.65, green: 0.47, blue: 0.76)
        case 4: Color(red: 0.19, green: 0.43, blue: 0.05)
        case 5: Color(red: 0.41, green: 0.41, blue: 0.41)
        default: accent
        }
    }
}

struct PixelImage: View {
    let name: String
    var size: CGFloat = 78

    var body: some View {
        Image(name)
            .resizable()
            .interpolation(.none)
            .antialiased(false)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct GameSprite: View {
    let resource: String
    var frame = 0
    var size: CGFloat = 78
    var locked = false

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
                    .saturation(locked ? 0 : 1)
                    .brightness(locked ? -0.75 : 0)
            } else {
                Image(systemName: "questionmark")
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.30)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct PixelGrid: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            for x in 0...30 {
                let position = size.width * CGFloat(x) / 30
                path.move(to: CGPoint(x: position, y: 0))
                path.addLine(to: CGPoint(x: position, y: size.height))
            }
            for y in 0...32 {
                let position = size.height * CGFloat(y) / 32
                path.move(to: CGPoint(x: 0, y: position))
                path.addLine(to: CGPoint(x: size.width, y: position))
            }
            context.stroke(path, with: .color(DetectorPalette.ink.opacity(0.09)), lineWidth: 0.45)
        }
        .allowsHitTesting(false)
    }
}

struct DetectorScreen<Content: View>: View {
    @ViewBuilder let content: Content
    var accent = DetectorPalette.accent
    var showGrid = true

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black)

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [DetectorPalette.screenBright, DetectorPalette.screen],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(5)
            if showGrid {
                PixelGrid()
                    .opacity(0.72)
                    .padding(5)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            content
                .foregroundStyle(DetectorPalette.ink)
                .padding(5)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DetectorPalette.ink, lineWidth: 2)
                .shadow(color: .black.opacity(0.50), radius: 4, y: 2)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(accent.opacity(0.62), lineWidth: 1)
                .padding(5)
        }
    }
}

struct Meter: View {
    let value: Double
    var color = DetectorPalette.accent

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.16))
                Capsule()
                    .fill(color)
                    .frame(width: geometry.size.width * min(1, max(0, value)))
            }
        }
        .frame(height: 5)
    }
}

struct DetectorButtonStyle: ButtonStyle {
    var tint = DetectorPalette.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .black, design: .rounded))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(
                Capsule()
                    .fill(tint.opacity(configuration.isPressed ? 0.65 : 1))
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

struct CompactDetectorButtonStyle: ButtonStyle {
    var tint = DetectorPalette.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .black, design: .rounded))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity, minHeight: 28)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.65 : 1))
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

struct StatPill: View {
    let icon: String
    let value: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
            Text(value)
        }
        .font(.system(size: 11, weight: .bold, design: .rounded))
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.white.opacity(0.12)))
    }
}

struct ScreenHeader: View {
    let title: String
    let back: () -> Void

    var body: some View {
        HStack {
            Button(action: back) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            Spacer()
            Text(title)
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .lineLimit(1)
            Spacer()
            Color.clear.frame(width: 18, height: 18)
        }
    }
}

struct DataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
        }
        .font(.system(size: 10, weight: .bold, design: .monospaced))
    }
}
