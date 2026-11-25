# Project-MultiNav-Demo

Standalone MultiNav demo for iOS 17.6 or later. Includes random map exploration,
intersection views, default exploration haptics, blind-mode route reconstruction,
and timed pass/fail results. No participant entry, questionnaires, Firebase or MOBO.

Open **MultiNav Demo.xcodeproj** in Xcode, select the **MultiNav Demo** scheme and
your iPhone, choose your signing team if needed, then build and run.

This folder contains all app sources and bundled resources: five demo Swift files,
six shared map/feedback Swift files, 66 map JSON files, and the asset catalog.
The `Project MultiNav App/` subfolder is a local copy of those required resources;
the original study-app folder is not needed. Xcode fetches the pinned tactile-map
Swift package on the first build. The installed app works offline.

Check that the folder is complete with Python:

```sh
python tools/check_demo.py --resources-only
```

See [Demo app](docs/Demo-app.md) for controls, build instructions, and full tests.
Physical iPhone testing is needed to verify haptics; Windows cannot build iOS apps.
