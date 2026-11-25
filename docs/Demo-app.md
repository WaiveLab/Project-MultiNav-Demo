# MultiNav Demo

The demo is a separate iOS app in `MultiNav Demo.xcodeproj`, with the shared
scheme **MultiNav Demo**, display name **MultiNav Demo**, and bundle identifier
`waivelab.multinav.demo`. The study app keeps its existing project and identity.
The demo requires iOS 17.6 or later, matching the study app's target setting.

## Build and install

1. On a Mac, open `MultiNav Demo.xcodeproj` in Xcode.
2. Select the **MultiNav Demo** scheme and your connected iPhone.
3. Under Signing & Capabilities, select your development team if necessary.
4. Build and run. No Firebase configuration or participant registration is needed.

Xcode downloads the tactile-map Swift package for the first build. The project
pins the same revision recorded in the study project's current lockfile. After
installation the demo works offline. Use a physical iPhone to verify vibrations;
the simulator can check screens and route drawing but cannot reproduce haptics.

For a simulator build from Terminal:

```sh
xcodebuild -project "MultiNav Demo.xcodeproj" -scheme "MultiNav Demo" \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

## Controls

- Launch goes directly to a randomly selected overview. **Next map** (top-right
  arrow) cycles through a shuffled deck of all 17 study maps without immediate
  repeats, reshuffling when exhausted.
- Explore with the same touch, speech and default burst vibrations as the study
  app. Double-tap an on-route intersection to open its detail view. Use the
  top-left back arrow, the existing three-finger right swipe, or double-tap the
  detail's end marker to return to the overview.
- **Blind mode** chooses a different map and starts the timer. The screen is
  black with the top-right checkmark visible. In an intersection view, a white
  top-left back arrow returns to the covered overview while staying in blind mode.
  The covered map remains interactive, including the three-finger back gesture.
- The first checkmark opens reconstruction of that same overview. The street
  grid is neutral; only start (**S**) and end (**E**) markers are shown. Drag
  from S to adjacent intersections, continuing from the tip after lifting your
  finger. Segments snap to the street grid. You can also draw continuously.
  Use **Clear route** to restart drawing. The drawing screen has no instruction
  text below the map and no Undo button. The **Draw route** title is centered,
  with the submission checkmark at the top right.
  VoiceOver provides directional actions to extend the route.
- The second checkmark submits the route, including an incomplete route if the
  user chooses. A pass requires the exact ordered route from start to end, not
  merely reaching the destination. The results show pass/fail, matched and drawn
  segments, and elapsed time from entering blind mode through submission.
  Failed attempts also show just the street grid and highlighted correct route,
  without landmarks, intersection symbols, or start/end markers. This preview
  appears only after submission.
- **Finish** returns to visible exploration of the completed challenge's map
  after either outcome. Next map and a fresh blind challenge remain available.

The timer continues while backgrounded and freezes at submission. Feedback stops
when leaving an interactive map, changing maps, or backgrounding the app.
Attempts and results are kept in memory only; relaunching starts fresh.

## Standalone files and isolation

This folder includes local copies of `MapAppearance.swift`, `MapFeedback.swift`,
`MapCatalog.swift`, `ParameterSet.swift`, `StudyMapLayout.swift`, and
`StudyMapSpeech.swift`, plus the complete map and asset directories under
`Project MultiNav App/`. That directory name preserves the existing Xcode
references; these are local demo dependencies, not a link to the study app.
The five demo screens/session sources live under `MultiNav Demo/`.

No files from the original app folder are needed to open or build this project.
Xcode resolves the pinned tactile-map package from GitHub on the first build.

The demo project links only TactileMapCore, TactileMapFeedback and TactileMapView.
It includes no Firebase SDKs or configuration, StudySession, database integration,
login, surveys, or study result uploads. Reconstruction rebuilds the streets from
their geometry and supplies no hidden-route feedback.

If files are added to the demo, or map resources change, regenerate the explicit
project references with `python tools/generate_demo_project.py`.

## Validation

From this folder, verify every referenced source, map, intersection overlay,
and asset using Python (no Swift installation required):

```sh
python tools/check_demo.py --resources-only
```

To compile the portable model tests, also install Swift and supply a checkout of
the tactile-map package (the package's `Package.swift` is at that checkout root):

```sh
python tools/check_demo.py --library /path/to/ProjectMultiNav
```

This extra checkout is only used by the portable test harness. Xcode downloads
its own package dependency when building the iOS app.

The portable demo checks compile and run the actual route and session models
against all 17 maps. They cover connected drawing, incorrect and incomplete
routes, undo/clear, drawing without answer cues, screen-coordinate snapping,
fast straight drags, timing, shuffled maps, intersection resource loading,
full pass/fail/finish flows, and load-error recovery. They also parse the Swift UI
source and check the independent project configuration. Portable checks cannot
type-check SwiftUI/UIKit or replace an Xcode build and physical-device review.

Before showing the app, verify on an iPhone:

1. Launch in airplane mode, explore, open an intersection, return, and change maps.
2. Enter blind mode and confirm the entire map stays black during touches and
   intersection changes. The checkmark remains visible; intersection views also
   show a white back arrow that returns to the overview without revealing it or
   resetting the challenge timer.
3. Leave the map in an intersection view, tap the checkmark, and confirm the
   reconstruction is the corresponding overview with no original route shown.
4. Draw a route over multiple drags, clear it, submit a correct route and a
   different or incomplete route, and check the corresponding results. Confirm
   only failed attempts show the correct-route map and that Finish remains reachable.
5. Confirm Finish returns to exploration after both outcomes and the next blind
   attempt uses a different map with a fresh timer.
6. Check VoiceOver, small/large devices, iPad rotation, background/resume, and
   that no haptics or speech continue onto drawing/results screens.
