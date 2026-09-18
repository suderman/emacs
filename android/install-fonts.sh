#!/usr/bin/env bash
# Copy a built Nix font bundle to native Emacs without replacing existing fonts.
set -euo pipefail

if [[ $# != 1 || ! -d $1/share/fonts ]]; then
  printf 'Usage: %s NIX_FONT_BUNDLE\n' "$0" >&2
  exit 2
fi

host="${EMACS_ANDROID_HOST:-gem}"
destination=/data/data/org.gnu.emacs/files/fonts
staging="$(mktemp -d)"
trap 'rm -rf -- "$staging"' EXIT

while IFS= read -r -d '' font; do
  name="$(basename "$font")"
  # Use normal static families, not alternate optical sizes or variable twins.
  case "$name" in
    CommitMono-*.ttf|IoskeleyMono-*.ttf|Literata-*.ttf|SymbolsNerdFontMono-Regular.ttf) ;;
    *) continue ;;
  esac
  [[ $name == *'['* ]] && continue
  [[ $name =~ ^[a-zA-Z0-9_.-]+$ ]] || { echo "Unsupported font filename: $name" >&2; exit 1; }
  if [[ -e $staging/$name ]]; then
    cmp -- "$font" "$staging/$name"
  else
    cp -- "$font" "$staging/$name"
  fi
done < <(find -L "$1/share/fonts" -type f -name '*.ttf' -print0)

shopt -s nullglob
fonts=("$staging"/*.ttf)
(( ${#fonts[@]} )) || { echo 'No TTF fonts found.' >&2; exit 1; }

# Refuse a different existing file before copying any of the missing files.
for font in "${fonts[@]}"; do
  name="$(basename "$font")"
  digest="$(sha256sum "$font")"
  ssh "$host" "if test -e '$destination/$name'; then printf '%s  %s\n' '${digest%% *}' '$destination/$name' | sha256sum -c -; fi"
done
ssh "$host" "mkdir -p '$destination'"
rsync -rt --ignore-existing -- "$staging/" "$host:$destination/"
(cd "$staging" && sha256sum -- *.ttf) |
  ssh "$host" "cd '$destination' && sha256sum -c -"
printf 'Fonts verified. Restart native Emacs to rescan %s.\n' "$destination"
