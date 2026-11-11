import AppKit
import QuartzCore
import SwiftUI

struct CalendarView: View {
    @ObservedObject var store: CalendarStore
    @Environment(\.notchHeaderLayout) private var notchHeaderLayout
    @Environment(\.calendarPresentationID) private var presentationID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(ThemeColor.preferenceKey) private var accentHex = ThemeColor.systemValue

    private var accent: Color { ThemeColor.color(accentHex) }
    private let muted = Color.white.opacity(0.58)
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
        let monthPage = CalendarMonthPage(month: store.displayMonth, days: days,
                                          events: store.events, dayHeight: layout.dayHeight)
        let monthCanvasHeight = layout.gridHeight + 2 * CalendarPanelLayout.gridOverflowPadding
        return VStack(alignment: .leading, spacing: 0) {
            header
                .frame(height: notchHeaderLayout.bandHeight)
            weekdayHeader
                .frame(height: CalendarPanelLayout.weekdayHeight)
                .padding(.horizontal, CalendarPanelLayout.gridHorizontalPadding - CalendarPanelLayout.contentHorizontalPadding)
                .padding(.top, CalendarPanelLayout.weekdayTopSpacing)
            CalendarMonthPager(
                month: monthPage.month,
                height: monthCanvasHeight,
                selection: store.selectedDate,
                content: { [accentHex, reduceMotion, presentationID, onSelect = store.select] selection, hoverEnabled in
                    AnyView(CalendarMonthGrid(
                        page: monthPage, selection: selection,
                        accentHex: accentHex, hoverEnabled: hoverEnabled,
                        reduceMotion: reduceMotion, presentationID: presentationID, onSelect: onSelect
                    ).preferredColorScheme(.dark))
                },
                reduceMotion: reduceMotion,
                presentationID: presentationID
            )
                .frame(height: monthCanvasHeight)
                // Move the existing side margins inside the clipped page. Its
                // transparent canvas can then contain the enlarged edge dates.
                .padding(.horizontal, -CalendarPanelLayout.contentHorizontalPadding)
                .padding(.top, CalendarPanelLayout.gridTopSpacing - CalendarPanelLayout.gridOverflowPadding)
                .padding(.bottom, -CalendarPanelLayout.gridOverflowPadding)
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

private typealias CalendarMonthContent = (Date?, Bool) -> AnyView

/// Each page keeps its dates and event markers while it slides out.
private struct CalendarMonthPage {
    let month: Date
    let days: [CalendarDay?]
    let events: [CalendarEvent]
    let dayHeight: CGFloat

    func events(on date: Date) -> [CalendarEvent] {
        events.filter { $0.occurs(on: date) }
    }
}

@MainActor
private final class CalendarHoverInput {
    var hoverPoint: CGPoint?
    var location: CGPoint?

    func clear() {
        hoverPoint = nil
        location = nil
    }
}

/// Only shader uniforms observe the frame clock; dates and event markers do
/// not need to be rebuilt for every animation frame or raw pointer movement.
private struct CalendarHoverEffect: ViewModifier {
    @ObservedObject var hover: CalendarHoverController
    let canvas: CalendarHoverCanvas

    func body(content: Content) -> some View {
        content.distortionEffect(
            ShaderLibrary.calendarHoverLens(
                .float2(canvas.canvasPosition(for: hover.lens.focus)), .float2(canvas.geometry.cellPitch),
                .float(CalendarHoverLens.radius), .float(hover.lens.strength),
                .float(CalendarHoverLens.maximumStrength)
            ),
            maxSampleOffset: CalendarHoverLens.maximumSampleOffset(cellPitch: canvas.geometry.cellPitch),
            isEnabled: hover.lens.strength > 0
        )
    }
}

private struct CalendarMonthGrid: View {
    let page: CalendarMonthPage
    let selection: Date?
    let accentHex: String
    let hoverEnabled: Bool
    let reduceMotion: Bool
    let presentationID: UInt
    let onSelect: (Date) -> Void
    @State private var hover = CalendarHoverController()
    @State private var pointer = CalendarHoverInput()

    private var accent: Color { ThemeColor.color(accentHex) }
    private var selectedText: Color { ThemeColor.keyInk(accentHex) }
    private let muted = Color.white.opacity(0.58)
    private let adjacentDayOpacity = 0.4
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        GeometryReader { proxy in
            let canvas = CalendarHoverCanvas(size: proxy.size, dayHeight: page.dayHeight,
                                              rowCount: page.days.count / 7)
            let geometry = canvas.geometry
            monthGrid(geometry: geometry)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                // Padding must be part of the shader's input, not outside it.
                .padding(.horizontal, canvas.contentOrigin.x)
                .padding(.vertical, canvas.contentOrigin.y)
                .modifier(CalendarHoverEffect(hover: hover, canvas: canvas))
                // The AppKit clock stays outside the filtered SwiftUI layer.
                .background(CalendarHoverFrameSource(controller: hover)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true))
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        let location = canvas.gridPosition(for: point)
                        pointer.location = location
                        guard hoverEnabled, !reduceMotion else {
                            pointer.hoverPoint = nil
                            hover.end()
                            return
                        }
                        if geometry.index(at: location) != nil {
                            pointer.hoverPoint = location
                            updateHover(geometry: geometry)
                        } else if date(at: location, geometry: geometry) == nil {
                            pointer.hoverPoint = nil
                            hover.end()
                        }
                        // An enlarged date can occupy the transparent margin.
                        // Retain its last valid focus while hovering that fringe.
                    case .ended:
                        pointer.clear()
                        hover.end()
                    }
                }
                .simultaneousGesture(SpatialTapGesture(coordinateSpace: .local).onEnded { value in
                    let location = canvas.gridPosition(for: value.location)
                    // Buttons handle the original grid; this disjoint route
                    // makes only the enlarged, out-of-grid pixels clickable.
                    guard geometry.index(at: location) == nil,
                          let date = date(at: location, geometry: geometry) else { return }
                    onSelect(date)
                })
                .onChange(of: hoverEnabled) { _, _ in updateHover(geometry: geometry) }
                .onChange(of: reduceMotion) { _, _ in updateHover(geometry: geometry) }
                .onChange(of: geometry) { _, _ in
                    hover.end()
                    updateHover(geometry: geometry)
                }
                .onChange(of: presentationID) { _, _ in
                    pointer.clear()
                    hover.end()
                }
                .onDisappear {
                    pointer.clear()
                    hover.reset()
                }
        }
    }

    private func monthGrid(geometry: CalendarHoverGeometry) -> some View {
        // Include the visual row gaps in the buttons' hit areas, so the warped
        // image has no dead strips between otherwise clickable dates.
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(Array(page.days.enumerated()), id: \.offset) { index, day in
                if let day {
                    dayCell(day, index: index, geometry: geometry)
                        .id(day.id)
                } else {
                    Color.clear.frame(height: page.dayHeight)
                        .accessibilityHidden(true)
                }
            }
        }
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }

    private func updateHover(geometry: CalendarHoverGeometry) {
        guard hoverEnabled, !reduceMotion else {
            pointer.hoverPoint = nil
            hover.end()
            return
        }
        if let point = pointer.hoverPoint { hover.move(to: point, geometry: geometry) }
    }

    private func isSelected(_ day: CalendarDay) -> Bool {
        guard let selection else { return false }
        return day.isInDisplayedMonth && Calendar.current.isDate(day.date, inSameDayAs: selection)
    }

    private func dayCell(_ day: CalendarDay, index: Int, geometry: CalendarHoverGeometry) -> some View {
        let selected = isSelected(day)
        let dayEvents = page.events(on: day.date)
        let bottomSpacing = index / 7 < geometry.rowCount - 1 ? CalendarPanelLayout.gridSpacing : 0
        return Button {
            select(day, geometry: geometry)
        } label: {
            dayContent(day, events: dayEvents, selected: selected)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(accent)
                            .padding(.horizontal, CalendarPanelLayout.dayHighlightHorizontalInset)
                    } else if day.isToday {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .strokeBorder(accent, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .padding(.horizontal, CalendarPanelLayout.dayHighlightHorizontalInset)
                    }
                }
                .padding(.bottom, bottomSpacing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(day.isInDisplayedMonth ? 1 : adjacentDayOpacity)
        .accessibilityLabel("\(day.date.formatted(.dateTime.year().month(.defaultDigits).day()))，\(day.lunarLabel)，\(dayEvents.count)个日程")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityAction { onSelect(day.date) }
    }

    private func select(_ fallback: CalendarDay, geometry: CalendarHoverGeometry) {
        // Shaders deform pixels, not Button layout. Pointer activation therefore
        // uses exactly the same destination-to-source map as the Metal shader.
        if NSApp.currentEvent?.type == .leftMouseUp,
           let location = pointer.location,
           let date = date(at: location, geometry: geometry) {
            onSelect(date)
        } else {
            onSelect(fallback.date)
        }
    }

    private func date(at location: CGPoint, geometry: CalendarHoverGeometry) -> Date? {
        let source = hover.lens.sourcePosition(for: location, cellPitch: geometry.cellPitch)
        guard let index = geometry.index(at: source), page.days.indices.contains(index) else { return nil }
        return page.days[index]?.date
    }

    private func dayContent(_ day: CalendarDay, events: [CalendarEvent], selected: Bool) -> some View {
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
                ForEach(Array(events.prefix(3).enumerated()), id: \.offset) { _, event in
                    Circle().fill(Color(nsColor: event.color)).frame(width: 4, height: 4)
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity)
        .frame(height: page.dayHeight)
    }
}

