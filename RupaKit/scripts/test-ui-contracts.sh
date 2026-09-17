#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Run only reviewed contracts and hidden hosts; never substitute a whole target.
bash scripts/check-ui-test-isolation.sh
ruby scripts/check-ui-test-results.rb --self-test
result_dir=$(mktemp -d "${TMPDIR:-/tmp}/rupa-ui-contracts.XXXXXX")
echo "Results: $result_dir"
targets=("$@")
if (( ${#targets[@]} == 0 )); then targets=(RupaUIPackageTests RupaRenderingTests); fi
for target in "${targets[@]}"; do
    case "$target" in
        RupaUIPackageTests|RupaRenderingTests) ;;
        *) echo "Unknown UI verification target: $target" >&2; exit 64 ;;
    esac
    selection=()
    while IFS= read -r identifier; do
        [[ "$identifier" == "$target/"* ]] || continue
        selection+=("-only-testing:$identifier")
    done < scripts/ui-contract-tests.txt
    (( ${#selection[@]} > 0 )) || { echo "Empty test selection: $target" >&2; exit 1; }
    # Bound each batch separately; the allowlist may grow without an unbounded run.
    for (( offset=0; offset<${#selection[@]}; offset+=12 )); do
        batch=("${selection[@]:offset:12}")
        result="$result_dir/$target-$offset.xcresult"
        env -u TOOLCHAINS bash scripts/swift-test-timeout.sh 120 -- \
            xcodebuild test -scheme "$target" \
            -destination 'platform=macOS,arch=arm64' \
            "${batch[@]}" -resultBundlePath "$result" -quiet
        xcrun xcresulttool get test-results tests --path "$result" | \
            ruby scripts/check-ui-test-results.rb "$target" "${batch[@]}"
    done
done
