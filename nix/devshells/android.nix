{
  perSystem,
  pkgs,
  ...
}:
let
  emacsAndroid = perSystem.self.emacs-android;
in
pkgs.mkShell {
  packages =
    emacsAndroid.apkTools
    ++ (with pkgs; [
      android-tools
      curl
      file
      gum
      nixfmt
      shellcheck
    ]);

  shellHook = ''
    export TERMACS_DEV_SHELL=1
    export TERMACS_APK_NAME=${emacsAndroid.apkName}
    export TERMACS_EMACS_VERSION=${emacsAndroid.emacsVersion}
    export TERMACS_MINIMUM_ANDROID_API=${emacsAndroid.minimumAndroidApi}
    export TERMACS_ABI=${emacsAndroid.abi}
    export TERMACS_EXPECTED_CERTIFICATE=${emacsAndroid.expectedCertificate}
  '';
}
