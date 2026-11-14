#!/usr/bin/env python3
"""Generates the .dproj files and WhisperAPI.groupproj from one definition list,
so the unit lists of the .dpr / .dpk and the .dproj always agree. Adapted
from TSteamAPI's tools/gen_projects.py (same layout and settings; Steam's
redistributable, data-file deployment and Skia parts removed).

    python3 tools/gen_projects.py            # create MISSING files only
    python3 tools/gen_projects.py --force    # overwrite existing files too

Once the Delphi IDE has re-saved the .dproj / .groupproj files, THOSE are
authoritative: without --force this script only creates files that do not
exist yet (e.g. a new demo), so it cannot overwrite IDE changes. Use --force
only for a deliberate rebuild, then check the result in the IDE.

Existing GUIDs are kept (read back from the current .dproj) so the IDE does
not see a "new" project after regeneration. Output files are UTF-8 with BOM
and CRLF line endings, as the IDE writes them. The .dpk files are
hand-written and never touched here (only created when missing).
"""
import os, re, uuid

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

LIB = ["Whisper.Types", "Whisper.DynLib", "Whisper.API", "Whisper.Audio", "Whisper.Words",
       "Whisper.Core", "Whisper.Components"]

# 64-bit targets only for programs (owner 2026-11-13: no 32-bit build; ggml
# does not link for 32-bit MSVC). The runtime packages also build for Win32,
# because a 32-bit IDE loads them under the design-time package (the IDE
# never loads whisper.dll, so no 32-bit whisper library is needed).
APP_PLATFORMS = ["Win64", "OSX64", "OSXARM64", "Linux64"]
PKG_PLATFORMS = ["Win32", "Win64", "OSX64", "OSXARM64", "Linux64", "Android64"]
ALL_PLATFORMS = ["Win32", "Win64", "OSX64", "OSXARM64", "Linux64", "Android64"]


def lib_units(rel):   # rel = path from project dir to repo root
    return [(u, f"{rel}lib\\{u}.pas") for u in LIB]


PROJECTS = [
    # The demos use the library like any user project: its DCUs come from the
    # runtime packages' output in Delphi's Dcp folder (default Library path),
    # so they list and search only their own sources. Build the packages first.
    dict(name="WhisperDemo", dir="demos\\WhisperDemo", kind="app", framework="FMX",
         platforms=APP_PLATFORMS, default="Win64",
         units=[], forms=[("uMain", "src\\uMain.pas", "frmMain")],
         search="src", depends=["WhisperAPIFMX"]),
    # Console (no framework): smoke test, --check / --bench / --device.
    dict(name="WhisperConsole", dir="demos\\WhisperConsole", kind="console", framework="None",
         platforms=APP_PLATFORMS, default="Win64",
         units=[], forms=[], search=".", depends=["WhisperAPI"]),
    # Framework-free runtime package: the whole library and TCustomWhisper.
    dict(name="WhisperAPI", dir="packages", kind="runtime", framework="None",
         platforms=PKG_PLATFORMS, default="Win64",
         units=lib_units("..\\"), forms=[], search="..\\lib", requires=["rtl"],
         description="whisper.cpp binding - runtime"),
    dict(name="WhisperAPIFMX", dir="packages", kind="runtime", framework="FMX",
         platforms=PKG_PLATFORMS, default="Win64",
         units=[("Whisper.FMX", "..\\fmx\\Whisper.FMX.pas")],
         forms=[], search="..\\lib;..\\fmx", requires=["rtl", "fmx", "WhisperAPI"],
         description="whisper.cpp binding for FireMonkey - runtime",
         depends=["WhisperAPI"]),
    # Registers the FMX TWhisperAPI after GroupDescendentsWith(TWhisperAPI,
    # TFmxObject), so a VCL TWhisperAPI of the same name can be registered later.
    dict(name="dclWhisperAPIFMX", dir="packages", kind="design", framework="FMX",
         platforms=["Win32", "Win64"], default="Win32",
         units=[("Whisper.FMX.Reg", "..\\fmx\\Whisper.FMX.Reg.pas")],
         forms=[], search="..\\lib;..\\fmx", requires=["rtl", "fmx", "designide", "WhisperAPI", "WhisperAPIFMX"],
         description="whisper.cpp binding for FireMonkey - design time",
         depends=["WhisperAPIFMX"]),
]

