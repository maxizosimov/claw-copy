#!/usr/bin/env bash
# Static guardrails for Claw Copy. Fails if the code gains any way to talk to the network
# (beyond the one documented update check), run other programs, load code dynamically, or pull
# in third-party dependencies.
set -euo pipefail
cd "$(dirname "$0")/.."

status=0
fail() { echo "SECURITY CHECK FAILED: $*" >&2; status=1; }

# Networking, process execution, scripting, dynamic loading and web rendering APIs.
banned='NSURLConnection|NSURLDownload|NWConnection|NWListener|NWBrowser|NWPathMonitor|import Network|CFSocket|CFStream|CFNetwork|CFHTTP|getaddrinfo|gethostbyname|socket\(|connect\(|Data\(contentsOf|String\(contentsOf|NSData\(contentsOf|import WebKit|WKWebView|WebView|JavaScriptCore|JSContext|Process\(|NSTask|posix_spawn|popen\(|system\(|execv|execl|dlopen|dlsym|NSAppleScript|OSAScript|NSUserAppleScriptTask|NSXPCConnection|NSUserUnixTask|SMLoginItemSetEnabled|SMJobBless|SMJobSubmit|LSSharedFileList|URLComponents'
if grep -rnE "$banned" Sources Package.swift; then
  fail "banned API found above"
fi

# The only network access is the update check in UpdateChecker.swift: one GET to GitHub's
# "latest release" API for this repository. No other file may use URLSession, and that file may
# not download, upload or send anything else.
UPDATER=Sources/ClawCopy/UpdateChecker.swift
if grep -rnE 'URLSession|URLRequest' Sources | grep -v "^$UPDATER:"; then
  fail "networking outside $UPDATER found above"
fi
if grep -nE 'downloadTask|uploadTask|\.download\(|\.upload\(|httpMethod|httpBody|webSocket|streamTask|dataTask\(' "$UPDATER"; then
  fail "the update check may only perform a plain GET"
fi

# No remote URL literals except the update check's two: the API endpoint and the releases page.
if grep -rnEi '"(https?|ftp|wss?)://' Sources | grep -v "^$UPDATER:"; then
  fail "remote URL literal found above"
fi
urls=$(grep -oEi '"(https?|ftp|wss?)://[^"]*"' "$UPDATER" | sort -u | tr '\n' ' ')
expected='"https://api.github.com/repos/maxizosimov/claw-copy/releases/latest" "https://github.com/maxizosimov/claw-copy/releases/" '
if [ "$urls" != "$expected" ]; then
  fail "unexpected URLs in $UPDATER: $urls"
fi

# Only two things may be opened: the local System Settings Accessibility pane and the
# (validated) release page.
opens=$(grep -rn 'NSWorkspace.shared.open' Sources | wc -l | tr -d ' ')
if [ "$opens" != "2" ]; then
  fail "expected exactly two NSWorkspace.shared.open calls, found $opens"
fi

# Keyboard privacy: key events are only ever reduced to "navigation key + Shift". The app must
# never read typed characters or install an event tap (which could block or rewrite keys).
if grep -rnE '\.characters([^A-Za-z]|$)|charactersIgnoringModifiers|charactersByApplyingModifiers|keyboardGetUnicodeString|UCKeyTranslate|tapCreate|CGEventTapCreate|IOHIDManager' Sources; then
  fail "keystroke content or event tap API found above"
fi
keymonitors=$(grep -rlE '\.keyDown|\.keyUp' Sources/ClawCopy | grep -vE 'KeyboardMonitor\.swift|ShortcutsWindow\.swift' || true)
if [ -n "$keymonitors" ]; then
  fail "key events may only be observed in KeyboardMonitor.swift (passive) and ShortcutsWindow.swift (own window), found in: $keymonitors"
fi
# System-wide monitors only where documented; the shortcut recorder only listens in its own window.
globalmonitors=$(grep -rl 'addGlobalMonitorForEvents' Sources/ClawCopy | grep -vE 'KeyboardMonitor\.swift|MouseMonitor\.swift' || true)
if [ -n "$globalmonitors" ]; then
  fail "system-wide event monitors may only be used in KeyboardMonitor.swift and MouseMonitor.swift, found in: $globalmonitors"
fi

# Open at Login: only SMAppService.mainApp (the app itself as a login item), only in LoginItem.swift.
# No helpers, daemons or launch agents.
if grep -rnE 'SMAppService' Sources | grep -vE 'SMAppService\.(mainApp|openSystemSettingsLoginItems)([^A-Za-z]|$)'; then
  fail "only SMAppService.mainApp may be used (no daemons, agents or helper login items)"
fi
smfiles=$(grep -rlE 'SMAppService|import ServiceManagement' Sources | grep -v 'Sources/ClawCopy/LoginItem.swift' || true)
if [ -n "$smfiles" ]; then
  fail "ServiceManagement may only be used in Sources/ClawCopy/LoginItem.swift, found in: $smfiles"
fi

# No persistence of clipboard contents: the app writes no files at all.
if grep -rnE 'FileManager|FileHandle|\.write\(to|\.write\(toFile|writeToFile|writeToURL|createFile|NSKeyedArchiver|fopen\(|CoreData|NSPersistentContainer|import SQLite|sqlite3_' Sources; then
  fail "file-writing or persistence API found above (clipboard history must stay in memory)"
fi

# HTML is only ever parsed by ClawCopyCore's own converter. AppKit's HTML import runs WebKit,
# which can load remote resources, so it must never be used.
if grep -rnE 'DocumentType\.html|documentType: *\.html|NSHTMLTextDocumentType|NSAttributedString\(html|initWithHTML|readFromHTML' Sources; then
  fail "HTML import API found above (use HTMLToMarkdown)"
fi

# Zero third-party dependencies.
if grep -nE '\.package\(' Package.swift; then
  fail "third-party package dependency found"
fi

if [ "$status" -eq 0 ]; then
  echo "Security checks passed: no network (except the update check), process, scripting, keystroke content or dependency usage."
fi
exit "$status"
