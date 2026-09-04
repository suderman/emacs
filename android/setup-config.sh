#!/usr/bin/env bash

set -uo pipefail

readonly emacs_package="org.gnu.emacs"
readonly config_origin="https://github.com/suderman/emacs.git"
readonly termux_git="${TERMACS_TERMUX_GIT:-/data/data/com.termux/files/usr/bin/git}"

device="${1:-}"
emacs_home=""
checkout_head=""
checkout_problem=""

device_quote() {
  local value="${1//\'/\'\\\'\'}"
  printf "'%s'" "$value"
}

device_shell() {
  local argument command="" quoted

  for argument in "$@"; do
    quoted="$(device_quote "$argument")"
    command+="${command:+ }$quoted"
  done
  adb -s "$device" shell "$command"
}

emacs_shell() {
  device_shell run-as "$emacs_package" "$@"
}

emacs_git() {
  emacs_shell env -u LD_LIBRARY_PATH HOME="$emacs_home" "$termux_git" "$@"
}

print_manual_setup() {
  local reason="$1" home_value="\$HOME"

  if [[ -n $emacs_home ]]; then
    home_value="$(device_quote "$emacs_home")"
  fi

  printf '\nConfiguration automation stopped: %s\n' "$reason"
  printf '%s\n' \
    "The APK installation remains successful." \
    "Termux and Emacs share an Android UID, but Termux \$HOME is not Emacs \$HOME." \
    "Run these commands in Termux. If the Emacs home could not be discovered," \
    "run them from M-x shell inside Emacs instead:"
  cat <<EOF

set -eu
EMACS_HOME=$home_value
GIT='$termux_git'
CONFIG="\$EMACS_HOME/.config/emacs"
ORIGIN='$config_origin'
mkdir -p "\$EMACS_HOME/.config"
if [ -d "\$CONFIG/.git" ]; then
  test -z "\$("\$GIT" -C "\$CONFIG" status --porcelain)"
  case "\$("\$GIT" -C "\$CONFIG" remote get-url origin)" in
    https://github.com/suderman/emacs|https://github.com/suderman/emacs.git) ;;
    *) printf '%s\n' "Refusing unexpected origin" >&2; exit 1 ;;
  esac
  "\$GIT" -C "\$CONFIG" pull --ff-only
elif [ -e "\$CONFIG" ]; then
  printf '%s\n' "Refusing non-Git target: \$CONFIG" >&2
  exit 1
else
  "\$GIT" clone "\$ORIGIN" "\$CONFIG"
fi
test -f "\$CONFIG/init.el"
test -z "\$("\$GIT" -C "\$CONFIG" status --porcelain)"
"\$GIT" -C "\$CONFIG" rev-parse --verify HEAD
if [ -e "\$EMACS_HOME/.emacs.d" ]; then
  BACKUP="\$EMACS_HOME/.local/state/emacs/legacy-emacs.d-\$(date +%Y%m%d-%H%M%S)"
  mkdir -p "\$EMACS_HOME/.local/state/emacs"
  mv "\$EMACS_HOME/.emacs.d" "\$BACKUP"
  printf 'Legacy configuration moved to %s\n' "\$BACKUP"
fi
EOF
}

check_checkout() {
  local directory="$1" inside origin status

  checkout_problem=""
  if ! emacs_shell test -f "$directory/init.el"; then
    checkout_problem="missing init.el"
    return 1
  fi
  inside="$(emacs_git -C "$directory" rev-parse --is-inside-work-tree 2>/dev/null)" || {
    checkout_problem="not a Git worktree"
    return 1
  }
  if [[ $inside != true ]]; then
    checkout_problem="not a Git worktree"
    return 1
  fi
  status="$(emacs_git -C "$directory" status --porcelain 2>/dev/null)" || {
    checkout_problem="could not read Git worktree status"
    return 1
  }
  if [[ -n $status ]]; then
    checkout_problem="Git worktree is dirty"
    return 1
  fi
  origin="$(emacs_git -C "$directory" remote get-url origin 2>/dev/null)" || {
    checkout_problem="missing Git origin"
    return 1
  }
  if [[ ${origin%.git} != "${config_origin%.git}" ]]; then
    checkout_problem="wrong Git origin: $origin"
    return 1
  fi
  checkout_head="$(emacs_git -C "$directory" rev-parse --verify HEAD 2>/dev/null)" || {
    checkout_problem="could not resolve Git HEAD"
    return 1
  }
  if [[ -z $checkout_head ]]; then
    checkout_problem="empty Git HEAD"
    return 1
  fi
}

