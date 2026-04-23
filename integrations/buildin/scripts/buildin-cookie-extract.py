#!/usr/bin/env python3
"""buildin-cookie-extract.py — read Buildin's `next_auth` cookie from a local
Chromium-family browser profile via pycookiecheat.

⚠️ DO NOT RUN THIS SCRIPT DIRECTLY FROM AN AGENT CONTEXT.
The raw cookie (a JWT whose payload contains the user's email) is written to
STDOUT — a naive agent invocation would pipe it straight into LLM context.

Always go through:
    bash integrations/buildin/scripts/buildin-login.sh cookie [browser]

…which captures stdout into a shell-local variable, validates, and writes to
.env without exposing anything to the agent beyond `ok <nickname> (via <browser>)`.

─────────────────────────────────────────────────────────────────────────────

Handles multiple profiles per browser: iterates Default, Profile 1, Profile 2,
... for each installed browser, picks the first profile where the cookie is
actually present.

Usage (for the shell wrapper only):
    buildin-cookie-extract.py [browser]

Arguments:
    browser (optional)  one of: chrome, chromium, brave, edge, vivaldi, opera,
                                arc, firefox, auto (default: auto — try all)

Contract:
    • On success: print the cookie value to STDOUT (no newline) and exit 0.
                  Print `browser:<name>/<profile>` to STDERR so the shell wrapper
                  can tell which browser+profile was used (non-sensitive).
    • On failure: print `error:<reason>` to STDERR and exit non-zero.
                  STDOUT must stay empty so wrapper can safely check emptiness.
"""
import glob
import os
import subprocess
import sys
from pathlib import Path

URL = "https://buildin.ai"
COOKIE_NAME = "next_auth"

# Per-browser data directory + Keychain service name (macOS).
# Linux: ~/.config/<browser-name>; Windows: %LOCALAPPDATA%\<vendor>\...
# We focus on macOS for now; Linux/Windows paths can be added later if needed.
BROWSERS = {
    "chrome": {
        "data_dir":  "~/Library/Application Support/Google/Chrome",
        "keychain":  "Chrome Safe Storage",
    },
    "chromium": {
        "data_dir":  "~/Library/Application Support/Chromium",
        "keychain":  "Chromium Safe Storage",
    },
    "brave": {
        "data_dir":  "~/Library/Application Support/BraveSoftware/Brave-Browser",
        "keychain":  "Brave Safe Storage",
    },
    "edge": {
        "data_dir":  "~/Library/Application Support/Microsoft Edge",
        "keychain":  "Microsoft Edge Safe Storage",
    },
    "vivaldi": {
        "data_dir":  "~/Library/Application Support/Vivaldi",
        "keychain":  "Vivaldi Safe Storage",
    },
    "opera": {
        "data_dir":  "~/Library/Application Support/com.operasoftware.Opera",
        "keychain":  "Opera Safe Storage",
    },
    "arc": {
        "data_dir":  "~/Library/Application Support/Arc/User Data",
        "keychain":  "Arc Safe Storage",
    },
}

SKIP_SUBDIRS = {
    "System Profile", "Guest Profile", "Crashpad", "Crash Reports", "Subresource Filter",
    "ShaderCache", "GrShaderCache", "GraphiteDawnCache", "component_crx_cache",
    "segmentation_platform", "OnDeviceHeadSuggestModel", "optimization_guide_model_store",
    "OptimizationHints", "First Party Sets", "Default Cache", "extensions_crx_cache",
    "GPUCache", "MEIPreload", "NativeMessagingHosts", "OnDeviceHeadSuggestModel",
    "PKIMetadata", "PrivacySandboxAttestationsPreloaded", "Safe Browsing", "Subresource Filter",
    "TrustTokenKeyCommitments", "WidevineCdm", "ZxcvbnData", "hyphen-data",
    "optimization_guide_hint_cache_store", "origin_trials",
}


def try_pycookiecheat_import():
    try:
        from pycookiecheat import chrome_cookies  # noqa: F401
        return True
    except ImportError:
        return False


