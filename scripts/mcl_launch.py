"""Shared helpers of the scripts that launch the app bundle (quit-e2e.py, smoke-run.py).

They never touch the user's own setup: the bundle is copied and re-signed under a throwaway bundle identifier, the
data directory is a temporary one, and the screen must be unlocked (an unreadable state counts as locked).
"""
import os
import plistlib
import shutil
import subprocess

REAL_DOMAIN = "cz.ok1xoe.maccontestlogger"


def screen_locked():
    """True when the screen is locked, when no user is on the console, or when the state cannot be read."""
    try:
        result = subprocess.run(["ioreg", "-n", "Root", "-d1", "-a"], capture_output=True, timeout=10)
        if result.returncode != 0:
            return True
        root = plistlib.loads(result.stdout)
    except Exception:
        return True
    if isinstance(root, list):
        root = root[0] if root else None
    if not isinstance(root, dict):
        return True
    users = [user for user in root.get("IOConsoleUsers", []) if isinstance(user, dict)]
    on_console = [user for user in users if user.get("kCGSSessionOnConsoleKey", False)]
    if not on_console:
        return True
    return any(user.get("CGSSessionScreenIsLocked", False) for user in users)


def preferences_file(domain):
    return os.path.expanduser(f"~/Library/Preferences/{domain}.plist")


def saved_state_dir(domain):
    return os.path.expanduser(f"~/Library/Saved Application State/{domain}.savedState")


def real_data_dir():
    return os.path.realpath(os.path.expanduser("~/Library/Application Support/MacContestLogger"))


def unsafe_data_dir(path):
    """Why `path` must not be used as MCL_DATA_DIR (the user's data, inside it, or a directory holding it), or None."""
    candidate = os.path.realpath(os.path.expanduser(path))
    real = real_data_dir()
    if candidate == real or candidate.startswith(real + os.sep):
        return "it is (inside) the user's own data directory"
    if real.startswith(candidate.rstrip(os.sep) + os.sep):
        return "it contains the user's own data directory"
    return None


def prepare_bundle(source, work, domain):
    """Copies the bundle into `work`, sets the throwaway bundle identifier `domain`, re-signs it ad hoc; returns the
    executable."""
    app = os.path.join(work, "MacContestLogger.app")
    shutil.copytree(source, app, symlinks=True)
    info = os.path.join(app, "Contents", "Info.plist")
    with open(info, "rb") as handle:
        plist = plistlib.load(handle)
    plist["CFBundleIdentifier"] = domain
    with open(info, "wb") as handle:
        plistlib.dump(plist, handle)
    subprocess.run(["codesign", "--force", "--deep", "-s", "-", app], check=True, capture_output=True)
    return os.path.join(app, "Contents", "MacOS", "MacContestLogger")


def clean_domain(domain):
    """Removes a throwaway domain (never the real one): its keys, the empty plist cfprefsd keeps, the saved state."""
    if domain == REAL_DOMAIN:
        raise ValueError("refusing to clean the user's own defaults domain")
    subprocess.run(["defaults", "delete", domain], capture_output=True)
    for path in (preferences_file(domain), saved_state_dir(domain)):
        if os.path.isdir(path):
            shutil.rmtree(path, ignore_errors=True)
        elif os.path.exists(path):
            os.remove(path)


def signal_child(process, signo):
    """Signals `process` (a subprocess.Popen this script started) only while it is unreaped: `poll()` reaps and
    records an exited child, and until then its pid cannot belong to anyone else."""
    if process.returncode is None and process.poll() is None:
        process.send_signal(signo)
        return True
    return False
