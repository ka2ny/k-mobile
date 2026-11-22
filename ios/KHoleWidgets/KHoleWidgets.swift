import WidgetKit
import SwiftUI

/// Home Screen and Lock Screen widgets from Home's last readings (the app keeps them when the phone app's Home reads
/// /app/widgets): nothing here asks the computer, so a widget costs the computer nothing. A tap opens that part.
struct ReadingsEntry: TimelineEntry {
    let date: Date
    let readings: Readings?
}

struct ReadingsProvider: TimelineProvider {
    func placeholder(in context: Context) -> ReadingsEntry {
        ReadingsEntry(date: .now, readings: Readings(at: .now, needs: 1, working: 2, first: "fix the build", assistant: "free",
                                                     battery: .init(level: 82, charging: false), storageFree: 412e9, memoryPercent: 38))
    }
    func getSnapshot(in context: Context, completion: @escaping (ReadingsEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : ReadingsEntry(date: .now, readings: Readings.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ReadingsEntry>) -> Void) {
        // the app reloads the timelines when a reading changes; this only refreshes the "how long ago"
        completion(Timeline(entries: [ReadingsEntry(date: .now, readings: Readings.load())], policy: .after(.now.addingTimeInterval(30 * 60))))
    }
}

private let ink = Color(red: 0.933, green: 0.945, blue: 0.925)
private let muted = Color(red: 0.612, green: 0.659, blue: 0.667)
private let accent = Color(red: 0.718, green: 0.843, blue: 0.761)
private let warn = Color(red: 0.918, green: 0.718, blue: 0.396)
private let ground = LinearGradient(colors: [Color(hue: 0.555, saturation: 0.12, brightness: 0.15), Color(hue: 0.555, saturation: 0.12, brightness: 0.10)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing)

/// Agents: what needs your yes, the first one's name, what is working.
struct AgentsWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: ReadingsEntry
    var body: some View {
        let r = entry.readings
        switch family {
        case .accessoryCircular:
            Gauge(value: Double(min(r?.needs ?? 0, 9)), in: 0...9) { Image(systemName: "terminal") } currentValueLabel: { Text("\(r?.needs ?? 0)") }
                .gaugeStyle(.accessoryCircularCapacity)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("agents").font(.caption2).foregroundStyle(.secondary)
                Text((r?.needs ?? 0) == 0 ? "nothing needs you" : (r?.needs ?? 0) == 1 ? "1 needs you" : "\(r?.needs ?? 0) need you").font(.headline)
                if let first = r?.first, !first.isEmpty { Text(first).font(.caption).lineLimit(1) }
            }
        default:
            VStack(alignment: .leading, spacing: 4) {
                Label("agents", systemImage: "terminal").font(.system(size: 12)).foregroundStyle(muted)
                Spacer()
                Text("\(r?.needs ?? 0)").font(.system(size: 34, weight: .regular)).foregroundStyle((r?.needs ?? 0) > 0 ? warn : ink)
                Text((r?.needs ?? 0) == 1 ? "needs you" : (r?.needs ?? 0) > 1 ? "need you" : "nothing needs you").font(.system(size: 13)).foregroundStyle(ink)
                if family != .systemSmall, let first = r?.first, !first.isEmpty { Text(first).font(.system(size: 13)).foregroundStyle(muted).lineLimit(1) }
                if let r { Text(r.at, style: .relative).font(.system(size: 11)).foregroundStyle(muted) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

/// The computer: its battery, else what is free on it.
struct ComputerWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: ReadingsEntry
    var body: some View {
        let r = entry.readings
        switch family {
        case .accessoryCircular:
            if let b = r?.battery {
                Gauge(value: Double(b.level), in: 0...100) { Image(systemName: b.charging ? "bolt.fill" : "laptopcomputer") } currentValueLabel: { Text("\(b.level)") }
                    .gaugeStyle(.accessoryCircular)
            } else { Image(systemName: "desktopcomputer") }
        default:
            VStack(alignment: .leading, spacing: 4) {
                Label("this computer", systemImage: "laptopcomputer").font(.system(size: 12)).foregroundStyle(muted)
                Spacer()
                if let b = r?.battery {
                    Text("\(b.level)%").font(.system(size: 34)).foregroundStyle(ink)
                    Text(b.charging ? "charging" : "on battery").font(.system(size: 13)).foregroundStyle(ink)
                } else if let free = r?.storageFree {
                    Text(free >= 1e12 ? String(format: "%.1f tb", free / 1e12) : "\(Int(free / 1e9)) gb").font(.system(size: 30)).foregroundStyle(ink)
                    Text("free").font(.system(size: 13)).foregroundStyle(ink)
                } else {
                    Text("open k-hole once").font(.system(size: 14)).foregroundStyle(muted)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

struct AgentsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "agents", provider: ReadingsProvider()) { entry in
            AgentsWidgetView(entry: entry)
                .containerBackground(for: .widget) { ground }
                .widgetURL(URL(string: "khole://open?path=/agents/"))
        }
        .configurationDisplayName("agents")
        .description("what needs your yes on the computer")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct ComputerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "computer", provider: ReadingsProvider()) { entry in
            ComputerWidgetView(entry: entry)
                .containerBackground(for: .widget) { ground }
                .widgetURL(URL(string: "khole://open?path=/"))
        }
        .configurationDisplayName("this computer")
        .description("its battery, or what is free on it")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

@main
struct KHoleWidgetBundle: WidgetBundle {
    var body: some Widget {
        AgentsWidget()
        ComputerWidget()
    }
}
