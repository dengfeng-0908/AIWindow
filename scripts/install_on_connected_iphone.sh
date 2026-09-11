#!/bin/zsh

# Build, install, and optionally launch AIWindow on one paired iPhone.
#
# The script reads the Personal Team from the Apple Account already signed in
# to Xcode and passes it only to this build. It never writes signing details,
# account identifiers, or profiles into the Xcode project.

set -euo pipefail

aiwindow_script_directory=${0:A:h}
aiwindow_project_root=${aiwindow_script_directory:h}
aiwindow_project_path="$aiwindow_project_root/apps/ios/AIWindow.xcodeproj"
aiwindow_scheme="AIWindow"
aiwindow_configuration="Debug"
aiwindow_device_identifier=""
aiwindow_dry_run=false
aiwindow_should_launch=true

aiwindow_usage() {
    cat <<'USAGE'
Usage:
  ./scripts/install_on_connected_iphone.sh [options]

Options:
  --device <identifier>  Install to a specific paired iPhone.
  --dry-run              Check signing and device selection without building.
  --no-launch            Install but do not launch the app.
  --list-devices         List devices known to Xcode and exit.
  --help                 Show this help.

Without --device, exactly one available iPhone must be present. The device may
be connected with a cable or paired with Xcode over the local network.
USAGE
}

aiwindow_require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        print -u2 "Missing required command: $1"
        exit 1
    fi
}

while (( $# > 0 )); do
    case "$1" in
        --device)
            if (( $# < 2 )); then
                print -u2 "--device requires a device identifier."
                exit 1
            fi
            aiwindow_device_identifier="$2"
            shift 2
            ;;
        --dry-run)
            aiwindow_dry_run=true
            shift
            ;;
        --no-launch)
            aiwindow_should_launch=false
            shift
            ;;
        --list-devices)
            aiwindow_require_command xcrun
            xcrun devicectl list devices
            exit 0
            ;;
        --help|-h)
            aiwindow_usage
            exit 0
            ;;
        *)
            print -u2 "Unknown option: $1"
            aiwindow_usage >&2
            exit 1
            ;;
    esac
done

aiwindow_require_command xcodebuild
aiwindow_require_command xcrun
aiwindow_require_command plutil
aiwindow_require_command sed
aiwindow_require_command tr
aiwindow_require_command mktemp

if [[ ! -d "$aiwindow_project_path" ]]; then
    print -u2 "AIWindow.xcodeproj was not found at: $aiwindow_project_path"
    exit 1
fi

aiwindow_xcode_preferences="$HOME/Library/Preferences/com.apple.dt.Xcode.plist"
if [[ ! -f "$aiwindow_xcode_preferences" ]]; then
    print -u2 "Xcode Apple Account settings were not found. Open Xcode → Settings → Accounts and sign in first."
    exit 1
fi

aiwindow_team_identifier=$(plutil -extract IDEProvisioningTeamByIdentifier json -o - "$aiwindow_xcode_preferences" 2>/dev/null \
    | tr '\n' ' ' \
    | sed -nE 's/.*"teamID"[[:space:]]*:[[:space:]]*"([A-Z0-9]{10})".*/\1/p' \
    | head -n 1)

