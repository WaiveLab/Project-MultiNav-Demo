import Foundation
import TactileMapCore

/// A street graph split at every intersection, independent of route highlighting.
struct DemoRouteGraph {
    struct Edge: Hashable {
        let a: Int
        let b: Int

        init(_ first: Int, _ second: Int) {
            a = min(first, second)
            b = max(first, second)
        }
    }

    let document: TactileMapDocument
    let nodes: [TactileCoordinate]
    let edges: Set<Edge>
    let expectedEdges: Set<Edge>
    let expectedPath: [Int]
    let start: Int
    let end: Int

    enum InvalidMap: LocalizedError {
        case invalidGrid
        var errorDescription: String? { "This map does not contain a complete street grid and route." }
    }

    init(document: TactileMapDocument) throws {
        let nodeTypes = ["start", "end", "onRouteIntersection", "offRouteIntersection"]
        let points = document.features.compactMap { feature -> TactileCoordinate? in
            guard nodeTypes.contains(feature.elementType.rawValue),
                  case .point(let point) = feature.geometry else { return nil }
            return point
        }
        let nodes = Array(Set(points)).sorted { $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y }
        func marker(_ type: String) -> Int? {
            guard let feature = document.features.first(where: { $0.elementType.rawValue == type }),
                  case .point(let coordinate) = feature.geometry else { return nil }
            return nodes.firstIndex(of: coordinate)
        }
        guard let start = marker("start"), let end = marker("end"), start != end,
              document.bounds.width > 0, document.bounds.height > 0 else { throw InvalidMap.invalidGrid }

        var edges: Set<Edge> = []
        var expected: Set<Edge> = []
        for feature in document.features where ["onRoute", "offRoute"].contains(feature.elementType.rawValue) {
            guard case .lineString(let coordinates) = feature.geometry else { continue }
            for (a, b) in zip(coordinates, coordinates.dropFirst()) {
                let dx = b.x - a.x, dy = b.y - a.y
                let lengthSquared = dx * dx + dy * dy
                guard lengthSquared > 0 else { continue }
                let indices = nodes.indices.filter { index in
                    let point = nodes[index]
                    let cross = (point.x - a.x) * dy - (point.y - a.y) * dx
                    let along = (point.x - a.x) * dx + (point.y - a.y) * dy
                    return abs(cross) < 0.001 && along >= -0.001 && along <= lengthSquared + 0.001
                }.sorted { left, right in
                    let l = nodes[left], r = nodes[right]
                    return (l.x - a.x) * dx + (l.y - a.y) * dy < (r.x - a.x) * dx + (r.y - a.y) * dy
                }
                for (first, second) in zip(indices, indices.dropFirst()) {
                    let edge = Edge(first, second)
                    edges.insert(edge)
                    if feature.elementType.rawValue == "onRoute" { expected.insert(edge) }
                }
            }
        }

        // Recover the exact ordered route, rejecting disconnected/branching data.
        var path = [start]
        var remaining = expected
        while path.last != end {
            guard let current = path.last else { throw InvalidMap.invalidGrid }
            let next = remaining.filter { $0.a == current || $0.b == current }
            guard next.count == 1, let edge = next.first else { throw InvalidMap.invalidGrid }
            let destination = edge.a == current ? edge.b : edge.a
            guard !path.contains(destination) else { throw InvalidMap.invalidGrid }
            path.append(destination)
            remaining.remove(edge)
        }
        guard remaining.isEmpty, !expected.isEmpty else { throw InvalidMap.invalidGrid }
        self.document = document
        self.nodes = nodes
        self.edges = edges
        self.expectedEdges = expected
        self.expectedPath = path
        self.start = start
        self.end = end
    }

    func neighbors(of node: Int) -> [Int] {
        edges.compactMap { $0.a == node ? $0.b : ($0.b == node ? $0.a : nil) }.sorted()
    }

    func isCorrect(_ path: [Int]) -> Bool { path == expectedPath }

    func matchingSegments(in path: [Int]) -> Int {
        Set(zip(path, path.dropFirst()).map { Edge($0.0, $0.1) }).intersection(expectedEdges).count
    }

    /// Rebuild uniform streets so neither original segmentation, feature types,
    /// names nor feedback can reveal the hidden answer during reconstruction.
    func drawingDocument(path: [Int]) -> TactileMapDocument {
        var features = edges.sorted { $0.a == $1.a ? $0.b < $1.b : $0.a < $1.a }.map { edge in
            MapElement(id: "street-\(edge.a)-\(edge.b)", elementType: TactileElementType(rawValue: "offRoute"),
                       geometry: .lineString([nodes[edge.a], nodes[edge.b]]),
                       properties: TactileProperties(name: "Street"))
        }
        for (index, pair) in zip(path, path.dropFirst()).enumerated() {
            guard nodes.indices.contains(pair.0), nodes.indices.contains(pair.1),
                  edges.contains(Edge(pair.0, pair.1)) else { continue }
            features.append(MapElement(id: "drawn-\(index)", elementType: TactileElementType(rawValue: "onRoute"),
                                       geometry: .lineString([nodes[pair.0], nodes[pair.1]]),
                                       properties: TactileProperties(name: "Your route")))
        }
        for (type, node) in [("start", start), ("end", end)] {
            features.append(MapElement(id: type, elementType: TactileElementType(rawValue: type),
                                       geometry: .point(nodes[node]),
                                       properties: TactileProperties(name: type.capitalized)))
        }
        return TactileMapDocument(bounds: document.bounds, features: features)
    }
}

struct DemoRouteDraft {
    private(set) var path: [Int]

