"""Validate standalone demo inputs, then optionally compile portable behavior tests.

Resource check (Python only): python tools/check_demo.py --resources-only
Full check: python tools/check_demo.py --library /path/to/ProjectMultiNav
The --library path is a checkout of the tactile-map Swift package, not the study app.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

from generate_demo_project import project_text, scheme_text

root = Path(__file__).resolve().parents[1]
app = root / "Project MultiNav App"
demo = root / "MultiNav Demo"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--resources-only", action="store_true", help="Verify all project inputs without Swift or the package source checkout")
parser.add_argument("--library", type=Path, default=root / "Library/TactileMapPackageCode",
                    help="Root of the tactile-map Swift package source checkout, for compiled portable tests")
args = parser.parse_args()
env = {k.upper(): v for k, v in os.environ.items()} if os.name == "nt" else dict(os.environ)


def run(command):
    subprocess.run(list(map(str, command)), env=env, check=True)


project_file = root / "MultiNav Demo.xcodeproj/project.pbxproj"
project = project_file.read_text(encoding="utf-8-sig")
references = re.findall(r'isa = PBXFileReference;[^\n]*?path = "([^"]+)"; sourceTree = SOURCE_ROOT;', project)
assert references, "No project inputs found"
for reference in references:
    target = (root / reference).resolve()
    assert target.is_relative_to(root.resolve()), f"Project depends on a file outside this folder: {reference}"
    assert target.exists(), f"Missing project input: {reference}"

swift_files = list(demo.glob("*.swift")) + list(app.glob("*.swift"))
assert len(swift_files) == 11, "Expected five demo sources and six shared map sources"
assert {p.relative_to(root).as_posix() for p in swift_files} == {p for p in references if p.endswith(".swift")}
assert "Firebase" not in project and "GoogleService" not in project and "StudySession.swift" not in project
assert "Survey" not in project and "LoginView" not in project and "DatabaseIntegration" not in project
for source in swift_files:
    assert not re.search(r'^\s*import Firebase', source.read_text(), re.M), f"Unexpected Firebase import: {source.name}"

maps = list((app / "Maps").rglob("*.json"))
assert {p.relative_to(root).as_posix() for p in maps} == {p for p in references if p.endswith(".json")}, "Map resources and project references differ"
assert len({p.name for p in maps}) == len(maps), "Duplicate bundled map filenames"
documents = {p.stem: json.loads(p.read_text(encoding="utf-8-sig")) for p in maps}
catalog = re.findall(r'"(map\d+_\w+)"', (app / "MapCatalog.swift").read_text())
assert len(catalog) == 17 and len(set(catalog)) == 17
for name in catalog:
    assert name in documents, f"Missing overview: {name}"
    overview = documents[name]
    assert any(f["type"] == "start" for f in overview["features"])
    assert any(f["type"] == "end" for f in overview["features"])
    for feature in overview["features"]:
        if feature["type"] == "onRouteIntersection":
            intersection = feature["properties"]["name"]
            for required in (intersection, f"{name}__{intersection}_route"):
                assert required in documents, f"Missing intersection resource: {required}"

for contents in (app / "Assets.xcassets").rglob("Contents.json"):
    def validate_assets(value):
        if isinstance(value, dict):
            if value.get("filename"):
                assert (contents.parent / value["filename"]).is_file(), f"Missing asset: {value['filename']}"
            for child in value.values():
                validate_assets(child)
        elif isinstance(value, list):
            for child in value:
                validate_assets(child)
    validate_assets(json.loads(contents.read_text()))

run([sys.executable, root / "tools/generate_demo_project.py", "--check"])
assert project.replace("\r\n", "\n") == project_text()
scheme = root / "MultiNav Demo.xcodeproj/xcshareddata/xcschemes/MultiNav Demo.xcscheme"
ET.fromstring(scheme.read_text())
assert scheme.read_text() == scheme_text()
if shutil.which("plutil"):
    run(["plutil", "-lint", project_file])
print(f"Verified {len(references)} local project inputs: 11 Swift files, {len(maps)} maps, and the asset catalog. All 17 demo maps and their intersection resources are present.", flush=True)
if args.resources_only:
    raise SystemExit(0)

swift = shutil.which("swiftc")
if not swift:
    raise SystemExit("Resource checks passed. Install Swift for compiled tests, or use --resources-only.")
library = args.library.resolve() / "Sources/TactileMapCore"
if not library.is_dir():
    raise SystemExit("Resource checks passed. Supply --library with the tactile-map package checkout for compiled tests. Xcode resolves this package automatically when building the app.")
run([swift, "-frontend", "-parse", *swift_files])
sources = [library / (name + ".swift") for name in [
    "TactileMapDocument", "TactileMapElement", "TactileProperties", "TactileElementType", "TactileGeometry", "TactileMapLayer",
]]
sources += [app / "StudyMapLayout.swift", app / "MapCatalog.swift", demo / "DemoRoute.swift", demo / "DemoSession.swift",
            root / "tools/tests/DemoTests.swift"]
staging = root / ".codex-validation"
staging.mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix="demo-", dir=staging) as temporary:
    directory = Path(temporary)
    copied = []
    for source in sources:
        text = source.read_text(encoding="utf-8-sig")
        text = text.replace("import TactileMapCore\n", "").replace("import Combine\n", "")
        target = directory / source.name
        target.write_text(text, encoding="utf-8")
        copied.append(target)
    executable = directory / ("demo-tests.exe" if os.name == "nt" else "demo-tests")
    run([swift, "-module-cache-path", directory / "cache", *copied, "-o", executable])
    run([executable, app / "Maps"])
print("Demo Swift syntax, project isolation and portable behavior checks passed. Xcode/device verification remains required.")
