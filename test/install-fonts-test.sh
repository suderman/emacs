#!/usr/bin/env bash
# Exercise the Android font copy against a local directory, never a phone.
set -euo pipefail
helper="$(cd "$(dirname "$0")/.." && pwd)/android/install-fonts.sh"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
export FONT_TEST_DEST="$work/phone" FONT_TEST_RSYNC
FONT_TEST_RSYNC="$(command -v rsync)"
mkdir -p "$work/bin" "$work/bundle/share/fonts" "$FONT_TEST_DEST"
cat > "$work/bin/ssh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
command=${2//\/data\/data\/org.gnu.emacs\/files\/fonts/$FONT_TEST_DEST}
bash -c "$command"
SH
cat > "$work/bin/rsync" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
args=("$@")
args[${#args[@]}-1]="$FONT_TEST_DEST/"
exec "$FONT_TEST_RSYNC" "${args[@]}"
SH
chmod +x "$work/bin/ssh" "$work/bin/rsync"
export PATH="$work/bin:$PATH"
for name in IoskeleyMono-Regular Literata-Regular SymbolsNerdFontMono-Regular; do
  printf '%s\n' "$name" > "$work/bundle/share/fonts/$name.ttf"
done
printf 'preserve\n' > "$FONT_TEST_DEST/Existing.ttf"
bash "$helper" "$work/bundle" > "$work/install.log"
before=$(stat -c '%i:%Y' "$FONT_TEST_DEST/IoskeleyMono-Regular.ttf")
bash "$helper" "$work/bundle" > "$work/repeat.log"
test "$before" = "$(stat -c '%i:%Y' "$FONT_TEST_DEST/IoskeleyMono-Regular.ttf")"
test "$(cat "$FONT_TEST_DEST/Existing.ttf")" = preserve
# A conflict must stop the whole copy, including new files earlier in the list.
printf 'new\n' > "$work/bundle/share/fonts/IoskeleyMono-Bold.ttf"
printf 'conflict\n' > "$work/bundle/share/fonts/Literata-Regular.ttf"
if bash "$helper" "$work/bundle" > "$work/conflict.log" 2>&1; then
  echo 'FAIL: accepted a different existing font' >&2
  exit 1
fi
test ! -e "$FONT_TEST_DEST/IoskeleyMono-Bold.ttf"
test "$(cat "$FONT_TEST_DEST/Literata-Regular.ttf")" = Literata-Regular
printf 'PASS: copy, repeat, preserve existing fonts, reject conflicts before copying\n'
