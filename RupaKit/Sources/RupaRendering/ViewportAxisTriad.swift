import SwiftUI
import RupaViewportScene

struct ViewportAxisTriad: View {
    static let controlSize = ViewportCanvasChromeLayout.axisControlSize
    static let bottomPadding = ViewportCanvasChromeLayout.axisBottomPadding

    var selectedAxis: ViewportCoordinateAxis?
    var basis: ViewportProjectionBasis = .isometric
    var onResetView: () -> Void
    var onSelectAxis: (ViewportCoordinateAxis?) -> Void

    var body: some View {
        HStack(spacing: 6.0) {
            iconButton(
                systemName: "arrow.counterclockwise",
                accessibilityIdentifier: "CanvasAxisTriad.Reset",
                accessibilityLabel: "Reset viewport"
            ) {
                onResetView()
            }

            ZStack {
                Canvas { context, size in
                    drawAxisDisk(in: &context, size: size)
                }

                GeometryReader { proxy in
                    centerButton(at: axisCenter(size: proxy.size))

                    ForEach(ViewportCoordinateAxis.allCases, id: \.self) { axis in
                        axisButton(
                            axis,
                            at: axisNodePoint(axis, size: proxy.size)
                        )
                    }
                }
            }
            .frame(width: 36.0, height: 36.0)
            .accessibilityIdentifier("CanvasAxisTriad")
            .accessibilityLabel("Canvas 3D axes")
            .accessibilityValue(accessibilityValue)

            projectionIndicator

            compactTextButton(
                title: "Iso",
                accessibilityIdentifier: "CanvasAxisTriad.IsometricButton",
                accessibilityLabel: "Isometric view"
            ) {
                onSelectAxis(nil)
            }
        }
        .padding(.horizontal, 7.0)
        .padding(.vertical, 4.0)
        .frame(width: Self.controlSize.width, height: Self.controlSize.height)
        .glassEffect(.regular, in: Capsule())
        .contentShape(Capsule())
        .accessibilityElement(children: .contain)
    }

    static func inputExclusionRect(
        in size: CGSize,
        bottomReservedHeight: CGFloat = 0.0
    ) -> CGRect {
        ViewportCanvasChromeLayout(
            viewportSize: size,
            bottomReservedHeight: bottomReservedHeight
        ).axisControlExclusionRect
    }

    private func iconButton(
        systemName: String,
        accessibilityIdentifier: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12.0, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
                .frame(width: 30.0, height: 30.0)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background(
            Capsule()
                .fill(.black.opacity(0.34))
        )
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityLabel(accessibilityLabel)
    }

