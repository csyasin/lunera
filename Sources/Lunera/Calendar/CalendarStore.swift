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
    let isInDisplayedMonth: Bool

    var id: Date { date }
}

struct CalendarEvent: Identifiable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let color: NSColor

    /// Total elapsed time, including any portion outside the selected day.
    var durationLabel: String {
        let seconds = endDate.timeIntervalSince(startDate)
        guard seconds > 0 else { return "0分钟" }
        guard seconds >= 60 else { return "不足1分钟" }
        let totalMinutes = Int(seconds / 60)
        let days = totalMinutes / (24 * 60)
        let hours = totalMinutes / 60 % 24
        let minutes = totalMinutes % 60
        var parts: [String] = []
        if days > 0 { parts.append("\(days)天") }
        if hours > 0 { parts.append("\(hours)小时") }
        if minutes > 0 { parts.append("\(minutes)分钟") }
        return parts.joined()
    }

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
                    Task { @MainActor [weak self] in
                        self?.refreshForEnvironmentChange(calendar: gregorianCalendar())
                    }
                }
                .store(in: &subscriptions)
        }
        refresh()
    }

    /// Complete Sunday-through-Saturday weeks surrounding the displayed month.
    var visibleGridInterval: DateInterval? {
        let calendar = gregorianCalendar()
        guard let month = calendar.dateInterval(of: .month, for: displayMonth),
              let monthDays = calendar.range(of: .day, in: .month, for: displayMonth) else { return nil }
        let leading = calendar.component(.weekday, from: month.start) - 1
        let dayCount = (leading + monthDays.count + 6) / 7 * 7
        guard let start = calendar.date(byAdding: .day, value: -leading, to: month.start),
              let end = calendar.date(byAdding: .day, value: dayCount, to: start) else { return nil }
        return DateInterval(start: start, end: end)
    }

    /// Retains the optional-cell API while filling every visible cell with a date.
    var days: [CalendarDay?] {
        let calendar = gregorianCalendar()
        guard let interval = visibleGridInterval,
              let dayCount = calendar.dateComponents([.day], from: interval.start, to: interval.end).day else { return [] }
        var result: [CalendarDay?] = []
        for offset in 0..<dayCount {
            guard let date = calendar.date(byAdding: .day, value: offset, to: interval.start) else { continue }
            result.append(CalendarDay(date: date,
                                      dayNumber: calendar.component(.day, from: date),
                                      lunarLabel: Self.lunarLabel(for: date),
                                      isToday: calendar.isDateInToday(date),
                                      isInDisplayedMonth: calendar.isDate(date, equalTo: displayMonth, toGranularity: .month)))
        }
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

    /// Keep the selected day's agenda available while browsing another month.
    /// Separate queries avoid fetching every event between distant dates.
    var eventQueryIntervals: [DateInterval] {
        let calendar = gregorianCalendar()
        guard let grid = visibleGridInterval else { return [] }
        if selectedDate >= grid.start && selectedDate < grid.end { return [grid] }
        guard let day = calendar.dateInterval(of: .day, for: selectedDate) else { return [grid] }
        return [grid, day]
    }

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
              let start = calendar.dateInterval(of: .month, for: target)?.start else { return }
        displayMonth = start
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
        guard authorization == .authorized else {
            events = []
            return
        }
        var seenIDs = Set<String>()
        events = eventQueryIntervals.flatMap { interval in
            let predicate = eventStore.predicateForEvents(withStart: interval.start, end: interval.end, calendars: nil)
            return eventStore.events(matching: predicate)
        }.compactMap { event -> CalendarEvent? in
            // A long event can overlap both the visible grid and selected day.
            let id = "\(event.calendarItemIdentifier)-\(event.startDate.timeIntervalSinceReferenceDate)"
            guard seenIDs.insert(id).inserted else { return nil }
            return CalendarEvent(
                id: id,
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

    func refreshForEnvironmentChange(calendar: Calendar) {
        if lastTimeZone != calendar.timeZone {
            var oldCalendar = calendar
            oldCalendar.timeZone = lastTimeZone
            let selectedCivilDate = oldCalendar.dateComponents([.era, .year, .month, .day], from: selectedDate)
            let displayedCivilDate = oldCalendar.dateComponents([.era, .year, .month, .day], from: displayMonth)
            selectedDate = calendar.date(from: selectedCivilDate) ?? selectedDate
            displayMonth = calendar.date(from: displayedCivilDate) ?? displayMonth
            lastTimeZone = calendar.timeZone
        }
        selectedDate = calendar.startOfDay(for: selectedDate)
        displayMonth = calendar.dateInterval(of: .month, for: displayMonth)?.start ?? displayMonth
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
