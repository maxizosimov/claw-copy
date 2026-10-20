# Claw Copy

A tiny macOS menu bar app: **select text anywhere and it's already copied.** No Cmd+C needed.

- Drag across text, double-click a word, triple-click a line, or shift-click to extend a selection, and the selection goes to the clipboard.
- Keyboard selections work too: select with Shift + arrow keys (also with Option or Command, and
  Shift + Home / End / Page Up / Page Down), and the selection is copied when you release Shift.
- Select All works the same way: press Cmd+A and the selection is copied when you release Cmd.
  Pressing another key while still holding Cmd (for example Cmd+A then Cmd+V to replace
  everything) skips the copy, so paste-to-replace keeps working.
- Lives in the menu bar (clipboard icon). It has no Dock icon and no windows.
- Fully offline, with zero dependencies (see [Security](#security)).

## Requirements

- macOS 13 Ventura or later
- Xcode 15+ or the Swift 5.9+ command line tools (`xcode-select --install`)

## Build & run

```sh
./scripts/build-app.sh          # builds and signs "build/Claw Copy.app"
open "build/Claw Copy.app"
```

On first launch macOS asks for **Accessibility** permission
(System Settings › Privacy & Security › Accessibility). Turn on **Claw Copy**. The menu bar
menu shows "Copy on select is active" once access is granted.

> **Keep the permission across rebuilds:** run `./scripts/create-signing-identity.sh` once.
> It creates a local, self-signed code-signing certificate in its own keychain
> (`~/Library/Keychains/claw-copy-signing.keychain-db`) with a password you choose, and
> `build-app.sh` uses it automatically. That keychain stays locked except while a build signs
> the app, so every build asks for its password and nothing can sign silently as Claw Copy.
> Without it, builds are ad-hoc signed and macOS treats every rebuild as a new app.
> After switching signatures, reset the old permission once:
> `tccutil reset Accessibility com.maxizosimov.ClawCopy`, then open the app and enable it again.
> `./scripts/create-signing-identity.sh --remove` deletes the certificate, its key and its trust setting.
> You can also sign with your own identity: `SIGN_IDENTITY="Apple Development: you@example.com" ./scripts/build-app.sh`.

**Open at Login** is on by default: the first launch adds Claw Copy to System Settings › General ›
Login Items. Toggle it in the menu bar menu (**Open at Login**). Once you turn it off it stays off.
Login Items records the app at its current location, so move it to `/Applications` first if you
don't want it running from `build/`.

## How it works

1. A passive, system-wide mouse monitor spots selection gestures. It only observes events and never blocks or changes them.
   A passive keyboard monitor spots Shift + navigation key selections and Cmd+A, and reports them
   when Shift or Cmd is released (see [Keyboard privacy](#keyboard-privacy)).
2. Claw Copy asks the focused app for its selected text through the macOS Accessibility API.
3. If an app doesn't expose its selection that way (for example Chrome/Electron web content), Claw Copy
   sends that app a normal **Cmd+C**. It never does this in Finder, the Dock or other non-text
   elements such as lists, tables, buttons or images, so double-clicking a file never touches your clipboard.

Claw Copy never copies:

- password / secure text fields (it doesn't read them at all),
- anything in password managers (1Password, Bitwarden, Keychain Access, Passwords, KeePassXC, LastPass, Dashlane, Enpass),
- whitespace-only selections, or selections over 1M characters.

## Security

Claw Copy's job is to see what you select, so it's built to be boring and auditable:

- **No network access at all.** No networking code, no analytics, no update checks, no remote URLs.
- **No code execution.** It never runs shell commands or scripts, never loads plugins, and never renders HTML.
- **Selected text is inert data.** It is copied exactly as selected, never parsed as instructions,
  executed or opened. "Prompt-injection" style text is just more text. A unit test covers this.
- **No dependencies.** Only Apple system frameworks.
- **Not a keylogger.** See [Keyboard privacy](#keyboard-privacy).
- **No background helpers.** Open at Login uses macOS's standard login item for the app itself
  (`SMAppService.mainApp`): no daemons, launch agents or helper apps. CI enforces this too.
- **Hardened runtime, no entitlements.**
- **Enforced in CI.** `scripts/check-security.sh` fails the build if networking, process/script
  execution, dynamic loading, web views, remote URL literals or package dependencies appear.
  CI also fails if the app reads typed characters, installs a keyboard event tap, or observes key
  events anywhere but `KeyboardMonitor.swift`. CI also checks that the signed app has no entitlements and that the binary links no
  networking or web frameworks. CI actions are pinned to commit SHAs and run with a read-only token.

### Keyboard privacy

To copy keyboard selections, Claw Copy has to watch key presses. It is built so it can't log them:

- Each key press is reduced on the spot to its kind ("arrow / Home / End / Page Up / Page Down",
  "the A key", or "something else") and which modifier keys were held. It never reads which
  character was typed, and it stores nothing about any other key.
- The monitor is passive. It can't block, change or inject keystrokes, and it doesn't take over
  Ctrl+C or any other shortcut.
- While a password field has focus, macOS turns on Secure Event Input and stops delivering key
  events to every monitor, including this one.

## Development

```sh
swift test                      # unit tests for the core logic
./scripts/check-security.sh     # static security guardrails
```

- `Sources/ClawCopyCore`: pure Foundation logic (gesture detection, copy policies), fully unit tested.
- `Sources/ClawCopy`: the AppKit / Accessibility layer.

### Manual test checklist

- [ ] TextEdit: drag-select, double-click a word, triple-click a line → paste elsewhere.
- [ ] TextEdit: Shift + arrows, Shift + Option + arrows, Shift + Cmd + arrows, Shift + Home / End,
      then release Shift → paste elsewhere.
- [ ] Chrome and VS Code: select with Shift + arrows, release Shift → paste.
- [ ] Shift + arrows, then type a capital letter before releasing Shift → the clipboard is **unchanged**.
- [ ] Plain arrow keys, or Shift alone → the clipboard is **unchanged**.
- [ ] TextEdit and Chrome: Cmd+A, release Cmd → paste elsewhere.
- [ ] Copy some text, then in TextEdit hold Cmd and press A then V → the copied text replaces
      everything (the old document text is **not** copied).
- [ ] Finder: Cmd+A selects all files → the clipboard is **unchanged**.
- [ ] Safari and Chrome: select text on a web page → paste.
- [ ] VS Code / Slack (Electron): select text → paste.
- [ ] Terminal: select output → paste.
- [ ] A password field (e.g. a web login form): select the dots → the clipboard is **unchanged**.
- [ ] Finder: double-click a file to open it → the clipboard is **unchanged**.
- [ ] A single plain click anywhere → the clipboard is **unchanged**.
- [ ] First launch: menu bar → **Open at Login** is checked, and Claw Copy appears in
      System Settings › General › Login Items.
- [ ] Uncheck **Open at Login** → it disappears from Login Items. Quit and reopen → it stays unchecked.
- [ ] Log out and back in with it checked → Claw Copy starts on its own.
- [ ] Menu bar icon → Quit works.

## License

MIT
