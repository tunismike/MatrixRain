import Cocoa
import WebKit

// ============================================================================
// Matrix Rain — Multi-Display Fullscreen WebView Launcher
// Launches a fullscreen WKWebView on each connected display showing index.html
// Exits on any key press or mouse click (screensaver behavior)
// ============================================================================

class MatrixWindow: NSWindow {
    var onUserInput: (() -> Void)?
    
    override func keyDown(with event: NSEvent) {
        onUserInput?()
    }
    
    override func mouseDown(with event: NSEvent) {
        onUserInput?()
    }
    
    override func mouseMoved(with event: NSEvent) {
        let dx = abs(event.deltaX)
        let dy = abs(event.deltaY)
        if dx > 5 || dy > 5 {
            onUserInput?()
        }
    }
    
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var windows: [MatrixWindow] = []
    var webViews: [WKWebView] = []
    
    let isScreensaverMode: Bool
    let isWallpaperMode: Bool
    let htmlURL: URL
    
    init(isScreensaver: Bool, isWallpaper: Bool, htmlURL: URL) {
        self.isScreensaverMode = isScreensaver
        self.isWallpaperMode = isWallpaper
        self.htmlURL = htmlURL
        super.init()
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        let screens = NSScreen.screens
        if screens.isEmpty {
            NSApp.terminate(nil)
            return
        }
        
        for (index, screen) in screens.enumerated() {
            createWindow(on: screen, displayIndex: index)
        }
        
        if isScreensaverMode {
            NSCursor.hide()
            // Bring all windows to front
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    func createWindow(on screen: NSScreen, displayIndex: Int) {
        let frame = screen.frame
        
        let window = MatrixWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        
        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = false
        window.acceptsMouseMovedEvents = isScreensaverMode
        
        // Set window level based on mode
        if isScreensaverMode {
            window.level = NSWindow.Level(rawValue: 2000) // Above everything
            window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        } else if isWallpaperMode {
            // kCGDesktopWindowLevel
            window.level = NSWindow.Level(rawValue: -2147483623)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary]
            window.ignoresMouseEvents = true
        }
        
        // Create WKWebView
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        
        let webView = WKWebView(frame: window.contentView!.bounds, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.setValue(false, forKey: "drawsBackground") // Transparent background during load
        
        window.contentView?.addSubview(webView)
        webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        
        // Exit handler for screensaver mode
        if isScreensaverMode {
            window.onUserInput = { [weak self] in
                self?.exitAll()
            }
        }
        
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()
        
        windows.append(window)
        webViews.append(webView)
    }
    
    func exitAll() {
        NSCursor.unhide()
        NSApp.terminate(nil)
    }
}

// ============================================================================
// MAIN
// ============================================================================

// Parse arguments
let args = CommandLine.arguments
let isScreensaver = args.contains("--screensaver")
let isWallpaper = args.contains("--wallpaper")

// Find the HTML file relative to the executable
let executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
var htmlURL = executableURL.appendingPathComponent("index.html")

// Also check for explicit --html argument
if let htmlIdx = args.firstIndex(of: "--html"), htmlIdx + 1 < args.count {
    htmlURL = URL(fileURLWithPath: args[htmlIdx + 1])
}

guard FileManager.default.fileExists(atPath: htmlURL.path) else {
    print("Error: Cannot find \(htmlURL.path)")
    print("Place index.html next to this executable, or use --html /path/to/index.html")
    exit(1)
}

let app = NSApplication.shared
let delegate = AppDelegate(isScreensaver: isScreensaver, isWallpaper: isWallpaper, htmlURL: htmlURL)
app.delegate = delegate
app.run()
