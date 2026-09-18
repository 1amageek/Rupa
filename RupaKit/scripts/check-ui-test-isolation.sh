#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# ripgrep is preferred but is not installed everywhere. A missing tool must not
# end this guard as a bare exit 1, which reads exactly like a clean result.
if command -v rg >/dev/null; then
    search() { rg -n "$1" "${@:2}"; }
else
    search() { grep -rnE "$1" "${@:2}"; }
fi
# This guards known desktop-taking APIs, not arbitrary source semantics.
pattern='orderFront|makeKeyAndOrderFront|orderWindow|orderBack|makeKeyWindow|XCUIApplication|XCUIElement|CGEventPost|\.post\(tap:|NSApp(lication\.shared)?\.activate|NSWorkspace\.shared\.open'
if search "$pattern" Tests/RupaUIPackageTests Tests/RupaRenderingTests; then
    echo 'UI tests contain desktop automation; use a hidden host or manual acceptance.' >&2
    exit 1
else
    status=$?
    (( status == 1 )) || exit "$status"
fi
if search 'com.apple.product-type.bundle.ui-testing|RupaUITests' ../Rupa/Rupa/Rupa.xcodeproj/project.pbxproj ../Rupa/Rupa/Rupa.xcodeproj/xcshareddata/xcschemes; then
    echo 'The retired foreground runner is still reachable.' >&2
    exit 1
else
    status=$?
    (( status == 1 )) || exit "$status"
fi
# The retired sources are deleted, not archived. A directory here is either a
# restored suite or a new one, and both take the desktop back.
if [[ -e ../Rupa/Rupa/RupaUITests ]]; then
    echo 'Foreground UI test sources are present again at Rupa/Rupa/RupaUITests.' >&2
    exit 1
fi
echo 'No known foreground automation entry points in active UI test targets.'
