#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: ./Examples/run-ios.sh [--build-only] [--demo] [SIMULATOR_UDID]

Build the BTC iOS example directly with Swift Package Manager, then install and
launch it in an iOS Simulator. No Xcode project or developer account is needed.

  --build-only       Build the .app without opening or changing a simulator.
  --demo             Play the automatic detail demo after launching.
  SIMULATOR_UDID     Use this available iOS simulator instead of choosing an iPhone.
  -h, --help         Show this help.

Environment:
  SIMULATOR_UDID     Alternative to the positional simulator UUID.
  CONFIGURATION     debug (default) or release.

Requires macOS, full Xcode selected with xcode-select, and an iOS Simulator runtime.
USAGE
}

build_only=false
demo_mode=false
requested_simulator="${SIMULATOR_UDID:-}"
positional_simulator=false
for argument in "$@"; do
    case "$argument" in
        --build-only) build_only=true ;;
        --demo) demo_mode=true ;;
        -h|--help) usage; exit 0 ;;
        -*) printf 'Unknown option: %s\n' "$argument" >&2; usage >&2; exit 1 ;;
        *)
            if "$positional_simulator"; then
                printf 'Pass at most one simulator UUID.\n' >&2
                exit 1
            fi
            requested_simulator="$argument"
            positional_simulator=true
            ;;
    esac
done

if [[ "$(uname -s)" != Darwin ]]; then
    printf 'This example requires macOS and Xcode.\n' >&2
    exit 1
fi

examples_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
build_dir="$examples_dir/.build/ios"
configuration="${CONFIGURATION:-debug}"
case "$configuration" in
    debug|release) ;;
    *) printf 'CONFIGURATION must be debug or release.\n' >&2; exit 1 ;;
esac

architecture="$(uname -m)"
case "$architecture" in
    arm64|x86_64) ;;
    *) printf 'Unsupported simulator architecture: %s\n' "$architecture" >&2; exit 1 ;;
esac

sdk_path="$(xcrun --sdk iphonesimulator --show-sdk-path)"
build_arguments=(
    --package-path "$examples_dir"
    --scratch-path "$build_dir"
    --configuration "$configuration"
    --product BTCiOSExample
    --triple "$architecture-apple-ios15.0-simulator"
    --sdk "$sdk_path"
)

xcrun swift build "${build_arguments[@]}"
binary_dir="$(xcrun swift build "${build_arguments[@]}" --show-bin-path)"
app_dir="$build_dir/BTCiOSExample.app"

# SwiftPM builds the executable and resources; Simulator requires an app bundle.
# All generated output stays in the ignored .build directory.
rm -rf "$app_dir"
mkdir -p "$app_dir"
cp "$binary_dir/BTCiOSExample" "$app_dir/BTCiOSExample"
cp "$examples_dir/iOS/Info.plist" "$app_dir/Info.plist"
shopt -s nullglob
for resource_bundle in "$binary_dir"/*.bundle; do
    cp -R "$resource_bundle" "$app_dir/"
done
codesign --force --sign - "$app_dir"
printf 'Built %s\n' "$app_dir"

if "$build_only"; then
    exit 0
fi

# Prefer a booted iPhone, otherwise an iPhone on the newest installed iOS runtime.
# Python is supplied with Xcode's command-line tools; JSON avoids parsing device names.
simulator_selection="$(xcrun simctl list devices available --json | /usr/bin/python3 -c '
import json
import re
import sys

requested = sys.argv[1].lower()
devices = json.load(sys.stdin)["devices"]
runtime_version = lambda runtime: tuple(int(n) for n in re.findall(r"\d+", runtime))
candidates = []
for runtime in sorted(devices, key=runtime_version, reverse=True):
    if ".iOS-" not in runtime:
        continue
    for device in devices[runtime]:
        if not device.get("isAvailable", False):
            continue
        if requested:
            if device["udid"].lower() == requested:
                candidates = [device]
                break
        elif device["name"].startswith("iPhone"):
            candidates.append(device)
    if requested and candidates:
        break
if not candidates:
    message = ("The requested iOS simulator is unavailable: " + requested) if requested else "No available iPhone simulator. Install an iOS runtime in Xcode Settings > Components."
    sys.exit(message)
device = next((d for d in candidates if d["state"] == "Booted"), candidates[0])
print(device["udid"] + "\t" + device["state"] + "\t" + device["name"])
' "$requested_simulator")"
IFS=$'\t' read -r simulator_udid simulator_state simulator_name <<< "$simulator_selection"

if [[ "$simulator_state" != Booted ]]; then
    xcrun simctl boot "$simulator_udid"
fi
xcrun simctl bootstatus "$simulator_udid" -b
xcrun simctl install "$simulator_udid" "$app_dir"
launch_arguments=(--terminate-running-process "$simulator_udid" dev.infinitechart.BTCiOSExample)
if "$demo_mode"; then
    launch_arguments+=(--demo)
fi
xcrun simctl launch "${launch_arguments[@]}"
printf 'Launched BTC Chart on %s (%s).\n' "$simulator_name" "$simulator_udid"

# Resolve the GUI from the same Xcode installation as xcrun. Launch Services may
# not know the short application name when Xcode has a versioned bundle name.
developer_dir="${DEVELOPER_DIR:-$(xcode-select -p)}"
developer_dir="${developer_dir%/}"
if [[ "$developer_dir" == *.app ]]; then
    developer_dir="$developer_dir/Contents/Developer"
fi
simulator_app="$developer_dir/Applications/Simulator.app"
if [[ ! -d "$simulator_app" ]]; then
    printf 'The app is running, but this Xcode installation has no Simulator GUI at %s.\n' "$simulator_app" >&2
elif ! open -a "$simulator_app" --args -CurrentDeviceUDID "$simulator_udid"; then
    # GUI availability is optional on CI/remote sessions; installation and
    # process launch above still fail the script if either operation fails.
    printf 'The app is running, but the Simulator window could not open. Open %s to view it.\n' "$simulator_app" >&2
fi
