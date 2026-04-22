#if canImport(DashboardCore)
import DashboardCore
#endif
import AppKit
import SwiftUI

struct DashboardRootView: View {
    @ObservedObject var navigation: DashboardNavigationStore
    @State private var viewModel = DashboardViewModel()

    init(navigation: DashboardNavigationStore = .shared) {
        self.navigation = navigation
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.13, blue: 0.16),
                    Color(red: 0.05, green: 0.09, blue: 0.11),
                    Color(red: 0.11, green: 0.10, blue: 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                HeaderView(
                    snapshot: viewModel.snapshot,
                    isRefreshing: viewModel.isRefreshing,
                    googleCalendarConfigured: viewModel.googleCalendarConfigured,
                    googleCalendarConnected: viewModel.googleCalendarConnected,
                    googleCalendarAuthError: viewModel.googleCalendarAuthError,
                    refresh: {
                    Task {
                        await viewModel.refresh()
                    }
                },
                    connectGoogle: {
                        Task {
                            await viewModel.connectGoogleCalendar()
                        }
                    },
                    disconnectGoogle: {
                        Task {
                            await viewModel.disconnectGoogleCalendar()
                        }
                    }
                )

                GeometryReader { proxy in
                    let compact = proxy.size.width < 1100

                    if compact {
                        ScrollViewReader { proxy in
                            ScrollView {
                                VStack(spacing: 14) {
                                    WeatherCard(weather: viewModel.snapshot.weather)
                                    AgendaCard(calendar: viewModel.snapshot.calendar, reminders: viewModel.snapshot.reminders)
                                    MailCard(mail: viewModel.snapshot.mail)
                                    MarketCard(markets: viewModel.snapshot.markets)
                                    ClocksCard(clocks: viewModel.snapshot.clocks)
                                    SunCard(weather: viewModel.snapshot.weather)
                                    LinksCard(links: DashboardLink.defaults)
                                    ArxivBrowserCard(
                                        selectedDate: viewModel.arxivSelectedDate,
                                        digest: viewModel.arxivDigest,
                                        isLoading: viewModel.arxivIsLoading,
                                        error: viewModel.arxivError,
                                        canMoveNext: viewModel.canMoveArxivNext,
                                        previous: {
                                            Task {
                                                await viewModel.previousArxivDate()
                                            }
                                        },
                                        next: {
                                            Task {
                                                await viewModel.nextArxivDate()
                                            }
                                        }
                                    )
                                    .id(DashboardSection.arxiv)
                                }
                                .padding(.bottom, 18)
                            }
                            .onChange(of: navigation.focusRequest) { _, request in
                                scrollIfNeeded(request, proxy: proxy)
                            }
                            .onAppear {
                                scrollIfNeeded(navigation.focusRequest, proxy: proxy)
                            }
                        }
                    } else {
                        ScrollViewReader { scrollProxy in
                            ScrollView {
                                VStack(spacing: 14) {
                                    Grid(horizontalSpacing: 14, verticalSpacing: 14) {
                                        GridRow {
                                            AgendaCard(calendar: viewModel.snapshot.calendar, reminders: viewModel.snapshot.reminders)
                                                .gridCellColumns(2)
                                            WeatherCard(weather: viewModel.snapshot.weather)
                                                .gridCellColumns(2)
                                        }

                                        GridRow {
                                            MailCard(mail: viewModel.snapshot.mail)
                                            MarketCard(markets: viewModel.snapshot.markets)
                                            ClocksCard(clocks: viewModel.snapshot.clocks)
                                            SunCard(weather: viewModel.snapshot.weather)
                                        }

                                        GridRow {
                                            LinksCard(links: DashboardLink.defaults)
                                                .gridCellColumns(4)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .top)
                                    .frame(minHeight: 360)

                                    ArxivBrowserCard(
                                        selectedDate: viewModel.arxivSelectedDate,
                                        digest: viewModel.arxivDigest,
                                        isLoading: viewModel.arxivIsLoading,
                                        error: viewModel.arxivError,
                                        canMoveNext: viewModel.canMoveArxivNext,
                                        previous: {
                                            Task {
                                                await viewModel.previousArxivDate()
                                            }
                                        },
                                        next: {
                                            Task {
                                                await viewModel.nextArxivDate()
                                            }
                                        }
                                    )
                                    .frame(maxWidth: .infinity)
                                    .frame(minHeight: 620)
                                    .id(DashboardSection.arxiv)
                                }
                                .padding(.bottom, 18)
                            }
                            .onChange(of: navigation.focusRequest) { _, request in
                                scrollIfNeeded(request, proxy: scrollProxy)
                            }
                            .onAppear {
                                scrollIfNeeded(navigation.focusRequest, proxy: scrollProxy)
                            }
                        }
                    }
                }
            }
            .padding(22)
        }
        .task {
            await viewModel.startRefreshLoop()
        }
        .onOpenURL { url in
            guard url.scheme == "kapiboard" else {
                return
            }

            if url.host == "refresh" {
                Task {
                    await viewModel.refresh()
                }
            } else if KapiBoardURLHandler.handle(url), url.host != "arxiv" {
                NSApp.hide(nil)
            }
        }
    }

    private func scrollIfNeeded(_ request: DashboardFocusRequest?, proxy: ScrollViewProxy) {
        guard request?.target == .arxiv else {
            return
        }

        withAnimation(.easeInOut(duration: 0.25)) {
            proxy.scrollTo(DashboardSection.arxiv, anchor: .top)
        }
    }
}

