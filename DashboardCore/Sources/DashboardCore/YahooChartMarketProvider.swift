import Foundation

public struct YahooChartMarketProvider: MarketProviding {
    private let session: URLSession
    private static let cache = YahooMarketCache()

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchQuotes(symbols: [String]) async -> MarketSnapshot {
        let now = Date()
        if let cached = await Self.cache.cachedSnapshot(for: symbols, now: now) {
            return cached
        }

        var quotes: [MarketQuote] = []
        for symbol in symbols {
            if let quote = await fetchQuote(symbol: symbol) {
                quotes.append(quote)
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        quotes.sort { $0.symbol < $1.symbol }

        let snapshot = MarketSnapshot(
            quotes: quotes,
            checkedAt: now,
            status: quotes.isEmpty ? .unavailable("No quotes returned from Yahoo chart endpoint.") : .ready
        )
        return await Self.cache.record(snapshot: snapshot, symbols: symbols, now: now)
    }

    private func fetchQuote(symbol: String) async -> MarketQuote? {
        let encodedSymbol = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? symbol
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encodedSymbol)?range=1d&interval=5m") else {
            return nil
        }

        do {
            var request = URLRequest(url: url)
            request.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                forHTTPHeaderField: "User-Agent"
            )
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, urlResponse) = try await session.data(for: request)
            guard let httpResponse = urlResponse as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                return nil
            }

            let chartResponse = try JSONDecoder().decode(YahooChartResponse.self, from: data)
            guard let result = chartResponse.chart.result?.first else {
                return nil
            }

            let meta = result.meta
            let closes = result.indicators.quote.first?.close.compactMap { $0 } ?? []
            let price = meta.regularMarketPrice ?? closes.last
            let previousClose = meta.previousClose
            let change = price.flatMap { price in previousClose.map { price - $0 } }
            let changePercent = change.flatMap { change in previousClose.map { (change / $0) * 100 } }

            return MarketQuote(
                symbol: meta.symbol ?? symbol,
                name: meta.longName ?? meta.shortName ?? symbol,
                price: price,
                change: change,
                changePercent: changePercent,
                sparkline: Array(closes.suffix(24)),
                updatedAt: meta.regularMarketTime.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            )
        } catch {
            return nil
        }
    }
}

private actor YahooMarketCache {
    private let minimumFetchInterval: TimeInterval = 5 * 60
    private var lastAttemptAt: Date?
    private var lastSymbols: [String] = []
    private var lastSuccessfulSnapshot: MarketSnapshot?

    func cachedSnapshot(for symbols: [String], now: Date) -> MarketSnapshot? {
        guard let lastAttemptAt,
              Set(lastSymbols) == Set(symbols),
              now.timeIntervalSince(lastAttemptAt) < minimumFetchInterval else {
            return nil
        }

        return lastSuccessfulSnapshot
    }

    func record(snapshot: MarketSnapshot, symbols: [String], now: Date) -> MarketSnapshot {
        lastAttemptAt = now
        lastSymbols = symbols

        if !snapshot.quotes.isEmpty {
            lastSuccessfulSnapshot = snapshot
            return snapshot
        }

        if var cached = lastSuccessfulSnapshot {
            cached.checkedAt = snapshot.checkedAt
            cached.status = snapshot.status
            return cached
        }

        return snapshot
    }
}

private struct YahooChartResponse: Decodable {
    var chart: Chart

    struct Chart: Decodable {
        var result: [Result]?
    }

    struct Result: Decodable {
        var meta: Meta
        var indicators: Indicators
    }

    struct Meta: Decodable {
        var symbol: String?
        var shortName: String?
        var longName: String?
        var regularMarketPrice: Double?
        var regularMarketTime: Int?
        var previousClose: Double?
    }

    struct Indicators: Decodable {
        var quote: [Quote]
    }

    struct Quote: Decodable {
        var close: [Double?]
    }
}
