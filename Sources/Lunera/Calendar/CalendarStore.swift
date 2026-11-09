import AppKit
import Combine
import EventKit
import Foundation

private func gregorianCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    calendar.locale = .current
    return calendar
}

struct CalendarDay: Identifiable {
    let date: Date
    let dayNumber: Int
    let lunarLabel: String
    let isToday: Bool

    var id: Date { date }
}

struct CalendarEvent: Identifiable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let color: NSColor

    func occurs(on date: Date, calendar: Calendar = gregorianCalendar()) -> Bool {
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return false }
        if endDate <= startDate { return startDate >= start && startDate < end }
        return startDate < end && endDate > start
    }
}

enum CalendarAuthorization: Equatable {
    case notDetermined
    case denied
    case restricted
    case writeOnly
    case authorized
    case unknown
}

/// Owns the visible month and the read-only system calendar connection.
@MainActor
final class CalendarStore: ObservableObject {
    @Published private(set) var displayMonth: Date
    @Published private(set) var selectedDate: Date
    @Published private(set) var authorization: CalendarAuthorization = .notDetermined
    @Published private(set) var events: [CalendarEvent] = []
    @Published private(set) var authorizationError: String?

    private let eventStore = EKEventStore()
    private var subscriptions = Set<AnyCancellable>()
    private var lastTimeZone = TimeZone.current
    private var isRequestingCalendarAccess = false

