# Working on this Emacs config

## What this repository is

This is Jon Suderman's personal Emacs configuration. It is used every day, but
it is still under active construction. Some parts are polished. Some parts are
experiments that solved a real problem and have not had much time to settle.

Do not mistake "work in progress" for permission to redesign it from scratch.
The general feel is right. The customized Meow editing model, project-oriented
buffer workflow, completion stack, modeline, explorers, icons, and most chosen
packages are taking shape deliberately.

Prefer a small repair that preserves this direction. Broad rewrites need a
clear reason and explicit approval.

It runs in four places: PGTK Emacs on NixOS/Hyprland, terminal frames (local,
over SSH, inside tmux or Herdr), the native Android APK, and terminal Emacs in
Termux. Prefer capability checks such as `display-graphic-p` and
`executable-find` over platform checks. `(featurep 'android)` means the Android
GUI APK only. Termux Emacs also reports `system-type` as `android`, so keep
`(eq system-type 'android)` for what both share, such as packages coming from
package.el rather than Nix.

## Human editability and tests

This is a personal configuration, not a public library. Jon must be able to
change a variable, keybinding, hook, face, package option, or other preference
in one obvious place without knowing a test architecture or asking an agent.
Prefer direct, idiomatic Elisp over wrappers or indirection added for testing.
Interactive evaluation and Git are normal parts of the safety model.

Keep each fact in one place. If a change needs the same list edited in two
files, fix that first. Current single sources:

- `suderman/window-keys` in `suderman-windows.el` holds the Meta window keys.
  `suderman/install-keys` copies it into the global map, Meow's Normal and
  Motion maps, IBuffer, Dirvish, and Magit.
- The whole `SPC` leader is one `define-keymap` form in `suderman-keys.el`.
  Labels sit beside bindings as `("label" . command)`.
- `suderman/dirvish-keys` in `suderman-files.el` holds Dired/Dirvish keys and
  their `?` help labels.
- `suderman/command-labels` in `suderman-help.el` holds cheatsheet labels for
  Meow and local-map views.

Tests protect code that changes things outside Emacs (files, mail, clipboards,
terminals, Android setup), code that hooks into package internals an upgrade
could silently break, hot reload, and named regressions. They do not freeze
configuration choices. Do not add a test because a module changed, create one
test file per module, or assert keys, labels, fonts, faces, hooks, package
options, enabled modes, or editing feel. Small intentional configuration changes
should need only the source edit.

## The NixOS half of the setup

Two Nix places matter. Read both before changing package ownership, daemon
behavior, fonts, tree-sitter grammars, language servers, or external tools.

- `nix/packages/emacs.nix` in this repository builds Emacs 31 PGTK with every
  `use-package` package, native modules, tree-sitter grammars, language servers,
  formatters, and command-line tools. It also bundles the config into the Nix
  store as a fallback for hosts without a checkout.
