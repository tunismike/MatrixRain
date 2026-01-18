import pygame
import random
import sys
import os
import screeninfo
import math
import configparser # Added for reading the config file

# --- macOS Desktop Level Support ---
def get_all_displays_rect():
    """Get the bounding rectangle covering all displays using PyObjC NSScreen (more reliable than screeninfo)."""
    try:
        from AppKit import NSScreen
        screens = NSScreen.screens()
        if not screens:
            return None
        
        # Get the bounding box of all screens
        # Note: macOS uses bottom-left origin, but we need top-left for SDL
        min_x = min(screen.frame().origin.x for screen in screens)
        max_x = max(screen.frame().origin.x + screen.frame().size.width for screen in screens)
        
        # For Y, macOS origin is bottom-left, so we need to find the visual top-left
        min_y = min(screen.frame().origin.y for screen in screens)
        max_y = max(screen.frame().origin.y + screen.frame().size.height for screen in screens)
        
        width = max_x - min_x
        height = max_y - min_y
        
        return (int(min_x), int(min_y), int(width), int(height))
    except ImportError:
        return None
    except Exception as e:
        print(f"Could not get display rect: {e}")
        return None

def set_wallpaper_mode():
    """Send the pygame window to the desktop level (behind all windows) on macOS."""
    try:
        from AppKit import NSApplication, NSWindow
        from Cocoa import NSWindowCollectionBehaviorCanJoinAllSpaces, NSWindowCollectionBehaviorStationary
        
        app = NSApplication.sharedApplication()
        for window in app.windows():
            # kCGDesktopWindowLevel = -2147483623 (desktop level)
            window.setLevel_(-2147483623)
            # Make it appear on all spaces/desktops
            window.setCollectionBehavior_(
                NSWindowCollectionBehaviorCanJoinAllSpaces | 
                NSWindowCollectionBehaviorStationary
            )
            # Prevent it from appearing in Mission Control
            window.setCanHide_(False)
        return True
    except ImportError:
        print("Note: AppKit not available. Install pyobjc for wallpaper mode: pip install pyobjc")
        return False
    except Exception as e:
        print(f"Could not enable wallpaper mode: {e}")
        return False

def reposition_window_to_all_displays():
    """After pygame window is created, reposition it to cover all displays using PyObjC."""
    try:
        from AppKit import NSApplication, NSScreen
        from Foundation import NSMakeRect
        
        screens = NSScreen.screens()
        if not screens:
            return False
        
        # Calculate bounding box of all screens
        min_x = min(screen.frame().origin.x for screen in screens)
        max_x = max(screen.frame().origin.x + screen.frame().size.width for screen in screens)
        min_y = min(screen.frame().origin.y for screen in screens)
        max_y = max(screen.frame().origin.y + screen.frame().size.height for screen in screens)
        
        width = max_x - min_x
        height = max_y - min_y
        
        print(f"Repositioning window to: origin=({min_x}, {min_y}), size=({width}x{height})")
        
        app = NSApplication.sharedApplication()
        for window in app.windows():
            new_frame = NSMakeRect(min_x, min_y, width, height)
            window.setFrame_display_(new_frame, True)
        return True
    except Exception as e:
        print(f"Could not reposition window: {e}")
        return False

def resource_path(relative_path):
    """ Get absolute path to resource, works for dev and for PyInstaller. """
    try:
        base_path = sys._MEIPASS
    except Exception:
        base_path = os.path.abspath(".")
    return os.path.join(base_path, relative_path)

def quantize_color(color, step=16):
    """
    Snaps a color to a limited palette to improve cache performance.
    A larger step is faster but has more visible color banding.
    """
    try:
        r, g, b = color
    except (TypeError, ValueError):
        # Failsafe in case the incoming color is somehow invalid.
        return (0, 255, 0) 

    # Quantize each component
    r_quant = int(round(r / step)) * step
    g_quant = int(round(g / step)) * step
    b_quant = int(round(b / step)) * step

    # Clamp the FINAL values to the valid 0-255 range to prevent the ValueError.
    # This is the critical fix.
    return (
        max(0, min(255, r_quant)),
        max(0, min(255, g_quant)),
        max(0, min(255, b_quant))
    )

# --- General Configuration ---
# NOTE: These are now DEFAULTS. They will be overridden by config.ini
FRAME_RATE = 60
BACKGROUND_COLOR = (0, 0, 0)
FONT_STRETCH_FACTOR = 1.25

#==============================================================================
# --- MASTER LAYER CONTROL PANEL ---
# NOTE: These are now DEFAULTS. They will be overridden by config.ini
#==============================================================================

# --- Green Haze/Fog Overlay ---
HAZE_ENABLED = True
HAZE_COLOR = (0, 255, 0)
HAZE_ALPHA = 10

# --- CRT Grid Overlay ---
CRT_GRID_ENABLED = True
CRT_GRID_SIZE = 3
CRT_GRID_COLOR = (0, 0, 0, 40)

# --- General Streak Behavior ---
LEADER_BRIGHTNESS_SPEED_MULTIPLIER = 1
SLOWEST_LEADER_FLICKER_INTERVAL_MS = 600  # Canon: even slow streaks flicker fairly often
FASTEST_LEADER_FLICKER_INTERVAL_MS = 4
FLICKER_SPEED_CURVE_EXPONENT = 1.3  # Canon: slight ease-in curve
SPEED_DISTRIBUTION_BIAS = 2.5
LEADER_EXTRA_BOLDNESS = 2