    private func compactTextButton(
        title: String,
        accessibilityIdentifier: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.0, weight: .semibold))
                .foregroundStyle(.white.opacity(0.86))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(width: 38.0, height: 30.0)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background(
            Capsule()
                .fill(.black.opacity(0.34))
        )
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityLabel(accessibilityLabel)
    }

    private var projectionIndicator: some View {
        HStack(spacing: 0.0) {
            Text(projectionTitle)
                .font(.system(size: 10.0, weight: .medium))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(width: 74.0, height: 28.0)
                .background(
                    Capsule()
                        .fill(.white.opacity(0.14))
                )

            Text("Persp")
                .font(.system(size: 10.0, weight: .medium))
                .foregroundStyle(.white.opacity(0.54))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(width: 54.0, height: 28.0)
        }
        .padding(2.0)
        .background(
            Capsule()
                .fill(.black.opacity(0.34))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("CanvasProjectionIndicator")
        .accessibilityLabel("Canvas projection mode")
        .accessibilityValue(projectionTitle)
    }

    private var projectionTitle: String {
        switch basis.mode {
        case .isometric:
            return "Isometric"
        case .orbit:
            return "Orbit"
        case .axisFront(_):
            guard let selectedAxis else {
                return "Axis Front"
            }
            return "\(selectedAxis.label) Front"
        }
    }

    private var accessibilityValue: String {
        switch basis.mode {
        case .isometric:
            return "Isometric selected"
        case .orbit:
            return "Orbit view"
        case .axisFront(_):
            guard let selectedAxis else {
                return "Axis front view"
            }
            return "\(selectedAxis.label) selected"
        }
    }

    private func axisButton(_ axis: ViewportCoordinateAxis, at point: CGPoint) -> some View {
        Button {
            onSelectAxis(axis)
        } label: {
            Circle()
                .fill(Color.clear)
                .frame(width: 18.0, height: 18.0)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .position(point)
        .help("Select \(axis.label) axis")
        .accessibilityIdentifier("CanvasAxisTriad.\(axis.label)")
        .accessibilityLabel("\(axis.label) axis")
        .accessibilityValue(selectedAxis == axis ? "Selected" : "Not selected")
    }

    private func centerButton(at point: CGPoint) -> some View {
        Button {
            onSelectAxis(nil)
        } label: {
            Circle()
                .fill(Color.clear)
                .frame(width: 18.0, height: 18.0)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .position(point)
        .help("Reset isometric view")
        .accessibilityIdentifier("CanvasAxisTriad.Isometric")
        .accessibilityLabel("Isometric view")
        .accessibilityValue(basis.mode == .isometric ? "Selected" : "Not selected")
    }

    private func drawAxisDisk(in context: inout GraphicsContext, size: CGSize) {
        let diskRect = CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5)
        context.fill(
            Path(ellipseIn: diskRect),
            with: .color(.black.opacity(0.30))
        )
        context.stroke(
            Path(ellipseIn: diskRect),
            with: .color(.white.opacity(0.10)),
            lineWidth: 1.0
        )

        let center = axisCenter(size: size)
        var axes = [
            AxisNode(axis: .x, color: ViewportCoordinateAxis.x.color, end: axisNodePoint(.x, size: size), radius: 3.3),
            AxisNode(axis: .y, color: ViewportCoordinateAxis.y.color, end: axisNodePoint(.y, size: size), radius: 3.3),
            AxisNode(axis: .z, color: ViewportCoordinateAxis.z.color, end: axisNodePoint(.z, size: size), radius: 3.3),
        ]
        for axis in ViewportCoordinateAxis.allCases where axis != selectedAxis {
            axes.append(
                AxisNode(
                    axis: nil,
                    color: .white.opacity(0.28),
                    end: negativeAxisNodePoint(axis, size: size),
                    radius: 3.0
                )
            )
        }

        for axis in axes {
            drawAxisLine(
                from: center,
                to: axis.end,
                color: axis.color,
                in: &context
            )
        }

        for axis in axes {
            drawNode(
                at: axis.end,
                radius: axis.radius,
                color: axis.color,
                in: &context
            )
        }

        if basis.mode == .isometric {
            drawNode(
                at: center,
                radius: 3.4,
                color: .white.opacity(0.34),
                in: &context
            )
        }
    }

    private func axisCenter(size: CGSize) -> CGPoint {
        CGPoint(x: size.width * 0.50, y: size.height * 0.50)
    }

    private func axisLength(size: CGSize) -> CGFloat {
        size.width * 0.28
    }

    private func axisNodePoint(_ axis: ViewportCoordinateAxis, size: CGSize) -> CGPoint {
        if axis == selectedAxis {
            return axisCenter(size: size)
        }
        return basis.endpoint(
            from: axisCenter(size: size),
            axis: axis,
            length: axisLength(size: size)
        )
    }

    private func negativeAxisNodePoint(_ axis: ViewportCoordinateAxis, size: CGSize) -> CGPoint {
        return basis.endpoint(
            from: axisCenter(size: size),
            axis: axis,
            length: -axisLength(size: size)
        )
    }

    private func drawAxisLine(
        from start: CGPoint,
        to end: CGPoint,
        color: Color,
        in context: inout GraphicsContext
    ) {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        context.stroke(path, with: .color(color.opacity(0.58)), lineWidth: 1.4)
    }

    private func drawNode(
        at point: CGPoint,
        radius: CGFloat,
        color: Color,
        in context: inout GraphicsContext
    ) {
        let rect = CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2.0,
            height: radius * 2.0
        )
        context.fill(Path(ellipseIn: rect), with: .color(color))
    }
}

private struct AxisNode {
    var axis: ViewportCoordinateAxis?
    var color: Color
    var end: CGPoint
    var radius: CGFloat
}
