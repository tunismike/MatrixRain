import subprocess
import time
import os
import sys
import configparser

# --- CONFIG ---
CHECK_INTERVAL = 5            # Check every 5 seconds
LAUNCHER_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "multi_display_launcher.py")
SCRIPT_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "matrix_rain.py")
CONFIG_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "config.ini")
# Determine the correct Python executable (prefer venv)
CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
VENV_PYTHON = os.path.join(CURRENT_DIR, "venv", "bin", "python")
if os.path.exists(VENV_PYTHON):
    PYTHON_EXEC = VENV_PYTHON
else:
    PYTHON_EXEC = sys.executable

def get_idle_time():
    """Returns macOS idle time in seconds using ioreg."""
    try:
        cmd = "ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print $NF/1000000000; exit}'"
        result = subprocess.check_output(cmd, shell=True)
        return float(result.strip())
    except Exception:
        return 0.0

def is_running(script_name):
    """Checks if the script is already running."""
    try:
        # Check for python process running matrix_rain.py
        subprocess.check_output(f"pgrep -f '{script_name}'", shell=True)
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
    except Exception as e:
        # Fallback defaults if config is unreadable
        return 180, True

def main():
    print(f"Matrix Screensaver Watcher started.")
    
    while True:
        try:
            idle_threshold, enabled = load_config()
            
            if enabled:
                idle_time = get_idle_time()
                if idle_time > idle_threshold:
                    if not is_running("matrix_rain.py --screensaver"):
                        print(f"System idle ({idle_time:.1f}s > {idle_threshold}s). Launching Matrix Rain on all displays...")
                        # Launch multi-display screensaver
                        subprocess.Popen([PYTHON_EXEC, LAUNCHER_PATH])
            
            time.sleep(CHECK_INTERVAL)
        except KeyboardInterrupt:
            break
        except Exception as e:
            print(f"Error: {e}")
            time.sleep(CHECK_INTERVAL)

if __name__ == "__main__":
    main()