# --- Variable Speed (Canon Matrix Effect) ---
VARIABLE_SPEED_ENABLED = True
SPEED_CHANGE_INTERVAL_RANGE = (0.1, 0.5)  # Time in seconds between speed adjustments
SPEED_CHANGE_AMOUNT = 0.3  # Max fraction of speed range to change per adjustment


# --- Riding Cascade Effect (Original) ---
CASCADE_CHANCE_PER_SECOND = 0.25
CASCADE_RADIUS_PPS = 500
CASCADE_MAX_RADIUS = 500
CASCADE_FADE_IN_TIME_MS = 250
DARK_CASCADE_CHANCE = 0.5
CASCADE_BRIGHTNESS_BOOST = 1
CASCADE_FADE_LENGTH = 10
CASCADE_SPEED_CPS = 20

# --- Morphing Ripple Effect ---
RIPPLE_CHANCE_PER_SECOND = 0.25
RIPPLE_RADIUS_PPS = 120
RIPPLE_MAX_RADIUS = 700
RIPPLE_FADE_IN_TIME_MS = 2000
RIPPLE_FADE_OUT_TIME_S = 5.0
RIPPLE_BRIGHTNESS_BOOST = 1.3
RIPPLE_DISTORTION_FREQUENCY = 5.0
RIPPLE_DISTORTION_AMPLITUDE = 80.0
RIPPLE_DISTORTION_SPEED = 1.0


# --- Foreground Layer (Canon Colors) ---
FG_IS_BOLD = False
FG_FONT_SIZE = 18
FG_LINE_HEIGHT_MULTIPLIER = 1.1
FG_STREAM_SPACING = 11  # Canon: tight columns, minimal gaps
FG_SPEED_RANGE = (10, 300)
FG_LENGTH_RANGE = (5, 70)  # Canon: wider range, biased toward shorter
FG_DORMANCY_RANGE = (0, 1000)  # Canon: shorter dormancy for more constant activity
FG_FLICKER_CHANCE = 0.04  # Reduced: more stable trails, less chaotic
FG_LEADER_COLOR = (255, 255, 255)  # Canon: pure white leader
FG_TRAIL_COLOR = (50, 180, 120)  # Canon: noticeably cyan-tinted green
FG_CHAR_LIST = list("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabdefghijklmnopqrstuvwx____")
FG_HIGHLIGHT_HALO_SIZE = 8
FG_SECOND_CHAR_COLOR = (80, 255, 160)  # Canon: bright cyan-green just behind leader
FG_SECOND_CHAR_GRADIENT_RANGE = (0, 10)


# This will be set from config.ini
COLOR_QUANTIZATION_STEP = 16

class FontCache:
    def __init__(self, font, char_list, stretch_factor=1.0):
        self.font = font
        self.stretch_factor = stretch_factor
        self.master_cache = {}
        self.color_cache = {}

        for char in set(char_list):
            master_surface = font.render(char, True, (255, 255, 255))
            if self.stretch_factor != 1.0:
                original_width = master_surface.get_width()
                original_height = master_surface.get_height()
                new_height = int(original_height * self.stretch_factor)
                stretched_surface = pygame.transform.scale(master_surface, (original_width, new_height))
                self.master_cache[char] = stretched_surface
            else:
                self.master_cache[char] = master_surface

    def get_surface(self, char, color):
        if (char, color) in self.color_cache:
            return self.color_cache[(char, color)]
        
        master_surface = self.master_cache.get(char)
        if not master_surface:
            return self.font.render(char, True, color)
            
        tinted_surface = master_surface.copy()
        tinted_surface.fill(color, special_flags=pygame.BLEND_RGBA_MULT)
        self.color_cache[(char, color)] = tinted_surface
        return tinted_surface

class HighlightCascade:
    def __init__(self, origin_x, origin_y, is_dark):
        self.origin_x = origin_x
        self.origin_y = origin_y
        self.is_dark = is_dark
        self.current_radius = 0.0
        self.speed = CASCADE_RADIUS_PPS
        self.max_radius = CASCADE_MAX_RADIUS
        self.triggered_columns = set()

class Ripple:
    def __init__(self, origin_x, origin_y):
        self.origin_x = origin_x
        self.origin_y = origin_y
        self.current_radius = 0.0
        self.age = 0.0
        self.speed = RIPPLE_RADIUS_PPS
        self.max_radius = RIPPLE_MAX_RADIUS
        self.distortion_phase = 0.0 # For pre-calculation
        
        base_color = FG_LEADER_COLOR
        brightness = RIPPLE_BRIGHTNESS_BOOST
        r, g, b = base_color[0] * brightness, base_color[1] * brightness, base_color[2] * brightness
        max_val = max(r, g, b)
        if max_val > 255:
            scale = 255 / max_val
            r, g, b = r * scale, g * scale, b * scale
        self.target_color = (int(r), int(g), int(b))


def distance_sq_point_to_vertical_segment(px, py, seg_x, seg_y1, seg_y2):
    if seg_y1 > seg_y2:
        seg_y1, seg_y2 = seg_y2, seg_y1
    qx = seg_x
    qy = max(seg_y1, min(py, seg_y2))
    return (px - qx)**2 + (py - qy)**2