    init(graph: DemoRouteGraph) { path = [graph.start] }

    @discardableResult
    mutating func extend(to node: Int, in graph: DemoRouteGraph) -> Bool {
        guard let last = path.last, last != graph.end, !path.contains(node),
              graph.edges.contains(DemoRouteGraph.Edge(last, node)) else { return false }
        path.append(node)
        return true
    }

    mutating func undo() { if path.count > 1 { path.removeLast() } }
    mutating func clear() { path = Array(path.prefix(1)) }
}

/// Monotonic elapsed time includes both exploration and drawing, including time
/// spent with the app in the background. Results freeze on the first submission.
struct DemoChallenge {
    enum Phase { case exploring, blind, drawing, results }
    struct Result {
        let correct: Bool
        let elapsed: TimeInterval
        let matchedSegments: Int
        let requiredSegments: Int
        let drawnSegments: Int
    }

    private(set) var phase: Phase = .exploring
    private(set) var result: Result?
    private var startedAt: TimeInterval?

    mutating func begin(now: TimeInterval) {
        guard phase == .exploring else { return }
        startedAt = now
        result = nil
        phase = .blind
    }

    mutating func beginDrawing() { if phase == .blind { phase = .drawing } }

    mutating func submit(path: [Int], graph: DemoRouteGraph, now: TimeInterval) {
        guard phase == .drawing, let startedAt else { return }
        result = Result(correct: graph.isCorrect(path), elapsed: max(0, now - startedAt),
                        matchedSegments: graph.matchingSegments(in: path),
                        requiredSegments: graph.expectedEdges.count, drawnSegments: max(0, path.count - 1))
        phase = .results
    }

    mutating func finish() {
        guard phase == .results else { return }
        self = DemoChallenge()
    }
}

struct DemoMapDeck {
    let maps: [String]
    private var remaining: [String] = []

    init(maps: [String]) {
        precondition(!maps.isEmpty)
        self.maps = maps
    }

    mutating func next(excluding current: String?) -> String {
        if remaining.isEmpty { remaining = maps.shuffled() }
        if let index = remaining.firstIndex(where: { $0 != current }) { return remaining.remove(at: index) }
        // The sole remaining card can be the map just displayed after a reset.
        // Begin a new deck in that case, still avoiding an immediate repeat.
        remaining = maps.shuffled()
        let index = remaining.firstIndex(where: { $0 != current }) ?? 0
        return remaining.remove(at: index)
    }
}

/// Mirrors the package's aspect-fit canvas transform for route drawing hits.
struct DemoCanvasTransform {
    let scale: Double
    let offsetX: Double
    let offsetY: Double

    init(bounds: TactileMapBounds, size: CGSize, padding: CGFloat) {
        scale = max(0.001, min((Double(size.width) - 2 * Double(padding)) / bounds.width,
                               (Double(size.height) - 2 * Double(padding)) / bounds.height))
        offsetX = (Double(size.width) - bounds.width * scale) / 2
        offsetY = (Double(size.height) - bounds.height * scale) / 2
    }

    func screenPoint(_ coordinate: TactileCoordinate) -> CGPoint {
        CGPoint(x: coordinate.x * scale + offsetX, y: coordinate.y * scale + offsetY)
    }

    func distance(from point: CGPoint, to coordinate: TactileCoordinate) -> Double {
        let target = screenPoint(coordinate)
        return hypot(Double(point.x - target.x), Double(point.y - target.y))
    }
}

enum DemoRouteDrawing {
    static func nextNode(at point: CGPoint, path: [Int], graph: DemoRouteGraph,
                         transform: DemoCanvasTransform) -> Int? {
        guard let tip = path.last, tip != graph.end else { return nil }
        let origin = transform.screenPoint(graph.nodes[tip])
        return graph.neighbors(of: tip).filter { !path.contains($0) }.first { node in
            let target = transform.screenPoint(graph.nodes[node])
            let projection = project(point, from: origin, to: target)
            // A small tolerance makes touching a junction comfortable. Beyond
            // it, only continue if the finger is still aligned with that street.
            let tolerance = min(24.0, projection.length * 0.28)
            return projection.distance <= tolerance && projection.along >= projection.length - tolerance
        }
    }

    static func preview(at point: CGPoint, path: [Int], graph: DemoRouteGraph,
                        transform: DemoCanvasTransform) -> CGPoint? {
        guard let tip = path.last, tip != graph.end else { return nil }
        let origin = transform.screenPoint(graph.nodes[tip])
        let candidates = graph.neighbors(of: tip).filter { !path.contains($0) }.compactMap { node -> (CGPoint, Double)? in
            let target = transform.screenPoint(graph.nodes[node])
            let projection = project(point, from: origin, to: target)
            guard projection.along > 0, projection.distance <= 32 else { return nil }
            let fraction = min(1, projection.along / projection.length)
            return (CGPoint(x: Double(origin.x) + Double(target.x - origin.x) * fraction,
                            y: Double(origin.y) + Double(target.y - origin.y) * fraction), projection.distance)
        }
        return candidates.min { $0.1 < $1.1 }?.0
    }

    private static func project(_ point: CGPoint, from a: CGPoint, to b: CGPoint)
        -> (along: Double, distance: Double, length: Double) {
        let dx = Double(b.x - a.x), dy = Double(b.y - a.y)
        let length = hypot(dx, dy)
        guard length > 0 else { return (0, .infinity, 0) }
        let px = Double(point.x - a.x), py = Double(point.y - a.y)
        return ((px * dx + py * dy) / length, abs(px * dy - py * dx) / length, length)
    }
}
