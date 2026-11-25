import SwiftUI
import UIKit
import TactileMapCore
import TactileMapFeedback
import TactileMapView

struct DemoDrawingView: View {
    @ObservedObject var session: DemoSession
    let graph: DemoRouteGraph
    @State private var dragAccepted: Bool?
    @State private var finger: CGPoint?

    private var path: [Int] { session.draft?.path ?? [graph.start] }

    var body: some View {
        let configuration = MapAppearance.configuration(isZoomed: false)
        GeometryReader { canvas in
            let transform = DemoCanvasTransform(bounds: graph.document.bounds,
                                                size: canvas.size, padding: configuration.canvasPadding)
            ZStack {
                TactileMapView(document: graph.drawingDocument(path: path),
                               configuration: configuration, feedbackPolicy: SilentDrawingFeedback())
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                if let finger, let tip = path.last, tip != graph.end,
                   let preview = DemoRouteDrawing.preview(at: finger, path: path, graph: graph, transform: transform) {
                    Path { line in
                        line.move(to: transform.screenPoint(graph.nodes[tip]))
                        line.addLine(to: preview)
                    }
                    .stroke(Color(UIColor(red: 72 / 255, green: 202 / 255, blue: 228 / 255, alpha: 1)),
                            style: StrokeStyle(lineWidth: PhysicalDimensions.mmToPoints(3.5), lineCap: .round))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }

                marker("S", at: transform.screenPoint(graph.nodes[graph.start]))
                marker("E", at: transform.screenPoint(graph.nodes[graph.end]))

                Color.clear
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard let tip = path.last else { return }
                            if dragAccepted == nil {
                                dragAccepted = transform.distance(from: value.startLocation, to: graph.nodes[tip]) <= 32
                            }
                            guard dragAccepted == true else { return }
                            finger = value.location
                            // Process every crossed node, even if a fast swipe skips
                            // an intermediate gesture sample on a straight street.
                            while let node = DemoRouteDrawing.nextNode(at: value.location, path: path,
                                                                       graph: graph, transform: transform) {
                                if !session.extendRoute(to: node) { break }
                            }
                        }
                        .onEnded { _ in dragAccepted = nil; finger = nil })
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Draw your remembered route")
                    .accessibilityValue("\(max(0, path.count - 1)) segments drawn. \(path.last == graph.end ? "At the end." : "Extend from the current tip.")")
                    .accessibilityHint("Drag from the start to connected intersections, or use the directional actions.")
                    .accessibilityActions {
                        if let tip = path.last, tip != graph.end {
                            ForEach(graph.neighbors(of: tip).filter { !path.contains($0) }, id: \.self) { neighbor in
                                Button(direction(from: tip, to: neighbor)) { session.extendRoute(to: neighbor) }
                            }
                        }
                    }
            }
        }
    }

    private func marker(_ label: String, at point: CGPoint) -> some View {
        Text(label).font(.system(size: 13, weight: .heavy)).foregroundStyle(.black)
            .position(point).allowsHitTesting(false).accessibilityHidden(true)
    }

    private func direction(from: Int, to: Int) -> String {
        let a = graph.nodes[from], b = graph.nodes[to]
        if b.x > a.x { return "Extend route right" }
        if b.x < a.x { return "Extend route left" }
        return b.y > a.y ? "Extend route down" : "Extend route up"
    }
}

/// Shows only the street grid and correct route after a failed submission.
/// The static preview uses the map's line styles and lets the results scroll.
struct DemoCorrectRouteView: View {
    let graph: DemoRouteGraph

    var body: some View {
        let drawing = graph.drawingDocument(path: graph.expectedPath)
        let routeOnly = TactileMapDocument(
            bounds: drawing.bounds,
            features: drawing.features.filter { feature in
                if case .lineString = feature.geometry { return true }
                return false
            }
        )
        TactileMapView(document: routeOnly,
                       configuration: MapAppearance.configuration(isZoomed: false),
                       feedbackPolicy: SilentDrawingFeedback())
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Correct route map")
            .accessibilityValue(routeDirections)
    }

    private var routeDirections: String {
        let directions = zip(graph.expectedPath, graph.expectedPath.dropFirst()).map { from, to in
            let a = graph.nodes[from], b = graph.nodes[to]
            if b.x > a.x { return "right" }
            if b.x < a.x { return "left" }
            return b.y > a.y ? "down" : "up"
        }
        return "From start, follow one street segment " + directions.joined(separator: ", then ") + " to the end."
    }
}

/// Drawing and result previews are silent; the preview cannot resume exploration.
@MainActor
private final class SilentDrawingFeedback: FeedbackPolicy {
    func onEnter(element: any TactileMapElement, touchType: TouchType) {}
    func onContinue(element: any TactileMapElement, touchType: TouchType) {}
    func onExit(element: any TactileMapElement) {}
    func onTap(element: any TactileMapElement, touchType: TouchType) {}
    func stopAll() {}
}
