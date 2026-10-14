#!/usr/bin/env python3
"""Wire Libbox.xcframework + Ensure Libbox build phase into project.pbxproj."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATH = ROOT / "ClevVPN.xcodeproj" / "project.pbxproj"

FR = "D4E5F6A7B8C9D0E1F2A3B4C5"
BF_APP = "E5F6A7B8C9D0E1F2A3B4C5D6"
BF_EMB = "F6A7B8C9D0E1F2A3B4C5D6E7"
BF_EXT = "A7B8C9D0E1F2A3B4C5D6E7F8"
SH_APP = "B8C9D0E1F2A3B4C5D6E7F809"
SH_EXT = "C9D0E1F2A3B4C5D6E7F8091A"
GR = "D0E1F2A3B4C5D6E7F8091A2B"

SHELL = (
    'set -euo pipefail\\n'
    'cd "${SRCROOT}"\\n'
    'chmod +x scripts/ensure-libbox.sh scripts/build-libbox.sh\\n'
    './scripts/ensure-libbox.sh\\n'
)


def main() -> int:
    text = PATH.read_text(encoding="utf-8")
    if "Ensure Libbox" in text and "Libbox.xcframework in Frameworks" in text:
        print("already patched")
        return 0

    build_files = f"""
\t\t{BF_APP} /* Libbox.xcframework in Frameworks */ = {{isa = PBXBuildFile; fileRef = {FR} /* Libbox.xcframework */; }};
\t\t{BF_EMB} /* Libbox.xcframework in Embed Frameworks */ = {{isa = PBXBuildFile; fileRef = {FR} /* Libbox.xcframework */; settings = {{ATTRIBUTES = (CodeSignOnCopy, RemoveHeadersOnCopy, ); }}; }};
\t\t{BF_EXT} /* Libbox.xcframework in Frameworks */ = {{isa = PBXBuildFile; fileRef = {FR} /* Libbox.xcframework */; }};
"""
    text = text.replace(
        "/* Begin PBXBuildFile section */\n",
        "/* Begin PBXBuildFile section */\n" + build_files,
        1,
    )

    file_ref = f"""
\t\t{FR} /* Libbox.xcframework */ = {{isa = PBXFileReference; lastKnownFileType = wrapper.xcframework; name = Libbox.xcframework; path = Frameworks/Libbox.xcframework; sourceTree = "<group>"; }};
"""
    text = text.replace(
        "/* Begin PBXFileReference section */\n",
        "/* Begin PBXFileReference section */\n" + file_ref,
        1,
    )

    frameworks_group = f"""
\t\t{GR} /* Frameworks */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{FR} /* Libbox.xcframework */,
\t\t\t);
\t\t\tname = Frameworks;
\t\t\tpath = Frameworks;
\t\t\tsourceTree = "<group>";
\t\t}};
"""
    text = text.replace(
        "/* Begin PBXGroup section */\n",
        "/* Begin PBXGroup section */\n" + frameworks_group,
        1,
    )

    pat = re.compile(
        r"(children = \(\n(?:\t+\t+[A-F0-9]{24} /\* [^*]+ \*/,\n)*)"
        r"(\t+\t+[A-F0-9]{24} /\* Products \*/,)",
    )
    mm = pat.search(text)
    if not mm:
        print("error: root children with Products not found", file=sys.stderr)
        return 1
    if "Frameworks */," not in mm.group(0):
        text = text[: mm.start(2)] + f"\t\t\t{GR} /* Frameworks */,\n" + text[mm.start(2) :]

    old = """\t\t537F7900B032299F0660CA10 /* Frameworks */ = {
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t7C27D3399501E2794B0E77FB /* ClevVPNKit.framework in Frameworks */,
\t\t\t);
"""
    new = f"""\t\t537F7900B032299F0660CA10 /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t7C27D3399501E2794B0E77FB /* ClevVPNKit.framework in Frameworks */,
\t\t\t\t{BF_APP} /* Libbox.xcframework in Frameworks */,
\t\t\t);
"""
    if old not in text:
        print("error: ClevVPN Frameworks phase not found", file=sys.stderr)
        return 1
    text = text.replace(old, new, 1)

    old = """\t\t778C2307D015DAB0EE549AB8 /* Frameworks */ = {
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t01FBA7FFF981E5C168AFD0A4 /* ClevVPNKit.framework in Frameworks */,
\t\t\t);
"""
    new = f"""\t\t778C2307D015DAB0EE549AB8 /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t01FBA7FFF981E5C168AFD0A4 /* ClevVPNKit.framework in Frameworks */,
