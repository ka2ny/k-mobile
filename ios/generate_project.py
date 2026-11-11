#!/usr/bin/env python3
"""Generate the dependency-free Xcode project deterministically; run after adding Swift files."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def ident(label):
    return hashlib.sha256(label.encode()).hexdigest()[:24].upper()


def quoted(value):
    return json.dumps(str(value))


def main():
    objects = {}

    def add(label, body):
        key = ident(label)
        objects[key] = body
        return key

    def array(values):
        return "(" + ", ".join(values) + ",)" if values else "()"

    def settings(values):
        return "{" + " ".join(f"{key} = {quoted(value)};" for key, value in values.items()) + "}"

    def configurations(label, values):
        ids = []
        for name in ("Debug", "Release"):
            config = dict(values)
            config["SWIFT_OPTIMIZATION_LEVEL"] = "-Onone" if name == "Debug" else "-O"
            if name == "Debug":
                config["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "DEBUG $(inherited)"
                config["ENABLE_TESTABILITY"] = "YES"
            ids.append(add(label + name, f"isa = XCBuildConfiguration; name = {name}; buildSettings = {settings(config)};"))
        return add(label + "configs", f"isa = XCConfigurationList; buildConfigurations = {array(ids)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")

    source_groups, phases = [], {}
    for target, folder in (("app", "KMobile"), ("tests", "KMobileTests"), ("ui", "KMobileUITests")):
        refs, builds = [], []
        for path in sorted((ROOT / folder).rglob("*.swift")):
            relative = path.relative_to(ROOT).as_posix()
            ref = add(relative, f"isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quoted(relative)}; sourceTree = SOURCE_ROOT;")
            builds.append(add("build:" + relative, f"isa = PBXBuildFile; fileRef = {ref};"))
            refs.append(ref)
        if target == "app":
            resource_builds = []
            for path, kind in (("KMobile/Assets.xcassets", "folder.assetcatalog"), ("KMobile/PrivacyInfo.xcprivacy", "text.xml"),
                               ("KMobile/Resources/SourceNotice.txt", "text")):
                ref = add(path, f"isa = PBXFileReference; lastKnownFileType = {kind}; path = {quoted(path)}; sourceTree = SOURCE_ROOT;")
                resource_builds.append(add("build:" + path, f"isa = PBXBuildFile; fileRef = {ref};"))
                refs.append(ref)
            phases["resources"] = add("resources", f"isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {array(resource_builds)}; runOnlyForDeploymentPostprocessing = 0;")
        phases[target] = add(target + "sources", f"isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {array(builds)}; runOnlyForDeploymentPostprocessing = 0;")
        source_groups.append(add(folder + "group", f"isa = PBXGroup; children = {array(refs)}; name = {folder}; sourceTree = \"<group>\";"))

    app_product = add("appProduct", 'isa = PBXFileReference; explicitFileType = wrapper.application; path = KMobile.app; sourceTree = BUILT_PRODUCTS_DIR;')
    tests_product = add("testsProduct", 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = KMobileTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
    ui_product = add("uiProduct", 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = KMobileUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
    products = add("products", f'isa = PBXGroup; children = {array([app_product, tests_product, ui_product])}; name = Products; sourceTree = "<group>";')
    group = add("mainGroup", f'isa = PBXGroup; children = {array(source_groups + [products])}; sourceTree = "<group>";')
    common = {"SDKROOT": "iphoneos", "IPHONEOS_DEPLOYMENT_TARGET": "27.0", "SWIFT_VERSION": "6.0",
              "SWIFT_STRICT_CONCURRENCY": "complete", "CLANG_ENABLE_MODULES": "YES", "CODE_SIGN_STYLE": "Automatic",
              "TARGETED_DEVICE_FAMILY": "1,2", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator"}
    project_configs = configurations("project", common)
    app_configs = configurations("app", {"PRODUCT_NAME": "KMobile", "PRODUCT_BUNDLE_IDENTIFIER": "app.khole.mobile",
        "INFOPLIST_FILE": "KMobile/Info.plist", "GENERATE_INFOPLIST_FILE": "NO",
        "MARKETING_VERSION": "0.1.0", "CURRENT_PROJECT_VERSION": "1",
        "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor", "SWIFT_EMIT_LOC_STRINGS": "YES"})
    test_configs = configurations("tests", {"PRODUCT_NAME": "KMobileTests", "PRODUCT_BUNDLE_IDENTIFIER": "app.khole.mobile.tests",
        "GENERATE_INFOPLIST_FILE": "YES", "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/KMobile.app/KMobile",
        "BUNDLE_LOADER": "$(TEST_HOST)"})
    ui_configs = configurations("ui", {"PRODUCT_NAME": "KMobileUITests", "PRODUCT_BUNDLE_IDENTIFIER": "app.khole.mobile.uitests",
        "GENERATE_INFOPLIST_FILE": "YES", "TEST_TARGET_NAME": "KMobile"})
    app = add("appTarget", f'isa = PBXNativeTarget; buildConfigurationList = {app_configs}; buildPhases = {array([phases["app"], phases["resources"]])}; buildRules = (); dependencies = (); name = KMobile; productName = KMobile; productReference = {app_product}; productType = "com.apple.product-type.application";')
    proxy = add("proxy", f'isa = PBXContainerItemProxy; containerPortal = {ident("project")}; proxyType = 1; remoteGlobalIDString = {app}; remoteInfo = KMobile;')
    dependency = add("dependency", f'isa = PBXTargetDependency; target = {app}; targetProxy = {proxy};')
    tests = add("testsTarget", f'isa = PBXNativeTarget; buildConfigurationList = {test_configs}; buildPhases = {array([phases["tests"]])}; buildRules = (); dependencies = {array([dependency])}; name = KMobileTests; productName = KMobileTests; productReference = {tests_product}; productType = "com.apple.product-type.bundle.unit-test";')
    ui = add("uiTarget", f'isa = PBXNativeTarget; buildConfigurationList = {ui_configs}; buildPhases = {array([phases["ui"]])}; buildRules = (); dependencies = {array([dependency])}; name = KMobileUITests; productName = KMobileUITests; productReference = {ui_product}; productType = "com.apple.product-type.bundle.ui-testing";')
    project = add("project", f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2710; }}; buildConfigurationList = {project_configs}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = {group}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = {array([app, tests, ui])};')
    destination = ROOT / "KMobile.xcodeproj"
    destination.mkdir(exist_ok=True)
    body = "\n".join(f"\t\t{key} = {{ {value} }};" for key, value in sorted(objects.items()))
    (destination / "project.pbxproj").write_text(f"// !$*UTF8*$!\n{{\n\tarchiveVersion = 1;\n\tclasses = {{}};\n\tobjectVersion = 56;\n\tobjects = {{\n{body}\n\t}};\n\trootObject = {project};\n}}\n")
    scheme = destination / "xcshareddata/xcschemes/KMobile.xcscheme"
    scheme.parent.mkdir(parents=True, exist_ok=True)

    def reference(key, name, product):
        return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{key}" BuildableName="{product}" BlueprintName="{name}" ReferencedContainer="container:KMobile.xcodeproj"/>'

    app_ref = reference(app, "KMobile", "KMobile.app")
    test_ref = reference(tests, "KMobileTests", "KMobileTests.xctest")
    ui_ref = reference(ui, "KMobileUITests", "KMobileUITests.xctest")
    scheme.write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2710" version="1.7">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
  <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app_ref}</BuildActionEntry>
 </BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{test_ref}</TestableReference><TestableReference skipped="NO">{ui_ref}</TestableReference></Testables></TestAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/>
 <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
    print(f"Generated {destination.relative_to(ROOT)} ({len(objects)} objects)")


if __name__ == "__main__":
    main()
