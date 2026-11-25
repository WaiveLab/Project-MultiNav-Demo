import SwiftUI
import UIKit
import TactileMapCore
import TactileMapFeedback
import TactileMapView

struct DemoRootView: View {
    @StateObject private var session = DemoSession()
    // Fixed exploration baseline for every map; there is no optimizer session.
    @StateObject private var policy = OptimizedSpatialPolicy(studyParameters: ParameterSet())
    @Environment(\.scenePhase) private var scenePhase

    private var isBlind: Bool { session.challenge.phase == .blind }

    var body: some View {
        Group {
            if session.challenge.phase == .results, let result = session.challenge.result {
                DemoResultsView(result: result, onFinish: session.finish)
            } else {
                VStack(spacing: 0) {
                    header
                    if session.overview == nil {
                        ContentUnavailableView {
                            Label("Map unavailable", systemImage: "map")
                        } description: {
                            Text("The bundled map could not be opened.")
                        } actions: {
                            Button("Try another map", action: session.nextMap)
                        }
                    } else if session.challenge.phase == .drawing, let graph = session.graph {
                        DemoDrawingView(session: session, graph: graph)
                        drawingFooter
                    } else {
                        explorationCanvas
                    }
                }
            }
        }
        .background(isBlind ? Color.black : Color.white)
        .preferredColorScheme(.light)
        .statusBarHidden(isBlind)
        .persistentSystemOverlays(isBlind ? .hidden : .automatic)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { policy.stopAll() }
        }
        .onChange(of: session.challenge.phase) { _, _ in policy.stopAll() }
        .onDisappear { policy.stopAll() }
        .alert("Could not open map", isPresented: Binding(
            get: { session.error != nil }, set: { if !$0 { session.error = nil } }
        )) {
            Button("OK", role: .cancel) { session.error = nil }
        } message: { Text(session.error ?? "") }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if isBlind {
                Spacer()
                iconButton("checkmark", label: "Finish blind exploration and draw the route") {
                    policy.stopAll()
                    session.beginDrawing()
                }
                .foregroundStyle(.white)
            } else if session.challenge.phase == .drawing {
                iconButton("arrow.uturn.backward", label: "Undo last segment", action: session.undo)
                    .disabled((session.draft?.path.count ?? 0) <= 1)
                Text("Draw route").font(.headline)
                Spacer()
                iconButton("checkmark", label: "Check my route", action: session.submit)
            } else {
                if session.isZoomed {
                    iconButton("arrow.left", label: "Back to overview") {
                        policy.stopAll()
                        session.backToOverview()
                    }
                    Text("Intersection").font(.headline)
                    Spacer()
                } else {
                    Button {
                        policy.stopAll()
                        session.beginBlind()
                    } label: {
                        Label("Blind mode", systemImage: "eye.slash")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .background(Color.blue.opacity(0.09), in: Capsule())
                    }
                    .accessibilityHint("Starts a timed challenge on a different map. The screen will be blank. Explore by touch, then use the checkmark to draw your remembered route.")
                    .disabled(session.overview == nil)
                    Spacer()
                    iconButton("arrow.right", label: "Next map") {
                        policy.stopAll()
                        session.nextMap()
                    }
                }
            }
        }
        .foregroundStyle(isBlind ? Color.white : Color(UIColor(red: 2 / 255, green: 62 / 255, blue: 138 / 255, alpha: 1)))
        .padding(.horizontal, 12)
        .frame(height: 56)
        .background(isBlind ? Color.black : Color.white)
    }

    private var explorationCanvas: some View {
        let configuration = MapAppearance.configuration(isZoomed: session.isZoomed)
        let layers = session.layers
        return GeometryReader { canvas in
            let padding = configuration.canvasPadding
            let contentSize = CGSize(width: canvas.size.width - 2 * padding,
                                     height: canvas.size.height - 2 * padding)
            let fitted = StudyMapLayout.fittedLayers(layers,
                intersectionContentSize: session.isZoomed ? contentSize : nil)
            TactileMapView(
                layers: StudyMapLayout.withCrosswalkStripes(fitted),
                configuration: configuration,
                feedbackPolicy: ExplorationTouchFeedback(policy: policy),
                onBackGesture: {
                    policy.stopAll()
                    session.backToOverview()
                },
                onDoubleTap: { element in
                    policy.stopAll()
                    session.openIntersection(element)
                }
            )
            // An opaque, non-interactive cover preserves all touch handling below
            // it, including the existing three-finger back gesture in blind mode.
            .overlay {
                if isBlind {
                    Color.black.allowsHitTesting(false).accessibilityHidden(true)
                }
            }
        }
        .id(layers.map(\.id))
        .task(id: layers.map(\.id)) {
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            guard !Task.isCancelled,
                  session.challenge.phase == .exploring || session.challenge.phase == .blind else { return }
            let announcement = session.isZoomed ? "Intersection view" : "Route overview"
            if UIAccessibility.isVoiceOverRunning {
                UIAccessibility.post(notification: .announcement, argument: announcement)
            } else {
                policy.audioEngine.speak(announcement, configuration: policy.config)
            }
        }
    }

    private var drawingFooter: some View {
        VStack(spacing: 8) {
            Text(session.draft?.path.last == session.graph?.end
                 ? "At the end. Tap the checkmark when you’re ready."
                 : "Drag from S through the intersections to E. Lift and continue from your route’s tip.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
            Button("Clear route", action: session.clear)
                .frame(minHeight: 44)
                .disabled((session.draft?.path.count ?? 0) <= 1)
        }
        .padding(.horizontal)
        .padding(.bottom, 4)
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }
}

private struct DemoResultsView: View {
    let result: DemoChallenge.Result
    let onFinish: () -> Void

    private var elapsed: String {
        let seconds = Int(result.elapsed.rounded(.down))
        return "\(seconds / 60)m \(seconds % 60)s"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: result.correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(result.correct ? Color.green : Color.orange)
                    .accessibilityHidden(true)
                Text(result.correct ? "Route matched!" : "Route didn’t match")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(result.correct
                     ? "You reconstructed the route you explored in blind mode."
                     : "Your route was different from the one you explored. Explore some more, then try another blind challenge.")
                    .multilineTextAlignment(.center)
                VStack(spacing: 16) {
                    stat(result.correct ? "Time to solve" : "Attempt time", value: elapsed)
                    stat("Correct route segments", value: "\(result.matchedSegments) of \(result.requiredSegments)")
                    stat("Segments drawn", value: "\(result.drawnSegments)")
                }
                .padding(20)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
                Text("Time includes blind exploration and route drawing.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Finish", action: onFinish)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityHint("Returns to visible map exploration.")
            }
            .frame(maxWidth: 480)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.center)
    }

    private func stat(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).fontWeight(.semibold).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}
