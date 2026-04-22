import Foundation

public struct GmailAPIProvider: MailProviding {
    private let session: URLSession
    private let accessTokenProvider: @Sendable () async -> String?

    public init(
        session: URLSession = .shared,
        accessTokenProvider: @escaping @Sendable () async -> String? = { nil }
    ) {
        self.session = session
        self.accessTokenProvider = accessTokenProvider
    }

    public func fetchUnreadSummary(enabled: Bool) async -> MailSnapshot {
        guard enabled else {
            return .empty
        }

        guard let accessToken = await accessTokenProvider(), !accessToken.isEmpty else {
            return MailSnapshot(unreadCount: 0, messages: [], status: .unavailable("Connect Google to load Gmail."))
        }

        do {
            let unreadResponse = try await fetchMessageList(
                query: "in:inbox is:unread",
                maxResults: 5,
                accessToken: accessToken
            )
            let unreadCount = unreadResponse.resultSizeEstimate ?? unreadResponse.messages?.count ?? 0
            let messageIDs: [GmailMessageListResponse.Message]
            if let unreadMessages = unreadResponse.messages, !unreadMessages.isEmpty {
                messageIDs = unreadMessages
            } else {
                messageIDs = try await fetchMessageList(
                    query: "in:inbox",
                    maxResults: 3,
                    accessToken: accessToken
                ).messages ?? []
            }
            let messages = await fetchMessages(messageIDs, accessToken: accessToken)

            return MailSnapshot(
                unreadCount: unreadCount,
                messages: messages,
                status: .ready
            )
        } catch {
            return MailSnapshot(unreadCount: 0, messages: [], status: .unavailable(error.localizedDescription))
        }
    }

    private func fetchMessageList(
        query: String,
        maxResults: Int,
        accessToken: String
    ) async throws -> GmailMessageListResponse {
        var components = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "maxResults", value: String(maxResults))
        ]

        guard let url = components?.url else {
            throw DashboardHTTPError(statusCode: 0, body: "Invalid Gmail messages URL.")
        }

        return try await gmailRequest(GmailMessageListResponse.self, url: url, accessToken: accessToken)
    }

    private func fetchMessages(
        _ messageIDs: [GmailMessageListResponse.Message],
        accessToken: String
    ) async -> [MailItem] {
        await withTaskGroup(of: MailItem?.self) { group in
            for message in messageIDs {
                group.addTask {
                    await fetchMessage(id: message.id, accessToken: accessToken)
                }
            }

            var results: [MailItem] = []
            for await item in group {
                if let item {
                    results.append(item)
                }
            }
            return results.sorted { lhs, rhs in
                switch (lhs.receivedAt, rhs.receivedAt) {
                case let (lhsDate?, rhsDate?):
                    lhsDate > rhsDate
                case (_?, nil):
                    true
                case (nil, _?):
                    false
                case (nil, nil):
                    lhs.id < rhs.id
                }
            }
        }
    }

    private func fetchMessage(id: String, accessToken: String) async -> MailItem? {
        var components = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)")
        components?.queryItems = [
            URLQueryItem(name: "format", value: "metadata"),
            URLQueryItem(name: "metadataHeaders", value: "From"),
            URLQueryItem(name: "metadataHeaders", value: "Subject"),
            URLQueryItem(name: "metadataHeaders", value: "Date")
        ]

        guard let url = components?.url else {
            return nil
        }

        do {
            let response = try await gmailRequest(GmailMessageResponse.self, url: url, accessToken: accessToken)
            let headers = Dictionary(uniqueKeysWithValues: response.payload.headers.map { ($0.name.lowercased(), $0.value) })
            return MailItem(
                id: response.id,
                from: headers["from"] ?? "Unknown sender",
                subject: headers["subject"] ?? "(No subject)",
                snippet: response.snippet ?? "",
                receivedAt: headers["date"].flatMap(Self.parseMailDate)
            )
        } catch {
            return nil
        }
    }

    private func gmailRequest<T: Decodable>(_ type: T.Type, url: URL, accessToken: String) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw DashboardHTTPError(
                statusCode: httpResponse.statusCode,
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func parseMailDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, d MMM yyyy HH:mm:ss Z"
        return formatter.date(from: value)
    }
}

private struct GmailMessageListResponse: Decodable {
    var messages: [Message]?
    var resultSizeEstimate: Int?

    struct Message: Decodable {
        var id: String
    }
}

private struct GmailMessageResponse: Decodable {
    var id: String
    var snippet: String?
    var payload: Payload

    struct Payload: Decodable {
        var headers: [Header]
    }

    struct Header: Decodable {
        var name: String
        var value: String
    }
}
