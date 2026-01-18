#!/usr/bin/env python3
"""
Multi-Display Wallpaper Launcher

This script launches a separate Matrix Rain wallpaper process for each connected display.
Each process runs as a desktop-level window (behind all other windows) on its assigned display.
"""

import subprocess
import sys
import os
import signal
import time

# Get the directory where this script is located
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
MATRIX_RAIN_SCRIPT = os.path.join(SCRIPT_DIR, "matrix_rain.py")

def get_num_displays():
    """Get the number of connected displays using PyObjC (more reliable than pygame for this)."""
    try:
        from AppKit import NSScreen
        return len(NSScreen.screens())
    except Exception as e:
        print(f"Error getting display count: {e}")
        return 1

def launch_wallpapers():
    """Launch a wallpaper process for each display."""
    num_displays = get_num_displays()
    print(f"Launching wallpaper on {num_displays} display(s)...")
    
    processes = []
    
    # Launch in REVERSE order - secondary displays first, primary (0) last
    # This helps avoid conflicts where display 0 takes over rendering
    for display_index in reversed(range(num_displays)):
        # Launch matrix_rain.py with --wallpaper and --display arguments
        cmd = [
            sys.executable,
            MATRIX_RAIN_SCRIPT,
            "--wallpaper",
            "--display", str(display_index)
        ]
        print(f"  Starting on display {display_index}: {' '.join(cmd)}")
        proc = subprocess.Popen(cmd)
        processes.append(proc)
        # Delay between launches to prevent race conditions
        time.sleep(1.0)
    
    print("Wallpapers running on all displays.")
    print("To stop: run 'pkill -f \"matrix_rain.py --wallpaper\"' or use Activity Monitor")
    
    return processes

def stop_all_wallpapers():
    """Stop all running wallpaper instances."""
    try:
        subprocess.run(["pkill", "-f", "matrix_rain.py --wallpaper"], check=False)
        print("All wallpaper instances stopped.")
    except Exception as e:
        print(f"Error stopping wallpapers: {e}")

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--stop":
        stop_all_wallpapers()
    else:
        processes = launch_wallpapers()
        
        # Keep running to maintain the processes
        try:
            # Wait indefinitely - wallpapers run until killed
            while True:
                # Check if all processes are still running
                alive = [p for p in processes if p.poll() is None]
                if not alive:
                    print("All wallpaper processes have exited.")
                    break
                time.sleep(5)
        except KeyboardInterrupt:
            print("\nStopping all wallpapers...")
            for proc in processes:
                if proc.poll() is None:
                    proc.terminate()
            print("Done.")
