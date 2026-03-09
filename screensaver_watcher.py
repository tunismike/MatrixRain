import subprocess
import time
import os
import sys
import configparser

# --- CONFIG ---
CHECK_INTERVAL = 5            # Check every 5 seconds
CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
SWIFT_LAUNCHER = os.path.join(CURRENT_DIR, "MatrixScreensaver")
CONFIG_PATH = os.path.join(CURRENT_DIR, "config.ini")
HTML_PATH = os.path.join(CURRENT_DIR, "index.html")

def get_idle_time():
    """Returns macOS idle time in seconds using ioreg."""
    try:
        cmd = "ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print $NF/1000000000; exit}'"
        result = subprocess.check_output(cmd, shell=True)
        return float(result.strip())
    except Exception:
        return 0.0

def is_running():
    """Checks if the screensaver is already running."""
    try:
        subprocess.check_output(["pgrep", "-f", "MatrixScreensaver.*--screensaver"])
        return True
    except subprocess.CalledProcessError:
        return False

def load_config():
    """Reads screensaver settings from config.ini."""
    config = configparser.ConfigParser()
    try:
        config.read(CONFIG_PATH)
        idle_seconds = config.getint('Screensaver', 'IdleTimeSeconds', fallback=180)
        enabled = config.getboolean('Screensaver', 'Enabled', fallback=True)
        return idle_seconds, enabled
    except Exception:
        return 180, True

def main():
    if not os.path.exists(SWIFT_LAUNCHER):
        print(f"Error: MatrixScreensaver binary not found at {SWIFT_LAUNCHER}")
        print("Compile it with: swiftc -o MatrixScreensaver MatrixScreensaver.swift -framework Cocoa -framework WebKit")
        sys.exit(1)

    print(f"Matrix JS Screensaver Watcher started.")

    while True:
        try:
            idle_threshold, enabled = load_config()

            if enabled:
                idle_time = get_idle_time()
                if idle_time > idle_threshold:
                    if not is_running():
                        print(f"System idle ({idle_time:.1f}s > {idle_threshold}s). Launching JS Matrix Rain screensaver...")
                        subprocess.Popen([
                            SWIFT_LAUNCHER,
                            "--screensaver",
                            "--html", HTML_PATH
                        ])

            time.sleep(CHECK_INTERVAL)
        except KeyboardInterrupt:
            break
        except Exception as e:
            print(f"Error: {e}")
            time.sleep(CHECK_INTERVAL)

if __name__ == "__main__":
    main()