- `/etc/nixos/modules/home/default/options/emacs/default.nix` (also
  <https://github.com/suderman/nixos>) wraps that package and owns the `em`
  workspace launcher, `ema`, `emd`, `EDITOR`, persistence, and on desktop
  hosts the shared daemon, keyd shortcuts, and the style exporter. It lives in
  the terminal (`default`) layer and guards graphical pieces with
  `config.desktop.enable`. `modules/home/users/jon/programs.nix` enables it.

Package ownership:

- `use-package` forms are the one list of Elisp packages. On NixOS the flake
  reads them and supplies each package, so `:ensure` finds it installed.
- A package added locally installs through package.el into
  `~/.local/share/emacs/elpa` until the next flake update moves it into Nix.
- `edger` and `meow-purrsist` install from GitHub through `package-vc` on every
  platform. `SPC q u` upgrades Git packages everywhere and archive packages
  only on Android.
- Use `:ensure nil` for built-ins (Which-Key, Eglot) and for packages Nix adds
  through `extraEmacsPackages` (PDF Tools, Kitty graphics), so package.el
  neither fetches nor shadows them.
- Pure Elisp belongs in a `use-package` form. Add to `extraEmacsPackages` in
  `nix/packages/emacs.nix` only for native code, grammar data, external
  programs, or sources outside ELPA and MELPA.

Appearance data:

- Stylix supplies typography and both light/dark palettes. On one desktop host
  NixOS exports them to `~/profile/apps/emacs/style.el`, which Syncthing
  carries to other machines. `suderman/system-style-files` lists where Emacs
  looks. Without a readable file, `suderman/fallback-style`
  supplies the same fonts and base16-theme's bundled Catppuccin palettes.
- Emacs defines `suderman-light` and `suderman-dark` with the Base16 engine and
  follows native `toolkit-theme` events on PGTK and Android. The Stylix Emacs
  target is disabled; do not add a second theme loader.
- Do not hardcode a palette. When a derived color is needed, calculate it from
  active semantic faces as `suderman/theme-blend` does.
- Shared GUI typography uses CommitMono, Literata, and Symbols Nerd Font Mono,
  with Ioskeley Mono as Android's ordinary-glyph fallback. Nix installs them;
  `android/install-fonts.sh` copies them to the APK's `~/fonts/`. Keep Nerd Font
  fallback limited to its private-use ranges.

`package.el` data lives under `~/.local/share/emacs/elpa`. Emacs state,
history, backups, auto-saves, Custom data, and caches follow XDG paths set in
`suderman-paths.el`.

## Repository shape

Keep `init.el` boring. It requires every module in dependency order, and hot
reload reloads exactly that list, so every `lisp/suderman-*.el` file must
appear there. New behavior belongs in the narrowest existing module, or in a
new one when a concern has genuinely outgrown its home.

- `suderman-android.el`: Android-only input, the server, and Termux paths.
- `suderman-toolbar.el`: the touch toolbar shared by Android and desktop.
- `suderman-paths.el`: XDG paths and mutable state locations.
- `suderman-packages.el`: package.el and `use-package` defaults.
- `suderman-defaults.el`: small built-in behavior changes.
- `suderman-clipboard.el`: terminal copy through Wayland or OSC 52.
- `suderman-appearance.el`: style file, fonts, theme faces, Doom Modeline,
  line numbers, and the column guide.
- `suderman-windows.el`: window helpers, Meta window keys, smooth jumps.
- `suderman-projects.el`: Org work projects with source and data companions.
- `suderman-buffers.el`: project-grouped IBuffer.
- `suderman-completion.el`: Vertico, Orderless, Consult, Marginalia, Embark,
  Corfu, and Cape.
- `suderman-meow.el`: personal editing commands and the Normal/Motion maps.
- `suderman-terminal.el`: Ghostel integration, currently disabled.
- `suderman-transfer.el`: staged copy/cut/paste, clipboard and terminal file
  import, Ripdrag, and Kitty transfers.
- `suderman-files.el`: Dired, Dirvish, the sidebar, previews, and their keys.
- `suderman-images.el`: Image mode and the Image-Dired gallery.
- `suderman-dashboard.el`: the on-demand dashboard.
- `suderman-markdown.el`: Markdown and Pandoc preview.
- `suderman-org.el`: Org agenda, capture, archive, and refile.
- `suderman-mail-moves.el`, `suderman-mail.el`, `suderman-mail-drafts.el`:
  Notmuch reading, folder moves, sending, and Org-authored drafts.
- `suderman-languages.el`: language associations, tree-sitter, and Eglot.
- `suderman-nix.el`: embedded-language highlighting in Nix strings.
- `suderman-git.el`: Magit, diff-hl, and conflict handling.
- `suderman-formatting.el`: project-aware formatting and environment setup.
- `suderman-help.el`: keyboard cheatsheets and command labels.
- `suderman-reload.el`: hot reload.
- `suderman-keys.el`: global keys and the `SPC` leader, loaded last.

`meow-purrsist` (`~/src/suderman/meow-purrsist`) owns generic persistent Meow
selection behavior. `edger` (`~/src/suderman/edger`) owns window movement that
can hand off to the surrounding terminal multiplexer.

Do not put generated files, package trees, caches, or compiled Elisp in the
repository. `.gitignore` describes those boundaries.

## Keys

The source is the keymap. Do not copy key lists into documentation; the
cheatsheet (`SPC ?`, `C-c h`), Which-Key, and Dirvish `?` show live bindings.

- Meow Normal and Motion: `suderman/meow-setup-qwerty` in `suderman-meow.el`.
  It restores Meow's stock maps first, so deleting a binding there really
  deletes it on reload.
- Global keys and `SPC`: `suderman-keys.el`.
- Meta window keys: `suderman/window-keys`.
- Dired/Dirvish: `suderman/dirvish-keys`. IBuffer, Magit, Org Agenda, Image
  mode, and mail: the `:config` of their `use-package` forms.

Traps that cost real debugging time:

- Meow's emulation maps outrank major-mode maps. A key can look right in a
  keymap inspection and do something else in a live buffer. Check
  `key-binding` in the real buffer.
- IBuffer, Dirvish, Magit, Org Agenda, and the cheatsheet disable Meow locally
  so their own maps own `hjkl` and single letters. `SPC` there calls
  `meow-keypad` directly without enabling a Meow state.
- `SPC` is both Meow's keypad and the leader. Its native `h` translation starts
  a `C-h` sequence.
- On Android, a tap on Dired's highlighted filename arrives as `mouse-2`. Do
  not let native Dired's other-window binding win there.
- Desktop single click in Dirvish must keep focus in the root pane rather than
  activating the preview.
- Dirvish parent and breadcrumb buffers are sparse special modes, not Dired
  buffers. Preserve the parent navigation bindings, the windmove filter, and
  the breadcrumb advice. Preview panes stay normal windows because `M-o` can
  turn one into an editable buffer.
- Do not open a sidebar over the full-frame Dirvish layout; close it first.
  Narrowing clears subtree overlays by upstream design, and emerge groups do
  not coexist with active subtrees.
- `M-w` closes a window. Meow's internal copy backend calls `kill-ring-save`
  directly instead of replaying `M-w`.
- An isolated `<escape>` quits one Transient level without replacing raw `ESC`
  as the Meta prefix.
- Conflict commands use upper/lower because ours/theirs swap during a rebase.
- IBuffer relies on native `quit-window` restoration. Do not add a custom
  window stack unless native restoration has been shown to fail.

Test explorer changes with real windows: contextual IBuffer transitions,
breadcrumb clicks, parent clicks and keyboard navigation, and sidebar toggling.
Calling commands in an arbitrary temporary buffer proves little.

## Package choices that already have a reason

These choices are not immutable, but replacing one needs a concrete benefit.

- Built-in `project.el` is the project API. Do not add Projectile alongside it.
- Vertico, Orderless, Consult, Marginalia, and Embark form the minibuffer stack.
- Meow owns modal editing.
- Repeat-FU owns edit repeat on `;`. Its Meow preset records edits across
  insert-state transitions and keeps history across buffers.
- `surround` owns pair insertion, deletion, change, and pair selection.
- `scroll-on-jump` animates keyboard pages and selected jumps. Built-in
  pixel-scroll precision mode stays off because it interfered with
  cursor-preserving keyboard paging.
- Doom Modeline supplies the modeline and native Meow state segment.
- Nerd Icons packages decorate Doom Modeline, IBuffer, and Dirvish.
- Dirvish owns both focused file management and the persistent project tree,
  with its official extensions.
- PDF Tools renders PDFs inside Emacs. EPUB, audio, and video opened from
  Dirvish use the desktop MIME handler. Kitty graphics and `mpv` preview images
  and video inside terminal frames.
- Magit owns repository operations, diff-hl owns live hunk indicators, and
  built-in smerge-mode plus Ediff resolve conflicts. Forge is intentionally
  absent.
- Tree-sitter modes are preferred where the Nix package supplies grammars.
- Markdown preview uses Pandoc and a small local HTTP server. It refreshes only
  after save and preserves browser scroll position.
- Emacs 31 supplies `markdown-ts-mode`; do not install the incompatible
  third-party package with the same name.

Avoid adding a package when an existing package or Emacs itself already covers
the request. This config has enough moving pieces.

## Hot reload is useful and imperfect

`suderman/reload-config` (F5) unloads and reloads the modules listed in
`init.el`. It is intended for command, keymap, face, and ordinary module edits.

- Meow's Normal and Motion maps are restored from a stock snapshot on each
  load, and the leader is rebuilt whole, so deleted bindings disappear.
  Bindings deleted from other packages' maps (IBuffer, Dired, Magit, global)
  stay live until restart.
- Re-enabling global Meow unnecessarily can leak a Meow state into buffers
  where Meow was disabled locally.
- `unload-feature` can demote live buffers to `fundamental-mode`. The reload
  code snapshots and restores major modes to prevent this.
- Advice, hooks, global minor modes, and frame callbacks must stay idempotent.
  `advice-add` and `add-hook` already replace an existing entry of the same
  function, so no `advice-remove` is needed first.
- Do not add one-off cleanup for code that no longer exists. A restart clears
  it; the cleanup would live forever.

`suderman-reload.el` excludes itself from hot unloading. When changing the
reload implementation, load that file explicitly before testing the full
reload command.

Restart Emacs for changes to `early-init.el`, package initialization, native
modules, daemon options, or process-level state.

## How to investigate bugs

Reproduce before editing. This config combines package internals, global minor
modes, emulation maps, side windows, daemon frames, and hot reload. The obvious
caller is often not the cause.

1. Inspect the effective command with `key-binding`, not only the declared
   major-mode map.
2. Reproduce in a fresh batch load when possible.
3. Reproduce in the running graphical daemon when frames, fonts, faces, side
   windows, or selected-window history matter.
4. Read the installed package source. The locally installed version is more
   useful than an old snippet from the web.
5. Change the smallest shared point that explains every failing path.

Actual keyboard sequences matter for Meow, Repeat-FU, command repetition,
physical Return versus `RET`, and commands that inspect `last-command` or
`this-command`. Separate calls to `execute-kbd-macro` can break consecutive-key
state. Use one macro for one sequence.

Batch Emacs differs from an interactive session. `transient-mark-mode`, the
selected window, active regions, graphical face resolution, and daemon frame
state have all produced misleading test results. Meow also prints cursor-shape
escapes in batch; that noise is harmless.

When a command should follow the user's visible editor context, prefer the
selected window's buffer over ambient `current-buffer`. Sidebars and package
callbacks can leave `current-buffer` somewhere surprising.

## Verification

Use the smallest checks that match the change.

- Run the safety suite with `./test/run.sh`.
- Load the full config with `emacs --batch -l init.el`.
- Byte-compile every changed module, sending `.elc` output outside the
  repository.
- Run `git diff --check`.
- Inspect the relevant diff and keep it limited to the task.

For interactive behavior, also reload or restart the daemon and exercise the
real key sequence. Check GUI and terminal frames when frame handling or Nerd
Font rendering changes. Check two frames when changing frame-local explorer or
sidebar behavior.

Known warnings are not a reason to ignore new warnings. Confirm that a warning
is pre-existing before calling it harmless.

## Git and generated state

The ignored `projects` file is mutable Emacs project history. The running
editor rewrites it. Treat it as user-owned runtime state.

Other agents or the user may change the worktree while work is in progress.
Do not undo unrelated changes. If a concurrent change conflicts with the same
code, stop and ask.

Do not commit or push unless asked. Before a requested commit, inspect status,
unstaged and staged diffs, and recent history. Stage only the intended files.

## Taste and maintenance rules

Use lexical binding. Follow the existing `suderman/` namespace for functions
and variables that are not private file constants. Keep comments short and
explain only behavior that the code cannot make obvious.

Prefer built-in Emacs behavior, then an installed package, then a small custom
command. Delete obsolete code when the reason for it is gone. Do not add
compatibility branches for versions this setup does not run.

This config values direct keyboard workflows, stable cursor and window
behavior, project context, and a clean interface. It does not value framework
construction or an abstract configuration system. Make the smallest change
that works, verify it in the path Jon actually uses, and leave the code easier
to understand than you found it.
