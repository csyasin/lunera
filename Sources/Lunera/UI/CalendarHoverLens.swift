import AppKit
import Combine
import CoreGraphics
import Foundation
import QuartzCore
import SwiftUI

/// A transparent drawing canvas around the logical grid, allowing magnified
/// edge dates to extend without changing date geometry or hit-test coordinates.
struct CalendarHoverCanvas: Equatable {
    let size: CGSize
    let dayHeight: CGFloat
    let rowCount: Int

    var contentOrigin: CGPoint {
        CGPoint(x: CalendarPanelLayout.gridHorizontalPadding,
                y: CalendarPanelLayout.gridOverflowPadding)
    }

    var geometry: CalendarHoverGeometry {
        CalendarHoverGeometry(
            size: CGSize(width: max(0, size.width - 2 * contentOrigin.x),
                         height: max(0, size.height - 2 * contentOrigin.y)),
            dayHeight: dayHeight,
            rowCount: rowCount
        )
    }

    func gridPosition(for point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - contentOrigin.x, y: point.y - contentOrigin.y)
    }

    func canvasPosition(for point: CGPoint) -> CGPoint {
        CGPoint(x: point.x + contentOrigin.x, y: point.y + contentOrigin.y)
    }
}

/// Geometry is expressed in the calendar grid's local, top-left coordinate space.
struct CalendarHoverGeometry: Equatable {
    let size: CGSize
    let dayHeight: CGFloat
    let rowCount: Int

    var cellPitch: CGSize {
        CGSize(width: size.width / 7, height: dayHeight + CalendarPanelLayout.gridSpacing)
    }

    func index(at point: CGPoint) -> Int? {
        let pitch = cellPitch
        guard rowCount > 0, dayHeight > 0,
              size.width.isFinite, size.height.isFinite,
              pitch.width.isFinite, pitch.height.isFinite,
              pitch.width > 0, pitch.height > 0,
              point.x.isFinite, point.y.isFinite,
              point.x >= 0, point.y >= 0,
              point.x < size.width, point.y < size.height else { return nil }
        let column = Int(point.x / pitch.width)
        let row = Int(point.y / pitch.height)
        guard column < 7, row < rowCount else { return nil }
        return row * 7 + column
    }

    func focus(at point: CGPoint) -> CGPoint? {
        guard index(at: point) != nil else { return nil }
        let pitch = cellPitch
        return CGPoint(x: biasedPosition(point.x, pitch: pitch.width, centerFraction: 0.5),
                       y: biasedPosition(point.y, pitch: pitch.height,
                                         centerFraction: dayHeight / (2 * pitch.height)))
    }

    private func biasedPosition(_ position: CGFloat, pitch: CGFloat, centerFraction: CGFloat) -> CGFloat {
        let phase = CGFloat.pi * centerFraction
        // This periodic bias fixes both cell boundaries and the actual date
        // center, including rows whose bottom spacing shifts that center.
        let bias: CGFloat = min(0.9, 0.95 * sin(phase))
        let amplitude = bias / (2 * .pi * sin(phase))
        return position + pitch * amplitude * (cos(2 * .pi * position / pitch - phase) - cos(phase))
    }

}

/// Destination-to-source lens mapping, shared with CalendarHoverLens.metal.
struct CalendarHoverLens: Equatable {
    var focus: CGPoint
    var strength: CGFloat

    static let radius: CGFloat = 2.4
    static let maximumStrength: CGFloat = 1 - 1 / 1.45

    func sourcePosition(for point: CGPoint, cellPitch: CGSize) -> CGPoint {
        guard cellPitch.width.isFinite, cellPitch.height.isFinite,
              cellPitch.width > 0, cellPitch.height > 0,
              point.x.isFinite, point.y.isFinite,
              focus.x.isFinite, focus.y.isFinite,
              strength.isFinite, strength > 0 else { return point }
        // Match the shader's float arithmetic for hit testing the rendered grid.
        let dx = Float(point.x) - Float(focus.x)
        let dy = Float(point.y) - Float(focus.y)
        let qx = dx / Float(cellPitch.width)
        let qy = dy / Float(cellPitch.height)
        let radius = Float(Self.radius)
        let distanceSquared = (qx * qx + qy * qy) / (radius * radius)
        guard distanceSquared < 1 else { return point }
        let remaining = 1 - distanceSquared
        let weight = remaining * remaining * remaining
        let amount = Float(min(strength, Self.maximumStrength))
        let scale = 1 - amount * weight
        return CGPoint(x: CGFloat(Float(focus.x) + dx * scale),
                       y: CGFloat(Float(focus.y) + dy * scale))
    }

