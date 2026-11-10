import AppKit
import Foundation

@main
struct Check {
    @MainActor static func main() {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = .current
        func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
            gregorian.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
        }
        let store = CalendarStore(now: date(2024, 2, 10))
        precondition(store.days.count == 35)
        precondition(store.days.prefix(4).allSatisfy { $0 == nil })
        precondition(store.days.compactMap { $0 }.count == 29)
        precondition(store.selectedLunarTitle == "农历正月初一", store.selectedLunarTitle)
        store.select(date(2023, 3, 22))
        precondition(store.selectedLunarTitle == "农历闰二月初一", store.selectedLunarTitle)
        store.select(date(2024, 1, 31))
        let januarySelection = store.selectedDate
        store.moveMonth(1)
        precondition(store.selectedDate == januarySelection)
        precondition(store.displayMonth == gregorian.startOfDay(for: date(2024, 2, 1)))
        precondition(store.days.compactMap { $0 }.count == 29)
        precondition(!store.days.compactMap { $0 }.contains { gregorian.isDate($0.date, inSameDayAs: store.selectedDate) })
        precondition(store.eventQueryIntervals == [gregorian.dateInterval(of: .month, for: date(2024, 2, 1))!,
                                                   gregorian.dateInterval(of: .day, for: januarySelection)!])

        // Paging years away must retain the agenda without querying all intervening months.
        store.moveMonth(60)
        precondition(store.selectedDate == januarySelection)
        precondition(store.displayMonth == gregorian.startOfDay(for: date(2029, 2, 1)))
        precondition(store.eventQueryIntervals.count == 2)
        precondition(store.eventQueryIntervals.allSatisfy { $0.duration <= 32 * 24 * 60 * 60 })
        precondition(store.eventQueryIntervals[1] == gregorian.dateInterval(of: .day, for: januarySelection))
        store.moveMonth(-61)
        precondition(store.selectedDate == januarySelection)
        precondition(store.displayMonth == gregorian.startOfDay(for: date(2024, 1, 1)))
        precondition(store.eventQueryIntervals == [gregorian.dateInterval(of: .month, for: januarySelection)!])

        store.select(date(2024, 12, 31))
        let decemberSelection = store.selectedDate
        store.moveMonth(1)
        precondition(store.displayMonth == gregorian.startOfDay(for: date(2025, 1, 1)))
        precondition(store.selectedDate == decemberSelection)
        store.select(date(2025, 1, 4))
        precondition(store.selectedDate == gregorian.startOfDay(for: date(2025, 1, 4)))
        precondition(store.eventQueryIntervals.count == 1)

        store.select(date(2024, 2, 29))
        let leapSelection = store.selectedDate
        store.moveMonth(12)
        precondition(store.selectedDate == leapSelection)
        precondition(store.days.compactMap { $0 }.count == 28)

        // Activation and time-zone changes preserve browsing and selection independently.
        store.select(date(2024, 1, 31))
        store.moveMonth(1)
        let browsingMonth = store.displayMonth
        store.refreshForEnvironmentChange(calendar: gregorian)
        precondition(store.selectedDate == januarySelection)
        precondition(store.displayMonth == browsingMonth)
        var westernCalendar = gregorian
        westernCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        store.refreshForEnvironmentChange(calendar: westernCalendar)
        precondition(westernCalendar.dateComponents([.year, .month, .day], from: store.selectedDate)
                     == DateComponents(year: 2024, month: 1, day: 31))
        precondition(westernCalendar.dateComponents([.year, .month, .day], from: store.displayMonth)
                     == DateComponents(year: 2024, month: 2, day: 1))
        store.refreshForEnvironmentChange(calendar: gregorian)
        precondition(store.selectedDate == januarySelection)
        precondition(store.displayMonth == browsingMonth)

        let todayBefore = gregorian.startOfDay(for: Date())
        store.goToToday()
        let todayAfter = gregorian.startOfDay(for: Date())
        precondition([todayBefore, todayAfter].contains(store.selectedDate))
        precondition(store.displayMonth == gregorian.dateInterval(of: .month, for: store.selectedDate)?.start)
        precondition(store.eventQueryIntervals.count == 1)
        let crossing = CalendarEvent(id: "cross", title: "Crossing midnight",
                                     startDate: gregorian.date(from: DateComponents(year: 2024, month: 2, day: 10, hour: 23))!,
                                     endDate: gregorian.date(from: DateComponents(year: 2024, month: 2, day: 11, hour: 1))!,
                                     isAllDay: false, color: .systemPurple)
        precondition(crossing.occurs(on: date(2024, 2, 10)))
        precondition(crossing.occurs(on: date(2024, 2, 11)))
        precondition(!crossing.occurs(on: date(2024, 2, 12)))
        precondition(crossing.durationLabel == "2小时")
        let midnightEnd = CalendarEvent(id: "midnight", title: "Ends at midnight",
                                        startDate: date(2024, 2, 10),
                                        endDate: gregorian.startOfDay(for: date(2024, 2, 11)),
                                        isAllDay: false, color: .systemPurple)
        precondition(!midnightEnd.occurs(on: date(2024, 2, 11)))
        func durationLabel(seconds: TimeInterval) -> String {
            let start = date(2024, 2, 10)
            return CalendarEvent(id: "duration", title: "Duration",
                                 startDate: start, endDate: start.addingTimeInterval(seconds),
                                 isAllDay: false, color: .systemPurple).durationLabel
        }
        precondition(durationLabel(seconds: 45 * 60) == "45分钟")
        precondition(durationLabel(seconds: 60 * 60) == "1小时")
        precondition(durationLabel(seconds: 90 * 60 + 59) == "1小时30分钟")
        precondition(durationLabel(seconds: 24 * 60 * 60) == "1天")
        precondition(durationLabel(seconds: (24 * 60 + 2 * 60 + 15) * 60) == "1天2小时15分钟")
        precondition(durationLabel(seconds: 30) == "不足1分钟")
        precondition(durationLabel(seconds: 0) == "0分钟")
        precondition(durationLabel(seconds: -60) == "0分钟")
        print("Calendar grid, lunar dates, independent month navigation, agenda query coverage, time zones, today, cross-day events and elapsed durations passed")
    }
}
