{
  pkgs,
  ...
}:
let
  emacsVersion = "31.0.50";
  minimumAndroidApi = "35";
  targetAndroidApi = "36";
  abi = "arm64-v8a";
  inputName = "emacs-${emacsVersion}-${minimumAndroidApi}-${abi}.apk";
  outputName = "emacs-${emacsVersion}-${minimumAndroidApi}-${abi}-termux.apk";

  expectedCertificate = "b6da01480eefd5fbf2cd3771b8d1021ec791304bdd6c4bf41d3faabad48ee5e1";
  keyAlias = "alias";
  keyPassword = "xrj45yWGLbsO7W0v";

  emacsApk = pkgs.fetchurl {
    name = inputName;
    url = "https://downloads.sourceforge.net/project/android-ports-for-gnu-emacs/termux/${inputName}";
    hash = "sha256-6etSaqTDA0GSPDCKIP6Iw2+2EdkXI1sOsB3Gp3D2J+I=";
  };

  # This commit is the Termux 0.118.3 tag, matching the target installation.
  termuxKey = pkgs.fetchurl {
    name = "termux-0.118.3-dev-keystore.jks";
    url = "https://raw.githubusercontent.com/termux/termux-app/5b657c6adf4304e5198951ce815fe0205dcac29c/app/dev_keystore.jks";
    hash = "sha256-oroZ8kF96U3Tvfts7s4HDNxfm0kq8JzVkABY6GCxjH0=";
  };

  androidComposition = pkgs.androidenv.composeAndroidPackages {
    buildToolsVersions = [ "35.0.0" ];
    platformVersions = [ ];
    toolsVersion = null;
    includeCmake = false;
    includeEmulator = false;
    includeSystemImages = false;
    includeNDK = false;
  };
  androidBuildTools = builtins.elemAt androidComposition.build-tools 0;
  androidApkTools = pkgs.runCommand "android-apk-tools-35.0.0" { } ''
    mkdir -p "$out/bin"
    ln -s ${androidBuildTools}/libexec/android-sdk/build-tools/35.0.0/aapt2 "$out/bin/aapt2"
    ln -s ${androidBuildTools}/libexec/android-sdk/build-tools/35.0.0/zipalign "$out/bin/zipalign"
  '';

  apkTools = with pkgs; [
    apksigner
    androidApkTools
    bash
    coreutils
    gnugrep
    gnused
    jdk17_headless
    unzip
    zip
  ];
in
pkgs.stdenvNoCC.mkDerivation {
  pname = "termux-emacs-apk";
  version = emacsVersion;
  dontUnpack = true;
  strictDeps = true;
  nativeBuildInputs = apkTools;

  buildPhase = ''
    runHook preBuild
    set -euo pipefail
    export LC_ALL=C

    source_apk=${emacsApk}
    signed_apk=${outputName}
    aapt2=${androidApkTools}/bin/aapt2
    apksigner=${pkgs.apksigner}/bin/apksigner
    zipalign=${androidApkTools}/bin/zipalign

    require() {
      local message="$1"
      shift
      if ! "$@"; then
        echo "$message" >&2
        exit 1
      fi
    }

    "$aapt2" dump badging "$source_apk" > badging.txt
    "$aapt2" dump xmltree "$source_apk" --file AndroidManifest.xml > manifest.txt
    zipinfo -1 "$source_apk" > entries.txt
    unzip -p "$source_apk" AndroidManifest.xml > input-manifest.xml

    require "unexpected package name" grep -Fq "package: name='org.gnu.emacs'" badging.txt
    require "unexpected Emacs version" grep -Fq "versionName='${emacsVersion}'" badging.txt
    require "unexpected minimum Android API" grep -Fq "minSdkVersion:'${minimumAndroidApi}'" badging.txt
    require "unexpected target Android API" grep -Fq "targetSdkVersion:'${targetAndroidApi}'" badging.txt
    require "unexpected or missing shared UID" grep -Eq 'A: .*sharedUserId[^=]*="com\.termux"' manifest.txt
    require "source APK is not debuggable" grep -Eq 'A: .*:debuggable[^=]*=true$' manifest.txt
    require "APK has no ${abi} native libraries" grep -Eq '^lib/${abi}/[^/]+\.so$' entries.txt
    if grep -E '^lib/.+\.so$' entries.txt | grep -Evq '^lib/${abi}/[^/]+\.so$'; then
      echo "APK contains native libraries outside ${abi}" >&2
      exit 1
    fi

    keytool -list -v \
      -keystore ${termuxKey} \
      -alias ${keyAlias} \
      -storepass ${keyPassword} > key.txt
    key_fingerprint="$({ sed -n 's/^[[:space:]]*SHA256: //p' key.txt | tr -d ':\r\n'; } | tr '[:upper:]' '[:lower:]')"
    require "Termux key certificate mismatch" test "$key_fingerprint" = ${expectedCertificate}

    grep -E '^META-INF/(MANIFEST\.MF|[^/]+\.(SF|RSA|DSA|EC))$' entries.txt > old-signatures.txt
    require "input APK has no removable v1 signature" test -s old-signatures.txt
    cp "$source_apk" unsigned.apk
    chmod u+w unsigned.apk
    while IFS= read -r entry; do
      zip -q -d unsigned.apk "$entry"
    done < old-signatures.txt
    if zipinfo -1 unsigned.apk | grep -Eq '^META-INF/(MANIFEST\.MF|[^/]+\.(SF|RSA|DSA|EC))$'; then
      echo "old APK signatures remain" >&2
      exit 1
    fi

    "$zipalign" -P 16 -f 4 unsigned.apk aligned.apk
    "$apksigner" sign \
      --ks ${termuxKey} \
      --ks-key-alias ${keyAlias} \
      --ks-pass pass:${keyPassword} \
      --key-pass pass:${keyPassword} \
      --v4-signing-enabled false \
      --out "$signed_apk" \
      aligned.apk

    "$apksigner" verify --verbose --print-certs "$signed_apk" > verification.txt
    require "signed APK does not have exactly one signer" test "$(grep -c '^Signer #[0-9]\+ certificate SHA-256 digest:' verification.txt)" -eq 1
    signer_fingerprint="$(sed -n 's/^Signer #[0-9]\+ certificate SHA-256 digest: //p' verification.txt | tr -d ':\r\n' | tr '[:upper:]' '[:lower:]')"
    require "signed APK certificate mismatch" test "$signer_fingerprint" = ${expectedCertificate}
    "$zipalign" -c -P 16 4 "$signed_apk"

    unzip -p "$signed_apk" AndroidManifest.xml > output-manifest.xml
    require "AndroidManifest.xml changed while signing" cmp input-manifest.xml output-manifest.xml
    if zipinfo -1 "$signed_apk" | grep -Eq '^META-INF/EMACS_KE\.(SF|RSA|DSA|EC)$'; then
      echo "GNU signing records remain in signed APK" >&2
      exit 1
    fi

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp ${outputName} "$out/${outputName}"
    runHook postInstall
  '';

  passthru = {
    inherit
      apkTools
      emacsVersion
      minimumAndroidApi
      abi
      expectedCertificate
      ;
    apkName = outputName;
  };

  meta = {
    description = "GNU Android Emacs signed for the Termux GitHub ecosystem";
    platforms = [ "x86_64-linux" ];
  };
}
