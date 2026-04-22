import AppIntents
import SwiftUI
import WidgetKit

struct LinkLauncherConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Link Launcher"
    static let description = IntentDescription("Configure up to five fixed URL shortcuts.")

    @Parameter(title: "Title 1", default: "")
    var title1: String

    @Parameter(title: "URL 1", default: "")
    var url1: String

    @Parameter(title: "Title 2", default: "")
    var title2: String

    @Parameter(title: "URL 2", default: "")
    var url2: String

    @Parameter(title: "Title 3", default: "")
    var title3: String

    @Parameter(title: "URL 3", default: "")
    var url3: String

    @Parameter(title: "Title 4", default: "")
    var title4: String

    @Parameter(title: "URL 4", default: "")
    var url4: String

    @Parameter(title: "Title 5", default: "")
    var title5: String

    @Parameter(title: "URL 5", default: "")
    var url5: String
}

struct LinkLauncherEntry: TimelineEntry {
    let date: Date
    let configuration: LinkLauncherConfigurationIntent
}

struct LinkLauncherTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> LinkLauncherEntry {
        LinkLauncherEntry(date: Date(), configuration: LinkLauncherConfigurationIntent())
    }

    func snapshot(
        for configuration: LinkLauncherConfigurationIntent,
        in context: Context
    ) async -> LinkLauncherEntry {
        LinkLauncherEntry(date: Date(), configuration: configuration)
    }

    func timeline(
        for configuration: LinkLauncherConfigurationIntent,
        in context: Context
    ) async -> Timeline<LinkLauncherEntry> {
        Timeline(entries: [LinkLauncherEntry(date: Date(), configuration: configuration)], policy: .never)
    }
}

struct LinkLauncherWidgetView: View {
    var entry: LinkLauncherEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("LINKS", systemImage: "link")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)

            if configuredLinks.isEmpty {
                Text("No links configured")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                ForEach(configuredLinks.prefix(5)) { link in
                    Link(destination: WidgetLinks.source(link.url)) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.forward.app.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.cyan)
                                .frame(width: 12)

                            Text(link.title)
                                .font(.system(size: 12, weight: .bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)

                            Spacer(minLength: 0)
                        }
                        .frame(height: 18)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var configuredLinks: [ConfiguredLink] {
        [
            ConfiguredLink(title: entry.configuration.title1, rawURL: entry.configuration.url1),
            ConfiguredLink(title: entry.configuration.title2, rawURL: entry.configuration.url2),
            ConfiguredLink(title: entry.configuration.title3, rawURL: entry.configuration.url3),
            ConfiguredLink(title: entry.configuration.title4, rawURL: entry.configuration.url4),
            ConfiguredLink(title: entry.configuration.title5, rawURL: entry.configuration.url5)
        ].compactMap { $0 }
    }
}

struct KapiBoardLinksWidget: Widget {
    let kind = "KapiBoardLinksWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: LinkLauncherConfigurationIntent.self,
            provider: LinkLauncherTimelineProvider()
        ) { entry in
            LinkLauncherWidgetView(entry: entry)
        }
        .configurationDisplayName("KapiBoard links")
        .description("Small configurable shortcut widget for up to five URLs.")
        .supportedFamilies([.systemSmall])
    }
}

private struct ConfiguredLink: Identifiable {
    let title: String
    let url: URL

    var id: String {
        "\(title)-\(url.absoluteString)"
    }

    init?(title: String, rawURL: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty,
              let url = Self.normalizedURL(from: trimmedURL) else {
            return nil
        }

        self.title = trimmedTitle
        self.url = url
    }

    private static func normalizedURL(from value: String) -> URL? {
        guard !value.isEmpty else {
            return nil
        }

        let candidate = value.contains("://") ? value : "https://\(value)"
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return nil
        }
        return url
    }
}
