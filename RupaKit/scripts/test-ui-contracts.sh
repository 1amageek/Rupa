#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Run only the reviewed, non-window contracts. Never substitute a whole target.
result_dir=$(mktemp -d "${TMPDIR:-/tmp}/rupa-ui-contracts.XXXXXX")
echo "Results: $result_dir"
for target in RupaUIPackageTests RupaRenderingTests; do
    selection=()
    while IFS= read -r identifier; do
        [[ "$identifier" == "$target/"* ]] || continue
        selection+=("-only-testing:$identifier")
    done < scripts/ui-contract-tests.txt
    (( ${#selection[@]} > 0 )) || { echo "Empty test selection: $target" >&2; exit 1; }
    env -u TOOLCHAINS bash scripts/swift-test-timeout.sh 120 -- \
        xcodebuild test -scheme "$target" \
        -destination 'platform=macOS,arch=arm64' \
        "${selection[@]}" -resultBundlePath "$result_dir/$target.xcresult" -quiet
    xcrun xcresulttool get test-results summary --path "$result_dir/$target.xcresult" | \
        ruby -rjson -e 's = JSON.parse(STDIN.read); abort "Missing passing test evidence" unless s["result"] == "Passed" && s["passedTests"] >= Integer(ARGV[0]) && s["failedTests"] == 0 && s["skippedTests"] == 0; puts "Passed: #{s["passedTests"]} tests, no failures or skips"' "${#selection[@]}"
done
