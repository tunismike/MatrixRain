import subprocess
import time
import os
import sys
import signal

# --- CONFIG ---
CHECK_INTERVAL = 10  # Check power status every 10 seconds
LAUNCHER_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "multi_display_wallpaper.py")
SCRIPT_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "matrix_rain.py")
PYTHON_EXEC = sys.executable

def is_plugged_in():
    """Returns True if the Mac is plugged into AC power."""
    try:
        # 'pmset -g batt' returns 'AC Power' if plugged in
        output = subprocess.check_output("pmset -g batt", shell=True).decode()
        return "AC Power" in output
    except Exception:
        # Default to True (safe behavior) if check fails
        return True

def get_wallpaper_pids():
    """Finds all PIDs of matrix wallpaper processes (NOT screensaver)."""
    pids = []
    try:
        # Check for multi_display_wallpaper.py launcher
        try:
            launcher_pids = subprocess.check_output(["pgrep", "-f", "multi_display_wallpaper.py"]).decode().strip().split('\n')
            pids.extend([int(p) for p in launcher_pids if p])
        except subprocess.CalledProcessError:
            pass
        
        # Check for matrix_rain.py with --wallpaper flag
        try:
            cmd = ["pgrep", "-f", "matrix_rain.py.*--wallpaper"]
            wallpaper_pids = subprocess.check_output(cmd).decode().strip().split('\n')
            pids.extend([int(p) for p in wallpaper_pids if p])
        except subprocess.CalledProcessError:
            pass
        
        # Also check for old-style wallpaper (matrix_rain.py without --screensaver and without --wallpaper)
        # This maintains backward compatibility
        try:
            all_pids = subprocess.check_output(["pgrep", "-f", "matrix_rain.py"]).decode().strip().split('\n')
            for pid in all_pids:
                if not pid: continue
                try:
                    args = subprocess.check_output(["ps", "-p", pid, "-o", "command="]).decode()
                    if "matrix_rain.py" in args and "--screensaver" not in args and int(pid) not in pids:
                        pids.append(int(pid))
                except:
                    continue
        except subprocess.CalledProcessError:
            pass
    except Exception:
        pass
    return pids if pids else None

def main():
    print("Matrix Wallpaper Power Manager started.")
    
    while True:
        try:
            plugged_in = is_plugged_in()
            pids = get_wallpaper_pids()
            
            if plugged_in:
                if not pids:
                    print("⚡️ AC Power detected. Starting Matrix Wallpaper on all displays...")
                    subprocess.Popen([PYTHON_EXEC, LAUNCHER_PATH])
            else:
                if pids:
                    print(f"🔋 Battery Mode detected. Stopping {len(pids)} Matrix Wallpaper process(es)...")
                    for pid in pids:
                        try:
                            os.kill(pid, signal.SIGTERM)
                        except ProcessLookupError:
                            pass  # Process already terminated
            
            time.sleep(CHECK_INTERVAL)
            
        except KeyboardInterrupt:
            break
        except Exception as e:
            print(f"Error: {e}")
            time.sleep(CHECK_INTERVAL)

if __name__ == "__main__":
    main()
