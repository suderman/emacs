#!/usr/bin/env bash

set -euo pipefail

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_directory/.." && pwd)"
script_path="$script_directory/$(basename -- "${BASH_SOURCE[0]}")"

if [[ ${TERMACS_DEV_SHELL:-} != 1 ]]; then
  if ! command -v nix >/dev/null 2>&1; then
    printf '%s\n' "Nix is required to run this installer." >&2
    exit 1
  fi
  exec nix develop "$repo_root#android" -c env TERMACS_DEV_SHELL=1 "$script_path" "$@"
fi

if [[ ! -t 0 || ! -t 1 ]]; then
  printf '%s\n' "This guided installer requires an interactive terminal." >&2
  exit 1
fi

for variable in \
  TERMACS_APK_NAME \
  TERMACS_EMACS_VERSION \
  TERMACS_MINIMUM_ANDROID_API \
  TERMACS_ABI \
  TERMACS_EXPECTED_CERTIFICATE; do
  if [[ -z ${!variable:-} ]]; then
    printf 'Missing %s. Run this script through the Android dev shell.\n' "$variable" >&2
    exit 1
  fi
done

readonly termux_package="com.termux"
readonly emacs_package="org.gnu.emacs"
readonly apk="$repo_root/result-android/$TERMACS_APK_NAME"
device=""
temporary_directory=""

cleanup() {
  if [[ -n $temporary_directory ]]; then
    rm -rf -- "$temporary_directory"
  fi
}
trap cleanup EXIT

heading() {
  gum style --foreground 212 --bold --margin "1 0" "$1"
}

note() {
  gum style --foreground 245 "$1"
}

success() {
  gum style --foreground 42 --bold "$1"
}

die() {
  gum style --foreground 196 --bold "Error: $1" >&2
  exit 1
}

cancel() {
  note "Cancelled. No app was installed or removed."
  exit 0
}

spin() {
  local title="$1"
  shift
  if ! gum spin --title "$title" --show-error -- "$@"; then
    die "$title failed."
  fi
}

certificate_digest() {
  local output
  output="$(apksigner verify --print-certs "$1")" || return 1
  sed -n 's/^Signer #1 certificate SHA-256 digest: //p' <<< "$output" |
    tr -d ':\r\n' |
    tr '[:upper:]' '[:lower:]'
}

apk_version_code() {
  aapt2 dump badging "$1" |
    sed -n "s/^package:.* versionCode='\([^']*\)'.*/\1/p"
}

apk_version_name() {
  aapt2 dump badging "$1" |
    sed -n "s/^package:.* versionCode='[^']*' versionName='\([^']*\)'.*/\1/p"
}

package_path() {
  adb -s "$device" shell pm path "$1" 2>/dev/null |
    tr -d '\r' |
    sed -n '1s/^package://p'
}

