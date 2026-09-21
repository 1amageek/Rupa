#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Run only reviewed contracts and hidden hosts; never substitute a whole target.
bash scripts/check-ui-test-isolation.sh
ruby scripts/check-ui-contract-selection.rb --self-test
ruby scripts/check-ui-contract-selection.rb
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
    for (( offset=0; offset<${#selection[@]}; )); do
        result="$result_dir/$target-$offset.xcresult"
        batch=()
        while (( offset<${#selection[@]} && ${#batch[@]}<12 )); do
            identifier="${selection[offset]}"
            # Each serialized gesture family already exercises multiple mounted
            # windows and release/cancel paths; give it its own bounded run.
            if [[ "$identifier" == */ViewportNativeObjectAffordancePressTests/*HandleGestureFollowsItsCommitContract* ]]; then
                (( ${#batch[@]} == 0 )) || break
                batch+=("$identifier")
                offset=$((offset + 1))
                break
            fi
            batch+=("$identifier")
            offset=$((offset + 1))
        done
        env -u TOOLCHAINS bash scripts/swift-test-timeout.sh 120 -- \
            xcodebuild test -scheme "$target" \
            -destination 'platform=macOS,arch=arm64' \
            -parallel-testing-enabled NO \
            "${batch[@]}" -resultBundlePath "$result" -quiet
        xcrun xcresulttool get test-results tests --path "$result" | \
            ruby scripts/check-ui-test-results.rb "$target" "${batch[@]}"
    done
done