/// Keeps the weekday header outside the moving, clipped month viewport.
private struct CalendarMonthPager: NSViewRepresentable {
    let month: Date
    let height: CGFloat
    let selection: Date
    let content: CalendarMonthContent
    let reduceMotion: Bool
    let presentationID: UInt

    func makeNSView(context: Context) -> MonthPagerView { MonthPagerView(frame: .zero) }

    func updateNSView(_ view: MonthPagerView, context: Context) {
        view.update(month: month, height: height, selection: selection, content: content,
                    reduceMotion: reduceMotion, presentationID: presentationID)
    }
}

@MainActor
private final class MonthPagerView: NSView {
    private struct Page {
        let host: NSHostingView<AnyView>
        let height: CGFloat
        let content: CalendarMonthContent
    }

    private var pages: [Date: Page] = [:]
    private var month: Date?
    private var selection: Date?
    private var presentationID: UInt?
    private var animationID: UInt = 0
    private var isTransitioning = false
    private let animationKey = "lunera.month"

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isTransitioning, let hit = super.hitTest(point), let month, let host = pages[month]?.host,
              hit === host || hit.isDescendant(of: host) else { return nil }
        return hit
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for page in pages.values {
            let frame = CGRect(x: page.host.frame.minX, y: 0, width: bounds.width, height: page.height)
            if page.host.frame != frame { page.host.frame = frame }
        }
        CATransaction.commit()
    }

    func update(month: Date, height: CGFloat, selection: Date, content: @escaping CalendarMonthContent,
                reduceMotion: Bool, presentationID: UInt) {
        let previousMonth = self.month
        let reset = self.presentationID != presentationID || reduceMotion || bounds.width <= 0
        let startsTransition = !reset && previousMonth != nil && previousMonth != month
        if startsTransition || self.selection != selection {
            // Exiting snapshots cannot retain hover; selection still clears
            // immediately when the user actually selects another date.
            let outgoingSelection = self.selection == selection ? self.selection : nil
            for (key, page) in pages where key != month {
                page.host.rootView = page.content(outgoingSelection, false)
            }
        }
        self.selection = selection
        self.presentationID = presentationID
        self.month = month

        // Freeze every outgoing page's content and retain its visible position.
        var starts = pages.mapValues { page -> CGFloat in
            guard let layer = page.host.layer else { return page.host.frame.minX }
            return page.host.frame.minX + (layer.presentation()?.position.x ?? layer.position.x) - layer.position.x
        }
        let host: NSHostingView<AnyView>
        let renderedContent = content(selection, reset || (!startsTransition && !isTransitioning))
        if let page = pages[month] {
            host = page.host
            host.rootView = renderedContent
        } else {
            host = NSHostingView(rootView: renderedContent)
            host.sizingOptions = []
            host.safeAreaRegions = []
            host.wantsLayer = true
            host.autoresizingMask = []
            addSubview(host)
        }
        pages[month] = Page(host: host, height: height, content: content)
        needsLayout = true

        if !reset, previousMonth == month { return }
        animationID &+= 1
        let generation = animationID

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        guard let previousMonth, !reset else {
            isTransitioning = false
            removeOutgoingPages()
            host.layer?.removeAnimation(forKey: animationKey)
            host.frame = CGRect(x: 0, y: 0, width: bounds.width, height: height)
            host.setAccessibilityHidden(false)
            CATransaction.commit()
            return
        }

        isTransitioning = true
        let direction: CGFloat = month > previousMonth ? 1 : -1
        // Discard pages that have already left the viewport. A rapid reversal can
        // reuse a still-visible month instead of replacing it with a fresh page.
        let invisible = pages.keys.filter { $0 != month && abs(starts[$0] ?? bounds.width) >= bounds.width }
        for key in invisible { pages.removeValue(forKey: key)?.host.removeFromSuperview() }
        if starts[month] == nil { starts[month] = direction * bounds.width }
        addSubview(host, positioned: .above, relativeTo: nil)
        host.frame = CGRect(x: starts[month] ?? 0, y: 0, width: bounds.width, height: height)
        host.layoutSubtreeIfNeeded()

        CATransaction.setCompletionBlock { [weak self] in
            Task { @MainActor in
                guard let self, self.animationID == generation else { return }
                self.isTransitioning = false
                self.removeOutgoingPages()
                if let month = self.month, let page = self.pages[month] {
                    page.host.rootView = page.content(self.selection, true)
                }
            }
        }
        for (key, page) in pages {
            let start = starts[key] ?? page.host.frame.minX
            let target: CGFloat = key == month ? 0 : -direction * bounds.width
            page.host.setAccessibilityHidden(key != month)
            // Let older pages finish exiting during held keys instead of
            // repeatedly restarting their animation and keeping them alive.
            if key != month, key != previousMonth, page.host.frame.minX == target { continue }
            page.host.layer?.removeAnimation(forKey: animationKey)
            page.host.frame = CGRect(x: target, y: 0, width: bounds.width, height: page.height)
            if let layer = page.host.layer, start != target {
                let animation = CABasicAnimation(keyPath: "position.x")
                animation.fromValue = layer.position.x + start - target
                animation.toValue = layer.position.x
                animation.duration = 0.28
                animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                layer.add(animation, forKey: animationKey)
            }
        }
        CATransaction.commit()
    }

    private func removeOutgoingPages() {
        for key in pages.keys.filter({ $0 != month }) {
            pages.removeValue(forKey: key)?.host.removeFromSuperview()
        }
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
