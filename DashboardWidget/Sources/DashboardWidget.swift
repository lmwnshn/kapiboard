#if canImport(DashboardCore)
import DashboardCore
#endif
import SwiftUI

struct DashboardWidgetView: View {
    var entry: DashboardEntry

    var body: some View {
        ExtraLargeWidget(snapshot: entry.snapshot)
    }
}

struct ExtraLargeWidget: View {
    var snapshot: DashboardSnapshot

    var body: some View {
        GeometryReader { proxy in
            let wide = proxy.size.width > 620
            let utilityWidth = wide ? max(132, min(170, (proxy.size.width - 18) * 0.28)) : proxy.size.width
            let rowHeight = (proxy.size.height - 22) / 2

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    TodayPanel(snapshot: snapshot, showsAllDayEvents: false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    MonthPanel(date: snapshot.generatedAt)
                        .frame(width: utilityWidth)
                        .frame(maxHeight: .infinity)
                }
                .frame(height: rowHeight)

                HStack(spacing: 10) {
                    AgendaPanel(calendar: snapshot.calendar, reminders: snapshot.reminders, showsAllDayEvents: false, maxItems: 4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    MailPanel(mail: snapshot.mail)
                        .frame(width: utilityWidth)
                        .frame(maxHeight: .infinity)
                }
                .frame(height: rowHeight)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct DetailStripWidgetView: View {
    var snapshot: DashboardSnapshot

    var body: some View {
        LowerOneMediumWidget(snapshot: snapshot)
    }
}

struct LowerTwoWidgetView: View {
    var snapshot: DashboardSnapshot

    var body: some View {
        LowerTwoMediumWidget(snapshot: snapshot)
    }
}

struct LowerOneMediumWidget: View {
    var snapshot: DashboardSnapshot

    var body: some View {
        LowerMarketsBlock(markets: snapshot.markets)
        .padding(12)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct LowerTwoMediumWidget: View {
    var snapshot: DashboardSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Link(destination: WidgetLinks.weather(for: snapshot.weather)) {
                DenseWeatherBlock(weather: snapshot.weather)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .buttonStyle(.plain)

            Divider().opacity(0.45)

            DenseClocksBlock(clocks: snapshot.clocks)
                .frame(minWidth: 78, idealWidth: 78, maxWidth: 78, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(12)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct LowerMarketsBlock: View {
    var markets: MarketSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("MARKETS", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)

                Spacer()

                if let marketTimestampText {
                    Text(marketTimestampText)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
            }

            if markets.quotes.isEmpty {
                Text("No quotes")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(markets.quotes.prefix(3)) { quote in
                    LowerMarketRow(quote: quote, marketIsOpen: marketIsOpen)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var marketTimestampText: String? {
        let quoteTime = markets.quotes
            .compactMap(\.updatedAt)
            .max()
            .map { $0.formatted(date: .omitted, time: .shortened) } ?? "N/A"
        let pulledTime = markets.checkedAt?
            .formatted(date: .omitted, time: .shortened) ?? "N/A"
        return "Yahoo quote @ \(quoteTime), pulled @ \(pulledTime)"
    }

    private var marketIsOpen: Bool {
        Self.isUSMarketOpen(at: Date())
    }

    private static func isUSMarketOpen(at date: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current

        let weekday = calendar.component(.weekday, from: date)
        guard (2...6).contains(weekday) else {
            return false
        }

        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let minutesAfterMidnight = hour * 60 + minute
        return minutesAfterMidnight >= 9 * 60 + 30 && minutesAfterMidnight < 16 * 60
    }
}

struct LowerMarketRow: View {
    var quote: MarketQuote
    var marketIsOpen: Bool

    var body: some View {
        Link(destination: WidgetLinks.yahooFinance(symbol: quote.symbol)) {
            row
        }
        .buttonStyle(.plain)
    }

    private var row: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(quote.symbol)
                    .font(.system(size: 14, weight: .bold))
                    .lineLimit(1)

                Text(quote.name)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 118, alignment: .leading)

            SparklineShape(values: quote.sparkline)
                .stroke(sparklineColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(maxWidth: .infinity, minHeight: 20, maxHeight: 22)

            VStack(alignment: .trailing, spacing: 1) {
                Text(quote.price.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? "--")
                    .font(.system(size: 14, weight: .bold))
                    .monospacedDigit()

                HStack(spacing: 4) {
                    Text(quote.change.map { signed($0) } ?? "--")
                    Text(quote.changePercent.map { "(\(signed($0))%)" } ?? "")
                }
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle((quote.change ?? 0) >= 0 ? .green : .red)
                .monospacedDigit()
            }
            .frame(width: 92, alignment: .trailing)
        }
    }

    private func signed(_ value: Double) -> String {
        value.formatted(.number.sign(strategy: .always()).precision(.fractionLength(2)))
    }

    private var sparklineColor: Color {
        guard marketIsOpen else {
            return .secondary.opacity(0.7)
        }

        return (quote.change ?? 0) >= 0 ? .green : .red
    }
}

struct SparklineShape: Shape {
    var values: [Double]

    func path(in rect: CGRect) -> Path {
        guard values.count > 1,
              let min = values.min(),
              let max = values.max(),
              max > min else {
            return Path()
        }

        let points = values.enumerated().map { index, value in
            let x = rect.minX + rect.width * CGFloat(index) / CGFloat(values.count - 1)
            let ratio = (value - min) / (max - min)
            let y = rect.maxY - (rect.height * CGFloat(ratio))
            return CGPoint(x: x, y: y)
        }

        var path = Path()
        path.move(to: points[0])
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }
}

struct DenseWeatherBlock: View {
    var weather: WeatherSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "cloud.sun.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.cyan)
                Text(locationTitle)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(alignment: .center, spacing: 8) {
                Text(weather.temperature.map { "\(Int($0.rounded()))°" } ?? "--")
                    .font(.system(size: 34, weight: .light))
                    .monospacedDigit()

                VStack(alignment: .leading, spacing: 2) {
                    Text(umbrellaAdvice)
                    Text(clothingAdvice)
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    DenseMetric(label: "Wind", value: wind(weather.windSpeed))
                    DenseMetric(label: "Feel", value: temperature(weather.apparentTemperature))
                    DenseMetric(label: "Air", value: airQuality(weather.airQualityIndex))
                    DenseMetric(label: "Rise", value: time(weather.sunrise))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 3) {
                    DenseMetric(label: "Hum", value: percent(weather.humidity))
                    DenseMetric(label: "Rain", value: precipitation(weather.precipitation))
                    DenseMetric(label: "UV", value: uv(weather.uvIndex))
                    DenseMetric(label: "Set", value: time(weather.sunset))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func temperature(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded()))°" } ?? "--"
    }

    private func precipitation(_ value: Double?) -> String {
        guard let value else {
            return "--"
        }

        if value < 0.005 {
            return "0 in"
        }
        return value.formatted(.number.precision(.fractionLength(2))) + " in"
    }

    private func percent(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded()))%" } ?? "--"
    }

    private func wind(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded())) mph" } ?? "--"
    }

    private func airQuality(_ value: Double?) -> String {
        value.map { "AQI \(Int($0.rounded()))" } ?? "--"
    }

    private func uv(_ value: Double?) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "--"
    }

    private func time(_ value: Date?) -> String {
        value?.formatted(date: .omitted, time: .shortened) ?? "--"
    }

    private var umbrellaAdvice: String {
        if let precipitation = weather.precipitation, precipitation >= 0.005 {
            return "Bring umbrella"
        }

        guard let maxProbability = remainingDayPrecipitationProbability() else {
            return "N/A"
        }

        if maxProbability >= 55 {
            return "Bring umbrella"
        }
        if maxProbability >= 30 {
            return "Umbrella maybe"
        }
        return "No umbrella"
    }

    private var clothingAdvice: String {
        guard let apparentTemperature = weather.apparentTemperature ?? weather.temperature else {
            return "N/A"
        }

        if apparentTemperature < 32 {
            return "Heavy coat"
        }
        if apparentTemperature < 50 {
            return "Dress warmer"
        }
        if apparentTemperature < 65 {
            return "Light layer"
        }
        if apparentTemperature <= 78 {
            return "Comfortable"
        }
        return "Dress cooler"
    }

    private func remainingDayPrecipitationProbability() -> Double? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        let now = Date()
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else {
            return nil
        }

        return weather.hourly
            .filter { $0.time >= now && $0.time < endOfDay }
            .compactMap(\.precipitationProbability)
            .max()
    }

    private var locationTitle: String {
        switch weather.locationName.lowercased() {
        case "pittsburgh":
            "PITTSBURGH, PA"
        default:
            weather.locationName.uppercased()
        }
    }
}

struct DenseMetric: View {
    var label: String
    var value: String

    var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .leading)
            Text(value)
                .font(.system(size: 10, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

struct DenseClocksBlock: View {
    var clocks: [ClockSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("CLOCKS", systemImage: "clock.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            ForEach(clockItems) { clock in
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 3) {
                        Text(abbreviation(clock))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Text(clockDate(clock))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                    }

                    Text(clockTime(clock))
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var clockItems: [ClockSnapshot] {
        let wanted = ["America/New_York", "America/Los_Angeles", "Asia/Singapore"]
        return wanted.compactMap { identifier in
            clocks.first { $0.timeZoneIdentifier == identifier }
        }
    }

    private func abbreviation(_ clock: ClockSnapshot) -> String {
        switch clock.timeZoneIdentifier {
        case "America/New_York":
            return "NYC"
        case "America/Los_Angeles":
            return "SFO"
        case "Asia/Singapore":
            return "SIN"
        default:
            return String(clock.city.prefix(3)).uppercased()
        }
    }

    private func clockDate(_ clock: ClockSnapshot) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        formatter.timeZone = TimeZone(identifier: clock.timeZoneIdentifier)
        return formatter.string(from: clock.currentDate)
    }

    private func clockTime(_ clock: ClockSnapshot) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "hh:mm a"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: clock.timeZoneIdentifier)
        return formatter.string(from: clock.currentDate)
    }
}

struct WidgetPanel<Content: View>: View {
    var title: String
    var systemImage: String
    var destination: URL?
    var content: Content

    init(
        title: String,
        systemImage: String,
        destination: URL? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.destination = destination
        self.content = content()
    }

    var body: some View {
        if let destination {
            Link(destination: destination) {
                panel
            }
            .buttonStyle(.plain)
        } else {
            panel
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title.uppercased(), systemImage: systemImage)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct TodayPanel: View {
    var snapshot: DashboardSnapshot
    var showsAllDayEvents = true

    var body: some View {
        WidgetPanel(
            title: snapshot.generatedAt.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()),
            systemImage: "calendar"
        ) {
            let items = todayItems
            Spacer(minLength: 4)
            if items.isEmpty {
                Text("No events today")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items.prefix(2)) { item in
                    WidgetRow(
                        title: item.title,
                        subtitle: itemTime(item),
                        systemImage: "calendar.badge.clock",
                        destination: item.widgetURL
                    )
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func itemTime(_ item: CalendarItem) -> String {
        let time = item.isAllDay ? "All day" : item.startDate.formatted(date: .omitted, time: .shortened)
        return "\(time) · \(item.calendarTitle)"
    }

    private var todayItems: [CalendarItem] {
        showsAllDayEvents ? snapshot.calendar.today : snapshot.calendar.today.filter { !$0.isAllDay }
    }
}

struct MonthPanel: View {
    var date: Date

    var body: some View {
        WidgetPanel(title: date.formatted(.dateTime.month(.wide)), systemImage: "calendar.circle", destination: WidgetLinks.googleCalendar) {
            let days = monthDays()
            Spacer(minLength: 0)

            Grid(horizontalSpacing: 3, verticalSpacing: 2) {
                GridRow {
                    ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) {
                        Text($0)
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 13)
                    }
                }

                ForEach(0..<6, id: \.self) { row in
                    GridRow {
                        ForEach(0..<7, id: \.self) { column in
                            let index = row * 7 + column
                            if index < days.count, let day = days[index] {
                                Text("\(day)")
                                    .font(.system(size: 9, weight: isToday(day) ? .bold : .semibold))
                                    .foregroundStyle(isToday(day) ? .white : .primary)
                                    .frame(width: 13, height: 13)
                                    .background(isToday(day) ? Color.red : Color.clear, in: Circle())
                            } else {
                                Text("")
                                    .frame(width: 13, height: 13)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Spacer(minLength: 0)
        }
    }

    private func monthDays() -> [Int?] {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: date),
              let range = calendar.range(of: .day, in: .month, for: date) else {
            return []
        }

        let firstWeekday = calendar.component(.weekday, from: monthInterval.start) - 1
        var days: [Int?] = Array(repeating: nil, count: firstWeekday)
        days.append(contentsOf: range.map { Optional($0) })
        while days.count < 42 {
            days.append(nil)
        }
        return days
    }

    private func isToday(_ day: Int) -> Bool {
        Calendar.current.component(.day, from: date) == day
    }
}

struct AgendaPanel: View {
    var calendar: CalendarSnapshot
    var reminders: ReminderSnapshot
    var showsAllDayEvents = true
    var maxItems = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Label("UPCOMING", systemImage: "list.bullet.rectangle")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text(calendarSyncText)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            let items = agendaItems
            if items.isEmpty {
                Text("No upcoming items")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items.prefix(maxItems), id: \.id) { item in
                    WidgetRow(title: item.title, subtitle: item.subtitle, systemImage: item.systemImage, destination: item.widgetURL)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var agendaItems: [AgendaDisplayItem] {
        let events = calendar.today + calendar.upcoming
        let visibleEvents = showsAllDayEvents ? events : events.filter { !$0.isAllDay }
        let eventItems = visibleEvents.map { event in
            let time = event.isAllDay ? "All day" : event.startDate.formatted(date: .abbreviated, time: .shortened)
            return AgendaDisplayItem(
                id: "event-\(event.id)",
                title: event.title,
                subtitle: "\(time) · \(event.calendarTitle)",
                systemImage: "calendar",
                url: event.url
            )
        }
        let reminderItems = reminders.dueSoon.map {
            AgendaDisplayItem(
                id: "reminder-\($0.id)",
                title: $0.title,
                subtitle: $0.dueDate?.formatted(date: .abbreviated, time: .shortened) ?? $0.listTitle,
                systemImage: "checklist",
                url: nil
            )
        }
        return eventItems + reminderItems
    }

    private var calendarSyncText: String {
        let sourceTime = calendar.sourceUpdatedAt?
            .formatted(date: .omitted, time: .shortened) ?? "N/A"
        let pulledTime = calendar.checkedAt?
            .formatted(date: .omitted, time: .shortened) ?? "N/A"

        return "\(calendarSourceLabel) event edit @ \(sourceTime), pulled @ \(pulledTime)"
    }

    private var calendarSourceLabel: String {
        switch calendar.source {
        case .google:
            "Google"
        case .eventKit:
            "Local"
        case nil:
            "Calendar"
        }
    }
}

struct MailPanel: View {
    var mail: MailSnapshot

    var body: some View {
        WidgetPanel(title: "Gmail", systemImage: "envelope.fill", destination: WidgetLinks.gmailInbox) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(mail.unreadCount)")
                    .font(.system(size: 36, weight: .light))
                    .monospacedDigit()
                Text("unread")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
            }

            if !mail.messages.isEmpty {
                ForEach(mail.messages.prefix(2)) { message in
                    WidgetRow(title: message.subject, subtitle: message.from, systemImage: "envelope")
                }
            } else if mail.status != .ready {
                Text(mailStatus)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var mailStatus: String {
        switch mail.status {
        case .ready:
            "No unread mail"
        case .notConfigured:
            "Gmail not configured"
        case let .unavailable(message):
            message
        }
    }
}

struct WidgetRow: View {
    var title: String
    var subtitle: String
    var systemImage: String
    var destination: URL? = nil

    var body: some View {
        if let destination {
            Link(destination: destination) {
                row
            }
            .buttonStyle(.plain)
        } else {
            row
        }
    }

    private var row: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.cyan)
                .frame(width: 12)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct AgendaDisplayItem {
    var id: String
    var title: String
    var subtitle: String
    var systemImage: String
    var url: String?

    var widgetURL: URL? {
        url.flatMap(URL.init(string:)).map(WidgetLinks.source)
    }
}
