import AppKit
import SwiftUI

struct CalendarView: View {
    @ObservedObject var store: CalendarStore
    @Environment(\.notchHeaderLayout) private var notchHeaderLayout
    @AppStorage(ThemeColor.preferenceKey) private var accentHex = ThemeColor.systemValue

    private var accent: Color { ThemeColor.color(accentHex) }
    private var selectedText: Color { ThemeColor.keyInk(accentHex) }
    private let muted = Color.white.opacity(0.58)
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private let weekdays = ["日", "一", "二", "三", "四", "五", "六"]
    var body: some View {
        let days = store.days
        let events = store.selectedEvents
        let layout = CalendarPanelLayout(weekCount: days.count / 7,
                            headerHeight: notchHeaderLayout.bandHeight,
                            hasCalendarAccess: store.authorization == .authorized,
                            allDayCount: events.filter(\.isAllDay).count,
                            timedEventCount: events.filter { !$0.isAllDay }.count,
                            maximumHeight: notchHeaderLayout.maximumPanelHeight)
        return VStack(alignment: .leading, spacing: 0) {
            header
                .frame(height: notchHeaderLayout.bandHeight)
            weekdayHeader
                .frame(height: CalendarPanelLayout.weekdayHeight)
                .padding(.top, CalendarPanelLayout.weekdayTopSpacing)
            calendarGrid(days, dayHeight: layout.dayHeight)
                .frame(height: layout.gridHeight)
                .padding(.top, CalendarPanelLayout.gridTopSpacing)
            if store.authorization == .authorized {
                agenda(events: events, layout: layout)
                    .padding(.top, CalendarPanelLayout.agendaTopSpacing)
            }
        }
        .padding(.horizontal, 38)
        .padding(.bottom, CalendarPanelLayout.bottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        GeometryReader { geometry in
            let sideWidth = max(0, (geometry.size.width - notchHeaderLayout.reservedWidth) / 2)
            HStack(alignment: .center, spacing: 0) {
                Text(store.monthTitle)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: sideWidth, alignment: .leading)
                Color.clear
                    .frame(width: notchHeaderLayout.reservedWidth, height: 1)
                    .accessibilityHidden(true)
                HStack(spacing: 9) {
                    circleButton("chevron.left", accessibility: "上个月") { store.moveMonth(-1) }
                    circleButton("chevron.right", accessibility: "下个月") { store.moveMonth(1) }
                }
                .frame(width: sideWidth, alignment: .trailing)
            }
            .frame(height: geometry.size.height)
        }
    }

