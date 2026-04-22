import Foundation
#if canImport(EventKit)
import EventKit
#endif

#if canImport(EventKit)
public final class EventKitAgendaProvider: CalendarProviding, ReminderProviding, @unchecked Sendable {
    private let eventStore: EKEventStore

    public init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    public func fetchCalendar() async -> CalendarSnapshot {
        do {
            guard try await ensureCalendarAccess() else {
                return .empty
            }

            let calendar = Calendar.current
            let now = Date()
            let todayInterval = calendar.dateInterval(of: .day, for: now)
            let start = todayInterval?.start ?? now
            let todayEnd = todayInterval?.end ?? now.addingTimeInterval(24 * 60 * 60)
            let upcomingEnd = calendar.date(byAdding: .day, value: 7, to: todayEnd) ?? todayEnd.addingTimeInterval(7 * 24 * 60 * 60)
            let predicate = eventStore.predicateForEvents(withStart: start, end: upcomingEnd, calendars: nil)

            let items = eventStore.events(matching: predicate)
                .sorted { $0.startDate < $1.startDate }
                .map(Self.calendarItem)

            return CalendarSnapshot(
                today: items.filter { $0.startDate < todayEnd },
                upcoming: items.filter { $0.startDate >= todayEnd },
                checkedAt: Date(),
                sourceUpdatedAt: nil,
                source: .eventKit,
                status: .ready
            )
        } catch {
            return .empty
        }
    }

    public func fetchReminders() async -> ReminderSnapshot {
        do {
            guard try await ensureReminderAccess() else {
                return .empty
            }

            let predicate = eventStore.predicateForIncompleteReminders(withDueDateStarting: nil, ending: dueSoonEndDate(), calendars: nil)
            let reminders = await fetchReminderItems(matching: predicate)
                .sorted { lhs, rhs in
                    switch (lhs.dueDate, rhs.dueDate) {
                    case let (lhsDate?, rhsDate?):
                        return lhsDate < rhsDate
                    case (_?, nil):
                        return true
                    case (nil, _?):
                        return false
                    case (nil, nil):
                        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                    }
                }

            return ReminderSnapshot(dueSoon: Array(reminders.prefix(8)))
        } catch {
            return .empty
        }
    }

    private func ensureCalendarAccess() async throws -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized:
            return true
        case .notDetermined:
            return try await eventStore.requestFullAccessToEvents()
        default:
            return false
        }
    }

    private func ensureReminderAccess() async throws -> Bool {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess, .authorized:
            return true
        case .notDetermined:
            return try await eventStore.requestFullAccessToReminders()
        default:
            return false
        }
    }

    private func fetchReminderItems(matching predicate: NSPredicate) async -> [ReminderItem] {
        await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).map(Self.reminderItem))
            }
        }
    }

    private func dueSoonEndDate() -> Date {
        Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date().addingTimeInterval(7 * 24 * 60 * 60)
    }

    private static func calendarItem(_ event: EKEvent) -> CalendarItem {
        CalendarItem(
            id: event.eventIdentifier ?? "\(event.title ?? "event")-\(event.startDate.timeIntervalSince1970)",
            title: event.title ?? "(No title)",
            startDate: event.startDate,
            endDate: event.endDate,
            calendarTitle: event.calendar?.title ?? "Calendar",
            isAllDay: event.isAllDay,
            url: nil
        )
    }

    private static func reminderItem(_ reminder: EKReminder) -> ReminderItem {
        ReminderItem(
            id: reminder.calendarItemIdentifier,
            title: reminder.title ?? "(No title)",
            dueDate: reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) },
            listTitle: reminder.calendar?.title ?? "Reminders"
        )
    }
}
#else
public struct EventKitAgendaProvider: CalendarProviding, ReminderProviding {
    public init() {}

    public func fetchCalendar() async -> CalendarSnapshot {
        .empty
    }

    public func fetchReminders() async -> ReminderSnapshot {
        .empty
    }
}
#endif