if [[ ${#aiwindow_team_identifier} -ne 10 || "$aiwindow_team_identifier" == *[^A-Z0-9]* ]]; then
    print -u2 "No usable Personal Team is cached by Xcode. Confirm that the Apple Account has finished loading in Xcode → Settings → Accounts."
    exit 1
fi

aiwindow_signing_build_setting_key='DEVELOPMENT_TEAM'

if [[ -z "$aiwindow_device_identifier" ]]; then
    aiwindow_device_inventory=$(mktemp -t aiwindow-device-inventory)
    if ! xcrun devicectl list devices --json-output "$aiwindow_device_inventory" >/dev/null; then
        print -u2 "Could not query devices paired with Xcode."
        exit 1
    fi

    aiwindow_device_identifiers=()
    aiwindow_device_index=0

    while true; do
        aiwindow_candidate_type=$(plutil \
            -extract "result.devices.$aiwindow_device_index.hardwareProperties.deviceType" \
            raw \
            -o - \
            "$aiwindow_device_inventory" 2>/dev/null) || break

        if [[ "$aiwindow_candidate_type" == "iPhone" ]]; then
            aiwindow_candidate_boot_state=$(plutil \
                -extract "result.devices.$aiwindow_device_index.deviceProperties.bootState" \
                raw \
                -o - \
                "$aiwindow_device_inventory" 2>/dev/null || true)

            if [[ "$aiwindow_candidate_boot_state" == "booted" ]]; then
                aiwindow_candidate_udid=$(plutil \
                    -extract "result.devices.$aiwindow_device_index.hardwareProperties.udid" \
                    raw \
                    -o - \
                    "$aiwindow_device_inventory" 2>/dev/null || true)

                if [[ -n "$aiwindow_candidate_udid" ]]; then
                    aiwindow_device_identifiers+=("$aiwindow_candidate_udid")
                fi
            fi
        fi

        (( aiwindow_device_index += 1 ))
    done

    if (( ${#aiwindow_device_identifiers[@]} != 1 )); then
        print -u2 "Expected exactly one available and unlocked iPhone, found ${#aiwindow_device_identifiers[@]}."
        print -u2 "Run ./scripts/install_on_connected_iphone.sh --list-devices and retry with --device <identifier>."
        exit 1
    fi

    aiwindow_device_identifier=${aiwindow_device_identifiers[1]}
fi

if [[ "$aiwindow_dry_run" == true ]]; then
    print "Ready for a signed device build."
    print "Project: $aiwindow_project_path"
    print "Scheme: $aiwindow_scheme ($aiwindow_configuration)"
    print "Device: an available paired iPhone has been selected"
    print "Signing team: detected from the Apple Account currently signed in to Xcode"
    exit 0
fi

aiwindow_derived_data_path=$(mktemp -d -t aiwindow-device-build)
aiwindow_bundle_identifier=$(xcodebuild \
    -project "$aiwindow_project_path" \
    -scheme "$aiwindow_scheme" \
    -configuration "$aiwindow_configuration" \
    "$aiwindow_signing_build_setting_key=$aiwindow_team_identifier" \
    -showBuildSettings 2>/dev/null \
    | sed -nE 's/^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER = (.*)$/\1/p' \
    | head -n 1)

if [[ -z "$aiwindow_bundle_identifier" ]]; then
    print -u2 "Could not determine the app bundle identifier from Xcode build settings."
    exit 1
fi

print "Building AIWindow for the paired iPhone…"
aiwindow_build_log=$(mktemp -t aiwindow-device-build-log)
if ! xcodebuild \
    -project "$aiwindow_project_path" \
    -scheme "$aiwindow_scheme" \
    -configuration "$aiwindow_configuration" \
    -destination "id=$aiwindow_device_identifier" \
    -derivedDataPath "$aiwindow_derived_data_path" \
    -allowProvisioningUpdates \
    "$aiwindow_signing_build_setting_key=$aiwindow_team_identifier" \
    build >"$aiwindow_build_log" 2>&1; then
    print -u2 "Build failed. Recent build output:"
    sed "s/$aiwindow_team_identifier/[redacted signing team]/g" "$aiwindow_build_log" | tail -n 100 >&2
    exit 1
fi

aiwindow_app_path="$aiwindow_derived_data_path/Build/Products/Debug-iphoneos/AIWindow.app"
if [[ ! -d "$aiwindow_app_path" ]]; then
    print -u2 "The signed app was not found at the expected build location: $aiwindow_app_path"
    exit 1
fi

print "Installing AIWindow…"
aiwindow_install_log=$(mktemp -t aiwindow-device-install-log)
if ! xcrun devicectl device install app \
    --device "$aiwindow_device_identifier" \
    "$aiwindow_app_path" >"$aiwindow_install_log" 2>&1; then
    print -u2 "Installation failed. Recent device output:"
    tail -n 100 "$aiwindow_install_log" >&2
    exit 1
fi
print "AIWindow installed."

if [[ "$aiwindow_should_launch" == true ]]; then
    print "Launching AIWindow…"
    aiwindow_launch_log=$(mktemp -t aiwindow-device-launch-log)
    if ! xcrun devicectl device process launch \
        --device "$aiwindow_device_identifier" \
        "$aiwindow_bundle_identifier" >"$aiwindow_launch_log" 2>&1; then
        print -u2 "The app was installed, but could not be launched. Recent device output:"
        tail -n 100 "$aiwindow_launch_log" >&2
        exit 1
    fi
    print "AIWindow launched."
fi

print "Done. The temporary build directory is: $aiwindow_derived_data_path"
