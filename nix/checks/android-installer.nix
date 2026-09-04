{ pkgs, ... }:
pkgs.runCommand "android-installer-check" {
  nativeBuildInputs = with pkgs; [
    bash
    coreutils
    git
  ];
} ''
  export HOME="$TMPDIR/home"
  export TERMACS_REPO_ROOT=${../..}
  export TERMACS_FAKE_ADB=${../../test/fake-adb}
  bash ${../../test/android-installer-test.sh}
  touch "$out"
''
