#if canImport(DashboardCore)
import DashboardCore
#endif
import Foundation
import SwiftUI
import WidgetKit

struct ArxivDigestEntry: TimelineEntry {
    let date: Date
    let digest: ArxivDigest
}

struct ArxivDigestTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> ArxivDigestEntry {
        ArxivDigestEntry(date: Date(), digest: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (ArxivDigestEntry) -> Void) {
        completion(ArxivDigestEntry(date: Date(), digest: ArxivDigestStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ArxivDigestEntry>) -> Void) {
        let entry = ArxivDigestEntry(date: Date(), digest: ArxivDigestStore.load())
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct KapiBoardArxivWidget: Widget {
    let kind = "KapiBoardArxivWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ArxivDigestTimelineProvider()) { entry in
            ArxivDigestWidgetView(entry: entry)
        }
        .configurationDisplayName("KapiBoard arXiv")
        .description("Large widget with the latest cs.DB digest.")
        .supportedFamilies([.systemLarge])
    }
}

struct ArxivDigestWidgetView: View {
    var entry: ArxivDigestEntry

    private var digest: ArxivDigest {
        entry.digest
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if digest.digest.isEmpty && digest.items.isEmpty {
                emptyState
            } else {
                metricsSection

                if !digest.digest.isEmpty {
                    digestSection
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "kapiboard://arxiv"))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Label("arXiv cs.DB", systemImage: "doc.text.magnifyingglass")
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            Text(updatedText)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private var digestSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("DAILY SIGNAL")
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(.secondary)

            Text(summaryText)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(8)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(paperCount)")
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundStyle(.primary)
                Text(paperCount == 1 ? "paper" : "papers")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(.secondary)
            }

            if !categorySummary.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CATEGORIES")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(.secondary)

                    Text(categorySummary)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No digest available")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.primary)

            Text("Run scripts/update_arxiv_digest.py to populate the latest summary.")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var updatedText: String {
        let date = digest.summarizedAt ?? digest.pulledAt
        guard let date else {
            return "Not updated"
        }

        if !digest.dateLabel.isEmpty {
            return "\(digest.dateLabel) @ \(date.formatted(.dateTime.hour().minute()))"
        }

        return "Updated \(date.formatted(.dateTime.hour().minute()))"
    }

    private var paperCount: Int {
        digest.paperCount ?? digest.items.count
    }

    private var summaryText: String {
        digest.digest.joined(separator: " ")
    }

    private var categorySummary: String {
        guard let counts = digest.categoryCounts, !counts.isEmpty else {
            return ""
        }

        return counts
            .sorted { left, right in
                if left.count == right.count {
                    return left.category < right.category
                }
                return left.count > right.count
            }
            .map { "\($0.category) \($0.count)" }
            .joined(separator: "  |  ")
    }
}

#if ARXIV_WIDGET_EXTENSION
@main
struct KapiBoardArxivWidgetBundle: WidgetBundle {
    var body: some Widget {
        KapiBoardArxivWidget()
    }
}
#endif