NS_BASE = "System;Xml;Data;Datasnap;Web;Soap"
# VCL projects: unscoped VCL unit names (Forms, Controls, ...) resolve through these
NS_VCL = "Vcl;Vcl.Imaging;Vcl.Touch;Vcl.Samples;Vcl.Shell"
NS_PLAT = {
    "Win32": "Winapi;System.Win;Data.Win;Datasnap.Win;Web.Win;Soap.Win;Xml.Win",
    "Win64": "Winapi;System.Win;Data.Win;Datasnap.Win;Web.Win;Soap.Win;Xml.Win",
    "OSX64": "Macapi;Posix", "OSXARM64": "Macapi;Posix", "Linux64": "Posix",
    "Android64": "Androidapi;Posix",
}
# macOS bundle keys (Info.plist) for apps and console programs
MAC_KEYS = ("CFBundleName=$(MSBuildProjectName);CFBundleDevelopmentRegion=en;CFBundleDisplayName=$(MSBuildProject"
            "Name);CFBundleIdentifier=$(MSBuildProjectName);CFBundleInfoDictionaryVersion=6.0;CFBundleVersion=1.0"
            ".0;CFBundleShortVersionString=1.0.0;CFBundlePackageType=APPL;CFBundleSignature=????;CFBundleAllowMix"
            "edLocalizations=YES;CFBundleExecutable=$(MSBuildProjectName);NSHighResolutionCapable=true;"
            "LSApplicationCategoryType=public.app-category.productivity")


def existing_guid(path):
    if os.path.exists(path):
        m = re.search(r"<ProjectGuid>(\{[0-9A-Fa-f-]+\})</ProjectGuid>", open(path, encoding="utf-8-sig").read())
        if m:
            return m.group(1)
    return "{" + str(uuid.uuid4()).upper() + "}"


def target(p, ext, name=None):
    return os.path.join(ROOT, *p["dir"].split("\\"), (name or p["name"]) + ext)


def write_crlf_bom(path, lines):
    with open(path, "wb") as fh:
        fh.write(b"\xef\xbb\xbf" + ("\r\n".join(lines) + "\r\n").encode("utf-8"))


# <TargetedPlatforms> bit mask: the IDE lists only these platforms under
# "Target Platforms" (without it, only the default one). Values taken from
# TSteamAPI's projects; OSX64, OSXARM64 and Linux64 always come together here.
TARGETED = {
    frozenset(["Win32", "Win64"]): 3,
    frozenset(["Win64", "OSX64", "OSXARM64", "Linux64"]): 135296,
    frozenset(["Win32", "Win64", "OSX64", "OSXARM64", "Linux64"]): 135299,
    frozenset(["Win32", "Win64", "OSX64", "OSXARM64", "Linux64", "Android64"]): 168067,
}