    private func circleButton(_ symbol: String, accessibility: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.08), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(accessibility)
        .accessibilityLabel(accessibility)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(weekdays, id: \.self) { weekday in
                Text(weekday)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.78))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func calendarGrid(_ days: [CalendarDay?], dayHeight: CGFloat) -> some View {
        LazyVGrid(columns: columns, spacing: CalendarPanelLayout.gridSpacing) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                if let day {
                    dayCell(day, height: dayHeight)
                } else {
                    Color.clear.frame(height: dayHeight)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private func dayCell(_ day: CalendarDay, height: CGFloat) -> some View {
        let selected = Calendar.current.isDate(day.date, inSameDayAs: store.selectedDate)
        let dayEvents = store.events(on: day.date)
        return Button {
            store.select(day.date)
        } label: {
            VStack(spacing: 2) {
                Text("\(day.dayNumber)")
                    .font(.system(size: 16, weight: selected || day.isToday ? .semibold : .medium, design: .rounded))
                    .foregroundStyle(selected ? selectedText : .white)
                Text(day.lunarLabel)
                    .font(.system(size: 9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(selected ? selectedText.opacity(0.86) : muted)
                HStack(spacing: 3) {
                    ForEach(Array(dayEvents.prefix(3).enumerated()), id: \.offset) { _, event in
                        Circle().fill(Color(nsColor: event.color)).frame(width: 4, height: 4)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(accent)
                        .padding(.horizontal, 3)
                } else if day.isToday {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                        .padding(.horizontal, 3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(day.dayNumber)日，\(day.lunarLabel)，\(dayEvents.count)个日程")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private let eventTimeWidth: CGFloat = 58
    private let eventColumnSpacing: CGFloat = 10
    private let markerWidth: CGFloat = 8
    private let timedMarkerHeight: CGFloat = 32

    private func agenda(events: [CalendarEvent], layout: CalendarPanelLayout) -> some View {
        let allDayEvents = events.filter(\.isAllDay)
        let timedEvents = events.filter { !$0.isAllDay }
        return VStack(alignment: .leading, spacing: 0) {
            if events.isEmpty {
                emptyAgenda
                    .frame(maxWidth: .infinity)
                    .frame(height: layout.agendaContentHeight)
                    .clipped()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: CalendarPanelLayout.eventGroupSpacing) {
                        if !allDayEvents.isEmpty {
                            eventGroup(allDayEvents, isAllDay: true)
                        }
                        if !timedEvents.isEmpty {
                            eventGroup(timedEvents, isAllDay: false)
                        }
                    }
                }
                .scrollDisabled(!layout.agendaNeedsScrolling)
                .frame(height: layout.agendaContentHeight)
            }
        }
    }

    private var emptyAgenda: some View {
        ViewThatFits(in: .vertical) {
            VStack(spacing: 7) {
                emptyAgendaIcon
                emptyAgendaMessage
            }
            HStack(spacing: 8) {
                emptyAgendaIcon
                emptyAgendaMessage
            }
            emptyAgendaMessage
        }
    }

    private var emptyAgendaIcon: some View {
        ZStack {
            Circle()
                .fill(accent.opacity(0.18))
                .frame(width: 38, height: 38)
            Image(systemName: "calendar")
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(accent)
            Image(systemName: "sparkle")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(accent)
                .offset(x: 15, y: -14)
        }
        .frame(width: 46, height: 42)
        .accessibilityHidden(true)
    }

    private var emptyAgendaMessage: some View {
        Text("这天空空的，轻松一下～")
            .font(.system(size: 12))
            .foregroundStyle(muted)
    }

    private func eventGroup(_ events: [CalendarEvent], isAllDay: Bool) -> some View {
        VStack(alignment: .leading,
               spacing: isAllDay ? CalendarPanelLayout.allDaySpacing : CalendarPanelLayout.timedSpacing) {
            ForEach(events) { event in
                eventRow(event)
                    .frame(height: isAllDay ? CalendarPanelLayout.allDayRowHeight : CalendarPanelLayout.timedRowHeight)
            }
        }
        .padding(.horizontal, CalendarPanelLayout.eventGroupHorizontalPadding)
        .padding(.vertical, CalendarPanelLayout.eventGroupVerticalPadding)
        .background(alignment: .topLeading) {
            if !isAllDay && events.count > 1 {
                timedConnections(count: events.count)
                    .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            }
        }
        .background(Color(red: 0.105, green: 0.11, blue: 0.13),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.75)
                .allowsHitTesting(false)
        }
    }

    private func eventRow(_ event: CalendarEvent) -> some View {
        HStack(spacing: eventColumnSpacing) {
            VStack(alignment: .leading, spacing: 2) {
                if event.isAllDay {
                    Text("全天")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.76))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.8))
                } else {
                    if !Calendar.current.isDate(event.startDate, inSameDayAs: store.selectedDate) {
                        Text(event.startDate.formatted(.dateTime.month(.defaultDigits).day()))
                            .font(.system(size: 10))
                            .foregroundStyle(muted)
                    }
                    Text(time(event.startDate))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.72))
                }
            }
            .frame(width: eventTimeWidth, alignment: .leading)
            Capsule()
                .fill(Color(nsColor: event.color))
                .frame(width: markerWidth, height: event.isAllDay ? 24 : timedMarkerHeight)
                .shadow(color: Color(nsColor: event.color).opacity(0.55), radius: 6)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !event.isAllDay {
                    Text("至 " + endTime(event))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(muted)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .help(event.title)
        }
        .accessibilityElement(children: .combine)
    }

    private func timedConnections(count: Int) -> Path {
        let x = CalendarPanelLayout.eventGroupHorizontalPadding + eventTimeWidth + eventColumnSpacing + markerWidth / 2
        let firstCenter = CalendarPanelLayout.eventGroupVerticalPadding + CalendarPanelLayout.timedRowHeight / 2
        let step = CalendarPanelLayout.timedRowHeight + CalendarPanelLayout.timedSpacing
        return Path { path in
            for index in 0..<(count - 1) {
                let from = firstCenter + CGFloat(index) * step + timedMarkerHeight / 2
                let to = firstCenter + CGFloat(index + 1) * step - timedMarkerHeight / 2
                path.move(to: CGPoint(x: x, y: from))
                path.addCurve(to: CGPoint(x: x, y: to),
                              control1: CGPoint(x: x + 6, y: from + (to - from) * 0.45),
                              control2: CGPoint(x: x + 6, y: from + (to - from) * 0.55))
            }
        }
    }

    private func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func endTime(_ event: CalendarEvent) -> String {
        if Calendar.current.isDate(event.endDate, inSameDayAs: store.selectedDate) {
            return time(event.endDate)
        }
        return event.endDate.formatted(.dateTime.month(.defaultDigits).day()) + " " + time(event.endDate)
    }
}
