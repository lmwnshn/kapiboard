import SwiftUI
import WidgetKit

struct KapiBoardWidget: Widget {
    let kind = "KapiBoardWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DashboardTimelineProvider()) { entry in
            DashboardWidgetView(entry: entry)
        }
        .configurationDisplayName("KapiBoard main")
        .description("Primary dashboard view with weather, mail, markets, clocks, and agenda.")
        .supportedFamilies([.systemExtraLarge])
    }
}

struct KapiBoardLowerOneWidget: Widget {
    let kind = "KapiBoardLowerOneWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DashboardTimelineProvider()) { entry in
            DetailStripWidgetView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("KapiBoard lower1")
        .description("Medium companion widget with stretched market quotes.")
        .supportedFamilies([.systemMedium])
    }
}

struct KapiBoardLowerTwoWidget: Widget {
    let kind = "KapiBoardLowerTwoWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DashboardTimelineProvider()) { entry in
            LowerTwoWidgetView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("KapiBoard lower2")
        .description("Medium companion widget with weather, clocks, and next items.")
        .supportedFamilies([.systemMedium])
    }
}

#if DETAIL_WIDGET_EXTENSION
@main
struct KapiBoardDetailWidgetBundle: WidgetBundle {
    var body: some Widget {
        KapiBoardLowerOneWidget()
        KapiBoardLowerTwoWidget()
    }
}
#else
@main
struct KapiBoardWidgetBundle: WidgetBundle {
    var body: some Widget {
        KapiBoardWidget()
        KapiBoardLinksWidget()
    }
}
#endif
