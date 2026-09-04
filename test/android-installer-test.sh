#!/usr/bin/env bash

set -euo pipefail

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="${TERMACS_REPO_ROOT:-$(cd -- "$script_directory/.." && pwd)}"
fake_adb="${TERMACS_FAKE_ADB:-$script_directory/fake-adb}"
real_git="$(command -v git)"
test_bash="$(command -v bash)"
test_root="$(mktemp -d)"
tests_run=0

cleanup() {
  rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  if [[ -n ${output:-} ]]; then
    printf '%s\n' "$output" >&2
  fi
  exit 1
}

assert_exists() {
  [[ -e $1 ]] || fail "expected $1 to exist"
}

assert_absent() {
  [[ ! -e $1 ]] || fail "expected $1 to be absent"
}

assert_output() {
  [[ $output == *"$1"* ]] || fail "expected output to contain: $1"
}

new_case() {
  local name="$1"

  case_root="$test_root/$name"
  app_data="$case_root/app data"
  emacs_home="$app_data/files"
  fake_bin="$case_root/bin"
  origin="$case_root/origin.git"
  seed="$case_root/seed"
  mkdir -p "$emacs_home" "$fake_bin"

  "$real_git" init -q --bare "$origin"
  "$real_git" init -q -b main "$seed"
  "$real_git" -C "$seed" config user.name Test
  "$real_git" -C "$seed" config user.email test@example.com
  printf '%s\n' ';;; init.el' > "$seed/init.el"
  "$real_git" -C "$seed" add init.el
  "$real_git" -C "$seed" commit -q -m initial
  "$real_git" -C "$seed" remote add origin "$origin"
  "$real_git" -C "$seed" push -q -u origin main
  "$real_git" -C "$origin" symbolic-ref HEAD refs/heads/main

  cat > "$fake_bin/run-as" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
shift
if [[ ${1:-} == pwd ]]; then
  printf '%s\n' "$FAKE_APP_DATA"
  exit 0
fi
exec "$@"
EOF

  cat > "$fake_bin/gum" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$FAKE_GUM_LOG"
if [[ ${1:-} == confirm ]]; then
  [[ ${FAKE_CONFIRM:-yes} == yes ]]
fi
EOF

  cat > "$fake_bin/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ ${1:-} == clone && ${2:-} == "$FAKE_EXPECTED_ORIGIN" ]]; then
  if [[ ${FAKE_FAIL_CLONE:-0} == 1 ]]; then
    exit 1
  fi
  "$REAL_GIT" clone -q "$FAKE_ORIGIN" "$3"
  "$REAL_GIT" -C "$3" remote set-url origin "$FAKE_EXPECTED_ORIGIN"
  exit 0
fi

if [[ ${1:-} == -C && ${3:-} == pull && ${4:-} == --ff-only ]]; then
  directory="$2"
  "$REAL_GIT" -C "$directory" remote set-url origin "$FAKE_ORIGIN"
  status=0
  "$REAL_GIT" -C "$directory" pull -q --ff-only || status=$?
  "$REAL_GIT" -C "$directory" remote set-url origin "$FAKE_EXPECTED_ORIGIN"
  exit "$status"
fi

if [[ ${FAKE_FAIL_FINAL_VERIFY:-0} == 1 && ${1:-} == -C &&
  $2 == "$FAKE_EMACS_HOME/.config/emacs" && ${3:-} == rev-parse &&
  ${4:-} == --verify && ${5:-} == HEAD ]]; then
  exit 1
fi

exec "$REAL_GIT" "$@"
EOF

  chmod +x "$fake_bin/run-as" "$fake_bin/gum" "$fake_bin/git"
  cp "$fake_adb" "$fake_bin/adb"
  sed -i "1c #!$test_bash" "$fake_bin/run-as" "$fake_bin/gum" "$fake_bin/git" "$fake_bin/adb"
  chmod +x "$fake_bin/adb"

  export PATH="$fake_bin:$PATH"
  export FAKE_DEVICE_PATH="$fake_bin"
  export FAKE_APP_DATA="$app_data"
  export FAKE_ORIGIN="$origin"
  export FAKE_EXPECTED_ORIGIN="https://github.com/suderman/emacs.git"
  export FAKE_EMACS_HOME="$emacs_home"
  export FAKE_GUM_LOG="$case_root/gum.log"
  export REAL_GIT="$real_git"
  export TERMACS_TERMUX_GIT="$fake_bin/git"
  export TERMACS_TIMESTAMP="20260904-120000"
  unset FAKE_FAIL_CLONE FAKE_FAIL_FINAL_VERIFY FAKE_RUN_AS_UNAVAILABLE
}

run_setup() {
  local answer="${1:-yes}"

  : > "$FAKE_GUM_LOG"
  output="$(FAKE_CONFIRM="$answer" bash "$repo_root/android/setup-config.sh" test-device 2>&1)"
}

clone_existing() {
  local target="$emacs_home/.config/emacs"

  mkdir -p "$emacs_home/.config"
  "$real_git" clone -q "$origin" "$target"
  "$real_git" -C "$target" remote set-url origin "$FAKE_EXPECTED_ORIGIN"
}

test_fresh_clone() {
  new_case fresh-clone
  run_setup
  assert_exists "$emacs_home/.config/emacs/init.el"
  [[ $("$real_git" -C "$emacs_home/.config/emacs" remote get-url origin) == "$FAKE_EXPECTED_ORIGIN" ]] ||
    fail "fresh clone has wrong origin"
  assert_output "Configuration HEAD:"
}

