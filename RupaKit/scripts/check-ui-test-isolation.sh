#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v rg >/dev/null
# This guards known desktop-taking APIs, not arbitrary source semantics.
pattern='orderFront|makeKeyAndOrderFront|orderWindow|orderBack|makeKeyWindow|XCUIApplication|XCUIElement|CGEventPost|\.post\(tap:|NSApp(lication\.shared)?\.activate|NSWorkspace\.shared\.open'
if rg -n "$pattern" Tests/RupaUIPackageTests Tests/RupaRenderingTests; then
    echo 'UI tests contain desktop automation; use a hidden host or manual acceptance.' >&2
    exit 1
else
    status=$?
    (( status == 1 )) || exit "$status"
fi
if rg -n 'com.apple.product-type.bundle.ui-testing|RupaUITests' ../Rupa/Rupa/Rupa.xcodeproj/project.pbxproj ../Rupa/Rupa/Rupa.xcodeproj/xcshareddata/xcschemes; then
    echo 'The retired foreground runner is still reachable.' >&2
    exit 1
else
    status=$?
    (( status == 1 )) || exit "$status"
fi
echo 'No known foreground automation entry points in active UI test targets.'
