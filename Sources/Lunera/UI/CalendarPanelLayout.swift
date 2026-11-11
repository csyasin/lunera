import Foundation

/// Shared dimensions keep the native window and SwiftUI content in agreement.
struct CalendarPanelLayout {
    // One visible inset governs header controls, date fills and the agenda.
    // The panel's curved top moves its straight sides inward by this radius.
    static let visualSpacing: CGFloat = 24
    static let panelTopCornerRadius: CGFloat = 12
    static let dayHighlightHorizontalInset: CGFloat = 3
    static let contentHorizontalPadding = panelTopCornerRadius + visualSpacing
    static let gridHorizontalPadding = contentHorizontalPadding - dayHighlightHorizontalInset
    static let agendaSideInset = visualSpacing
    static let bottomPadding = visualSpacing
    static let eventGroupCornerRadius: CGFloat = 10
    static let agendaHorizontalOutset = contentHorizontalPadding - panelTopCornerRadius - agendaSideInset
    static let panelBottomCornerRadius = eventGroupCornerRadius + bottomPadding
    static let weekdayTopSpacing: CGFloat = 14
    static let weekdayHeight: CGFloat = 18
    static let gridOverflowPadding: CGFloat = 12
    static let gridTopSpacing = gridOverflowPadding
    static let gridSpacing: CGFloat = 2
    static let agendaTopSpacing = visualSpacing
    static let agendaDividerHeight: CGFloat = 1
    static let agendaDividerSpacing: CGFloat = 12
    static let occupiedAgendaHeaderHeight = agendaDividerHeight + agendaDividerSpacing
    static let allDayRowHeight: CGFloat = 32
    static let allDaySpacing: CGFloat = 4
    static let timedRowHeight: CGFloat = 52
    static let timedSpacing: CGFloat = 4
    static let eventGroupSpacing: CGFloat = 16
    static let eventGroupHorizontalPadding: CGFloat = 10
    static let emptyAgendaHeight: CGFloat = 108

    let weekCount: Int
    let headerHeight: CGFloat
    let hasCalendarAccess: Bool
    let allDayCount: Int
    let timedEventCount: Int
    let maximumHeight: CGFloat

    static func dayHeight(forWeekCount weekCount: Int) -> CGFloat { weekCount > 5 ? 46 : 52 }
    var dayHeight: CGFloat { Self.dayHeight(forWeekCount: weekCount) }
    var gridHeight: CGFloat {
        CGFloat(weekCount) * dayHeight + CGFloat(max(0, weekCount - 1)) * Self.gridSpacing
    }
    var calendarHeight: CGFloat {
        headerHeight + Self.weekdayTopSpacing + Self.weekdayHeight + Self.gridTopSpacing + gridHeight
    }
    var naturalAgendaContentHeight: CGFloat {
        guard hasCalendarAccess else { return 0 }
        guard allDayCount + timedEventCount > 0 else { return Self.emptyAgendaHeight }
        let allDayHeight = allDayCount > 0 ? CGFloat(allDayCount) * Self.allDayRowHeight
            + CGFloat(allDayCount - 1) * Self.allDaySpacing : 0
        let timedHeight = timedEventCount > 0 ? CGFloat(timedEventCount) * Self.timedRowHeight
            + CGFloat(timedEventCount - 1) * Self.timedSpacing : 0
        let groupSpacing = allDayCount > 0 && timedEventCount > 0 ? Self.eventGroupSpacing : 0
        return Self.occupiedAgendaHeaderHeight + allDayHeight + timedHeight + groupSpacing
    }
    var preferredHeight: CGFloat {
        calendarHeight + Self.bottomPadding
        + (hasCalendarAccess ? Self.agendaTopSpacing + naturalAgendaContentHeight : 0)
    }
    var height: CGFloat { min(preferredHeight, maximumHeight) }
    var agendaContentHeight: CGFloat {
        guard hasCalendarAccess else { return 0 }
        return max(0, min(naturalAgendaContentHeight,
                          height - calendarHeight - Self.bottomPadding - Self.agendaTopSpacing))
    }
    var agendaScrollHeight: CGFloat {
        guard allDayCount + timedEventCount > 0 else { return agendaContentHeight }
        return max(0, agendaContentHeight - Self.occupiedAgendaHeaderHeight)
    }
    var agendaNeedsScrolling: Bool { naturalAgendaContentHeight > agendaContentHeight }
}
