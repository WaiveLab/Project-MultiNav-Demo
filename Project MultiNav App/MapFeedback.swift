import Combine
import Foundation
import AVFAudio
import TactileMapCore
import TactileMapFeedback

extension OptimizedSpatialPolicy: ObservableObject {
    convenience init(studyParameters: ParameterSet?) {
        // The speech engine configures the shared audio session for play-and-record.
        // Allow haptics on that session before starting the map's haptic engine.
        let audio = AVSpatialAudioEngine()
        do {
            try AVAudioSession.sharedInstance().setAllowHapticsAndSystemSoundsDuringRecording(true)
        } catch {
            NSLog("Could not enable map haptics on the audio session: %@", error.localizedDescription)
        }
        self.init(studyParameters: studyParameters, hapticEngine: CoreHapticsEngine(), audioEngine: audio)
    }
}

// MARK: Custom Element Types
extension TactileElementType {
    ///Overview elements:
    static let onRoute = TactileElementType(rawValue: "onRoute")
    static let offRoute = TactileElementType(rawValue: "offRoute")
    static let onRouteIntersection = TactileElementType(rawValue: "onRouteIntersection")
    static let offRouteIntersection = TactileElementType(rawValue: "offRouteIntersection")
    static let start = TactileElementType(rawValue: "start")
    static let end = TactileElementType(rawValue: "end")

    ///Zoomed in elements:
    static let street = TactileElementType(rawValue: "street")
    static let onRouteSidewalk = TactileElementType(rawValue: "onRouteSidewalk")
    static let offRouteSidewalk = TactileElementType(rawValue: "offRouteSidewalk")
    static let onRouteCrosswalk = TactileElementType(rawValue: "onRouteCrosswalk")
    static let offRouteCrosswalk = TactileElementType(rawValue: "offRouteCrosswalk")
    static let turn = TactileElementType(rawValue: "turn")
    static let intersectionCenter = TactileElementType(rawValue: "intersectionCenter")
}



// MARK: Feedback Policy

/// The package calls stopAll on finger lift. End touch-driven vibration there,
/// but let the current audio cue finish. Map/screen exits still call the real
/// policy's stopAll to silence every channel.
@MainActor
final class ExplorationTouchFeedback: FeedbackPolicy {
    let policy: OptimizedSpatialPolicy

    init(policy: OptimizedSpatialPolicy) { self.policy = policy }

    func onEnter(element: any TactileMapElement, touchType: TouchType) {
        policy.onEnter(element: element, touchType: touchType)
    }

    func onContinue(element: any TactileMapElement, touchType: TouchType) {
        policy.onContinue(element: element, touchType: touchType)
    }

    func onExit(element: any TactileMapElement) { policy.onExit(element: element) }

    func onTap(element: any TactileMapElement, touchType: TouchType) {
        policy.onTap(element: element, touchType: touchType)
    }

    func stopAll() { policy.hapticEngine.stopAll() }
}

/// Plays the practice baseline or the active round's profiles. Each element
/// gets its burst profile from its `HapticPat` element type.
@MainActor
class OptimizedSpatialPolicy: DefaultFeedbackPolicy {
    
    // MARK: Speech config
    let config = SpeechConfiguration(rate: 0.65, volume: 1.0, language: "en-US", pitchMultiplier: 1.0)

    let toneGen = ToneGenerator()

    private let parameters: ParameterSet
    private let isPractice: Bool

    init(studyParameters: ParameterSet?, hapticEngine: HapticEngine, audioEngine: SpatialAudioEngine) {
        isPractice = studyParameters == nil
        parameters = studyParameters ?? ParameterSet()
        super.init(hapticEngine: hapticEngine, audioEngine: audioEngine)
    }

    /// Hook for the session (behavioral measurement — detects when the
    /// finger reaches the round's destination).
    var onElementEntered: ((any TactileMapElement) -> Void)?

    override func onEnter(element: any TactileMapElement, touchType: TouchType) {
        // Replace the previous cue even when the new element has no speech.
        audioEngine.stopAll()
        toneGen.stop()
        onElementEntered?(element)

        let name = StudyMapSpeech.label(type: element.elementType.rawValue,
                                        name: element.properties.name)
        let optimizedType = HapticPat(rawValue: element.elementType.rawValue)

        if let optimizedType {
            hapticEngine.start(pattern: parameters.hapticPattern(for: optimizedType))
            if isPractice && !hapticEngine.isPlaying {
                // Give the first touch feedback even if the looping player failed.
                playPracticeTap(for: optimizedType)
            }
        }

        switch element.elementType {
        // Haptics are selected independently above. This switch preserves
        // the speech and tones associated with each semantic element.
        case .onRoute, .onRouteSidewalk:
            audioEngine.speak(name, configuration: config)

        case .start:
            audioEngine.speak(name, configuration: config)

        case .offRoute:
            audioEngine.speak(name, configuration: config)

        case .onRouteIntersection:
            audioEngine.speak(name, configuration: config)

        case .offRouteIntersection:
            audioEngine.speak("This intersection is not on your route.", configuration: config)

        case .landmark:
            audioEngine.speak(name, configuration: config)

        case .end:
            audioEngine.speak(name, configuration: config)
//            if isZoomed {
//                audioEngine.speak("Double tap to exit", configuration: config)
//            }

        // ── Zoomed-in view ──
        case .street:
            audioEngine.speak(name, configuration: config)

        case .offRouteSidewalk:
            audioEngine.speak(name, configuration: config)

        case .onRouteCrosswalk:
            toneGen.playRepeatingTone(frequency: 300, duration: 0.05, interval: 0.50, count: 15)
            audioEngine.speak(name, configuration: config)

        case .offRouteCrosswalk:
            toneGen.playRepeatingTone(frequency: 200, duration: 0.05, interval: 0.17, count: 100)
            audioEngine.speak(name, configuration: config)
            
        default:
            audioEngine.speak(name, configuration: config)
        }
    }

    /// A discrete tap can arrive after finger lift. Give it one pulse from the
    /// practice profile, so it cannot leave a repeating vibration running.
    override func onTap(element: any TactileMapElement, touchType: TouchType) {
        audioEngine.stopAll()
        toneGen.stop()
        if isPractice, !hapticEngine.isPlaying, let type = HapticPat(rawValue: element.elementType.rawValue) {
            playPracticeTap(for: type)
        }
        audioEngine.speak(StudyMapSpeech.label(type: element.elementType.rawValue,
                                              name: element.properties.name), configuration: config)
    }

    private func playPracticeTap(for type: HapticPat) {
        let cue = parameters.burstParameters(for: type)
        hapticEngine.start(pattern: HapticPattern(intensity: Float(cue.intensity),
                                                  sharpness: Float(cue.sharpness), mode: .transient))
    }

    override func stopAll() {
        super.stopAll()
        toneGen.stop()
    }
    
    // Audio is one-shot per entry and may finish across empty space/finger lift.
    // Only vibration stops here; the next entry or map/screen exit stops audio.
    override func onExit(element: any TactileMapElement) {
        hapticEngine.stopAll()
    }

    /// Restart any optimized type's own burst when its cycle finishes while
    /// the finger remains on that element.
    override func onContinue(element: any TactileMapElement, touchType: TouchType) {
        guard !hapticEngine.isPlaying,
              let optimizedType = HapticPat(rawValue: element.elementType.rawValue)
        else {
            return
        }

        hapticEngine.start(pattern: parameters.hapticPattern(for: optimizedType))
    }
}