\t\t\t\t{BF_EXT} /* Libbox.xcframework in Frameworks */,
\t\t\t);
"""
    if old not in text:
        print("error: PacketTunnel Frameworks phase not found", file=sys.stderr)
        return 1
    text = text.replace(old, new, 1)

    old = """\t\tBF651AA2EA55C69F9B5BDABD /* Embed Frameworks */ = {
\t\t\tisa = PBXCopyFilesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tdstPath = "";
\t\t\tdstSubfolderSpec = 10;
\t\t\tfiles = (
\t\t\t\t81DCA97CCCEE726CA8414B4B /* ClevVPNKit.framework in Embed Frameworks */,
\t\t\t);
"""
    new = f"""\t\tBF651AA2EA55C69F9B5BDABD /* Embed Frameworks */ = {{
\t\t\tisa = PBXCopyFilesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tdstPath = "";
\t\t\tdstSubfolderSpec = 10;
\t\t\tfiles = (
\t\t\t\t81DCA97CCCEE726CA8414B4B /* ClevVPNKit.framework in Embed Frameworks */,
\t\t\t\t{BF_EMB} /* Libbox.xcframework in Embed Frameworks */,
\t\t\t);
"""
    if old not in text:
        print("error: Embed Frameworks phase not found", file=sys.stderr)
        return 1
    text = text.replace(old, new, 1)

    shell_section = f"""
/* Begin PBXShellScriptBuildPhase section */
\t\t{SH_APP} /* Ensure Libbox */ = {{
\t\t\tisa = PBXShellScriptBuildPhase;
\t\t\talwaysOutOfDate = 1;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\tinputFileListPaths = (
\t\t\t);
\t\t\tinputPaths = (
\t\t\t);
\t\t\tname = "Ensure Libbox";
\t\t\toutputFileListPaths = (
\t\t\t);
\t\t\toutputPaths = (
\t\t\t\t"$(SRCROOT)/Frameworks/Libbox.xcframework",
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t\tshellPath = /bin/sh;
\t\t\tshellScript = "{SHELL}";
\t\t}};
\t\t{SH_EXT} /* Ensure Libbox */ = {{
\t\t\tisa = PBXShellScriptBuildPhase;
\t\t\talwaysOutOfDate = 1;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\tinputFileListPaths = (
\t\t\t);
\t\t\tinputPaths = (
\t\t\t);
\t\t\tname = "Ensure Libbox";
\t\t\toutputFileListPaths = (
\t\t\t);
\t\t\toutputPaths = (
\t\t\t\t"$(SRCROOT)/Frameworks/Libbox.xcframework",
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t\tshellPath = /bin/sh;
\t\t\tshellScript = "{SHELL}";
\t\t}};
/* End PBXShellScriptBuildPhase section */

"""
    marker = "/* Begin PBXSourcesBuildPhase section */"
    if marker not in text:
        print("error: Sources section not found", file=sys.stderr)
        return 1
    if "PBXShellScriptBuildPhase" not in text:
        text = text.replace(marker, shell_section + marker, 1)

    old = """\t\t98AAF36820052EB7B5722704 /* ClevVPN */ = {
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = CA4F47AE758AFD9188578EED /* Build configuration list for PBXNativeTarget "ClevVPN" */;
\t\t\tbuildPhases = (
\t\t\t\t95894FF5B62A41EE413BCC03 /* Sources */,
"""
    new = f"""\t\t98AAF36820052EB7B5722704 /* ClevVPN */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = CA4F47AE758AFD9188578EED /* Build configuration list for PBXNativeTarget "ClevVPN" */;
\t\t\tbuildPhases = (
\t\t\t\t{SH_APP} /* Ensure Libbox */,
\t\t\t\t95894FF5B62A41EE413BCC03 /* Sources */,
"""
    if old not in text:
        print("error: ClevVPN native target not found", file=sys.stderr)
        return 1
    text = text.replace(old, new, 1)

    old = """\t\t273DE14089D5250D07AEC586 /* PacketTunnel */ = {
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = 6D2ACC0D1B0D408C19C5F2DC /* Build configuration list for PBXNativeTarget "PacketTunnel" */;
\t\t\tbuildPhases = (
\t\t\t\t1829B9E79E17EBCA945907E6 /* Sources */,
"""
    new = f"""\t\t273DE14089D5250D07AEC586 /* PacketTunnel */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = 6D2ACC0D1B0D408C19C5F2DC /* Build configuration list for PBXNativeTarget "PacketTunnel" */;
\t\t\tbuildPhases = (
\t\t\t\t{SH_EXT} /* Ensure Libbox */,
\t\t\t\t1829B9E79E17EBCA945907E6 /* Sources */,
"""
    if old not in text:
        print("error: PacketTunnel native target not found", file=sys.stderr)
        return 1
    text = text.replace(old, new, 1)

    PATH.write_text(text, encoding="utf-8")
    print("patched OK")
    print("Libbox refs:", text.count("Libbox.xcframework"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
