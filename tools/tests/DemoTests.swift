import Foundation

// Minimal observation stand-ins for portable tests; production uses Combine.
protocol ObservableObject: AnyObject {}
@propertyWrapper struct Published<Value> {
    var wrappedValue: Value
    init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
}

@main
struct DemoTests {
    @MainActor
    static func main() throws {
        let maps = URL(fileURLWithPath: CommandLine.arguments[1])
        func load(_ name: String) throws -> TactileMapDocument {
            let folder = MapCatalog.overviews.contains(name) ? "overviews" : "intersection_views"
            let data = try Data(contentsOf: maps.appendingPathComponent(folder).appendingPathComponent(name + ".json"))
            return try JSONDecoder().decode(TactileMapDocument.self, from: data)
        }

        for name in MapCatalog.overviews {
            let overview = try load(name)
            let fitted = StudyMapLayout.fittedLayers([TactileMapLayer(id: name, document: overview)])[0].document
            let graph = try DemoRouteGraph(document: fitted)
            precondition(graph.nodes.count == 12 && graph.edges.count == 17, "Incomplete grid: \(name)")
            precondition(graph.expectedPath.count == 4 && graph.expectedEdges.count == 3)

            var draft = DemoRouteDraft(graph: graph)
            precondition(!graph.isCorrect(draft.path))
            precondition(!draft.extend(to: graph.start, in: graph))
            let nonNeighbor = graph.nodes.indices.first {
                $0 != graph.start && !graph.neighbors(of: graph.start).contains($0)
            }!
            precondition(!draft.extend(to: nonNeighbor, in: graph), "Must not jump across blocks")
            for node in graph.expectedPath.dropFirst() { precondition(draft.extend(to: node, in: graph)) }
            precondition(graph.isCorrect(draft.path))
            precondition(graph.matchingSegments(in: draft.path) == 3)
            precondition(!draft.extend(to: graph.neighbors(of: graph.end)[0], in: graph), "Stop at destination")
            precondition(!graph.isCorrect(Array(draft.path.reversed())))
            func alternative(_ path: [Int]) -> [Int]? {
                let tip = path.last!
                if tip == graph.end { return path == graph.expectedPath ? nil : path }
                for next in graph.neighbors(of: tip) where !path.contains(next) {
                    if let route = alternative(path + [next]) { return route }
                }
                return nil
            }
            let wrongRoute = alternative([graph.start])!
            var wrongDraft = DemoRouteDraft(graph: graph)
            for next in wrongRoute.dropFirst() { precondition(wrongDraft.extend(to: next, in: graph)) }
            precondition(wrongDraft.path.last == graph.end && !graph.isCorrect(wrongDraft.path),
                         "Reaching the end along different streets must fail")
            draft.undo()
            precondition(draft.path.count == 3 && !graph.isCorrect(draft.path))
            draft.clear()
            draft.undo()
            precondition(draft.path == [graph.start])

            // The drawing canvas must contain no original route cues or landmarks.
            let blank = graph.drawingDocument(path: draft.path)
            precondition(blank.features.count == 19)
            precondition(blank.features.filter { $0.elementType.rawValue == "offRoute" }.count == 17)
            precondition(blank.features.allSatisfy { ["start", "end", "offRoute"].contains($0.elementType.rawValue) })
            precondition(blank.features.filter { $0.elementType.rawValue == "offRoute" }.allSatisfy { $0.properties.name == "Street" })
            let drawn = graph.drawingDocument(path: graph.expectedPath)
            precondition(drawn.features.filter { $0.elementType.rawValue == "onRoute" }.count == 3)

            for size in [CGSize(width: 320, height: 480), CGSize(width: 393, height: 650),
                         CGSize(width: 1024, height: 700)] {
                let transform = DemoCanvasTransform(bounds: graph.document.bounds, size: size, padding: 30)
                for node in graph.nodes {
                    let point = transform.screenPoint(node)
                    precondition(point.x >= 29.9 && point.y >= 29.9)
                    precondition(point.x <= size.width - 29.9 && point.y <= size.height - 29.9)
                    precondition(transform.distance(from: point, to: node) < 0.001)
                }
                var traced = [graph.start]
                for next in graph.expectedPath.dropFirst() {
                    let point = transform.screenPoint(graph.nodes[next])
                    precondition(DemoRouteDrawing.nextNode(at: point, path: traced, graph: graph, transform: transform) == next)
                    traced.append(next)
                }
                precondition(DemoRouteDrawing.nextNode(at: .zero, path: traced, graph: graph, transform: transform) == nil)
            }

            var challenge = DemoChallenge()
            challenge.submit(path: graph.expectedPath, graph: graph, now: 1)
            precondition(challenge.phase == .exploring && challenge.result == nil)
            challenge.begin(now: 100)
            challenge.begin(now: 110) // Cannot restart the clock by entering twice.
            challenge.beginDrawing()
            challenge.submit(path: graph.expectedPath, graph: graph, now: 145)
            precondition(challenge.phase == .results && challenge.result?.correct == true)
            precondition(challenge.result?.elapsed == 45)
            challenge.submit(path: [], graph: graph, now: 200)
            precondition(challenge.result?.elapsed == 45 && challenge.result?.correct == true)
            challenge.finish()
            precondition(challenge.phase == .exploring && challenge.result == nil)
            challenge.begin(now: 200)
            challenge.beginDrawing()
            challenge.submit(path: wrongDraft.path, graph: graph, now: 230)
            precondition(challenge.result?.correct == false && challenge.result?.elapsed == 30)
            challenge.finish()
            precondition(challenge.phase == .exploring)

            for intersection in overview.features where intersection.elementType.rawValue == "onRouteIntersection" {
                _ = try load(intersection.properties.name)
                _ = try load("\(name)__\(intersection.properties.name)_route")
            }
        }

        // Fast straight drags traverse intermediate nodes without skipping them.
        let straight = try DemoRouteGraph(document: load("map14_storybook"))
        let transform = DemoCanvasTransform(bounds: straight.document.bounds, size: CGSize(width: 393, height: 650), padding: 30)
        let destination = transform.screenPoint(straight.nodes[straight.end])
        var fastPath = [straight.start]
        while let next = DemoRouteDrawing.nextNode(at: destination, path: fastPath, graph: straight, transform: transform) {
            fastPath.append(next)
        }
        precondition(straight.isCorrect(fastPath))
        let diagonal = CGPoint(x: destination.x + 150, y: destination.y)
        precondition(DemoRouteDrawing.nextNode(at: diagonal, path: [straight.start], graph: straight, transform: transform) == nil)

        // Each shuffled deck visits all maps; crossing a deck boundary never repeats.
        var deck = DemoMapDeck(maps: MapCatalog.overviews)
        var previous: String?
        for _ in 0..<10 {
            var visited: Set<String> = []
            for _ in MapCatalog.overviews {
                let next = deck.next(excluding: previous)
                precondition(next != previous)
                precondition(visited.insert(next).inserted)
                previous = next
            }
            precondition(visited == Set(MapCatalog.overviews))
        }

        // Exercise the actual session with bundled documents and a controlled clock.
        var time: TimeInterval = 10
        var failLoads = false
        let session = DemoSession(loadDocument: { name in
            if failLoads { throw DemoRouteGraph.InvalidMap.invalidGrid }
            return try load(name)
        }, now: { time })
        let initial = session.mapName
        precondition(session.challenge.phase == .exploring && session.graph != nil)
        session.beginBlind()
        let hiddenName = session.mapName
        precondition(hiddenName != initial && session.challenge.phase == .blind)
        session.nextMap()
        precondition(session.mapName == hiddenName)
        let onRouteIntersection = session.overview!.features.first { $0.elementType.rawValue == "onRouteIntersection" }!
        session.openIntersection(onRouteIntersection)
        precondition(session.isZoomed && session.layers.count == 2)
        session.backToOverview()
        precondition(!session.isZoomed && session.mapName == hiddenName)
        session.openIntersection(onRouteIntersection)
        time = 25
        session.beginDrawing()
        precondition(!session.isZoomed && session.mapName == hiddenName)
        for node in session.graph!.expectedPath.dropFirst() { precondition(session.extendRoute(to: node)) }
        time = 42
        session.submit()
        precondition(session.challenge.result?.correct == true && session.challenge.result?.elapsed == 32)
        session.finish()
        precondition(session.challenge.phase == .exploring && session.mapName == hiddenName)
        session.beginBlind()
        precondition(session.mapName != hiddenName)
        session.beginDrawing()
        session.submit() // An incomplete route is a failed attempt, not a crash or a win.
        precondition(session.challenge.result?.correct == false)
        session.finish()
        failLoads = true
        let priorName = session.mapName
        session.beginBlind()
        precondition(session.challenge.phase == .exploring && session.mapName == priorName && session.error != nil)
        failLoads = false
        session.nextMap()
        precondition(session.error == nil && session.mapName != priorName)

        print("Demo checks passed: all 17 grids/routes, drawing, timing, shuffled maps, intersection resources, full session flow and load recovery.")
    }
}