private enum DashboardSection: Hashable {
    case arxiv
}

struct HeaderView: View {
    var snapshot: DashboardSnapshot
    var isRefreshing: Bool
    var googleCalendarConfigured: Bool
    var googleCalendarConnected: Bool
    var googleCalendarAuthError: String?
    var refresh: () -> Void
    var connectGoogle: () -> Void
    var disconnectGoogle: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("KapiBoard")
                    .font(.system(size: 26, weight: .semibold))
                Text("Updated \(snapshot.generatedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                if let googleCalendarAuthError {
                    Text(googleCalendarAuthError)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button(action: googleCalendarConnected ? disconnectGoogle : connectGoogle) {
                Label(
                    googleCalendarConnected ? "Google Connected" : "Connect Google",
                    systemImage: googleCalendarConnected ? "checkmark.circle.fill" : "person.crop.circle.badge.plus"
                )
                .font(.system(size: 12, weight: .bold))
            }
            .buttonStyle(.borderless)
            .disabled(!googleCalendarConfigured && !googleCalendarConnected)
            .help(googleCalendarConfigured ? "Connect Google Calendar and Gmail" : "Set GOOGLE_CLIENT_ID to enable Google")

            Button(action: refresh) {
                Image(systemName: isRefreshing ? "arrow.triangle.2.circlepath.circle" : "arrow.clockwise")
                    .font(.system(size: 18, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .help("Refresh")
        }
        .foregroundStyle(.white)
    }
}

struct DashboardCard<Content: View>: View {
    var title: String
    var systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.cyan)
                Text(title.uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
        .foregroundStyle(.white)
    }
}

struct WeatherCard: View {
    var weather: WeatherSnapshot

