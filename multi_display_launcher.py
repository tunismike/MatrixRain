#!/usr/bin/env python3
"""
Multi-Display Screensaver Launcher

This script launches a separate Matrix Rain screensaver process for each connected display.
Each process runs in fullscreen mode on its assigned display.
"""

import subprocess
import sys
import os
import signal
import time

# Get the directory where this script is located
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
MATRIX_RAIN_SCRIPT = os.path.join(SCRIPT_DIR, "matrix_rain.py")

# Determine the correct Python executable (prefer venv)
VENV_PYTHON = os.path.join(SCRIPT_DIR, "venv", "bin", "python")
if os.path.exists(VENV_PYTHON):
    PYTHON_EXEC = VENV_PYTHON
else:
    PYTHON_EXEC = sys.executable

def get_num_displays():
    """Get the number of connected displays using AppKit (primary) or pygame (fallback)."""
    try:
        from AppKit import NSScreen
        return len(NSScreen.screens())
    except ImportError:
        pass
        
    try:
        import pygame
        pygame.init()
        num = pygame.display.get_num_displays()
        pygame.quit()
        return num
    except Exception as e:
        print(f"Error getting display count: {e}")
        return 1

def launch_screensavers():
    """Launch a screensaver process for each display."""
    num_displays = get_num_displays()
    print(f"Launching screensaver on {num_displays} display(s)...")
    
    processes = []
    
    # Launch in REVERSE order - secondary displays first, primary (0) last
    # This helps avoid conflicts where display 0 takes over rendering
    for display_index in reversed(range(num_displays)):
        # Launch matrix_rain.py with --screensaver and --display arguments
        cmd = [
            PYTHON_EXEC,
            MATRIX_RAIN_SCRIPT,
            "--screensaver",
            "--display", str(display_index)
        ]
        print(f"  Starting on display {display_index}: {' '.join(cmd)}")
        proc = subprocess.Popen(cmd)
        processes.append(proc)
        # Longer delay between launches to prevent race conditions
        time.sleep(1.0)
    
    # Wait for all processes to complete (they'll exit on user input)
    print("Screensavers running. Press any key or move mouse to exit.")
    
    try:
        # Wait for the first process to exit (indicates user interaction)
        while all(p.poll() is None for p in processes):
            time.sleep(0.1)
    except KeyboardInterrupt:
        pass
    
    # When one exits, kill all others
    print("Terminating all screensaver instances...")
    for proc in processes:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
    
    print("All screensavers terminated.")

if __name__ == "__main__":
    launch_screensavers()
