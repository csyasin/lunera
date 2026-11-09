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
        store.moveMonth(1)
        precondition(gregorian.component(.day, from: store.selectedDate) == 29)
        precondition(gregorian.component(.month, from: store.selectedDate) == 2)
        let crossing = CalendarEvent(id: "cross", title: "Crossing midnight",
                                     startDate: gregorian.date(from: DateComponents(year: 2024, month: 2, day: 10, hour: 23))!,
                                     endDate: gregorian.date(from: DateComponents(year: 2024, month: 2, day: 11, hour: 1))!,
                                     isAllDay: false, color: .systemPurple)
        precondition(crossing.occurs(on: date(2024, 2, 10)))
        precondition(crossing.occurs(on: date(2024, 2, 11)))
        precondition(!crossing.occurs(on: date(2024, 2, 12)))
        let midnightEnd = CalendarEvent(id: "midnight", title: "Ends at midnight",
                                        startDate: date(2024, 2, 10),
                                        endDate: gregorian.startOfDay(for: date(2024, 2, 11)),
                                        isAllDay: false, color: .systemPurple)
        precondition(!midnightEnd.occurs(on: date(2024, 2, 11)))
        print("Calendar grid, lunar dates, leap month, navigation and cross-day events passed")
    }
}