test_legacy_migration_and_timestamp() {
  new_case legacy-migration
  mkdir -p "$emacs_home/.emacs.d"
  printf '%s\n' legacy > "$emacs_home/.emacs.d/init.el"
  run_setup
  assert_absent "$emacs_home/.emacs.d"
  assert_exists "$emacs_home/.local/state/emacs/legacy-emacs.d-20260904-120000/init.el"
  assert_exists "$emacs_home/.config/emacs/init.el"
  assert_output "legacy-emacs.d-20260904-120000"
}

test_clone_failure_rollback() {
  new_case clone-failure
  mkdir -p "$emacs_home/.emacs.d"
  printf '%s\n' legacy > "$emacs_home/.emacs.d/init.el"
  export FAKE_FAIL_CLONE=1
  run_setup
  assert_exists "$emacs_home/.emacs.d/init.el"
  assert_absent "$emacs_home/.config/emacs"
  assert_output "Git clone failed"
}

test_verification_failure_rollback() {
  new_case verification-failure
  mkdir -p "$emacs_home/.emacs.d"
  printf '%s\n' legacy > "$emacs_home/.emacs.d/init.el"
  export FAKE_FAIL_FINAL_VERIFY=1
  run_setup
  assert_exists "$emacs_home/.emacs.d/init.el"
  assert_absent "$emacs_home/.config/emacs"
  assert_absent "$emacs_home/.local/state/emacs/legacy-emacs.d-20260904-120000"
  assert_output "legacy state was restored"
}

test_existing_clean_update() {
  local checkout_head origin_head

  new_case clean-update
  clone_existing
  printf '%s\n' updated >> "$seed/init.el"
  "$real_git" -C "$seed" commit -q -am update
  "$real_git" -C "$seed" push -q
  run_setup
  checkout_head="$("$real_git" -C "$emacs_home/.config/emacs" rev-parse HEAD)"
  origin_head="$("$real_git" -C "$seed" rev-parse HEAD)"
  [[ $checkout_head == "$origin_head" ]] || fail "checkout was not updated"
  assert_output "Configuration HEAD:"
}

test_existing_checkout_with_legacy() {
  new_case existing-with-legacy
  clone_existing
  mkdir -p "$emacs_home/.emacs.d"
  printf '%s\n' legacy > "$emacs_home/.emacs.d/init.el"
  run_setup
  assert_absent "$emacs_home/.emacs.d"
  assert_exists "$emacs_home/.local/state/emacs/legacy-emacs.d-20260904-120000/init.el"
  assert_exists "$emacs_home/.config/emacs/init.el"
}

test_local_commit_refusal() {
  new_case local-commit
  clone_existing
  "$real_git" -C "$emacs_home/.config/emacs" config user.name Test
  "$real_git" -C "$emacs_home/.config/emacs" config user.email test@example.com
  printf '%s\n' local >> "$emacs_home/.config/emacs/init.el"
  "$real_git" -C "$emacs_home/.config/emacs" commit -q -am local
  run_setup
  assert_output "has local commits or is divergent"
  [[ ! -s $FAKE_GUM_LOG ]] || fail "divergent checkout prompted for a change"
}

test_dirty_checkout_refusal() {
  new_case dirty-refusal
  clone_existing
  printf '%s\n' dirty >> "$emacs_home/.config/emacs/init.el"
  run_setup
  assert_output "Git worktree is dirty"
  [[ ! -s $FAKE_GUM_LOG ]] || fail "dirty checkout prompted for a change"
}

test_wrong_origin_refusal() {
  new_case wrong-origin
  clone_existing
  "$real_git" -C "$emacs_home/.config/emacs" remote set-url origin https://example.com/wrong.git
  run_setup
  assert_output "wrong Git origin"
  [[ ! -s $FAKE_GUM_LOG ]] || fail "wrong origin prompted for a change"
}

test_non_git_target_refusal() {
  new_case non-git
  mkdir -p "$emacs_home/.config/emacs"
  printf '%s\n' user-data > "$emacs_home/.config/emacs/init.el"
  run_setup
  assert_exists "$emacs_home/.config/emacs/init.el"
  assert_output "not a Git worktree"
  [[ ! -s $FAKE_GUM_LOG ]] || fail "non-Git target prompted for a change"
}

test_declined_setup() {
  new_case declined
  run_setup no
  assert_absent "$emacs_home/.config/emacs"
  assert_output "configuration clone declined"
  assert_output "Termux \$HOME is not Emacs \$HOME"
}

test_run_as_unavailable() {
  new_case no-run-as
  export FAKE_RUN_AS_UNAVAILABLE=1
  run_setup
  assert_absent "$emacs_home/.config/emacs"
  assert_output "run-as org.gnu.emacs is unavailable"
  assert_output "EMACS_HOME=\$HOME"
}

for test_name in \
  test_fresh_clone \
  test_legacy_migration_and_timestamp \
  test_clone_failure_rollback \
  test_verification_failure_rollback \
  test_existing_clean_update \
  test_existing_checkout_with_legacy \
  test_local_commit_refusal \
  test_dirty_checkout_refusal \
  test_wrong_origin_refusal \
  test_non_git_target_refusal \
  test_declined_setup \
  test_run_as_unavailable; do
  "$test_name"
  ((tests_run += 1))
done

printf 'PASS: %d Android configuration installer tests\n' "$tests_run"
