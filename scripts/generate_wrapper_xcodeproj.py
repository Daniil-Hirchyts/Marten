import hashlib
import os
import plistlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
APP_SOURCES_DIR = ROOT / "ClipboardMac" / "Sources" / "ClipboardMacApp"
WRAPPER_DIR = ROOT / "ClipboardMacWrapper"
XCODEPROJ_DIR = WRAPPER_DIR / "ClipboardMacWrapper.xcodeproj"
PBXPROJ_PATH = XCODEPROJ_DIR / "project.pbxproj"


def _pbx_id(seed: str) -> str:
    return hashlib.md5(seed.encode("utf-8")).hexdigest()[:24].upper()


def main() -> None:
    swift_files = sorted(
        [p for p in APP_SOURCES_DIR.rglob("*.swift") if p.is_file()],
        key=lambda p: str(p).lower(),
    )

    if not swift_files:
        raise SystemExit(f"No Swift sources found under {APP_SOURCES_DIR}")

    WRAPPER_DIR.mkdir(parents=True, exist_ok=True)
    XCODEPROJ_DIR.mkdir(parents=True, exist_ok=True)

    project_id = _pbx_id("PBXProject")
    main_group_id = _pbx_id("MainGroup")
    products_group_id = _pbx_id("ProductsGroup")
    wrapper_group_id = _pbx_id("Group-ClipboardMacWrapper")
    sources_group_id = _pbx_id("Group-AppSources")
    target_id = _pbx_id("Target-ClipboardMacWrapper")

    product_ref_id = _pbx_id("ProductRef-ClipboardMacWrapper.app")
    sources_phase_id = _pbx_id("SourcesPhase")
    resources_phase_id = _pbx_id("ResourcesPhase")
    frameworks_phase_id = _pbx_id("FrameworksPhase")

    project_config_list_id = _pbx_id("ProjectConfigList")
    target_config_list_id = _pbx_id("TargetConfigList")
    project_debug_config_id = _pbx_id("ProjectDebugConfig")
    project_release_config_id = _pbx_id("ProjectReleaseConfig")
    target_debug_config_id = _pbx_id("TargetDebugConfig")
    target_release_config_id = _pbx_id("TargetReleaseConfig")

    info_plist_ref_id = _pbx_id("Info.plist")
    entitlements_ref_id = _pbx_id("Entitlements")
    assets_ref_id = _pbx_id("Assets.xcassets")
    assets_build_id = _pbx_id("BuildFile-Assets.xcassets")

    pkg_clipboardcore_id = _pbx_id("Pkg-ClipboardCore")
    pkg_clipboardmac_id = _pbx_id("Pkg-ClipboardMac")
    dep_clipboardcore_prod_id = _pbx_id("PkgProd-ClipboardCore")
    dep_clipboardmacservices_prod_id = _pbx_id("PkgProd-ClipboardMacServices")
    dep_clipboardcore_build_id = _pbx_id("BuildFile-PkgProd-ClipboardCore")
    dep_clipboardmacservices_build_id = _pbx_id("BuildFile-PkgProd-ClipboardMacServices")

    file_refs: list[tuple[str, str, str]] = []
    build_files: list[tuple[str, str, str]] = []
    sources_build_ids: list[str] = []

    for p in swift_files:
        rel = os.path.relpath(p, WRAPPER_DIR)
        ref_id = _pbx_id(f"FileRef:{rel}")
        build_id = _pbx_id(f"BuildFile:{rel}")
        file_refs.append((ref_id, rel, p.name))
        build_files.append((build_id, ref_id, p.name))
        sources_build_ids.append(build_id)

    objects: dict[str, dict] = {}

    def add(obj_id: str, isa: str, **fields) -> None:
        objects[obj_id] = {"isa": isa, **fields}

    # Build files
    add(assets_build_id, "PBXBuildFile", fileRef=assets_ref_id)
    add(dep_clipboardcore_build_id, "PBXBuildFile", productRef=dep_clipboardcore_prod_id)
    add(
        dep_clipboardmacservices_build_id,
        "PBXBuildFile",
        productRef=dep_clipboardmacservices_prod_id,
    )
    for build_id, ref_id, _ in build_files:
        add(build_id, "PBXBuildFile", fileRef=ref_id)

    # File references
    add(
        product_ref_id,
        "PBXFileReference",
        explicitFileType="wrapper.application",
        includeInIndex="0",
        path="ClipboardMacWrapper.app",
        sourceTree="BUILT_PRODUCTS_DIR",
    )
    add(
        assets_ref_id,
        "PBXFileReference",
        lastKnownFileType="folder.assetcatalog",
        path="Assets.xcassets",
        sourceTree="<group>",
    )
    add(
        info_plist_ref_id,
        "PBXFileReference",
        lastKnownFileType="text.plist.xml",
        path="Info.plist",
        sourceTree="<group>",
    )
    add(
        entitlements_ref_id,
        "PBXFileReference",
        lastKnownFileType="text.plist.entitlements",
        path="ClipboardMacWrapper.entitlements",
        sourceTree="<group>",
    )
    for ref_id, rel, name in file_refs:
        add(
            ref_id,
            "PBXFileReference",
            lastKnownFileType="sourcecode.swift",
            name=name,
            path=rel,
            sourceTree="<group>",
        )

    # Build phases
    add(
        frameworks_phase_id,
        "PBXFrameworksBuildPhase",
        buildActionMask="2147483647",
        files=[dep_clipboardcore_build_id, dep_clipboardmacservices_build_id],
        runOnlyForDeploymentPostprocessing="0",
    )
    add(
        resources_phase_id,
        "PBXResourcesBuildPhase",
        buildActionMask="2147483647",
        files=[assets_build_id],
        runOnlyForDeploymentPostprocessing="0",
    )
    add(
        sources_phase_id,
        "PBXSourcesBuildPhase",
        buildActionMask="2147483647",
        files=sources_build_ids,
        runOnlyForDeploymentPostprocessing="0",
    )

    # Groups
    add(
        products_group_id,
        "PBXGroup",
        children=[product_ref_id],
        name="Products",
        sourceTree="<group>",
    )
    add(
        wrapper_group_id,
        "PBXGroup",
        children=[assets_ref_id, info_plist_ref_id, entitlements_ref_id],
        path="ClipboardMacWrapper",
        sourceTree="<group>",
    )
    add(
        sources_group_id,
        "PBXGroup",
        children=[ref_id for ref_id, _, _ in file_refs],
        name="AppSources",
        sourceTree="<group>",
    )
    add(
        main_group_id,
        "PBXGroup",
        children=[wrapper_group_id, sources_group_id, products_group_id],
        sourceTree="<group>",
    )

    # Configurations
    add(
        project_debug_config_id,
        "XCBuildConfiguration",
        name="Debug",
        buildSettings={
            "ALWAYS_SEARCH_USER_PATHS": "NO",
            "CLANG_ENABLE_MODULES": "YES",
            "CLANG_ENABLE_OBJC_ARC": "YES",
            "CODE_SIGN_STYLE": "Automatic",
            "GCC_C_LANGUAGE_STANDARD": "gnu11",
            "INFOPLIST_FILE": "ClipboardMacWrapper/Info.plist",
            "MACOSX_DEPLOYMENT_TARGET": "13.0",
            "PRODUCT_BUNDLE_IDENTIFIER": "com.yourcompany.paste",
            "SWIFT_VERSION": "5.9",
        },
    )
    add(
        project_release_config_id,
        "XCBuildConfiguration",
        name="Release",
        buildSettings={
            "ALWAYS_SEARCH_USER_PATHS": "NO",
            "CLANG_ENABLE_MODULES": "YES",
            "CLANG_ENABLE_OBJC_ARC": "YES",
            "CODE_SIGN_STYLE": "Automatic",
            "GCC_C_LANGUAGE_STANDARD": "gnu11",
            "INFOPLIST_FILE": "ClipboardMacWrapper/Info.plist",
            "MACOSX_DEPLOYMENT_TARGET": "13.0",
            "PRODUCT_BUNDLE_IDENTIFIER": "com.yourcompany.paste",
            "SWIFT_VERSION": "5.9",
        },
    )
    add(
        target_debug_config_id,
        "XCBuildConfiguration",
        name="Debug",
        buildSettings={
            "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
            "CODE_SIGN_ENTITLEMENTS": "ClipboardMacWrapper/ClipboardMacWrapper.entitlements",
            "DEVELOPMENT_TEAM": "",
            "ENABLE_HARDENED_RUNTIME": "YES",
            "GENERATE_INFOPLIST_FILE": "NO",
            "INFOPLIST_FILE": "ClipboardMacWrapper/Info.plist",
            "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/../Frameworks"],
            "PRODUCT_NAME": "$(TARGET_NAME)",
            "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
        },
    )
    add(
        target_release_config_id,
        "XCBuildConfiguration",
        name="Release",
        buildSettings={
            "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
            "CODE_SIGN_ENTITLEMENTS": "ClipboardMacWrapper/ClipboardMacWrapper.entitlements",
            "DEVELOPMENT_TEAM": "",
            "ENABLE_HARDENED_RUNTIME": "YES",
            "GENERATE_INFOPLIST_FILE": "NO",
            "INFOPLIST_FILE": "ClipboardMacWrapper/Info.plist",
            "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/../Frameworks"],
            "PRODUCT_NAME": "$(TARGET_NAME)",
        },
    )

    add(
        project_config_list_id,
        "XCConfigurationList",
        buildConfigurations=[project_debug_config_id, project_release_config_id],
        defaultConfigurationIsVisible="0",
        defaultConfigurationName="Release",
    )
    add(
        target_config_list_id,
        "XCConfigurationList",
        buildConfigurations=[target_debug_config_id, target_release_config_id],
        defaultConfigurationIsVisible="0",
        defaultConfigurationName="Release",
    )

    # Swift packages
    add(pkg_clipboardcore_id, "XCLocalSwiftPackageReference", relativePath="../ClipboardCore")
    add(pkg_clipboardmac_id, "XCLocalSwiftPackageReference", relativePath="../ClipboardMac")
    add(
        dep_clipboardcore_prod_id,
        "XCSwiftPackageProductDependency",
        package=pkg_clipboardcore_id,
        productName="ClipboardCore",
    )
    add(
        dep_clipboardmacservices_prod_id,
        "XCSwiftPackageProductDependency",
        package=pkg_clipboardmac_id,
        productName="ClipboardMacServices",
    )

    # Target
    add(
        target_id,
        "PBXNativeTarget",
        buildConfigurationList=target_config_list_id,
        buildPhases=[sources_phase_id, resources_phase_id, frameworks_phase_id],
        buildRules=[],
        dependencies=[],
        name="ClipboardMacWrapper",
        packageProductDependencies=[dep_clipboardcore_prod_id, dep_clipboardmacservices_prod_id],
        productName="ClipboardMacWrapper",
        productReference=product_ref_id,
        productType="com.apple.product-type.application",
    )

    # Project
    add(
        project_id,
        "PBXProject",
        attributes={
            "BuildIndependentTargetsInParallel": "1",
            "LastUpgradeCheck": "1500",
            "ORGANIZATIONNAME": "Paste",
            "TargetAttributes": {target_id: {"CreatedOnToolsVersion": "15.0"}},
        },
        buildConfigurationList=project_config_list_id,
        compatibilityVersion="Xcode 15.0",
        developmentRegion="en",
        hasScannedForEncodings="0",
        knownRegions=["en"],
        mainGroup=main_group_id,
        packageReferences=[pkg_clipboardcore_id, pkg_clipboardmac_id],
        productRefGroup=products_group_id,
        projectDirPath="",
        projectRoot="",
        targets=[target_id],
    )

    root = {
        "archiveVersion": "1",
        "classes": {},
        "objectVersion": "56",
        "objects": objects,
        "rootObject": project_id,
    }

    PBXPROJ_PATH.write_bytes(plistlib.dumps(root, fmt=plistlib.FMT_XML))
    print(f"Wrote {PBXPROJ_PATH}")


if __name__ == "__main__":
    main()
