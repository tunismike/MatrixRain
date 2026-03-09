import subprocess
import time
import os
import sys
import signal

# --- CONFIG ---
CHECK_INTERVAL = 10  # Check power status every 10 seconds
CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
SWIFT_LAUNCHER = os.path.join(CURRENT_DIR, "MatrixScreensaver")
HTML_PATH = os.path.join(CURRENT_DIR, "index.html")

def is_plugged_in():
    """Returns True if the Mac is plugged into AC power."""
    try:
        output = subprocess.check_output("pmset -g batt", shell=True).decode()
        return "AC Power" in output
    except Exception:
        return True

def get_wallpaper_pids():
    """Finds all PIDs of matrix wallpaper processes."""
    pids = []
    try:
        result = subprocess.check_output(["pgrep", "-f", "MatrixScreensaver.*--wallpaper"]).decode().strip().split('\n')
        pids.extend([int(p) for p in result if p])
    except subprocess.CalledProcessError:
        pass
    return pids if pids else None

def main():
    if not os.path.exists(SWIFT_LAUNCHER):
        print(f"Error: MatrixScreensaver binary not found at {SWIFT_LAUNCHER}")
        print("Compile it with: swiftc -o MatrixScreensaver MatrixScreensaver.swift -framework Cocoa -framework WebKit")
        sys.exit(1)

    print("Matrix JS Wallpaper Power Manager started.")

    while True:
        try:
            plugged_in = is_plugged_in()
            pids = get_wallpaper_pids()

            if plugged_in:
                if not pids:
                    print("⚡️ AC Power detected. Starting JS Matrix Wallpaper...")
                    subprocess.Popen([
                        SWIFT_LAUNCHER,
                        "--wallpaper",
                        "--html", HTML_PATH
                    ])
            else:
                if pids:
                    print(f"🔋 Battery Mode detected. Stopping {len(pids)} Matrix Wallpaper process(es)...")
                    for pid in pids:
                        try:
                            os.kill(pid, signal.SIGTERM)
                        except ProcessLookupError:
                            pass

            time.sleep(CHECK_INTERVAL)

        except KeyboardInterrupt:
            break
        except Exception as e:
            print(f"Error: {e}")
            time.sleep(CHECK_INTERVAL)

if __name__ == "__main__":
    main()