rollback_new_checkout() {
  local target="$1" temporary="$2" backup="$3" target_created="$4" target_was_empty="$5"
  local failed=0

  if [[ $target_created == 1 ]]; then
    if ! emacs_shell rm -rf -- "$target" >/dev/null 2>&1; then
      failed=1
    elif [[ $target_was_empty == 1 ]] &&
      ! emacs_shell mkdir -p -- "$target" >/dev/null 2>&1; then
      failed=1
    fi
  fi
  if [[ -n $backup ]] && emacs_shell test -e "$backup"; then
    emacs_shell mv -- "$backup" "$emacs_home/.emacs.d" >/dev/null 2>&1 || failed=1
  fi
  if emacs_shell test -e "$temporary"; then
    emacs_shell rm -rf -- "$temporary" >/dev/null 2>&1 || failed=1
  fi
  return "$failed"
}

clone_checkout() {
  local target="$1" legacy="$2" target_was_empty="$3"
  local timestamp temporary backup="" target_created=0

  timestamp="${TERMACS_TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}"
  temporary="$emacs_home/.config/.emacs-installer-$timestamp-$$"

  if emacs_shell test -e "$temporary"; then
    print_manual_setup "installer temporary path already exists: $temporary"
    return
  fi
  if ! emacs_shell mkdir -p -- "$emacs_home/.config"; then
    print_manual_setup "could not create $emacs_home/.config"
    return
  fi
  if ! emacs_git clone "$config_origin" "$temporary"; then
    rollback_new_checkout "$target" "$temporary" "" 0 "$target_was_empty"
    print_manual_setup "Git clone failed"
    return
  fi
  if ! check_checkout "$temporary"; then
    rollback_new_checkout "$target" "$temporary" "" 0 "$target_was_empty"
    print_manual_setup "cloned checkout verification failed: $checkout_problem"
    return
  fi

  if [[ $legacy == 1 ]]; then
    backup="$emacs_home/.local/state/emacs/legacy-emacs.d-$timestamp"
    if emacs_shell test -e "$backup"; then
      rollback_new_checkout "$target" "$temporary" "" 0 "$target_was_empty"
      print_manual_setup "legacy backup path already exists: $backup"
      return
    fi
    if ! emacs_shell mkdir -p -- "$emacs_home/.local/state/emacs" ||
      ! emacs_shell mv -- "$emacs_home/.emacs.d" "$backup"; then
      rollback_new_checkout "$target" "$temporary" "$backup" 0 "$target_was_empty"
      print_manual_setup "could not back up the legacy configuration"
      return
    fi
  fi

  if [[ $target_was_empty == 1 ]] && ! emacs_shell rmdir -- "$target"; then
    rollback_new_checkout "$target" "$temporary" "$backup" 0 "$target_was_empty"
    print_manual_setup "the empty configuration target changed during setup"
    return
  fi
  if ! emacs_shell mv -- "$temporary" "$target"; then
    rollback_new_checkout "$target" "$temporary" "$backup" 0 "$target_was_empty"
    if [[ $target_was_empty == 1 ]]; then
      emacs_shell mkdir -p -- "$target" >/dev/null 2>&1 || true
    fi
    print_manual_setup "could not move the verified checkout into place"
    return
  fi
  target_created=1

  if ! check_checkout "$target" || emacs_shell test -e "$emacs_home/.emacs.d"; then
    if rollback_new_checkout "$target" "$temporary" "$backup" "$target_created" "$target_was_empty"; then
      print_manual_setup "final configuration verification failed; legacy state was restored"
    else
      print_manual_setup "final verification and automatic rollback failed; inspect $target and $backup"
    fi
    return
  fi

  printf 'Configuration installed at %s\n' "$target"
  if [[ -n $backup ]]; then
    printf 'Legacy configuration moved to %s\n' "$backup"
  fi
  printf 'Configuration HEAD: %s\n' "$checkout_head"
}

move_legacy_checkout() {
  local target="$1" timestamp backup

  timestamp="${TERMACS_TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}"
  backup="$emacs_home/.local/state/emacs/legacy-emacs.d-$timestamp"
  if emacs_shell test -e "$backup"; then
    print_manual_setup "legacy backup path already exists: $backup"
    return
  fi
  if ! emacs_shell mkdir -p -- "$emacs_home/.local/state/emacs" ||
    ! emacs_shell mv -- "$emacs_home/.emacs.d" "$backup"; then
    if emacs_shell test -e "$backup"; then
      emacs_shell mv -- "$backup" "$emacs_home/.emacs.d" >/dev/null 2>&1 || true
    fi
    print_manual_setup "could not back up the legacy configuration"
    return
  fi
  if ! check_checkout "$target"; then
    if emacs_shell mv -- "$backup" "$emacs_home/.emacs.d" >/dev/null 2>&1; then
      print_manual_setup "configuration verification failed after migration; legacy state was restored"
    else
      print_manual_setup "configuration verification and legacy restore failed; backup remains at $backup"
    fi
    return
  fi
  printf 'Legacy configuration moved to %s\n' "$backup"
}

