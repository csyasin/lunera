import AppKit
import QuartzCore
import SwiftUI

private enum CalendarSelectionAnimation {
    static let duration: TimeInterval = 0.20
}

struct CalendarView: View {
    @ObservedObject var store: CalendarStore
    @Environment(\.notchHeaderLayout) private var notchHeaderLayout
    @Environment(\.calendarPresentationID) private var presentationID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                    .padding(.horizontal, -CalendarPanelLayout.agendaHorizontalOutset)
                    .padding(.top, CalendarPanelLayout.agendaTopSpacing)
            }
        }
        .padding(.horizontal, CalendarPanelLayout.contentHorizontalPadding)
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
                        .id(day.id)
                } else {
                    Color.clear.frame(height: dayHeight)
                        .accessibilityHidden(true)
                }
            }
        }
        .overlay {
            GeometryReader { geometry in
                let index = days.firstIndex(where: { day in
                    day.map { Calendar.current.isDate($0.date, inSameDayAs: store.selectedDate) } ?? false
                })
                let cellWidth = geometry.size.width / 7
                CalendarSelectionHighlight(
                    selection: store.selectedDate,
                    displayMonth: store.displayMonth,
                    target: index.map {
                        CGRect(x: CGFloat($0 % 7) * cellWidth + 3,
                               y: CGFloat($0 / 7) * (dayHeight + CalendarPanelLayout.gridSpacing),
                               width: max(0, cellWidth - 6), height: dayHeight)
                    },
                    content: AnyView(selectionContent(days, dayHeight: dayHeight)),
                    reduceMotion: reduceMotion,
                    presentationID: presentationID
                )
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func selectionContent(_ days: [CalendarDay?], dayHeight: CGFloat) -> some View {
        LazyVGrid(columns: columns, spacing: CalendarPanelLayout.gridSpacing) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                if let day {
                    dayContent(day, events: store.events(on: day.date), height: dayHeight, highlighted: true)
                        .id(day.id)
                } else {
                    Color.clear.frame(height: dayHeight)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(accent)
        .preferredColorScheme(.dark)
    }

    private func dayCell(_ day: CalendarDay, height: CGFloat) -> some View {
        let selected = Calendar.current.isDate(day.date, inSameDayAs: store.selectedDate)
        let dayEvents = store.events(on: day.date)
        return Button {
            store.select(day.date)
        } label: {
            dayContent(day, events: dayEvents, height: height, highlighted: false)
                .background {
                    if day.isToday && !selected {
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

    private func dayContent(_ day: CalendarDay, events: [CalendarEvent], height: CGFloat,
                            highlighted: Bool) -> some View {
        let selected = Calendar.current.isDate(day.date, inSameDayAs: store.selectedDate)
        return VStack(spacing: 2) {
            Text("\(day.dayNumber)")
                .font(.system(size: 16, weight: selected || day.isToday ? .semibold : .medium, design: .rounded))
                .foregroundStyle(highlighted ? selectedText : .white)
            Text(day.lunarLabel)
                .font(.system(size: 9))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(highlighted ? selectedText.opacity(0.86) : muted)
            HStack(spacing: 3) {
                ForEach(Array(events.prefix(3).enumerated()), id: \.offset) { _, event in
                    Circle().fill(Color(nsColor: event.color)).frame(width: 4, height: 4)
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }

    private let eventTimeWidth: CGFloat = 58
    private let eventColumnSpacing: CGFloat = 12
    private let markerWidth: CGFloat = 8
    private let timedRowTopPadding: CGFloat = 8
    private let timedMarkerLineHeight: CGFloat = 18

    private func agenda(events: [CalendarEvent], layout: CalendarPanelLayout) -> some View {
        let allDayEvents = events.filter(\.isAllDay)
        let timedEvents = events.filter { !$0.isAllDay }
        return VStack(alignment: .leading, spacing: 0) {
            if events.isEmpty {
                emptyAgenda
                    .frame(maxWidth: .infinity)
                    .frame(height: layout.agendaContentHeight)
                    .overlay {
                        RoundedRectangle(cornerRadius: CalendarPanelLayout.eventGroupCornerRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.22),
                                          style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    .clipped()
            } else {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.white.opacity(0.14))
                        .frame(height: CalendarPanelLayout.agendaDividerHeight)
                        .padding(.bottom, CalendarPanelLayout.agendaDividerSpacing)
                        .accessibilityHidden(true)
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
                    .frame(height: layout.agendaScrollHeight)
                }
                .frame(height: layout.agendaContentHeight, alignment: .top)
                .clipped()
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
                .fill(accent.opacity(0.08))
                .frame(width: 37, height: 37)
            Circle()
                .strokeBorder(accent.opacity(0.2), lineWidth: 0.8)
                .frame(width: 37, height: 37)
            Ellipse()
                .stroke(accent.opacity(0.35), lineWidth: 0.9)
                .frame(width: 54, height: 22)
                .rotationEffect(.degrees(-25))
            EmptyAgendaMoon()
                .fill(LinearGradient(colors: [accent, accent.opacity(0.68)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 22, height: 28)
                .offset(x: -2)
            EmptyAgendaStar()
                .fill(accent)
                .frame(width: 8, height: 8)
                .offset(x: 21, y: -16)
            Circle()
                .fill(accent.opacity(0.65))
                .frame(width: 3, height: 3)
                .offset(x: -21, y: 14)
        }
        .frame(width: 60, height: 50)
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
                if isAllDay {
                    allDayEventRow(event)
                        .frame(height: CalendarPanelLayout.allDayRowHeight)
                } else {
                    timedEventRow(event)
                        .frame(height: CalendarPanelLayout.timedRowHeight)
                }
            }
        }
        .background(alignment: .topLeading) {
            if !isAllDay && !events.isEmpty {
                timelineRail(count: events.count)
                    .stroke(Color.white.opacity(0.2), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, CalendarPanelLayout.eventGroupHorizontalPadding)
    }

    private func allDayEventRow(_ event: CalendarEvent) -> some View {
        let color = Color(nsColor: event.color)
        return HStack(spacing: eventColumnSpacing) {
            Text("全天")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .overlay(Capsule().strokeBorder(color.opacity(0.65), lineWidth: 0.8))
                .frame(width: eventTimeWidth, alignment: .leading)
            Text(event.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(event.title)
        }
        .accessibilityElement(children: .combine)
    }

    private func timedEventRow(_ event: CalendarEvent) -> some View {
        HStack(alignment: .top, spacing: eventColumnSpacing) {
            VStack(alignment: .leading, spacing: 3) {
                Text(time(event.startDate))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if !Calendar.current.isDate(event.startDate, inSameDayAs: store.selectedDate) {
                    Text(event.startDate.formatted(.dateTime.month(.defaultDigits).day()))
                        .font(.system(size: 10))
                        .foregroundStyle(muted)
                        .lineLimit(1)
                }
            }
            .frame(width: eventTimeWidth, alignment: .leading)
            Circle()
                .fill(Color(nsColor: event.color))
                .frame(width: markerWidth, height: markerWidth)
                .frame(height: timedMarkerLineHeight)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("至 " + endTime(event))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(event.title)
            Text(event.durationLabel)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.64))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.top, 1)
                .accessibilityLabel("总耗时，" + event.durationLabel)
        }
        .padding(.top, timedRowTopPadding)
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .combine)
    }

    private func timelineRail(count: Int) -> Path {
        let x = eventTimeWidth + eventColumnSpacing + markerWidth / 2
        let height = CGFloat(count) * CalendarPanelLayout.timedRowHeight
            + CGFloat(max(0, count - 1)) * CalendarPanelLayout.timedSpacing
        return Path { path in
            path.move(to: CGPoint(x: x, y: timedRowTopPadding))
            path.addLine(to: CGPoint(x: x, y: max(timedRowTopPadding, height - timedRowTopPadding)))
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

/// Retarget one highlight from its visible position, including during rapid clicks.
private struct CalendarSelectionHighlight: NSViewRepresentable {
    let selection: Date
    let displayMonth: Date
    let target: CGRect?
    let content: AnyView
    let reduceMotion: Bool
    let presentationID: UInt

    func makeNSView(context: Context) -> SelectionHighlightView { SelectionHighlightView(content: content) }

    func updateNSView(_ view: SelectionHighlightView, context: Context) {
        view.update(selection: selection, displayMonth: displayMonth, target: target, content: content,
                    reduceMotion: reduceMotion, presentationID: presentationID)
    }
}

private final class SelectionHighlightView: NSView {
    private let highlight = CALayer()
    private let host: NSHostingView<AnyView>
    private var selection: Date?
    private var presentationID: UInt?
    private let animationKey = "lunera.selection"

    override var isFlipped: Bool { true }

    init(content: AnyView) {
        host = NSHostingView(rootView: content)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        highlight.backgroundColor = NSColor.white.cgColor
        highlight.cornerRadius = 15
        highlight.cornerCurve = .continuous
        layer?.mask = highlight
        host.sizingOptions = []
        host.safeAreaRegions = []
        host.wantsLayer = true
        host.autoresizingMask = [.width, .height]
        addSubview(host)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        host.frame = bounds
    }

    func update(selection: Date, displayMonth: Date, target: CGRect?, content: AnyView, reduceMotion: Bool,
                presentationID: UInt) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        if self.presentationID != presentationID {
            self.presentationID = presentationID
            self.selection = nil
            highlight.removeAnimation(forKey: animationKey)
        }
        host.rootView = content
        host.frame = bounds
        let previousSelection = self.selection
        self.selection = selection
        guard let target else {
            // Keep the logical selection even if its month is not visible.
            host.isHidden = true
            highlight.removeAnimation(forKey: animationKey)
            return
        }

        var from = highlight.presentation()?.position ?? highlight.position
        let changedSelection = previousSelection != nil && previousSelection != selection
        if changedSelection, let previousSelection,
           let origin = adjacentMonthOrigin(for: previousSelection, displayedMonth: displayMonth,
                                            targetHeight: target.height) {
            from = origin
        }
        let changedFrame = highlight.frame != target
        highlight.frame = target
        // The background and selected ink are revealed by this single mask,
        // keeping every glyph legible as the highlight enters or leaves it.
        host.isHidden = false

        if reduceMotion || (!changedSelection && changedFrame) {
            highlight.removeAnimation(forKey: animationKey)
        } else if changedSelection {
            let to = highlight.position
            let animation = CAKeyframeAnimation(keyPath: "position")
            // Quintic ease-in-out starts and ends with zero speed and
            // acceleration, emphasizing the faster middle without overshoot.
            // Retarget from the visible position when clicks interrupt it.
            animation.values = (0...60).map { index in
                let t = Double(index) / 60
                let progress = t * t * t * (t * (6 * t - 15) + 10)
                return NSValue(point: CGPoint(x: from.x + (to.x - from.x) * progress,
                                              y: from.y + (to.y - from.y) * progress))
            }
            animation.duration = CalendarSelectionAnimation.duration
            animation.calculationMode = .linear
            highlight.add(animation, forKey: animationKey)
        }
    }

    private func adjacentMonthOrigin(for date: Date, displayedMonth: Date, targetHeight: CGFloat) -> CGPoint? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let order = calendar.compare(date, to: displayedMonth, toGranularity: .month)
        guard order != .orderedSame,
              let month = calendar.dateInterval(of: .month, for: date),
              let days = calendar.range(of: .day, in: .month, for: date) else { return nil }
        let leading = calendar.component(.weekday, from: month.start) - 1
        let index = leading + calendar.component(.day, from: date) - 1
        let weeks = (leading + days.count + 6) / 7
        let dayHeight = CalendarPanelLayout.dayHeight(forWeekCount: weeks)
        let cellY = CGFloat(index / 7) * (dayHeight + CalendarPanelLayout.gridSpacing) + dayHeight / 2
        // Treat every earlier/later month as the adjacent page, irrespective
        // of the actual gap. Retain its day-cell position within that page.
        let pageOffset = order == .orderedAscending ? -bounds.width : bounds.width
        let x = (CGFloat(index % 7) + 0.5) * bounds.width / 7 + pageOffset
        // A six-row source month may be taller; keep entry on the side edge.
        let halfHeight = targetHeight / 2
        let y = min(max(cellY, halfHeight), max(halfHeight, bounds.height - halfHeight))
        return CGPoint(x: x, y: y)
    }
}

/// A crescent and a tiny four-point star, drawn specifically for Lunera's empty state.
private struct EmptyAgendaMoon: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: w * 0.79, y: h * 0.03))
        path.addCurve(to: CGPoint(x: w * 0.14, y: h * 0.5),
                      control1: CGPoint(x: w * 0.37, y: -h * 0.03),
                      control2: CGPoint(x: w * 0.14, y: h * 0.2))
        path.addCurve(to: CGPoint(x: w * 0.83, y: h * 0.97),
                      control1: CGPoint(x: w * 0.14, y: h * 0.81),
                      control2: CGPoint(x: w * 0.39, y: h * 1.04))
        path.addCurve(to: CGPoint(x: w * 0.44, y: h * 0.5),
                      control1: CGPoint(x: w * 0.6, y: h * 0.9),
                      control2: CGPoint(x: w * 0.44, y: h * 0.73))
        path.addCurve(to: CGPoint(x: w * 0.79, y: h * 0.03),
                      control1: CGPoint(x: w * 0.44, y: h * 0.26),
                      control2: CGPoint(x: w * 0.59, y: h * 0.08))
        path.closeSubpath()
        return path
    }
}

private struct EmptyAgendaStar: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: w * 0.5, y: 0))
        path.addQuadCurve(to: CGPoint(x: w, y: h * 0.5), control: CGPoint(x: w * 0.5, y: h * 0.5))
        path.addQuadCurve(to: CGPoint(x: w * 0.5, y: h), control: CGPoint(x: w * 0.5, y: h * 0.5))
        path.addQuadCurve(to: CGPoint(x: 0, y: h * 0.5), control: CGPoint(x: w * 0.5, y: h * 0.5))
        path.addQuadCurve(to: CGPoint(x: w * 0.5, y: 0), control: CGPoint(x: w * 0.5, y: h * 0.5))
        path.closeSubpath()
        return path
    }
}
