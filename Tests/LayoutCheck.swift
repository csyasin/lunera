import Foundation

@main
struct LayoutCheck {
    static func main() {
        let sideInset = CalendarPanelLayout.contentHorizontalPadding
            - CalendarPanelLayout.agendaHorizontalOutset - CalendarPanelLayout.panelTopCornerRadius
        precondition(sideInset == CalendarPanelLayout.bottomPadding)
        precondition(CalendarPanelLayout.panelBottomCornerRadius
                     == CalendarPanelLayout.eventGroupCornerRadius + CalendarPanelLayout.bottomPadding)
        func layout(access: Bool = true, allDay: Int = 0, timed: Int = 0,
                    weeks: Int = 5, maximum: CGFloat = 900) -> CalendarPanelLayout {
            CalendarPanelLayout(weekCount: weeks, headerHeight: 38,
                                hasCalendarAccess: access, allDayCount: allDay,
                                timedEventCount: timed, maximumHeight: maximum)
        }
        let denied = layout(access: false)
        precondition(denied.agendaContentHeight == 0)
        precondition(denied.agendaScrollHeight == 0)
        precondition(denied.height == layout(access: false, allDay: 10, timed: 20).height)
        let empty = layout()
        precondition(empty.height > denied.height)
        precondition(empty.height == empty.calendarHeight + CalendarPanelLayout.agendaTopSpacing
                     + CalendarPanelLayout.emptyAgendaHeight + CalendarPanelLayout.bottomPadding)
        precondition(empty.agendaContentHeight == CalendarPanelLayout.emptyAgendaHeight)
        precondition(empty.agendaScrollHeight == CalendarPanelLayout.emptyAgendaHeight)
        precondition(!empty.agendaNeedsScrolling)
        let constrainedEmpty = layout(maximum: empty.calendarHeight + CalendarPanelLayout.bottomPadding
                                      + CalendarPanelLayout.agendaTopSpacing + 45)
        precondition(constrainedEmpty.agendaContentHeight == 45)
        precondition(constrainedEmpty.agendaScrollHeight == 45)
        precondition(constrainedEmpty.height == constrainedEmpty.maximumHeight)
        let oneAllDay = layout(allDay: 1)
        let twoAllDay = layout(allDay: 2)
        let oneTimed = layout(timed: 1)
        let twoTimed = layout(timed: 2)
        let mixed = layout(allDay: 2, timed: 2)
        precondition(mixed.height == mixed.calendarHeight + CalendarPanelLayout.agendaTopSpacing
                     + mixed.naturalAgendaContentHeight + CalendarPanelLayout.bottomPadding)
        precondition(oneAllDay.agendaScrollHeight == 32)
        precondition(twoAllDay.agendaScrollHeight == 68)
        precondition(oneTimed.agendaScrollHeight == 52)
        precondition(twoTimed.agendaScrollHeight == 108)
        precondition(oneAllDay.naturalAgendaContentHeight == 45)
        precondition(twoAllDay.naturalAgendaContentHeight == 81)
        precondition(oneTimed.naturalAgendaContentHeight == 65)
        precondition(twoTimed.naturalAgendaContentHeight == 121)
        precondition(mixed.naturalAgendaContentHeight == 205)
        precondition(mixed.agendaScrollHeight == 192)
        precondition(oneAllDay.height < twoAllDay.height && oneTimed.height < twoTimed.height)
        precondition(!mixed.agendaNeedsScrolling)
        let constrainedMixed = layout(allDay: 2, timed: 2,
                                      maximum: mixed.calendarHeight + CalendarPanelLayout.bottomPadding
                                      + CalendarPanelLayout.agendaTopSpacing + 80)
        precondition(constrainedMixed.agendaContentHeight == 80)
        precondition(constrainedMixed.agendaScrollHeight == 67)
        precondition(constrainedMixed.agendaNeedsScrolling)
        let dividerOnly = layout(timed: 1,
                                 maximum: oneTimed.calendarHeight + CalendarPanelLayout.bottomPadding
                                 + CalendarPanelLayout.agendaTopSpacing + 8)
        precondition(dividerOnly.agendaContentHeight == 8)
        precondition(dividerOnly.agendaScrollHeight == 0)
        precondition(dividerOnly.agendaNeedsScrolling)
        for weeks in 4...6 {
            let crowded = layout(allDay: 20, timed: 80, weeks: weeks, maximum: 700)
            precondition(crowded.height == 700)
            precondition(crowded.agendaNeedsScrolling)
            precondition(crowded.agendaContentHeight > 0)
            precondition(crowded.agendaScrollHeight > 0)
            precondition(crowded.agendaContentHeight - crowded.agendaScrollHeight
                         == CalendarPanelLayout.occupiedAgendaHeaderHeight)
            precondition(crowded.calendarHeight + CalendarPanelLayout.bottomPadding < crowded.height)
        }
        precondition(layout(timed: 1, weeks: 6).height > oneTimed.height)
        print("A2 agenda divider, all-day/timed heights, scroll budget, unchanged empty state and screen-height cap passed")
    }
}