    init(now: Date = Date()) {
        let calendar = gregorianCalendar()
        let today = calendar.startOfDay(for: now)
        self.selectedDate = today
        self.displayMonth = calendar.dateInterval(of: .month, for: today)?.start ?? today

        NotificationCenter.default.publisher(for: .EKEventStoreChanged, object: eventStore)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh() }
            }
            .store(in: &subscriptions)

        NotificationCenter.default.publisher(for: NSColor.systemColorsDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.objectWillChange.send() }
            }
            .store(in: &subscriptions)

        for name in [NSApplication.didBecomeActiveNotification,
                     NSNotification.Name.NSSystemTimeZoneDidChange,
                     NSNotification.Name.NSCalendarDayChanged] {
            NotificationCenter.default.publisher(for: name)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    Task { @MainActor [weak self] in self?.refreshForEnvironmentChange() }
                }
                .store(in: &subscriptions)
        }
        refresh()
    }

    /// A Sunday-first month grid with empty cells outside the visible month.
    var days: [CalendarDay?] {
        let calendar = gregorianCalendar()
        guard let interval = calendar.dateInterval(of: .month, for: displayMonth),
              let dayRange = calendar.range(of: .day, in: .month, for: displayMonth) else { return [] }
        let leading = calendar.component(.weekday, from: interval.start) - 1
        var result: [CalendarDay?] = Array(repeating: nil, count: leading)
        for offset in 0..<dayRange.count {
            guard let date = calendar.date(byAdding: .day, value: offset, to: interval.start) else { continue }
            result.append(CalendarDay(date: date,
                                      dayNumber: calendar.component(.day, from: date),
                                      lunarLabel: Self.lunarLabel(for: date),
                                      isToday: calendar.isDateInToday(date)))
        }
        let trailing = (7 - result.count % 7) % 7
        result.append(contentsOf: Array(repeating: nil, count: trailing))
        return result
    }

    var monthTitle: String {
        let formatter = DateFormatter()
        formatter.calendar = gregorianCalendar()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月 yyyy"
        return formatter.string(from: displayMonth)
    }

    var selectedLunarTitle: String { "农历" + Self.lunarLabel(for: selectedDate) }
    var selectedEvents: [CalendarEvent] { events(on: selectedDate) }

    func events(on date: Date) -> [CalendarEvent] {
        events.filter { $0.occurs(on: date) }
    }

    func select(_ date: Date) {
        let calendar = gregorianCalendar()
        let day = calendar.startOfDay(for: date)
        selectedDate = day
        if !calendar.isDate(day, equalTo: displayMonth, toGranularity: .month) {
            displayMonth = calendar.dateInterval(of: .month, for: day)?.start ?? day
            refresh()
        }
    }

    func moveMonth(_ offset: Int) {
        let calendar = gregorianCalendar()
        guard let target = calendar.date(byAdding: .month, value: offset, to: displayMonth),
              let start = calendar.dateInterval(of: .month, for: target)?.start,
              let range = calendar.range(of: .day, in: .month, for: start) else { return }
        let selectedDay = min(calendar.component(.day, from: selectedDate), range.count)
        displayMonth = start
        selectedDate = calendar.date(byAdding: .day, value: selectedDay - 1, to: start) ?? start
        refresh()
    }

    func goToToday() {
        let calendar = gregorianCalendar()
        let today = calendar.startOfDay(for: Date())
        selectedDate = today
        displayMonth = calendar.dateInterval(of: .month, for: today)?.start ?? today
        refresh()
    }

    /// Called at startup. macOS owns the prompt; an existing denial is respected.
    func requestCalendarAccessIfNeeded() async {
        guard !isRequestingCalendarAccess else { return }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined, .writeOnly:
            break
        default:
            refresh()
            return
        }

        isRequestingCalendarAccess = true
        defer { isRequestingCalendarAccess = false }
        authorizationError = nil
        do {
            if try await eventStore.requestFullAccessToEvents() {
                // Discard any cached store state from before full access was granted.
                eventStore.reset()
            }
            refresh()
        } catch {
            authorizationError = error.localizedDescription
            refresh()
        }
    }

    /// Rechecks permission as well as data; EventKit may have changed outside the app.
    func refresh() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: authorization = .notDetermined
        case .restricted: authorization = .restricted
        case .denied: authorization = .denied
        case .fullAccess: authorization = .authorized
        case .writeOnly: authorization = .writeOnly
        @unknown default: authorization = .unknown
        }
        if authorization == .authorized { authorizationError = nil }
        guard authorization == .authorized,
              let interval = gregorianCalendar().dateInterval(of: .month, for: displayMonth) else {
            events = []
            return
        }
        let predicate = eventStore.predicateForEvents(withStart: interval.start, end: interval.end, calendars: nil)
        events = eventStore.events(matching: predicate).map { event in
            CalendarEvent(
                id: "\(event.calendarItemIdentifier)-\(event.startDate.timeIntervalSinceReferenceDate)",
                title: event.title?.isEmpty == false ? event.title : "（无标题）",
                startDate: event.startDate,
                endDate: event.endDate,
                isAllDay: event.isAllDay,
                color: NSColor(cgColor: event.calendar.cgColor) ?? .controlAccentColor
            )
        }.sorted {
            if $0.isAllDay != $1.isAllDay { return $0.isAllDay }
            return $0.startDate < $1.startDate
        }
    }

    private func refreshForEnvironmentChange() {
        let calendar = gregorianCalendar()
        if lastTimeZone != calendar.timeZone {
            var oldCalendar = calendar
            oldCalendar.timeZone = lastTimeZone
            let civilDate = oldCalendar.dateComponents([.era, .year, .month, .day], from: selectedDate)
            selectedDate = calendar.date(from: civilDate) ?? selectedDate
            lastTimeZone = calendar.timeZone
        }
        selectedDate = calendar.startOfDay(for: selectedDate)
        displayMonth = calendar.dateInterval(of: .month, for: selectedDate)?.start ?? selectedDate
        refresh()
    }

    private static func lunarLabel(for date: Date) -> String {
        var lunar = Calendar(identifier: .chinese)
        lunar.timeZone = .current
        let components = lunar.dateComponents([.month, .day, .isLeapMonth], from: date)
        let months = ["正月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "冬月", "腊月"]
        let days = ["初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
                    "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
                    "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"]
        guard let month = components.month, months.indices.contains(month - 1),
              let day = components.day, days.indices.contains(day - 1) else { return "" }
        return (components.isLeapMonth == true ? "闰" : "") + months[month - 1] + days[day - 1]
    }
}