    var body: some View {
        DashboardCard(title: weather.locationName, systemImage: "cloud.sun.fill") {
            HStack(alignment: .top) {
                Text(weather.temperature.map { "\(Int($0.rounded()))°" } ?? "--")
                    .font(.system(size: 72, weight: .light))
                    .monospacedDigit()

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    Text(weatherStatus)
                        .font(.system(size: 15, weight: .semibold))
                    Text("Open-Meteo")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                ForEach(weather.hourly.prefix(6)) { hour in
                    VStack(spacing: 8) {
                        Text(hour.time.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                        Image(systemName: "cloud.fill")
                            .font(.system(size: 19))
                        Text("\(Int(hour.temperature.rounded()))°")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var weatherStatus: String {
        switch weather.status {
        case .ready:
            "Live weather"
        case .notConfigured:
            "Not configured"
        case .unavailable:
            "Unavailable"
        }
    }
}

struct AgendaCard: View {
    var calendar: CalendarSnapshot
    var reminders: ReminderSnapshot

    var body: some View {
        DashboardCard(title: "Agenda", systemImage: "calendar") {
            if calendar.today.isEmpty && calendar.upcoming.isEmpty && reminders.dueSoon.isEmpty {
                EmptyState(text: "Calendar and reminders are not wired yet.")
            } else {
                VStack(spacing: 10) {
                    ForEach(calendar.today.prefix(3)) { item in
                        LinkedRow(
                            title: item.title,
                            subtitle: calendarSubtitle(item),
                            icon: "calendar.badge.clock",
                            destination: item.externalURL
                        )
                    }
                    ForEach(reminders.dueSoon.prefix(3)) { item in
                        Row(title: item.title, subtitle: item.listTitle, icon: "checklist")
                    }
                }
            }
        }
    }

    private func calendarSubtitle(_ item: CalendarItem) -> String {
        "\(item.startDate.formatted(date: .omitted, time: .shortened)) · \(item.calendarTitle)"
    }
}

struct MailCard: View {
    var mail: MailSnapshot

    var body: some View {
        Link(destination: AppLinks.gmailInbox) {
            DashboardCard(title: "Gmail", systemImage: "envelope.fill") {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(mail.unreadCount)")
                        .font(.system(size: 54, weight: .light))
                        .monospacedDigit()
                    Text("unread")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 10) {
                    if mail.messages.isEmpty {
                        if mail.status != .ready {
                            EmptyState(text: mailStatusText)
                        }
                    } else {
                        ForEach(mail.messages.prefix(2)) { message in
                            Row(title: message.subject, subtitle: message.from, icon: "envelope")
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .help("Open Gmail")
    }

    private var mailStatusText: String {
        switch mail.status {
        case .ready:
            "No unread mail"
        case .notConfigured:
            "Gmail API is not configured."
        case let .unavailable(message):
            message
        }
    }
}

struct MarketCard: View {
    var markets: MarketSnapshot

    var body: some View {
        DashboardCard(title: "Markets", systemImage: "chart.line.uptrend.xyaxis") {
            if markets.quotes.isEmpty {
                EmptyState(text: "No Yahoo quotes returned.")
            } else {
                VStack(spacing: 12) {
                    ForEach(markets.quotes.prefix(5)) { quote in
                        Link(destination: AppLinks.yahooFinance(symbol: quote.symbol)) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(quote.symbol)
                                        .font(.system(size: 18, weight: .bold))
                                    Text(quote.name)
                                        .lineLimit(1)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }

                                Sparkline(values: quote.sparkline)
                                    .frame(width: 72, height: 28)

                                Spacer()

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(quote.price.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? "--")
                                        .font(.system(size: 16, weight: .bold))
                                        .monospacedDigit()
                                    Text(quote.change.map { signed($0) } ?? "--")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle((quote.change ?? 0) >= 0 ? .green : .red)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Open \(quote.symbol) on Yahoo Finance")
                    }
                }
            }
        }
    }

    private func signed(_ value: Double) -> String {
        value.formatted(.number.sign(strategy: .always()).precision(.fractionLength(2)))
    }
}

struct ClocksCard: View {
    var clocks: [ClockSnapshot]

    var body: some View {
        DashboardCard(title: "World Clocks", systemImage: "clock.fill") {
            VStack(spacing: 12) {
                ForEach(clocks) { clock in
                    HStack {
                        Text(clock.city)
                            .font(.system(size: 15, weight: .bold))
                        Spacer()
                        Text(clockTime(clock))
                            .font(.system(size: 20, weight: .semibold))
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    private func clockTime(_ clock: ClockSnapshot) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.timeZone = TimeZone(identifier: clock.timeZoneIdentifier)
        return formatter.string(from: clock.currentDate)
    }
}

struct SunCard: View {
    var weather: WeatherSnapshot

    var body: some View {
        DashboardCard(title: "Sun", systemImage: "sunrise.fill") {
            VStack(alignment: .leading, spacing: 16) {
                Row(title: weather.sunrise?.formatted(date: .omitted, time: .shortened) ?? "--", subtitle: "Sunrise", icon: "sunrise")
                Row(title: weather.sunset?.formatted(date: .omitted, time: .shortened) ?? "--", subtitle: "Sunset", icon: "sunset")
            }
        }
    }
}

struct LinksCard: View {
    var links: [DashboardLink]

    var body: some View {
        DashboardCard(title: "Links", systemImage: "link") {
            if links.isEmpty {
                EmptyState(text: "No links configured.")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(links.prefix(5)) { link in
                        Link(destination: link.url) {
                            HStack(spacing: 10) {
                                Image(systemName: "arrow.up.forward.app.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.cyan)
                                    .frame(width: 18)

                                Text(link.title)
                                    .font(.system(size: 14, weight: .bold))
                                    .lineLimit(1)

                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .help(link.url.absoluteString)
                    }
                }
            }
        }
    }
}

struct ArxivBrowserCard: View {
    var selectedDate: Date
    var digest: ArxivDigest
    var isLoading: Bool
    var error: String?
    var canMoveNext: Bool
    var previous: () -> Void
    var next: () -> Void

    var body: some View {
        DashboardCard(title: "arXiv cs.DB", systemImage: "doc.text.magnifyingglass") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Text("Date: \(selectedDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(size: 14, weight: .bold))

                    Spacer()

                    Button("PREV", action: previous)
                        .font(.system(size: 11, weight: .black))
                        .buttonStyle(.borderless)
                        .disabled(isLoading)

                    Button("NEXT", action: next)
                        .font(.system(size: 11, weight: .black))
                        .buttonStyle(.borderless)
                        .disabled(isLoading || !canMoveNext)
                }

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }

                if let error {
                    Text(error)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Summary")
                        .font(.system(size: 14, weight: .heavy))
                    Divider()
                    if digest.digest.isEmpty {
                        EmptyState(text: "No summary available.")
                    } else {
                        Text(digest.digest.joined(separator: " "))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Divider()

                if digest.items.isEmpty {
                    EmptyState(text: "No papers found for this date.")
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            ForEach(digest.items.sorted(by: paperSort)) { item in
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack(spacing: 8) {
                                        Text(item.publishedAt?.formatted(date: .abbreviated, time: .shortened) ?? "--")
                                            .font(.system(size: 11, weight: .black))
                                            .foregroundStyle(.cyan)

                                        if let category = item.category, !category.isEmpty {
                                            Text(category)
                                                .font(.system(size: 10, weight: .black))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }

                                    Link(item.title, destination: item.externalURL ?? AppLinks.arxiv)
                                        .font(.system(size: 15, weight: .heavy))
                                        .foregroundStyle(.white)
                                        .lineLimit(3)
                                        .help("Open paper on arXiv")

                                    Text(authorLine(for: item))
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)

                                    Text(item.summary)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.primary.opacity(0.9))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
        }
    }

    private func paperSort(_ lhs: ArxivDigestItem, _ rhs: ArxivDigestItem) -> Bool {
        switch (lhs.publishedAt, rhs.publishedAt) {
        case let (left?, right?):
            return left < right
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return lhs.title < rhs.title
        }
    }

    private func authorLine(for item: ArxivDigestItem) -> String {
        if !item.authors.isEmpty {
            let institutions = item.authorInstitutions ?? []
            return item.authors.enumerated().map { index, author in
                let institution = index < institutions.count ? institutions[index] : ""
                guard !institution.isEmpty else {
                    return author
                }
                return "\(author) (\(institution))"
            }
            .joined(separator: ", ")
        }

        guard !item.firstAuthor.isEmpty else {
            return "arXiv"
        }

        if let institution = item.firstAuthorInstitution, !institution.isEmpty {
            return "\(item.firstAuthor) (\(institution))"
        }

        return item.firstAuthor
    }
}

struct Row: View {
    var title: String
    var subtitle: String
    var icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.cyan)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
    }
}

struct LinkedRow: View {
    var title: String
    var subtitle: String
    var icon: String
    var destination: URL?

    var body: some View {
        if let destination {
            Link(destination: destination) {
                Row(title: title, subtitle: subtitle, icon: icon)
            }
            .buttonStyle(.plain)
            .help(destination.absoluteString)
        } else {
            Row(title: title, subtitle: subtitle, icon: icon)
        }
    }
}

struct EmptyState: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
    }
}

struct DashboardLink: Identifiable {
    var id: String { "\(title)-\(url.absoluteString)" }
    var title: String
    var url: URL

    static let defaults: [DashboardLink] = []
}

private enum AppLinks {
    static let gmailInbox = URL(string: "https://mail.google.com/mail/u/0/#inbox")!
    static let arxiv = URL(string: "https://arxiv.org/list/cs.DB/recent")!

    static func yahooFinance(symbol: String) -> URL {
        let escaped = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? symbol
        return URL(string: "https://finance.yahoo.com/quote/\(escaped)")!
    }
}

private extension CalendarItem {
    var externalURL: URL? {
        url.flatMap { URL(string: $0) }
    }
}

private extension ArxivDigestItem {
    var externalURL: URL? {
        URL(string: url)
    }
}

struct Sparkline: View {
    var values: [Double]

    var body: some View {
        Canvas { context, size in
            guard values.count > 1,
                  let min = values.min(),
                  let max = values.max(),
                  max > min else {
                return
            }

            let points = values.enumerated().map { index, value in
                let x = size.width * CGFloat(index) / CGFloat(values.count - 1)
                let ratio = (value - min) / (max - min)
                let y = size.height - (size.height * CGFloat(ratio))
                return CGPoint(x: x, y: y)
            }

            var path = Path()
            path.move(to: points[0])
            for point in points.dropFirst() {
                path.addLine(to: point)
            }

            context.stroke(path, with: .color(.green), lineWidth: 2)
        }
    }
}
