import Combine
import Foundation
import TactileMapCore

@MainActor
final class DemoSession: ObservableObject {
    @Published private(set) var challenge = DemoChallenge()
    @Published private(set) var mapName = ""
    @Published private(set) var overview: TactileMapDocument?
    @Published private(set) var graph: DemoRouteGraph?
    @Published private(set) var draft: DemoRouteDraft?
    @Published private(set) var intersection: [TactileMapLayer]?
    @Published var error: String?

    private var deck = DemoMapDeck(maps: MapCatalog.overviews)
    private let loadDocument: (String) throws -> TactileMapDocument
    private let now: () -> TimeInterval

    init(loadDocument: @escaping (String) throws -> TactileMapDocument = {
        try TactileMapDocument.load(from: $0, bundle: .main)
    }, now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.loadDocument = loadDocument
        self.now = now
        loadNextMap()
    }

    var isZoomed: Bool { intersection != nil }
    var layers: [TactileMapLayer] {
        if let intersection { return intersection }
        guard let overview else { return [] }
        return [TactileMapLayer(id: "overview:\(mapName)", document: overview, isInteractable: true)]
    }

    func nextMap() {
        guard challenge.phase == .exploring else { return }
        loadNextMap()
    }

    func beginBlind() {
        guard challenge.phase == .exploring else { return }
        let startedAt = now()
        guard loadNextMap() else { return }
        challenge.begin(now: startedAt)
    }

    func beginDrawing() {
        guard challenge.phase == .blind else { return }
        intersection = nil
        challenge.beginDrawing()
    }

    func submit() {
        guard let graph, let draft else { return }
        challenge.submit(path: draft.path, graph: graph, now: now())
    }

    func finish() {
        guard challenge.phase == .results else { return }
        challenge.finish()
        intersection = nil
        // Keep the completed challenge visible for a natural return to exploration.
        if let graph { draft = DemoRouteDraft(graph: graph) }
    }

    @discardableResult
    func extendRoute(to node: Int) -> Bool {
        guard challenge.phase == .drawing, let graph else { return false }
        return draft?.extend(to: node, in: graph) ?? false
    }

    func undo() { if challenge.phase == .drawing { draft?.undo() } }
    func clear() { if challenge.phase == .drawing { draft?.clear() } }

    func openIntersection(_ element: any TactileMapElement) {
        guard challenge.phase == .exploring || challenge.phase == .blind else { return }
        if element.elementType.rawValue == "end" { backToOverview(); return }
        guard !isZoomed, element.elementType.rawValue == "onRouteIntersection" else { return }
        do {
            let name = element.properties.name
            let base = try loadDocument(name)
            let routeName = "\(mapName)__\(name)_route"
            let route = try loadDocument(routeName)
            intersection = [
                TactileMapLayer(id: "base:\(name)", document: base, isInteractable: true),
                TactileMapLayer(id: "route:\(routeName)", document: route, isInteractable: true),
            ]
        } catch { self.error = error.localizedDescription }
    }

    func backToOverview() { intersection = nil }

    @discardableResult
    private func loadNextMap() -> Bool {
        let name = deck.next(excluding: mapName)
        do {
            let document = try loadDocument(name)
            let fitted = StudyMapLayout.fittedLayers([
                TactileMapLayer(id: name, document: document, isInteractable: true)
            ])[0].document
            let graph = try DemoRouteGraph(document: fitted)
            // Publish only once every resource needed for this challenge is valid.
            self.graph = graph
            draft = DemoRouteDraft(graph: graph)
            overview = document
            intersection = nil
            mapName = name
            error = nil
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}