def dproj(p):
    path = target(p, ".dproj")
    guid = existing_guid(path)
    is_pkg = p["kind"] in ("runtime", "design")
    main = p["name"] + (".dpk" if is_pkg else ".dpr")
    apptype = "Package" if is_pkg else ("Console" if p["kind"] == "console" else "Application")
    L = []
    a = L.append
    a('<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">')
    a('    <PropertyGroup>')
    a(f'        <ProjectGuid>{guid}</ProjectGuid>')
    a('        <ProjectVersion>20.5</ProjectVersion>')  # Delphi 13 (Studio 37.0)
    a(f'        <FrameworkType>{p["framework"]}</FrameworkType>')
    a(f'        <AppType>{apptype}</AppType>')
    a(f'        <MainSource>{main}</MainSource>')
    a('        <Base>True</Base>')
    a("        <Config Condition=\"'$(Config)'==''\">Debug</Config>")
    a(f"        <Platform Condition=\"'$(Platform)'==''\">{p['default']}</Platform>")
    a(f"        <ProjectName Condition=\"'$(ProjectName)'==''\">{p['name']}</ProjectName>")
    a(f"        <TargetedPlatforms>{TARGETED[frozenset(p['platforms'])]}</TargetedPlatforms>")
    a('    </PropertyGroup>')
    a("    <PropertyGroup Condition=\"'$(Config)'=='Base' or '$(Base)'!=''\">")
    a('        <Base>true</Base>')
    a('    </PropertyGroup>')
    for pl in p["platforms"]:
        a(f"    <PropertyGroup Condition=\"('$(Platform)'=='{pl}' and '$(Base)'=='true') or '$(Base_{pl})'!=''\">")
        a(f'        <Base_{pl}>true</Base_{pl}>')
        a('        <CfgParent>Base</CfgParent>')
        a('        <Base>true</Base>')
        a('    </PropertyGroup>')
    for key, cfg in (("Cfg_1", "Debug"), ("Cfg_2", "Release")):
        a(f"    <PropertyGroup Condition=\"'$(Config)'=='{cfg}' or '$({key})'!=''\">")
        a(f'        <{key}>true</{key}>')
        a('        <CfgParent>Base</CfgParent>')
        a('        <Base>true</Base>')
        a('    </PropertyGroup>')
    a("    <PropertyGroup Condition=\"'$(Base)'!=''\">")
    a(f'        <SanitizedProjectName>{p["name"].replace(".", "_")}</SanitizedProjectName>')
    a(f'        <DCC_Namespace>{NS_BASE};$(DCC_Namespace)</DCC_Namespace>')
    a(f'        <DCC_UnitSearchPath>{p["search"]};$(DCC_UnitSearchPath)</DCC_UnitSearchPath>')
    a(f'        <DCC_IncludePath>{p["search"]};$(DCC_IncludePath)</DCC_IncludePath>')
    if p["kind"] == "runtime":
        # DCUs next to the .dcp, on the IDE's default Library path, so projects
        # (demos included) need no paths; Win32 is overridden in Base_Win32
        a('        <DCC_DcuOutput>$(BDSCOMMONDIR)\\Dcp\\$(Platform)</DCC_DcuOutput>')
    else:
        a('        <DCC_DcuOutput>.\\$(Platform)\\$(Config)\\dcu</DCC_DcuOutput>')
    if is_pkg:
        # No DCC_BplOutput / DCC_DcpOutput: Delphi's defaults ($(BDSCOMMONDIR)\Bpl and
        # \Dcp per platform) are on the IDE's PATH and library path, so the design
        # package finds WhisperAPIFMX.dcp and the IDE can load WhisperAPIFMX.bpl.
        a('        <GenDll>true</GenDll>')
        a('        <GenPackage>true</GenPackage>')
        a(f'        <DCC_Description>{p["description"]}</DCC_Description>')
        if p["kind"] == "runtime":
            a('        <RuntimeOnlyPackage>true</RuntimeOnlyPackage>')
        else:
            a('        <DesignOnlyPackage>true</DesignOnlyPackage>')
    else:
        a('        <DCC_ExeOutput>.\\$(Platform)\\$(Config)</DCC_ExeOutput>')
    a('        <DCC_E>false</DCC_E>')
    a('        <DCC_N>false</DCC_N>')
    a('        <DCC_S>false</DCC_S>')
    a('        <DCC_F>false</DCC_F>')
    a('        <DCC_K>false</DCC_K>')
    a('    </PropertyGroup>')
    for pl in p["platforms"]:
        a(f"    <PropertyGroup Condition=\"'$(Base_{pl})'!=''\">")
        ns = NS_PLAT[pl] + (";" + NS_VCL if p["framework"] == "VCL" else "")
        a(f'        <DCC_Namespace>{ns};$(DCC_Namespace)</DCC_Namespace>')
        if p["kind"] == "runtime" and pl == "Win32":
            # Win32's Dcp folder has no platform sub-folder (see the Base group)
            a('        <DCC_DcuOutput>$(BDSCOMMONDIR)\\Dcp</DCC_DcuOutput>')
        if pl.startswith("OSX") and p["kind"] in ("app", "console"):
            # Without bundle keys the IDE writes an EMPTY Info.plist and PAServer's
            # 'plutil -convert binary1' fails (E0264) - seen with TSteamAPI.
            a('        <VerInfo_IncludeVerInfo>true</VerInfo_IncludeVerInfo>')
            a(f'        <VerInfo_Keys>{MAC_KEYS}</VerInfo_Keys>')
        a('    </PropertyGroup>')
    a("    <PropertyGroup Condition=\"'$(Cfg_1)'!=''\">")
    a('        <DCC_Define>DEBUG;$(DCC_Define)</DCC_Define>')
    a('        <DCC_DebugDCUs>true</DCC_DebugDCUs>')
    a('        <DCC_Optimize>false</DCC_Optimize>')
    a('        <DCC_GenerateStackFrames>true</DCC_GenerateStackFrames>')
    a('        <DCC_DebugInfoInExe>true</DCC_DebugInfoInExe>')
    a('        <DCC_RemoteDebug>true</DCC_RemoteDebug>')
    a('    </PropertyGroup>')
    a("    <PropertyGroup Condition=\"'$(Cfg_2)'!=''\">")
    a('        <DCC_LocalDebugSymbols>false</DCC_LocalDebugSymbols>')
    a('        <DCC_Define>RELEASE;$(DCC_Define)</DCC_Define>')
    a('        <DCC_SymbolReferenceInfo>0</DCC_SymbolReferenceInfo>')
    a('        <DCC_DebugInformation>0</DCC_DebugInformation>')
    a('    </PropertyGroup>')
    a('    <ItemGroup>')
    a('        <DelphiCompile Include="$(MainSource)">')
    a('            <MainSource>MainSource</MainSource>')
    a('        </DelphiCompile>')
    for r in p.get("requires", []):
        a(f'        <DCCReference Include="{r}.dcp"/>')
    for u, f in p["units"]:
        a(f'        <DCCReference Include="{f}"/>')
    for u, f, form in p["forms"]:
        a(f'        <DCCReference Include="{f}">')
        a(f'            <Form>{form}</Form>')
        a(f'            <FormType>{"dfm" if p["framework"] == "VCL" else "fmx"}</FormType>')
        a('        </DCCReference>')
    a('        <BuildConfiguration Include="Base">')
    a('            <Key>Base</Key>')
    a('        </BuildConfiguration>')
    a('        <BuildConfiguration Include="Debug">')
    a('            <Key>Cfg_1</Key>')
    a('            <CfgParent>Base</CfgParent>')
    a('        </BuildConfiguration>')
    a('        <BuildConfiguration Include="Release">')
    a('            <Key>Cfg_2</Key>')
    a('            <CfgParent>Base</CfgParent>')
    a('        </BuildConfiguration>')
    a('    </ItemGroup>')
    a('    <ProjectExtensions>')
    a('        <Borland.Personality>Delphi.Personality.12</Borland.Personality>')
    a(f'        <Borland.ProjectType>{"Package" if is_pkg else "Application"}</Borland.ProjectType>')
    a('        <BorlandProject>')
    a('            <Delphi.Personality>')
    a('                <Source>')
    a(f'                    <Source Name="MainSource">{main}</Source>')
    a('                </Source>')
    # Project page: the IDE shows a README when the project opens - a demo's
    # own README.md next to its .dproj (what to put next to the .exe),
    # otherwise the repository README
    if p["dir"].startswith("demos\\"):
        a('                <WelcomePageFile Path="README.md"/>')
    else:
        up = "..\\" * (p["dir"].count("\\") + 1)
        a(f'                <WelcomePageFile Path="{up}README.md"/>')
    a('            </Delphi.Personality>')
    a('            <Platforms>')
    for pl in ALL_PLATFORMS:
        a(f'                <Platform value="{pl}">{"True" if pl in p["platforms"] else "False"}</Platform>')
    a('            </Platforms>')
    a('        </BorlandProject>')
    a('        <ProjectFileVersion>12</ProjectFileVersion>')
    a('    </ProjectExtensions>')
    a("    <Import Project=\"$(BDS)\\Bin\\CodeGear.Delphi.Targets\" Condition=\"Exists('$(BDS)\\Bin\\CodeGear.Delphi.Targets')\"/>")
    a("    <Import Project=\"$(APPDATA)\\Embarcadero\\$(BDSAPPDATABASEDIR)\\$(PRODUCTVERSION)\\UserTools.proj\" Condition=\"Exists('$(APPDATA)\\Embarcadero\\$(BDSAPPDATABASEDIR)\\$(PRODUCTVERSION)\\UserTools.proj')\"/>")
    a("    <Import Project=\"$(MSBuildProjectName).deployproj\" Condition=\"Exists('$(MSBuildProjectName).deployproj')\"/>")
    a('</Project>')
    write_crlf_bom(path, L)
    return path


