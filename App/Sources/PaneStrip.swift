import AppKit
import SwiftUI

/// Narrow-window navigation after Reeder: the panes (sidebar, list, detail) sit side by side on one strip that
/// slides as a whole. One pane is visible on phone-like widths, two adjacent panes on medium widths.
/// A two-finger swipe moves the strip with the fingers and springs to the nearest pane.
struct PaneStrip: View {
    let panes: [AnyView]
    /// Index of the deepest pane in view (0 = sidebar).
    @Binding var depth: Int
    /// How deep a swipe may go (e.g. no detail pane without a selection).
    var maxDepth: Int

    static let gap: CGFloat = 8
    static let sidebarWidth: CGFloat = 250
    static let listWidth: CGFloat = 300
    /// Two panes at once from this width.
    static let pairWidth: CGFloat = 640

    @State private var drag: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let layout = Layout(count: panes.count, available: geo.size.width, depth: depth)
            HStack(alignment: .top, spacing: Self.gap) {
                ForEach(panes.indices, id: \.self) { i in
                    panes[i]
                        .frame(width: layout.widths[i])
                        .frame(maxHeight: .infinity)
                        // Panes off the strip's window are dimmed slightly as they slide out, like Reeder's.
                        .opacity(layout.visible.contains(i) ? 1 : 0.35)
                        .allowsHitTesting(layout.visible.contains(i))
                        .accessibilityHidden(!layout.visible.contains(i))
                }
            }
            .offset(x: layout.offset + drag)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
            .clipped()
            .background(SwipeCatcher(onChange: track, onEnd: finish))
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: depth)
    }

    /// Fingers moving: follow them, with resistance past the ends.
    private func track(_ dx: CGFloat) {
        let canBack = depth > 0, canForward = depth < maxDepth
        let resisted = (dx > 0 && !canBack) || (dx < 0 && !canForward)
        drag = resisted ? dx * 0.18 : dx
    }

    /// Fingers lifted: go to the next pane if the swipe was far or fast enough, else spring back.
    private func finish(_ dx: CGFloat, _ velocity: CGFloat) {
        var target = depth
        if dx > 70 || velocity > 600 { target = max(depth - 1, 0) }
        if dx < -70 || velocity < -600 { target = min(depth + 1, maxDepth) }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            drag = 0
            depth = target
        }
    }

    /// Pane widths, which panes are in view, and the strip's offset for a depth.
    struct Layout {
        var widths: [CGFloat]
        var visible: ClosedRange<Int>
        var offset: CGFloat

        init(count: Int, available: CGFloat, depth: Int) {
            let pair = available >= PaneStrip.pairWidth && count > 1
            if !pair {
                widths = Array(repeating: available, count: count)
                visible = min(depth, count - 1)...min(depth, count - 1)
            } else {
                // Two panes: the left one keeps its natural width, the right one takes the rest.
                let first = min(depth, count - 2)
                let natural = { (i: Int) in i == 0 ? PaneStrip.sidebarWidth : PaneStrip.listWidth }
                widths = (0..<count).map { i in
                    if i == first + 1 { return available - natural(first) - PaneStrip.gap }
                    if i > first + 1 { return available }
                    return natural(i)
                }
                visible = first...(first + 1)
            }
            offset = -(widths.prefix(visible.lowerBound).reduce(0, +) + CGFloat(visible.lowerBound) * PaneStrip.gap)
        }
    }
}

/// Reports horizontal two-finger trackpad swipes over this view: cumulative distance while the fingers move,
/// then distance and velocity when they lift. Vertical scrolling (lists) passes through untouched.
private struct SwipeCatcher: NSViewRepresentable {
    let onChange: (CGFloat) -> Void
    let onEnd: (CGFloat, CGFloat) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onChange = onChange
        view.onEnd = onEnd
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onChange = onChange
        view.onEnd = onEnd
    }

    final class CatcherView: NSView {
        var onChange: (CGFloat) -> Void = { _ in }
        var onEnd: (CGFloat, CGFloat) -> Void = { _, _ in }
        private var monitor: Any?
        private enum Axis { case undecided, horizontal, vertical }
        private var axis = Axis.undecided
        private var distance: CGFloat = 0
        private var lastDelta: CGFloat = 0
        private var lastTime: TimeInterval = 0
        private var velocity: CGFloat = 0

        override func hitTest(_ point: NSPoint) -> NSView? { nil } // never takes clicks

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        // The monitor is removed when the view leaves its window (above), before it's freed.

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard event.window === window, event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty else { return event }
            let point = convert(event.locationInWindow, from: nil)
            switch event.phase {
            case .began:
                guard bounds.contains(point) else { return event }
                axis = .undecided; distance = 0; velocity = 0; lastTime = event.timestamp
                return event
            case .changed:
                if axis == .undecided, abs(event.scrollingDeltaX) + abs(event.scrollingDeltaY) > 2 {
                    axis = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * 1.4 ? .horizontal : .vertical
                }
                guard axis == .horizontal else { return event }
                distance += event.scrollingDeltaX
                let dt = max(event.timestamp - lastTime, 0.001)
                velocity = velocity * 0.6 + (event.scrollingDeltaX / dt) * 0.4
                lastTime = event.timestamp
                onChange(distance)
                return nil // ours: don't let a list scroll sideways too
            case .ended, .cancelled:
                defer { axis = .undecided }
                guard axis == .horizontal else { return event }
                onEnd(distance, velocity)
                return nil
            default:
                return axis == .horizontal ? nil : event
            }
        }
    }
}
