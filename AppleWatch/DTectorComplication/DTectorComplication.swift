import SwiftUI
import WidgetKit

private struct DTectorEntry: TimelineEntry {
    let date: Date
    let isNight: Bool
}

private struct DTectorProvider: TimelineProvider {
    func placeholder(in context: Context) -> DTectorEntry {
        DTectorEntry(date: Date(), isNight: false)
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (DTectorEntry) -> Void
    ) {
        completion(entry(at: Date()))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<DTectorEntry>) -> Void
    ) {
        let now = Date()
        let interval: TimeInterval = 5 * 60
        let currentBoundary = floor(now.timeIntervalSince1970 / interval)
            * interval
        var entries = [entry(at: now)]

        // Future entries let the face switch at five-minute boundaries
        // without waking the game itself.
        for index in 1...24 {
            entries.append(
                entry(
                    at: Date(
                        timeIntervalSince1970:
                            currentBoundary + Double(index) * interval
                    )
                )
            )
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func entry(at date: Date) -> DTectorEntry {
        let minute = Calendar.current.component(.minute, from: date)
        return DTectorEntry(date: date, isNight: minute % 10 >= 5)
    }
}

private struct DTectorComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DTectorEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            Label(
                entry.isNight ? "D-TECTOR NIGHT" : "D-TECTOR DAY",
                systemImage: entry.isNight ? "moon.fill" : "sun.max.fill"
            )
        case .accessoryRectangular:
            rectangular
        case .accessoryCorner:
            corner
        default:
            circular
        }
    }

    private var circular: some View {
        ZStack {
            DTectorLCDScene(isNight: entry.isNight)
            Image("spr_takuya_0", bundle: .main)
                .resizable()
                .interpolation(.none)
                .renderingMode(.template)
                .foregroundStyle(.black)
                .scaledToFit()
                .padding(7)
        }
        .containerBackground(for: .widget) {
            DTectorPalette.background
        }
    }

    private var rectangular: some View {
        HStack(spacing: 3) {
            ZStack {
                DTectorLCDScene(isNight: entry.isNight)
                Image("spr_takuya_0", bundle: .main)
                    .resizable()
                    .interpolation(.none)
                    .renderingMode(.template)
                    .foregroundStyle(.black)
                    .scaledToFit()
                    .padding(3)
            }
            .frame(width: 46)

            VStack(alignment: .leading, spacing: 1) {
                Text("D-TECTOR")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                Label(
                    entry.isNight ? "NIGHT" : "DAY",
                    systemImage: entry.isNight ? "moon.fill" : "sun.max.fill"
                )
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(.black)
        }
        .containerBackground(for: .widget) {
            DTectorPalette.background
        }
    }

    private var corner: some View {
        Image(systemName: entry.isNight ? "moon.fill" : "sun.max.fill")
            .font(.system(size: 20, weight: .bold))
            .widgetLabel {
                Text("D-TECTOR")
            }
            .containerBackground(for: .widget) {
                DTectorPalette.background
            }
    }
}

private struct DTectorLCDScene: View {
    let isNight: Bool

    var body: some View {
        Canvas { context, size in
            let cell = min(size.width, size.height) / 16
            let offsetX = (size.width - cell * 16) / 2
            let offsetY = (size.height - cell * 16) / 2

            func plot(_ x: Int, _ y: Int) {
                context.fill(
                    Path(
                        CGRect(
                            x: offsetX + CGFloat(x) * cell + cell * 0.12,
                            y: offsetY + CGFloat(y) * cell + cell * 0.12,
                            width: cell * 0.76,
                            height: cell * 0.76
                        )
                    ),
                    with: .color(.black)
                )
            }

            for x in 0..<16 { plot(x, 14) }
            for x in 1...4 { plot(x, 4) }
            plot(2, 3)
            plot(3, 3)

            if isNight {
                for (x, y) in [(11, 2), (10, 3), (10, 4), (11, 5), (12, 5)] {
                    plot(x, y)
                }
            } else {
                plot(11, 3)
                for (x, y) in [(11, 1), (11, 5), (9, 3), (13, 3)] {
                    plot(x, y)
                }
            }
        }
    }
}

private enum DTectorPalette {
    static let background = Color(
        red: 166.0 / 255.0,
        green: 171.0 / 255.0,
        blue: 168.0 / 255.0
    )
}

@main
struct DTectorComplication: Widget {
    let kind = "com.kaisa.DTector.character"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DTectorProvider()) { entry in
            DTectorComplicationView(entry: entry)
        }
        .configurationDisplayName("D-Tector")
        .description("ตัวละครและฉากกลางวันกลางคืนของ D-Tector")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCorner,
        ])
    }
}