detect_device() {
  local line serial state
  local -a connected=()
  local -a authorized=()

  while IFS= read -r line; do
    [[ -n $line && $line != "List of devices attached"* ]] || continue
    read -r serial state _ <<< "$line"
    connected+=("$serial  $state")
    if [[ $state == "device" ]]; then
      authorized+=("$serial")
    fi
  done < <(adb devices)

  if (( ${#connected[@]} == 1 && ${#authorized[@]} == 1 )); then
    device="${authorized[0]}"
    return 0
  fi

  if (( ${#connected[@]} == 0 )); then
    note "No phone detected. Connect it with a data-capable USB cable."
  else
    note "Connected Android devices:"
    printf '%s\n' "${connected[@]}" | gum style --foreground 245
    if (( ${#authorized[@]} == 0 )); then
      note "Unlock the phone and approve its USB debugging prompt."
    else
      note "Leave exactly one authorized phone connected."
    fi
  fi
  return 1
}

gum style \
  --border rounded \
  --border-foreground 212 \
  --padding "1 3" \
  --margin "1 0" \
  --bold \
  "Android Emacs" \
  "Install or update GNU Emacs for the existing Termux GitHub ecosystem"

note "This script never modifies Termux or its plugins."

heading "1. Build and verify the APK"
spin "Building the signed Emacs APK" \
  nix build "$repo_root#emacs-android" --out-link "$repo_root/result-android"

[[ -f $apk ]] || die "Build did not produce $apk"
spin "Verifying the APK signature" apksigner verify --verbose "$apk"
spin "Checking 16 KiB APK alignment" zipalign -c -P 16 4 "$apk"

built_certificate="$(certificate_digest "$apk")" || die "Could not read the built APK certificate."
if [[ $built_certificate != "$TERMACS_EXPECTED_CERTIFICATE" ]]; then
  die "Built APK certificate does not match the pinned Termux certificate."
fi
built_version_code="$(apk_version_code "$apk")"
built_version_name="$(apk_version_name "$apk")"
[[ $built_version_code =~ ^[0-9]+$ ]] || die "Built APK has an invalid version code."
[[ $built_version_name == "$TERMACS_EMACS_VERSION" ]] ||
  die "Built APK version does not match the flake configuration."
success "Built Emacs $built_version_name (version code $built_version_code) with the expected certificate."

heading "2. Connect the phone"
gum style \
  --border normal \
  --border-foreground 240 \
  --padding "1 2" \
  "On the phone:" \
  "1. Stay in the owner profile." \
  "2. Enable USB debugging." \
  "3. Connect and unlock the phone." \
  "4. Approve this computer if Android asks."

gum confirm "Is the phone connected and unlocked?" || cancel
adb start-server >/dev/null
until detect_device; do
  gum confirm "Retry device detection?" || cancel
done
success "Using device $device."

heading "3. Check the phone"
phone_api="$(adb -s "$device" shell getprop ro.build.version.sdk | tr -d '\r')"
phone_abi="$(adb -s "$device" shell getprop ro.product.cpu.abi | tr -d '\r')"
current_user="$(adb -s "$device" shell am get-current-user | tr -d '\r')"
phone_model="$(adb -s "$device" shell getprop ro.product.model | tr -d '\r')"

[[ $phone_api =~ ^[0-9]+$ ]] || die "Could not determine the phone's Android API."
(( phone_api >= TERMACS_MINIMUM_ANDROID_API )) ||
  die "Phone API $phone_api is below required API $TERMACS_MINIMUM_ANDROID_API."
[[ $phone_abi == "$TERMACS_ABI" ]] ||
  die "Phone ABI $phone_abi does not match required ABI $TERMACS_ABI."
[[ $current_user == "0" ]] || die "The active Android profile is not the owner profile."

success "$phone_model: API $phone_api, $phone_abi, owner profile."

temporary_directory="$(mktemp -d)"
termux_path="$(package_path "$termux_package")"
[[ -n $termux_path ]] || die "Termux is not installed for the active profile."

spin "Reading the installed Termux certificate" \
  adb -s "$device" pull "$termux_path" "$temporary_directory/termux.apk"
termux_certificate="$(certificate_digest "$temporary_directory/termux.apk")" ||
  die "Could not verify the installed Termux APK."

if [[ $termux_certificate != "$TERMACS_EXPECTED_CERTIFICATE" ]]; then
  gum style \
    --border double \
    --border-foreground 196 \
    --foreground 196 \
    --padding "1 2" \
    --bold \
    "STOP: installed Termux has a different certificate." \
    "Expected: $TERMACS_EXPECTED_CERTIFICATE" \
    "Found:    $termux_certificate" >&2
  die "Do not replace, uninstall, or re-sign Termux."
fi
success "Installed Termux and the new Emacs APK use the same certificate."

heading "4. Choose the safe action"
installed_emacs_path="$(package_path "$emacs_package")"
if [[ -z $installed_emacs_path ]]; then
  action="install"
  completed_action="installed"
  action_label="Install Emacs $TERMACS_EMACS_VERSION"
  install_arguments=(install "$apk")
  note "Emacs is not installed. This will be a first installation."
else
  spin "Reading the installed Emacs certificate" \
    adb -s "$device" pull "$installed_emacs_path" "$temporary_directory/emacs.apk"
  installed_emacs_certificate="$(certificate_digest "$temporary_directory/emacs.apk")" ||
    die "Could not verify the installed Emacs APK."

  if [[ $installed_emacs_certificate != "$TERMACS_EXPECTED_CERTIFICATE" ]]; then
    gum style \
      --border double \
      --border-foreground 196 \
      --foreground 196 \
      --padding "1 2" \
      --bold \
      "STOP: the installed Emacs has a different certificate." \
      "Back up its app data before deciding whether to remove it." \
      "This script will not uninstall it automatically." >&2
    exit 1
  fi

  installed_version_code="$(apk_version_code "$temporary_directory/emacs.apk")"
  installed_version_name="$(apk_version_name "$temporary_directory/emacs.apk")"
  [[ $installed_version_code =~ ^[0-9]+$ ]] || die "Installed Emacs has an invalid version code."

  if (( installed_version_code > built_version_code )); then
    die "Refusing to downgrade Emacs from $installed_version_name to $built_version_name."
  elif (( installed_version_code == built_version_code )); then
    action="reinstall"
    completed_action="reinstalled"
    action_label="Reinstall Emacs $TERMACS_EMACS_VERSION"
  else
    action="update"
    completed_action="updated"
    action_label="Update Emacs from $installed_version_name to $TERMACS_EMACS_VERSION"
  fi
  install_arguments=(install -r "$apk")
  note "A compatible Emacs installation was found. Its app data will be retained."
fi

gum style \
  --border rounded \
  --border-foreground 39 \
  --padding "1 2" \
  "Ready" \
  "Device: $phone_model ($device)" \
  "Action: $action_label" \
  "Termux certificate: verified"

gum confirm --default=false "$action_label now?" || cancel

heading "5. $action_label"
if ! gum spin --title "$action_label" --show-output -- \
  adb -s "$device" "${install_arguments[@]}"; then
  die "Android rejected the APK. Termux was not modified."
fi

installed_emacs_path="$(package_path "$emacs_package")"
[[ -n $installed_emacs_path ]] || die "Android did not report Emacs as installed."
spin "Verifying Emacs after $action" \
  adb -s "$device" pull "$installed_emacs_path" "$temporary_directory/emacs-after.apk"
installed_emacs_certificate="$(certificate_digest "$temporary_directory/emacs-after.apk")" ||
  die "Could not verify Emacs after $action."
[[ $installed_emacs_certificate == "$TERMACS_EXPECTED_CERTIFICATE" ]] ||
  die "Installed Emacs certificate verification failed."
installed_version_code="$(apk_version_code "$temporary_directory/emacs-after.apk")"
[[ $installed_version_code == "$built_version_code" ]] ||
  die "Installed Emacs version verification failed."

success "Emacs $TERMACS_EMACS_VERSION was $completed_action and verified."

if gum confirm "Launch Emacs on the phone now?"; then
  if adb -s "$device" shell monkey \
    -p "$emacs_package" \
    -c android.intent.category.LAUNCHER \
    1 >/dev/null 2>&1; then
    gum confirm "Did Emacs open successfully?" ||
      note "The APK is installed, but launch behavior needs investigation."
  else
    note "Android could not launch Emacs automatically. Open it from the launcher."
  fi
fi

heading "Next: clone this configuration in Emacs"
gum style \
  --border normal \
  --border-foreground 240 \
  --padding "1 2" \
  "Clone this repository to \$HOME/.config/emacs inside Android Emacs." \
  "Keep LD_LIBRARY_PATH unset." \
  "The configuration adds /data/data/com.termux/files/usr/bin to PATH and exec-path." \
  "Then check (executable-find \"git\"), \"rg\", and \"fd\"."

success "Finished. Termux and its plugins were not changed."