class HighlightCascadeManager:
    def __init__(self, column_layers):
        self.column_layers = column_layers
        self.all_columns = [col for layer in self.column_layers for col in layer]
        self.active_cascades = []

    def _start_new_cascade(self):
        eligible_columns = [
            c for c in self.all_columns
            if c.dormant_counter <= 0 and 0 < c.leader_pos_float < c.num_chars
        ]
        if not eligible_columns:
            return
        start_column = random.choice(eligible_columns)
        origin_x = start_column.x
        origin_y = start_column.leader_pos_float * start_column.line_height

        is_dark_cascade = random.random() < DARK_CASCADE_CHANCE
        self.active_cascades.append(HighlightCascade(origin_x, origin_y, is_dark_cascade))

    def update(self, delta_time):
        if random.random() < CASCADE_CHANCE_PER_SECOND * delta_time:
            self._start_new_cascade()

        for cascade in self.active_cascades[:]:
            cascade.current_radius += cascade.speed * delta_time
            cascade_radius_sq = cascade.current_radius * cascade.current_radius

            for column in self.all_columns:
                if abs(cascade.origin_x - column.x) > cascade.current_radius:
                    continue

                if column in cascade.triggered_columns or column.dormant_counter > 0 or column.trail_length <= 1:
                    continue
                leader_pos_int = int(column.leader_pos_float)
                if not (0 <= leader_pos_int < column.num_chars):
                    continue
                trail_top_y = (leader_pos_int - column.trail_length + 1) * column.line_height
                trail_bottom_y = leader_pos_int * column.line_height
                dist_sq_to_streak = distance_sq_point_to_vertical_segment(
                    cascade.origin_x, cascade.origin_y, column.x, trail_top_y, trail_bottom_y
                )
                if dist_sq_to_streak <= cascade_radius_sq:
                    column.trigger_cascade(cascade.origin_y, cascade.is_dark)
                    cascade.triggered_columns.add(column)

            if cascade.current_radius > cascade.max_radius:
                self.active_cascades.remove(cascade)

class RippleManager:
    def __init__(self, screen_width, screen_height):
        self.active_ripples = []
        self.screen_width = screen_width
        self.screen_height = screen_height

    def _start_new_ripple(self):
        origin_x = random.randint(0, self.screen_width)
        origin_y = random.randint(0, self.screen_height)
        self.active_ripples.append(Ripple(origin_x, origin_y))

    def update(self, delta_time):
        if random.random() < RIPPLE_CHANCE_PER_SECOND * delta_time:
            self._start_new_ripple()

        for ripple in self.active_ripples[:]:
            ripple.age += delta_time
            ripple.current_radius += ripple.speed * delta_time
            ripple.distortion_phase = ripple.age * RIPPLE_DISTORTION_SPEED
            
            total_lifetime = (RIPPLE_FADE_IN_TIME_MS / 1000.0) + RIPPLE_FADE_OUT_TIME_S
            if ripple.age > total_lifetime or ripple.current_radius > ripple.max_radius:
                self.active_ripples.remove(ripple)

    def get_active_ripples(self):
        return self.active_ripples