    static func maximumSampleOffset(cellPitch: CGSize) -> CGSize {
        guard cellPitch.width.isFinite, cellPitch.height.isFinite,
              cellPitch.width > 0, cellPitch.height > 0 else { return .zero }
        // max[t * (1-t²)³] = 216 / (343√7) < 0.24. Include a point of
        // filtering margin so the shader never samples outside its declared area.
        let factor = 0.24 * maximumStrength * radius
        return CGSize(width: ceil(factor * cellPitch.width) + 1,
                      height: ceil(factor * cellPitch.height) + 1)
    }
}

/// Animates only the hover field; selection styling remains immediate.
@MainActor
final class CalendarHoverController: ObservableObject {
    @Published private(set) var lens = CalendarHoverLens(focus: .zero, strength: 0)

    private var targetFocus = CGPoint.zero
    private var targetStrength: CGFloat = 0
    private var focusVelocity = CGPoint.zero
    private var strengthVelocity: CGFloat = 0
    private var geometry: CalendarHoverGeometry?
    private weak var sourceView: NSView?
    private var displayLink: CADisplayLink?
    private var lastTargetTimestamp: CFTimeInterval?

    func move(to point: CGPoint, geometry: CalendarHoverGeometry) {
        guard let focus = geometry.focus(at: point) else {
            end()
            return
        }
        self.geometry = geometry
        // An invisible field can begin at the pointer. All visible retargeting
        // retains both position and velocity, including a quick re-entry.
        if lens.strength == 0, targetStrength == 0 {
            lens = CalendarHoverLens(focus: focus, strength: 0)
            focusVelocity = .zero
        }
        targetFocus = focus
        targetStrength = CalendarHoverLens.maximumStrength
        startFrames()
    }

    func end() {
        guard targetStrength != 0 else { return }
        targetFocus = lens.focus
        targetStrength = 0
        startFrames()
    }

    func reset() {
        stopFrames()
        targetFocus = .zero
        targetStrength = 0
        focusVelocity = .zero
        strengthVelocity = 0
        geometry = nil
        lens = CalendarHoverLens(focus: .zero, strength: 0)
    }

    fileprivate func attach(to view: NSView) {
        guard sourceView !== view else { return }
        stopFrames()
        sourceView = view
        startFrames()
    }

    fileprivate func detach(from view: NSView) {
        // SwiftUI can tear down an old source after its replacement attaches.
        guard sourceView === view else { return }
        stopFrames()
        sourceView = nil
    }

