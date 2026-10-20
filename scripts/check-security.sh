#!/usr/bin/env bash
# Static guardrails for Claw Copy. Fails if the code gains any way to talk to the network,
# run other programs, load code dynamically, or pull in third-party dependencies.
set -euo pipefail
cd "$(dirname "$0")/.."

status=0
fail() { echo "SECURITY CHECK FAILED: $*" >&2; status=1; }

# Networking, process execution, scripting, dynamic loading and web rendering APIs.
banned='URLSession|NSURLConnection|NSURLDownload|URLRequest|NWConnection|NWListener|NWBrowser|NWPathMonitor|import Network|CFSocket|CFStream|CFNetwork|CFHTTP|getaddrinfo|gethostbyname|socket\(|connect\(|Data\(contentsOf|String\(contentsOf|NSData\(contentsOf|import WebKit|WKWebView|WebView|JavaScriptCore|JSContext|Process\(|NSTask|posix_spawn|popen\(|system\(|execv|execl|dlopen|dlsym|NSAppleScript|OSAScript|NSUserAppleScriptTask|NSXPCConnection|SMAppService|NSUserUnixTask|URLComponents'
if grep -rnE "$banned" Sources Package.swift; then
  fail "banned API found above"
fi

# No hard-coded remote URLs anywhere in the app code.
if grep -rnEi '"(https?|ftp|wss?)://' Sources; then
  fail "remote URL literal found above"
fi

# Only one URL may be opened: the local System Settings Accessibility pane.
opens=$(grep -rn 'NSWorkspace.shared.open' Sources | wc -l | tr -d ' ')
if [ "$opens" != "1" ]; then
  fail "expected exactly one NSWorkspace.shared.open call, found $opens"
fi

# Zero third-party dependencies.
if grep -nE '\.package\(' Package.swift; then
  fail "third-party package dependency found"
fi

if [ "$status" -eq 0 ]; then
  echo "Security checks passed: no network, process, scripting or dependency usage."
fi
exit "$status"