class Column:
    def __init__(self, x, screen_height, config):
        self.x = x
        self.screen_height = screen_height
        self.config = config
        self.font_cache = config['font_cache']
        self.font_size = config['font_size']
        self.line_height = self.font_size * self.config['line_height_multiplier']
        self.num_chars = math.ceil(screen_height / self.line_height) if self.line_height > 0 else 0
        if self.num_chars <= 0: return

        padding = LEADER_EXTRA_BOLDNESS
        max_width = self.font_size + (2 * padding)
        try:
            self.temp_surface = pygame.Surface((max_width, self.screen_height), pygame.SRCALPHA)
        except pygame.error:
            self.temp_surface = None
            self.num_chars = 0

        self.is_first_run = True
        self.characters = [[i * self.line_height, random.choice(config['char_list'])] for i in range(self.num_chars)]
        self.dormant_counter = 0
        self.leader_flicker_timer = 0.0
        self.trail_length = int(random.randint(*self.config['length_range']))

        self.cascade_pos_float = -1.0
        self.target_cascade_color = None
        self.is_cascade_dark = False
        self.cascade_age = 0.0
        
        # Variable speed attributes
        self.speed_change_timer = 0.0
        self.next_speed_change = random.uniform(*SPEED_CHANGE_INTERVAL_RANGE)
        self.min_speed_pps = 0.0
        self.max_speed_pps = 0.0

        self._reset_streak()

    def _reset_streak(self):
        if self.is_first_run:
            self.leader_pos_float = float(random.randint(-self.num_chars, -1))
            self.dormant_counter = random.randint(*self.config['dormancy_range'])
            self.is_first_run = False
        else:
            self.leader_pos_float = float(random.randint(-self.trail_length, 0))
            self.dormant_counter = 0

        min_speed, max_speed = self.config['speed_range']
        bias_exponent = 1.0 / SPEED_DISTRIBUTION_BIAS if SPEED_DISTRIBUTION_BIAS > 0 else 1.0
        normalized_speed = random.random() ** bias_exponent
        self.speed_pps = min_speed + ((max_speed - min_speed) * normalized_speed)
        self.speed_cps = self.speed_pps / self.line_height if self.line_height > 0 else 0
        
        # Store min/max for variable speed bounds
        self.min_speed_pps = min_speed
        self.max_speed_pps = max_speed
        self.speed_change_timer = 0.0
        self.next_speed_change = random.uniform(*SPEED_CHANGE_INTERVAL_RANGE)

        curved_speed_factor = normalized_speed ** FLICKER_SPEED_CURVE_EXPONENT
        dynamic_interval_ms = (1 - curved_speed_factor) * SLOWEST_LEADER_FLICKER_INTERVAL_MS + curved_speed_factor * FASTEST_LEADER_FLICKER_INTERVAL_MS
        self.flicker_interval_s = dynamic_interval_ms / 1000.0

        min_len, max_len = self.config['length_range']
        # Canon: bias toward shorter streaks with occasional long dramatic ones
        length_bias = random.random() ** 2.0  # Square for bias toward 0
        self.trail_length = int(min_len + ((max_len - min_len) * length_bias))
        self.leader_flicker_timer = 0.0

        self.cascade_pos_float = -1.0
        self._precompute_gradient(normalized_speed)

    def _precompute_gradient(self, normalized_speed):
        if self.trail_length <= 0:
            self.gradient_colors = []
            return

        leader_color = self.config['leader_color']
        bright_green = self.config['second_char_color']
        trail_color = self.config['trail_color']
        
        brightness_multiplier = 1.0 + (normalized_speed * (LEADER_BRIGHTNESS_SPEED_MULTIPLIER - 1.0))
        dynamic_leader_color = tuple(min(255, int(c * brightness_multiplier)) for c in leader_color)

        self.gradient_colors = []
        
        # Canon: ultra-smooth gradient with 5 color stops
        # Create intermediate colors for smoother transitions
        mid_bright = (
            (bright_green[0] + trail_color[0]) // 2,
            (bright_green[1] + trail_color[1]) // 2,
            (bright_green[2] + trail_color[2]) // 2
        )
        dark_green = (
            trail_color[0] // 2,
            trail_color[1] // 2,
            trail_color[2] // 2
        )
        
        # Color stops: position -> color
        color_stops = [
            (0.0, dynamic_leader_color),   # Leader: white
            (0.02, bright_green),           # Char 1-2: immediate bright green
            (0.15, bright_green),           # Hold bright green
            (0.30, mid_bright),             # Transition through mid
            (0.50, trail_color),            # Main trail color
            (0.75, dark_green),             # Darker green
            (1.0, (0, 0, 0))                # Fade to black
        ]
        
        for i in range(self.trail_length):
            position = i / max(1, self.trail_length - 1)
            
            if i == 0:
                # Leader stays pure white
                color = dynamic_leader_color
            else:
                # Find which two stops we're between
                start_stop = color_stops[0]
                end_stop = color_stops[-1]
                
                for j in range(len(color_stops) - 1):
                    if color_stops[j][0] <= position <= color_stops[j + 1][0]:
                        start_stop = color_stops[j]
                        end_stop = color_stops[j + 1]
                        break
                
                # Interpolate between stops with smoothstep for extra smoothness
                if end_stop[0] > start_stop[0]:
                    t = (position - start_stop[0]) / (end_stop[0] - start_stop[0])
                    # Smoothstep interpolation for silky transitions
                    t = t * t * (3 - 2 * t)
                else:
                    t = 1.0
                
                start_color = start_stop[1]
                end_color = end_stop[1]
                r = int(start_color[0] + (end_color[0] - start_color[0]) * t)
                g = int(start_color[1] + (end_color[1] - start_color[1]) * t)
                b = int(start_color[2] + (end_color[2] - start_color[2]) * t)
                color = (max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b)))
            
            self.gradient_colors.append(color)

    def trigger_cascade(self, y_pos, is_dark):
        if self.cascade_pos_float != -1.0 or self.dormant_counter > 0 or self.trail_length <= (CASCADE_FADE_LENGTH * 2) + 5:
            return
        if self.line_height <= 0: return
        target_char_index = round(y_pos / self.line_height)
        if not (0 <= target_char_index < self.num_chars):
            return
        leader_pos_int = int(self.leader_pos_float)
        highlight_start_pos = float(leader_pos_int - target_char_index)
        if not (0 <= highlight_start_pos < self.trail_length):
            return

        self.cascade_pos_float = highlight_start_pos
        self.cascade_age = 0.0
        self.is_cascade_dark = is_dark

        if self.is_cascade_dark:
            self.target_cascade_color = BACKGROUND_COLOR
        else:
            base_color = self.config['leader_color']
            brightness = CASCADE_BRIGHTNESS_BOOST
            r, g, b = base_color[0] * brightness, base_color[1] * brightness, base_color[2] * brightness
            max_val = max(r, g, b)
            if max_val > 255:
                scale = 255 / max_val
                r, g, b = r * scale, g * scale, b * scale
            self.target_cascade_color = (int(r), int(g), int(b))

    def update_and_draw(self, main_surface, delta_time, active_ripples):
        if self.num_chars <= 0 or not self.temp_surface: return

        if self.dormant_counter > 0:
            self.dormant_counter -= 1
            return
        
        # Variable speed update (canon Matrix effect)
        if VARIABLE_SPEED_ENABLED:
            self.speed_change_timer += delta_time
            if self.speed_change_timer >= self.next_speed_change:
                # Randomly adjust speed within bounds
                speed_range = self.max_speed_pps - self.min_speed_pps
                max_change = speed_range * SPEED_CHANGE_AMOUNT
                speed_delta = random.uniform(-max_change, max_change)
                self.speed_pps = max(self.min_speed_pps, min(self.max_speed_pps, self.speed_pps + speed_delta))
                self.speed_cps = self.speed_pps / self.line_height if self.line_height > 0 else 0
                
                # Reset timer and set next change interval
                self.speed_change_timer = 0.0
                self.next_speed_change = random.uniform(*SPEED_CHANGE_INTERVAL_RANGE)

        self.leader_flicker_timer += delta_time
        self.leader_pos_float += self.speed_cps * delta_time

        if self.leader_pos_float - self.trail_length > self.num_chars:
            self._reset_streak()
            return

        leader_pos_int = int(self.leader_pos_float)
        drawable_chars = []

        start_char_index = max(0, leader_pos_int - self.trail_length + 1)
        end_char_index = min(self.num_chars, leader_pos_int + 2)

        for i in range(start_char_index, end_char_index):
            if not (0 <= i < self.num_chars): continue
            y_pos, value = self.characters[i]
            distance_from_leader = leader_pos_int - i

            if 0 <= distance_from_leader < self.trail_length:
                is_leader = (distance_from_leader == 0)

                if is_leader:
                    # Canon: flicker speed tied to current travel speed (recalculated dynamically)
                    min_speed, max_speed = self.config['speed_range']
                    current_normalized_speed = (self.speed_pps - min_speed) / (max_speed - min_speed) if max_speed > min_speed else 0.5
                    current_normalized_speed = max(0.0, min(1.0, current_normalized_speed))
                    curved_speed = current_normalized_speed ** FLICKER_SPEED_CURVE_EXPONENT
                    dynamic_interval_ms = (1 - curved_speed) * SLOWEST_LEADER_FLICKER_INTERVAL_MS + curved_speed * FASTEST_LEADER_FLICKER_INTERVAL_MS
                    current_flicker_interval = dynamic_interval_ms / 1000.0
                    
                    if current_flicker_interval < delta_time or self.leader_flicker_timer >= current_flicker_interval:
                        self.characters[i][1] = random.choice(self.config['char_list'])
                        if self.leader_flicker_timer >= self.flicker_interval_s: self.leader_flicker_timer = 0
                else:
                    # Canon: distance-based flicker - older/dimmer chars flicker more
                    base_flicker = self.config['flicker_chance']
                    distance_factor = distance_from_leader / self.trail_length  # 0 near leader, 1 at end
                    flicker_chance = base_flicker + (distance_factor * base_flicker * 2)  # Up to 3x more at tail
                    if random.random() < flicker_chance:
                        self.characters[i][1] = random.choice(self.config['char_list'])

                value = self.characters[i][1]
                final_color = self.gradient_colors[distance_from_leader]

                if self.cascade_pos_float != -1.0:
                    dist_from_hl_center = abs(distance_from_leader - int(self.cascade_pos_float))
                    halo_size = self.config['highlight_halo_size']
                    if dist_from_hl_center <= halo_size:
                        halo_falloff = (halo_size - dist_from_hl_center) / halo_size if halo_size > 0 else 1.0
                        lifecycle_fade = 1.0
                        fade_len = CASCADE_FADE_LENGTH
                        if fade_len > 0:
                            dist_from_start = (self.trail_length - 1) - self.cascade_pos_float
                            if dist_from_start < fade_len:
                                lifecycle_fade = dist_from_start / (fade_len - 1) if fade_len > 1 else 1.0
                            elif self.cascade_pos_float < fade_len:
                                lifecycle_fade = self.cascade_pos_float / (fade_len - 1) if fade_len > 1 else 1.0
                        final_intensity = halo_falloff * lifecycle_fade
                        fade_in_duration_s = CASCADE_FADE_IN_TIME_MS / 1000.0
                        if fade_in_duration_s > 0 and self.cascade_age < fade_in_duration_s:
                            final_intensity *= (self.cascade_age / fade_in_duration_s)
                        final_intensity = max(0.0, min(1.0, final_intensity))
                        r,g,b = final_color
                        tr,tg,tb = self.target_cascade_color
                        final_color = (int(r + (tr - r) * final_intensity), int(g + (tg - g) * final_intensity), int(b + (tb - b) * final_intensity))

                for ripple in active_ripples:
                    max_possible_radius = ripple.current_radius + RIPPLE_DISTORTION_AMPLITUDE
                    if abs(self.x - ripple.origin_x) > max_possible_radius or \
                       abs(y_pos - ripple.origin_y) > max_possible_radius:
                        continue
                    
                    dx = self.x - ripple.origin_x
                    dy = y_pos - ripple.origin_y
                    dist_sq = dx * dx + dy * dy
                    
                    angle = math.atan2(dy, dx)
                    distortion = math.sin(angle * RIPPLE_DISTORTION_FREQUENCY + ripple.distortion_phase) * RIPPLE_DISTORTION_AMPLITUDE
                    distorted_radius = ripple.current_radius + distortion
                    
                    if dist_sq < distorted_radius * distorted_radius:
                        dist = math.sqrt(dist_sq)
                        proximity_fade = 1.0 - (dist / distorted_radius) if distorted_radius > 0 else 0
                        
                        fade_in_duration_s = RIPPLE_FADE_IN_TIME_MS / 1000.0
                        lifecycle_fade = 0.0
                        if ripple.age < fade_in_duration_s:
                            progress = ripple.age / fade_in_duration_s
                            p = max(0.0, min(1.0, progress))
                            lifecycle_fade = p * p * p
                        else:
                            progress = (ripple.age - fade_in_duration_s) / RIPPLE_FADE_OUT_TIME_S
                            p = 1.0 - max(0.0, min(1.0, progress))
                            lifecycle_fade = p * p * p
                        
                        final_intensity = proximity_fade * lifecycle_fade
                        final_intensity = max(0.0, min(1.0, final_intensity))

                        r,g,b = final_color
                        tr,tg,tb = ripple.target_color
                        final_color = (
                            int(r + (tr - r) * final_intensity),
                            int(g + (tg - g) * final_intensity),
                            int(b + (tb - b) * final_intensity)
                        )
                
                # --- OPTIMIZATION: COLOR QUANTIZATION ---
                final_color = quantize_color(final_color, step=COLOR_QUANTIZATION_STEP)

                char_surface = self.font_cache.get_surface(value, final_color)
                drawable_chars.append((char_surface, y_pos, is_leader))
        
        if not drawable_chars: return

        min_y = drawable_chars[0][1]
        max_y = drawable_chars[-1][1]
        last_char_surf, _, _ = drawable_chars[-1]
        rect_height = (max_y - min_y) + last_char_surf.get_height()
        rect_width = self.temp_surface.get_width()
        dirty_area_on_temp_surf = pygame.Rect(0, min_y, rect_width, rect_height)

        self.temp_surface.fill((0, 0, 0, 0), dirty_area_on_temp_surf)

        padding = LEADER_EXTRA_BOLDNESS
        origin_x = padding
        blend_mode = pygame.BLEND_RGBA_MAX

        for char_surf, y_pos, is_leader in drawable_chars:
            if is_leader:
                bold_offset = 1 if self.config['is_bold'] else 0
                self.temp_surface.blit(char_surf, (origin_x, y_pos), special_flags=blend_mode)
                if self.config['is_bold']:
                    self.temp_surface.blit(char_surf, (origin_x + 1, y_pos), special_flags=blend_mode)
                for i in range(LEADER_EXTRA_BOLDNESS):
                    offset = (i // 2) + 1
                    if i % 2 == 0:
                        self.temp_surface.blit(char_surf, (origin_x + bold_offset + offset, y_pos), special_flags=blend_mode)
                    else:
                        self.temp_surface.blit(char_surf, (origin_x - offset, y_pos), special_flags=blend_mode)
            else:
                self.temp_surface.blit(char_surf, (origin_x, y_pos), special_flags=blend_mode)
                if self.config['is_bold']:
                    self.temp_surface.blit(char_surf, (origin_x + 1, y_pos), special_flags=blend_mode)

        blit_x = self.x - padding
        main_surface.blit(self.temp_surface, (blit_x, min_y), area=dirty_area_on_temp_surf)

        if self.cascade_pos_float != -1.0:
            self.cascade_pos_float -= CASCADE_SPEED_CPS * delta_time
            self.cascade_age += delta_time
            if self.cascade_pos_float < 0:
                self.cascade_pos_float = -1.0


def draw_crt_grid(surface, grid_size, color):
    surface.fill((0, 0, 0, 0))
    width, height = surface.get_size()
    for x in range(0, width, grid_size):
        pygame.draw.line(surface, color, (x, 0), (x, height))
    for y in range(0, height, grid_size):
        pygame.draw.line(surface, color, (0, y), (width, y))

def main():
    global HAZE_ENABLED, CRT_GRID_ENABLED, COLOR_QUANTIZATION_STEP, FRAME_RATE

    # --- READ CONFIGURATION ---
    config = configparser.ConfigParser()
    try:
        config.read(resource_path('config.ini'))
        ripples_enabled_startup = config.getboolean('Settings', 'EnableRipples')
        cascades_enabled_startup = config.getboolean('Settings', 'EnableCascades')
        HAZE_ENABLED = config.getboolean('Settings', 'EnableHaze')
        CRT_GRID_ENABLED = config.getboolean('Settings', 'EnableCrtGrid')
        
        fg_spacing = config.getint('Settings', 'ForegroundSpacing')
        
        COLOR_QUANTIZATION_STEP = config.getint('Settings', 'ColorQuantizationStep')
        FRAME_RATE = config.getint('Settings', 'TargetFPS')
        ADAPTIVE_THRESHOLD = config.getint('Settings', 'AdaptiveThreshold')
        
    except Exception as e:
        print(f"Could not read config.ini, using default settings. Error: {e}")
        ripples_enabled_startup = True
        cascades_enabled_startup = True
        fg_spacing = FG_STREAM_SPACING
        ADAPTIVE_THRESHOLD = 45
        wallpaper_mode = False

    # Read wallpaper mode with its own try block (optional setting)
    try:
        wallpaper_mode = config.getboolean('Settings', 'WallpaperMode')
    except:
        wallpaper_mode = False

    # --- ARGUMENT PARSING (do this early for display setup) ---
    is_screensaver_mode = '--screensaver' in sys.argv
    is_wallpaper_arg = '--wallpaper' in sys.argv  # New: explicit wallpaper mode from command line
    
    # Parse --display argument for multi-monitor support
    target_display = None
    if '--display' in sys.argv:
        try:
            display_idx = sys.argv.index('--display')
            target_display = int(sys.argv[display_idx + 1])
        except (IndexError, ValueError):
            print("Warning: --display requires a display index number")
            target_display = None

    # Determine if we're in a per-display mode (screensaver OR wallpaper with --display)
    is_per_display_mode = (is_screensaver_mode or is_wallpaper_arg) and target_display is not None

    # --- DISPLAY INITIALIZATION ---
    if is_per_display_mode:
        # Use PyObjC to get the exact display dimensions and position
        from AppKit import NSScreen
        from Foundation import NSMakeRect
        
        screens = NSScreen.screens()
        if target_display >= len(screens):
            print(f"Warning: Display {target_display} not found, using display 0")
            target_display = 0
        
        target_screen = screens[target_display]
        frame = target_screen.frame()
        screen_x = int(frame.origin.x)
        screen_y = int(frame.origin.y)
        total_width = int(frame.size.width)
        total_height = int(frame.size.height)
        
        print(f"Display {target_display}: origin=({screen_x}, {screen_y}), size=({total_width}x{total_height})")
        
        # Set SDL window position BEFORE pygame.init to ensure correct placement
        os.environ['SDL_VIDEO_WINDOW_POS'] = f"{screen_x},{screen_y}"
        
        # Initialize pygame and create a NOFRAME window (not FULLSCREEN to avoid minimize conflicts)
        pygame.init()
        screen = pygame.display.set_mode((total_width, total_height), pygame.NOFRAME | pygame.DOUBLEBUF)
        
        # Wait for window to be ready, then position it on the target display
        pygame.event.pump()
        pygame.time.wait(100)
        
        # Use PyObjC to move the window to the correct display
        from AppKit import NSApplication
        app = NSApplication.sharedApplication()
        for window in app.windows():
            new_frame = NSMakeRect(screen_x, screen_y, total_width, total_height)
            window.setFrame_display_animate_(new_frame, True, False)
        
        print(f"Screensaver on display {target_display}: {total_width}x{total_height}")
    else:
        # Normal mode or screensaver without --display: try to span all displays
        display_rect = get_all_displays_rect()
        if display_rect:
            min_x, min_y, total_width, total_height = display_rect
            print(f"Using PyObjC NSScreen: origin=({min_x}, {min_y}), size=({total_width}x{total_height})")
            os.environ['SDL_VIDEO_WINDOW_POS'] = f"{min_x},{min_y}"
            pygame.init()
            screen = pygame.display.set_mode((total_width, total_height), pygame.NOFRAME | pygame.DOUBLEBUF, vsync=1)
            # Also reposition with PyObjC after creation to ensure correct placement
            pygame.time.wait(50)
            reposition_window_to_all_displays()
        else:
            try:
                monitors = screeninfo.get_monitors()
                min_x, min_y = min(m.x for m in monitors), min(m.y for m in monitors)
                max_x, max_y = max(m.x + m.width for m in monitors), max(m.y + m.height for m in monitors)
                total_width, total_height = max_x - min_x, max_y - min_y
                print(f"Using screeninfo: origin=({min_x}, {min_y}), size=({total_width}x{total_height})")
                os.environ['SDL_VIDEO_WINDOW_POS'] = f"{min_x},{min_y}"
                pygame.init()
                screen = pygame.display.set_mode((total_width, total_height), pygame.NOFRAME | pygame.DOUBLEBUF, vsync=1)
            except (screeninfo.common.ScreenInfoError, pygame.error):
                pygame.init()
                total_width, total_height = 1280, 720
                screen = pygame.display.set_mode((total_width, total_height), pygame.RESIZABLE | pygame.DOUBLEBUF, vsync=1)

    # --- Re-check screensaver mode (already parsed above) ---

    # --- WALLPAPER / SCREENSAVER ACTIVATION ---
    if is_screensaver_mode:
        # Screensaver settings: High quality, top level, exit on input
        ripples_enabled_startup = True
        cascades_enabled_startup = True
        FRAME_RATE = 60
        WallpaperMode = False # Ignore config wallpaper mode
        pygame.mouse.set_visible(False)
    elif is_wallpaper_arg or wallpaper_mode:
        # Wallpaper mode: runs behind all windows at desktop level
        pygame.display.set_caption("Matrix Rain Wallpaper")
        pygame.time.wait(100)
        # For per-display wallpaper mode, we need to apply desktop window level
        if is_per_display_mode:
            # Apply desktop level for this specific window
            try:
                from AppKit import NSApplication
                from Cocoa import NSWindowCollectionBehaviorCanJoinAllSpaces, NSWindowCollectionBehaviorStationary
                
                app = NSApplication.sharedApplication()
                for window in app.windows():
                    # kCGDesktopWindowLevel = -2147483623 (desktop level)
                    window.setLevel_(-2147483623)
                    window.setCollectionBehavior_(
                        NSWindowCollectionBehaviorCanJoinAllSpaces | 
                        NSWindowCollectionBehaviorStationary
                    )
                    window.setCanHide_(False)
                    window.orderFrontRegardless()
            except Exception as e:
                print(f"Could not set wallpaper mode: {e}")
        else:
            set_wallpaper_mode()
    
    drawing_surface = pygame.Surface((total_width, total_height), pygame.SRCALPHA)
    haze_surface = pygame.Surface((total_width, total_height), pygame.SRCALPHA)
    grid_surface = pygame.Surface((total_width, total_height), pygame.SRCALPHA)

    clock = pygame.time.Clock()
    
    # If screensaver, ensure window is above everything
    if is_screensaver_mode:
        try:
            from AppKit import NSApplication, NSWindow
            from Cocoa import NSWindowCollectionBehaviorCanJoinAllSpaces, NSWindowCollectionBehaviorStationary
            
            app = NSApplication.sharedApplication()
            
            # Set window level and behaviors
            # kCGScreenSaverWindowLevel = 1000 or 1002 depending on OS version
            # Using a high floating level to cover dock and menus
            for window in app.windows():
                window.setLevel_(2000) 
                window.setHidesOnDeactivate_(False)
                # Make it appear on all spaces/desktops
                window.setCollectionBehavior_(
                    NSWindowCollectionBehaviorCanJoinAllSpaces | 
                    NSWindowCollectionBehaviorStationary
                )
            
            # Only reposition if NOT using --display (trying to span all monitors)
            # When using --display, we're in fullscreen mode on a specific display
            if target_display is None:
                # Small delay to let the window level change take effect
                pygame.time.wait(50)
                
                # Now reposition to cover all displays AFTER window level is set
                # This is critical - macOS may reset window frame when level changes
                reposition_window_to_all_displays()
            else:
                # Re-apply frame for specific display manually in case Level change reset it
                try:
                    from Foundation import NSMakeRect
                    # Make sure we use the coordinates calculated earlier
                    pygame.time.wait(50)
                    new_frame = NSMakeRect(screen_x, screen_y, total_width, total_height)
                    for window in app.windows():
                        window.setFrame_display_animate_(new_frame, True, False)
                    print(f"Re-applied frame for display {target_display}: {screen_x},{screen_y} {total_width}x{total_height}")
                except Exception as e:
                    print(f"Error re-applying frame: {e}")
                

            
            # Bring window to front WITHOUT affecting other windows
            for window in app.windows():
                # Use orderFrontRegardless instead of makeKeyAndOrderFront
                # This brings the window to front without minimizing other windows
                window.orderFrontRegardless()
            
            # Only activate app for the primary display (0) or when not using --display
            # This prevents display 0 from minimizing display 1's window
            if target_display is None or target_display == 0:
                NSApplication.sharedApplication().activateIgnoringOtherApps_(True)
        except Exception as e:
            print(f"Could not set screensaver window level: {e}")

    # Initial input flush to prevent instant exit from launch delay
    if is_screensaver_mode:
         pygame.event.clear()


    try:
        font_path = resource_path("fonts/matrix.ttf")
        fonts = {s: pygame.font.Font(font_path, s) for s in [FG_FONT_SIZE]}
        caches = {
            'FG': FontCache(fonts[FG_FONT_SIZE], FG_CHAR_LIST, FONT_STRETCH_FACTOR)
        }
    except Exception as e:
        print(f"Error loading font. Make sure 'matrix.ttf' is present in the 'fonts' folder. Details: {e}")
        pygame.time.wait(5000)
        return

    configs = {}
    prefix = 'FG'
    config_keys = [
        'font_size', 'line_height_multiplier', 'speed_range', 'length_range',
        'dormancy_range', 'leader_color', 'trail_color', 'is_bold',
        'flicker_chance', 'char_list', 'highlight_halo_size',
        'second_char_color', 'second_char_gradient_range'
    ]
    configs[prefix.lower()] = {k: globals()[f'{prefix}_{k.upper()}'] for k in config_keys}
    configs[prefix.lower()]['font_cache'] = caches[prefix]

    column_layers = [
        [Column(x, total_height, configs['fg']) for x in range(0, total_width, fg_spacing)]
    ]
    
    cascade_manager = HighlightCascadeManager(column_layers)
    ripple_manager = RippleManager(total_width, total_height)

    if CRT_GRID_ENABLED:
        draw_crt_grid(grid_surface, CRT_GRID_SIZE, CRT_GRID_COLOR)
    if HAZE_ENABLED:
        haze_surface.fill((*HAZE_COLOR, HAZE_ALPHA))

    # --- ADAPTIVE QUALITY STATE ---
    ripples_enabled_runtime = ripples_enabled_startup
    cascades_enabled_runtime = cascades_enabled_startup
    fps_history = [FRAME_RATE] * 20

    running = True
    while running:
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                running = False
            
            # --- SCREENSAVER EXIT LOGIC ---
            if is_screensaver_mode:
                if event.type in [pygame.KEYDOWN, pygame.MOUSEBUTTONDOWN]:
                    # Exit on any key or click
                    running = False 
                elif event.type == pygame.MOUSEMOTION:
                    # Check for significant mouse movement to avoid jitter exits
                    if abs(event.rel[0]) > 5 or abs(event.rel[1]) > 5:
                        running = False
            else:
                 # Normal exit logic
                 if event.type in [pygame.KEYDOWN, pygame.MOUSEBUTTONDOWN]:
                    if getattr(event, 'key', None) in [pygame.K_ESCAPE, pygame.K_q]:
                        running = False

        delta_time_s = clock.tick(FRAME_RATE) / 1000.0
        
        # --- ADAPTIVE QUALITY LOGIC ---
        current_fps = clock.get_fps()
        if current_fps > 0: # Avoid division by zero if paused
            fps_history.pop(0)
            fps_history.append(current_fps)
            avg_fps = sum(fps_history) / len(fps_history)

            if avg_fps < ADAPTIVE_THRESHOLD:
                if ripples_enabled_runtime:
                    ripples_enabled_runtime = False
                    print(f"Performance low (Avg FPS: {avg_fps:.1f}), disabling ripples.")
                elif cascades_enabled_runtime:
                    cascades_enabled_runtime = False
                    print(f"Performance low (Avg FPS: {avg_fps:.1f}), disabling cascades.")
        
        screen.fill(BACKGROUND_COLOR)
        drawing_surface.fill((0, 0, 0, 0))

        active_ripples = ripple_manager.get_active_ripples() if ripples_enabled_runtime else []

        for layer in column_layers:
            for column in layer:
                column.update_and_draw(drawing_surface, delta_time_s, active_ripples)

        if cascades_enabled_runtime:
            cascade_manager.update(delta_time_s)
        if ripples_enabled_runtime:
            ripple_manager.update(delta_time_s)
        
        screen.blit(drawing_surface, (0, 0))
        if HAZE_ENABLED:
            screen.blit(haze_surface, (0, 0))
        if CRT_GRID_ENABLED:
            screen.blit(grid_surface, (0,0))
            
        pygame.display.set_caption(f"Matrix Rain FX (FPS: {clock.get_fps():.2f})")
        pygame.display.flip()

    pygame.quit()
    sys.exit()

if __name__ == "__main__":
    main()