def list_profile_cookie_files(browser: str):
    """Return [(profile_name, cookies_path), ...] for all profiles of a browser.
    Handles both `<Profile>/Cookies` (legacy) and `<Profile>/Network/Cookies`
    (Chrome 96+). Also handles flat layouts where Cookies lives at data-dir root."""
    info = BROWSERS.get(browser)
    if not info:
        return []
    root = Path(os.path.expanduser(info["data_dir"]))
    if not root.exists():
        return []

    found = []
    seen_paths = set()

    # Flat layout (some Opera builds): <data_dir>/Cookies directly
    for rel in ("Cookies", "Network/Cookies"):
        p = root / rel
        if p.exists() and p not in seen_paths:
            found.append(("<root>", p))
            seen_paths.add(p)

    # Per-profile layout: <data_dir>/<Profile>/[Network/]Cookies
    try:
        entries = sorted(root.iterdir())
    except (PermissionError, OSError):
        return found

    for sub in entries:
        if not sub.is_dir():
            continue
        if sub.name in SKIP_SUBDIRS or sub.name.startswith("."):
            continue
        for rel in ("Cookies", "Network/Cookies"):
            p = sub / rel
            if p.exists() and p not in seen_paths:
                found.append((sub.name, p))
                seen_paths.add(p)

    return found


def keychain_password(service: str) -> bytes:
    """Fetch the browser's Safe Storage key from macOS Keychain.
    Triggers the first-time Keychain prompt if not yet granted."""
    raw = subprocess.check_output(
        ["security", "find-generic-password", "-s", service, "-w"],
        stderr=subprocess.DEVNULL,
    )
    return raw.strip()


def extract_from_profile(browser: str, profile_name: str, cookie_file: Path):
    """Try to extract the Buildin cookie from one specific profile's Cookies DB."""
    from pycookiecheat import chrome_cookies
    info = BROWSERS[browser]

    # Always pass explicit cookie_file + keychain password. That way we can
    # enumerate non-default profiles (pycookiecheat's browser= enum only looks
    # at the Default profile) AND support browsers not in the enum.
    password = keychain_password(info["keychain"])
    cookies = chrome_cookies(url=URL, cookie_file=str(cookie_file), password=password)
    return cookies.get(COOKIE_NAME)


def extract_firefox():
    from pycookiecheat import firefox_cookies  # noqa
    cookies = firefox_cookies(URL)
    return cookies.get(COOKIE_NAME)


def try_browser(browser: str):
    """Yield (profile_label, token, error_msg) for each profile attempted.
    token is non-None on success; error_msg is non-None on failure."""
    if browser == "firefox":
        try:
            token = extract_firefox()
            if token:
                yield ("default", token, None)
            else:
                yield ("default", None, "cookie not present (not logged in?)")
        except Exception as e:
            yield ("default", None, f"{type(e).__name__}: {e}")
        return

    profiles = list_profile_cookie_files(browser)
    if not profiles:
        yield ("(no profiles)", None, "browser not installed or no profile cookies DB")
        return

    for profile_name, cookie_file in profiles:
        try:
            token = extract_from_profile(browser, profile_name, cookie_file)
        except Exception as e:
            yield (profile_name, None, f"{type(e).__name__}: {e}")
            continue
        if token:
            yield (profile_name, token, None)
            return
        yield (profile_name, None, "cookie not present in this profile")


def main():
    if not try_pycookiecheat_import():
        print(
            "error:pycookiecheat_not_installed "
            "(install: python3 -m pip install --user pycookiecheat)",
            file=sys.stderr,
        )
        sys.exit(2)

    requested = sys.argv[1].lower() if len(sys.argv) > 1 else "auto"

    if requested == "auto":
        candidates = list(BROWSERS.keys()) + ["firefox"]
    elif requested in BROWSERS or requested == "firefox":
        candidates = [requested]
    else:
        print(f"error:unknown_browser '{requested}'", file=sys.stderr)
        sys.exit(2)

    diag = []  # (browser, profile, error)
    for browser in candidates:
        for profile, token, err in try_browser(browser):
            if token:
                print(f"browser:{browser}/{profile}", file=sys.stderr)
                sys.stdout.write(token)
                return 0
            diag.append((browser, profile, err))

    print("error:no_cookie_found", file=sys.stderr)
    for b, p, e in diag:
        print(f"  {b}/{p}: {e}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
