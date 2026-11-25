"""Generate the independent Demo Xcode project from shared sources and map assets.

Run with --check to verify that the checked-in project is up to date.
No Firebase package, configuration, study session or questionnaire is included.
"""
import argparse
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "MultiNav Demo.xcodeproj"


def identifier(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()


def quote(value):
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'


def project_text():
    objects = []

    def add(key, body):
        objects.append(f"\t\t{identifier(key)} = {{ {body} }};")
        return identifier(key)

    def array(items):
        return "(" + "".join(item + ", " for item in items) + ")"

    demo = sorted((ROOT / "MultiNav Demo").glob("*.swift"))
    shared = [ROOT / "Project MultiNav App" / (name + ".swift") for name in [
        "MapAppearance", "MapFeedback", "MapCatalog", "ParameterSet", "StudyMapLayout", "StudyMapSpeech",
    ]]
    resources = sorted((ROOT / "Project MultiNav App/Maps").rglob("*.json"))
    resources += [ROOT / "Project MultiNav App/Assets.xcassets"]
    groups = {"Demo": [], "Shared map code": [], "Maps and assets": []}
    sources, bundled = [], []
    for file in demo + shared + resources:
        path = file.relative_to(ROOT).as_posix()
        kind = {".swift": "sourcecode.swift", ".json": "text.json", ".xcassets": "folder.assetcatalog"}[file.suffix]
        ref = add(path, f"isa = PBXFileReference; lastKnownFileType = {kind}; path = {quote(path)}; sourceTree = SOURCE_ROOT;")
        build = add("build:" + path, f"isa = PBXBuildFile; fileRef = {ref};")
        (sources if file.suffix == ".swift" else bundled).append(build)
        groups["Demo" if file in demo else "Shared map code" if file in shared else "Maps and assets"].append(ref)

    frameworks, products = [], []
    for name in ["TactileMapCore", "TactileMapFeedback", "TactileMapView"]:
        product = add(name, f"isa = XCSwiftPackageProductDependency; package = {identifier('package')}; productName = {name};")
        products.append(product)
        frameworks.append(add("link:" + name, f"isa = PBXBuildFile; productRef = {product};"))

    for name, kind, files in [("sources", "PBXSourcesBuildPhase", sources),
                              ("resources", "PBXResourcesBuildPhase", bundled),
                              ("frameworks", "PBXFrameworksBuildPhase", frameworks)]:
        add(name, f"isa = {kind}; buildActionMask = 2147483647; files = {array(files)}; runOnlyForDeploymentPostprocessing = 0;")

    app = add("app", 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = "MultiNav Demo.app"; sourceTree = BUILT_PRODUCTS_DIR;')
    child_groups = []
    for name, children in groups.items():
        child_groups.append(add("group:" + name, f'isa = PBXGroup; children = {array(children)}; name = {quote(name)}; sourceTree = "<group>";'))
    child_groups.append(add("products", f'isa = PBXGroup; children = {array([app])}; name = Products; sourceTree = "<group>";'))
    add("root", f'isa = PBXGroup; children = {array(child_groups)}; sourceTree = "<group>";')

    for mode in ["Debug", "Release"]:
        project_settings = {
            "SDKROOT": "iphoneos", "IPHONEOS_DEPLOYMENT_TARGET": "17.6",
            "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES",
            "SWIFT_VERSION": "5.0", "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if mode == "Debug" else "-O",
            "DEBUG_INFORMATION_FORMAT": "dwarf" if mode == "Debug" else "dwarf-with-dsym",
            "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
        }
        if mode == "Debug":
            project_settings.update(ENABLE_TESTABILITY="YES", SWIFT_ACTIVE_COMPILATION_CONDITIONS="DEBUG $(inherited)")
        settings = {
            "PRODUCT_NAME": "$(TARGET_NAME)", "PRODUCT_BUNDLE_IDENTIFIER": "waivelab.multinav.demo",
            "INFOPLIST_KEY_CFBundleDisplayName": "MultiNav Demo", "DEVELOPMENT_TEAM": "YKQC794592",
            "CODE_SIGN_STYLE": "Automatic", "CURRENT_PROJECT_VERSION": "1", "MARKETING_VERSION": "1.0",
            "GENERATE_INFOPLIST_FILE": "YES", "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
            "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
            "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
            "INFOPLIST_KEY_UISupportedInterfaceOrientations": "UIInterfaceOrientationPortrait",
            "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad": "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
            "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon", "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
            "TARGETED_DEVICE_FAMILY": "1,2", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
            "SUPPORTS_MACCATALYST": "NO", "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks",
            "SWIFT_EMIT_LOC_STRINGS": "YES",
        }
        for scope, values in [("project", project_settings), ("target", settings)]:
            body = " ".join(f"{key} = {quote(value)};" for key, value in values.items())
            add(f"{scope}:{mode}", f"isa = XCBuildConfiguration; buildSettings = {{ {body} }}; name = {mode};")
    for scope in ["project", "target"]:
        configurations = array([identifier(f"{scope}:Debug"), identifier(f"{scope}:Release")])
        add(scope + ":configs", f"isa = XCConfigurationList; buildConfigurations = {configurations}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")

    add("target", f'''isa = PBXNativeTarget;
            buildConfigurationList = {identifier('target:configs')};
            buildPhases = {array([identifier('sources'), identifier('frameworks'), identifier('resources')])};
            buildRules = (); dependencies = (); name = "MultiNav Demo";
            packageProductDependencies = {array(products)}; productName = "MultiNav Demo";
            productReference = {app}; productType = "com.apple.product-type.application";''')
    # The same package revision recorded in the study app's lockfile. Pinning
    # avoids changes to demo gestures/appearance from an unrelated package update.
    add("package", '''isa = XCRemoteSwiftPackageReference;
            repositoryURL = "https://github.com/Hariprasath88/ProjectMultiNav";
            requirement = { kind = revision; revision = eb0de869671e9784fbc1ee1078fb984d6f2b83db; };''')
    add("project", f'''isa = PBXProject;
            attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2600; }};
            buildConfigurationList = {identifier('project:configs')}; compatibilityVersion = "Xcode 14.0";
            developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base,);
            mainGroup = {identifier('root')}; packageReferences = ({identifier('package')},);
            productRefGroup = {identifier('products')}; projectDirPath = ""; projectRoot = "";
            targets = ({identifier('target')},);''')
    return '// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n' + '\n'.join(objects) + f'\n\t}};\n\trootObject = {identifier("project")};\n}}\n'


def scheme_text():
    ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{identifier("target")}" BuildableName="MultiNav Demo.app" BlueprintName="MultiNav Demo" ReferencedContainer="container:MultiNav Demo.xcodeproj"/>'
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
    <BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry></BuildActionEntries>
  </BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"/>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="NO">
    <BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable>
  </LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    for file, text in [(PROJECT / "project.pbxproj", project_text()),
                       (PROJECT / "xcshareddata/xcschemes/MultiNav Demo.xcscheme", scheme_text())]:
        if args.check:
            if not file.exists() or file.read_text(encoding="utf-8") != text:
                raise SystemExit(f"Regenerate {file.relative_to(ROOT)} with python tools/generate_demo_project.py")
        else:
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text(text, encoding="utf-8", newline="\n")
    print("Demo Xcode project is up to date." if args.check else "Generated MultiNav Demo.xcodeproj.")