    private func startFrames() {
        guard displayLink == nil, !isSettled(lens),
              let sourceView, sourceView.window != nil else { return }
        let target = CalendarHoverDisplayLinkTarget(controller: self)
        let link = sourceView.displayLink(target: target, selector: #selector(CalendarHoverDisplayLinkTarget.frame(_:)))
        displayLink = link
        lastTargetTimestamp = nil
        link.add(to: .main, forMode: .common)
    }

    private func stopFrames() {
        displayLink?.invalidate()
        displayLink = nil
        lastTargetTimestamp = nil
    }

    fileprivate func frame(_ link: CADisplayLink) {
        guard displayLink === link else { return }
        let frameInterval = link.targetTimestamp - link.timestamp
        let normalInterval = frameInterval.isFinite && frameInterval > 0 && frameInterval <= 0.1
            ? frameInterval : 1 / 60
        let interval = lastTargetTimestamp.map { link.targetTimestamp - $0 } ?? normalInterval
        lastTargetTimestamp = link.targetTimestamp
        // A hidden view receives no frames. Resume by one display interval,
        // rather than integrating its entire hidden duration in a single jump.
        let elapsed = interval.isFinite && interval > 0 && interval <= 0.1 ? interval : normalInterval
        advance(elapsed: elapsed)
    }

    private func advance(elapsed: TimeInterval) {
        let x = Self.step(lens.focus.x, velocity: focusVelocity.x, target: targetFocus.x,
                          frequency: 34, elapsed: elapsed)
        let y = Self.step(lens.focus.y, velocity: focusVelocity.y, target: targetFocus.y,
                          frequency: 34, elapsed: elapsed)
        let strength = Self.step(lens.strength, velocity: strengthVelocity, target: targetStrength,
                                 frequency: 24, elapsed: elapsed)
        var next = CalendarHoverLens(focus: CGPoint(x: x.value, y: y.value), strength: strength.value)
        focusVelocity = CGPoint(x: x.velocity, y: y.velocity)
        strengthVelocity = strength.velocity
        if let geometry {
            Self.clamp(&next.focus.x, velocity: &focusVelocity.x, upper: geometry.size.width)
            Self.clamp(&next.focus.y, velocity: &focusVelocity.y, upper: geometry.size.height)
        }
        Self.clamp(&next.strength, velocity: &strengthVelocity, upper: CalendarHoverLens.maximumStrength)
        if isSettled(next) {
            next = CalendarHoverLens(focus: targetFocus, strength: targetStrength)
            focusVelocity = .zero
            strengthVelocity = 0
            stopFrames()
        }
        if next != lens { lens = next }
    }

    private func isSettled(_ value: CalendarHoverLens) -> Bool {
        hypot(value.focus.x - targetFocus.x, value.focus.y - targetFocus.y) < 0.02
            && hypot(focusVelocity.x, focusVelocity.y) < 0.2
            && abs(value.strength - targetStrength) < 0.0001
            && abs(strengthVelocity) < 0.001
    }

    /// Exact solution of x'' + 2ωx' + ω²(x-target) = 0 for one frame.
    private static func step(_ value: CGFloat, velocity: CGFloat, target: CGFloat,
                             frequency: CGFloat, elapsed: TimeInterval) -> (value: CGFloat, velocity: CGFloat) {
        let time = CGFloat(elapsed)
        let error = value - target
        let coefficient = velocity + frequency * error
        let decay = exp(-frequency * time)
        return (target + (error + coefficient * time) * decay,
                (velocity - frequency * coefficient * time) * decay)
    }

    private static func clamp(_ value: inout CGFloat, velocity: inout CGFloat, upper: CGFloat) {
        if value < 0 {
            value = 0
            if velocity < 0 { velocity = 0 }
        } else if value > upper {
            value = upper
            if velocity > 0 { velocity = 0 }
        }
    }
}

/// The display link retains this proxy, which never retains its controller.
@MainActor
private final class CalendarHoverDisplayLinkTarget: NSObject {
    private weak var controller: CalendarHoverController?

    init(controller: CalendarHoverController) {
        self.controller = controller
        super.init()
    }

    @objc func frame(_ link: CADisplayLink) {
        guard let controller else {
            link.invalidate()
            return
        }
        controller.frame(link)
    }
}

/// An unpainted, noninteractive source tied to the grid's actual display.
@MainActor
struct CalendarHoverFrameSource: NSViewRepresentable {
    let controller: CalendarHoverController

    func makeNSView(context: Context) -> ClockView { ClockView(controller: controller) }

    func updateNSView(_ view: ClockView, context: Context) { view.connect(to: controller) }

    static func dismantleNSView(_ view: ClockView, coordinator: ()) { view.disconnect() }

    final class ClockView: NSView {
        private weak var controller: CalendarHoverController?

        init(controller: CalendarHoverController) {
            self.controller = controller
            super.init(frame: .zero)
            setAccessibilityHidden(true)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                controller?.attach(to: self)
            } else {
                controller?.detach(from: self)
            }
        }

        func connect(to controller: CalendarHoverController) {
            if self.controller !== controller {
                self.controller?.detach(from: self)
                self.controller = controller
            }
            if window != nil { controller.attach(to: self) }
        }

        func disconnect() {
            controller?.detach(from: self)
            controller = nil
        }
    }
}