def dpk(p):
    path = target(p, ".dpk")
    L = [f"package {p['name']};", "",
         f"{{ {p['description']}. }}", "",
         f"{{$DESCRIPTION '{p['description']}'}}",
         "{$RUNONLY}" if p["kind"] == "runtime" else "{$DESIGNONLY}",
         "{$IMPLICITBUILD ON}", "", "requires"]
    L += [f"  {r}{',' if i < len(p['requires']) - 1 else ';'}" for i, r in enumerate(p["requires"])]
    L += ["", "contains"]
    L += [f"  {u} in '{f}'{',' if i < len(p['units']) - 1 else ';'}" for i, (u, f) in enumerate(p["units"])]
    L += ["", "end."]
    with open(path, "w", newline="\r\n") as fh:
        fh.write("\n".join(L) + "\n")


def groupproj():
    path = os.path.join(ROOT, "WhisperAPI.groupproj")
    guid = existing_guid(path)
    L = ['<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">',
         '    <PropertyGroup>', f'        <ProjectGuid>{guid}</ProjectGuid>', '    </PropertyGroup>',
         '    <ItemGroup>']
    # Shown in the Projects window (as TSteamAPI): applications first, then
    # runtime packages, then design packages. Build order is separate: the
    # Dependencies below (IDE) and the Build / Clean / Make targets (MSBuild)
    # build runtime packages, then design packages, then the applications,
    # which link the DCUs the runtime packages produce.
    rank_show = {"app": 0, "console": 0, "runtime": 1, "design": 2}
    rank_build = {"runtime": 0, "design": 1, "app": 2, "console": 2}
    fw = lambda p: {"None": 0, "FMX": 1, "VCL": 2}.get(p["framework"], 3) \
        if p["kind"] in ("runtime", "design") else 0
    ordered = sorted(PROJECTS, key=lambda p: (rank_show[p["kind"]], fw(p)))
    build_order = sorted(PROJECTS, key=lambda p: (rank_build[p["kind"]], fw(p)))
    for p in ordered:
        rel = f"{p['dir']}\\{p['name']}.dproj"
        deps = ";".join(f"{q['dir']}\\{q['name']}.dproj" for q in PROJECTS if q["name"] in p.get("depends", []))
        L += [f'        <Projects Include="{rel}">',
              f'            <Dependencies>{deps}</Dependencies>' if deps else '            <Dependencies/>',
              '        </Projects>']
    L += ['    </ItemGroup>', '    <ProjectExtensions>',
          '        <Borland.Personality>Default.Personality.12</Borland.Personality>',
          '        <Borland.ProjectType/>', '        <BorlandProject>',
          '            <Default.Personality/>', '        </BorlandProject>', '    </ProjectExtensions>']
    for p in ordered:
        rel = f"{p['dir']}\\{p['name']}.dproj"
        n = p["name"]
        L += [f'    <Target Name="{n}">', f'        <MSBuild Projects="{rel}"/>', '    </Target>',
              f'    <Target Name="{n}:Clean">', f'        <MSBuild Projects="{rel}" Targets="Clean"/>', '    </Target>',
              f'    <Target Name="{n}:Make">', f'        <MSBuild Projects="{rel}" Targets="Make"/>', '    </Target>']
    names = [p["name"] for p in build_order]
    for t, suf in (("Build", ""), ("Clean", ":Clean"), ("Make", ":Make")):
        L += [f'    <Target Name="{t}">', f'        <CallTarget Targets="{";".join(n + suf for n in names)}"/>', '    </Target>']
    L += ["    <Import Project=\"$(BDS)\\Bin\\CodeGear.Group.Targets\" Condition=\"Exists('$(BDS)\\Bin\\CodeGear.Group.Targets')\"/>",
          '</Project>']
    write_crlf_bom(path, L)
    return path


if __name__ == "__main__":
    import sys
    force = "--force" in sys.argv[1:]
    for p in PROJECTS:
        if force or not os.path.exists(target(p, ".dproj")):
            print("wrote", os.path.relpath(dproj(p), ROOT))
        else:
            print("kept (exists, use --force)", os.path.relpath(target(p, ".dproj"), ROOT))
        if p["kind"] in ("runtime", "design"):
            if not os.path.exists(target(p, ".dpk")):
                dpk(p)
                print("wrote", os.path.relpath(target(p, ".dpk"), ROOT))
    gp = os.path.join(ROOT, "WhisperAPI.groupproj")
    if force or not os.path.exists(gp):
        print("wrote", os.path.relpath(groupproj(), ROOT))
    else:
        print("kept (exists, use --force) WhisperAPI.groupproj")