update_checkout() {
  local target="$1"

  if ! emacs_git -C "$target" pull --ff-only; then
    print_manual_setup "fast-forward-only update failed; the checkout may be divergent or offline"
    return 1
  fi
  if ! check_checkout "$target"; then
    print_manual_setup "updated checkout verification failed: $checkout_problem"
    return 1
  fi
  printf 'Configuration HEAD: %s\n' "$checkout_head"
}

check_update_safety() {
  local target="$1" upstream counts ahead

  upstream="$(emacs_git -C "$target" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)" || {
    checkout_problem="managed checkout has no upstream branch"
    return 1
  }
  counts="$(emacs_git -C "$target" rev-list --left-right --count "HEAD...$upstream" 2>/dev/null)" || {
    checkout_problem="could not compare the managed checkout with $upstream"
    return 1
  }
  read -r ahead _ <<< "$counts"
  if (( ahead > 0 )); then
    checkout_problem="managed checkout has local commits or is divergent from $upstream"
    return 1
  fi
}

main() {
  local app_data target legacy=0 target_was_empty=0

  if [[ -z $device ]]; then
    printf '%s\n' "Missing Android device serial." >&2
    return 1
  fi

  app_data="$(device_shell run-as "$emacs_package" pwd 2>/dev/null)" || {
    print_manual_setup "run-as $emacs_package is unavailable"
    return 0
  }
  app_data="${app_data//$'\r'/}"
  if [[ $app_data != /* || $app_data == *$'\n'* ]]; then
    print_manual_setup "run-as returned an invalid app data directory"
    return 0
  fi
  emacs_home="$app_data/files"
  if ! emacs_shell test -d "$emacs_home"; then
    print_manual_setup "the discovered Emacs home does not exist: $emacs_home"
    return 0
  fi
  printf 'Discovered Emacs home: %s\n' "$emacs_home"

  if ! emacs_git --version >/dev/null 2>&1; then
    print_manual_setup "Termux Git is unavailable from the Emacs app context"
    return 0
  fi

  target="$emacs_home/.config/emacs"
  if emacs_shell test -e "$emacs_home/.emacs.d"; then
    legacy=1
  fi

  if emacs_shell test -e "$target"; then
    if ! check_checkout "$target"; then
      if emacs_shell test -d "$target" &&
        emacs_shell sh -c "[ -z \"\$(ls -A -- \"\$1\")\" ]" sh "$target"; then
        target_was_empty=1
      else
        print_manual_setup "unsafe configuration target $target: $checkout_problem"
        return 0
      fi
    else
      if ! check_update_safety "$target"; then
        print_manual_setup "unsafe configuration target $target: $checkout_problem"
        return 0
      fi
      if [[ $legacy == 1 ]]; then
        printf '%s\n' \
          "Legacy $emacs_home/.emacs.d currently takes precedence over $target." \
          "It must move to a timestamped XDG state backup for this checkout to load."
      fi
      if ! gum confirm --default=false "Update $target with git pull --ff-only?"; then
        print_manual_setup "configuration update declined"
        return 0
      fi
      update_checkout "$target" || return 0
      if [[ $legacy == 1 ]]; then
        if ! gum confirm --default=false "Move $emacs_home/.emacs.d to a timestamped XDG state backup?"; then
          print_manual_setup "legacy configuration migration declined; .emacs.d still controls startup"
          return 0
        fi
        move_legacy_checkout "$target"
      fi
      return 0
    fi
  fi

  if [[ $legacy == 1 ]]; then
    printf '%s\n' \
      "Legacy $emacs_home/.emacs.d currently controls startup." \
      "The installer will clone and verify first, then move it to a timestamped XDG state backup."
    if ! gum confirm --default=false "Clone the managed configuration and move the legacy .emacs.d?"; then
      print_manual_setup "configuration clone and legacy migration declined"
      return 0
    fi
  elif ! gum confirm --default=false "Clone the managed configuration to $target?"; then
    print_manual_setup "configuration clone declined"
    return 0
  fi

  clone_checkout "$target" "$legacy" "$target_was_empty"
}

main
