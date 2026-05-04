/**
 * AppDelegate.mm
 *
 * MilkDrop3 macOS application delegate.
 *
 * Render loop flow:
 *   MTKView (120 Hz preferred framerate)
 *     └─ drawInMTKView:
 *           ├─ IDirect3DDevice9::BeginFrame   (start Metal command buffer)
 *           ├─ CPlugin::PluginRender           (MilkDrop frame computation)
 *           ├─ IDirect3DDevice9::EndFrame      (commit + present)
 *           └─ [drawable present]
 *
 * Audio flow:
 *   CoreAudioCapture callback → pcmLeft/pcmRight uint8 arrays
 *     └─ CPlugin::PluginRender(pcmLeft, pcmRight)  (fed each frame)
 */

#import "AppDelegate.h"

// Pull in the full MilkDrop plugin with Windows compat layer active
#define MILKDROP_MACOS 1
#include "platform/win32_compat.h"
#include "platform/d3d_compat.h"
#include "platform/ini_parser.h"
#include "vis_milk2/plugin.h"

#include <cstring>
#include <atomic>

// ── Global plugin instance ────────────────────────────────────────────────────
static CPlugin            g_plugin;
static IDirect3DDevice9*  g_device        = nullptr;
static CoreAudioCapture*  g_audioCapture  = nullptr;

// PCM double-buffer: audio thread writes, render thread reads
static std::mutex   g_pcmMutex;
static uint8_t      g_pcmL[576] = {};
static uint8_t      g_pcmR[576] = {};

// ──────────────────────────────────────────────────────────────────────────────
// MilkDropView (MTKView subclass)
// ──────────────────────────────────────────────────────────────────────────────
@implementation MilkDropView {
    id<MTLDevice>  _metalDevice;
    BOOL           _pluginInitialized;
    int            _width, _height;
}

- (instancetype)initWithFrame:(NSRect)frame device:(id<MTLDevice>)device {
    self = [super initWithFrame:frame device:device];
    if (self) {
        _metalDevice     = device;
        self.delegate    = self;
        self.preferredFramesPerSecond = 60;
        self.colorPixelFormat         = MTLPixelFormatBGRA8Unorm;
        self.depthStencilPixelFormat  = MTLPixelFormatDepth32Float;
        self.clearColor = MTLClearColorMake(0, 0, 0, 1);
        _pluginInitialized = NO;

        // Accept keyboard input
        [self setAllowedTouchTypes:NSTouchTypeMaskIndirect];
    }
    return self;
}

- (BOOL)acceptsFirstResponder { return YES; }

// ── MTKViewDelegate ───────────────────────────────────────────────────────────
- (void)mtkView:(MTKView*)view drawableSizeWillChange:(CGSize)size {
    _width  = (int)size.width;
    _height = (int)size.height;
    NSLog(@"[MilkDropView] Drawable size → %d × %d", _width, _height);

    // Re-initialize DX9 stuff on resize
    if (_pluginInitialized) {
        g_plugin.CleanUpMyDX9Stuff(0);
        g_plugin.AllocateMyDX9Stuff();
    }
}

- (void)drawInMTKView:(MTKView*)view {
    id<CAMetalDrawable> drawable = view.currentDrawable;
    if (!drawable) return;

    // ── First-time plugin initialization ─────────────────────────────────────
    if (!_pluginInitialized) {
        _width  = (int)view.drawableSize.width;
        _height = (int)view.drawableSize.height;

        // Determine the plugin data directory (next to the app bundle)
        NSString* resourcePath = [[NSBundle mainBundle] resourcePath];
        std::wstring pluginsDir(resourcePath.UTF8String,
                                resourcePath.UTF8String + resourcePath.length);
        pluginsDir += L"/";

        // Build config .ini path
        std::wstring iniFile = pluginsDir + L"milk2.ini";

        // Initialize the plugin shell
        int ok = g_plugin.PluginPreInitialize(nullptr, nullptr);
        if (ok) {
            D3DPRESENT_PARAMETERS pp = {};
            pp.BackBufferWidth  = _width;
            pp.BackBufferHeight = _height;
            pp.BackBufferFormat = D3DFMT_A8R8G8B8;
            pp.Windowed         = TRUE;

            ok = g_plugin.PluginInitialize(g_device, &pp, nullptr, _width, _height);
        }
        if (!ok) {
            NSLog(@"[MilkDrop] Plugin initialization failed!");
            return;
        }
        _pluginInitialized = YES;
        NSLog(@"[MilkDrop] Plugin initialized at %d × %d", _width, _height);
    }

    // ── Get latest PCM ────────────────────────────────────────────────────────
    uint8_t pcmL[576], pcmR[576];
    {
        std::lock_guard<std::mutex> lk(g_pcmMutex);
        memcpy(pcmL, g_pcmL, 576);
        memcpy(pcmR, g_pcmR, 576);
    }

    // ── Render frame ──────────────────────────────────────────────────────────
    g_device->BeginFrame(drawable, (MTKView*)view);
    g_plugin.PluginRender(pcmL, pcmR);
    g_device->EndFrame();

    // Commit and present
    id<MTLCommandBuffer> cmdBuf = [g_device->GetCmdQueue() commandBuffer];
    [cmdBuf presentDrawable:drawable];
    [cmdBuf commit];
}

// ── Keyboard events ───────────────────────────────────────────────────────────
// Map macOS NSEvent key codes to Windows virtual key codes and forward to
// the plugin's MyWindowProc.  Only the keys MilkDrop actually uses are mapped.

static WPARAM NSKeyToVK(unsigned short keyCode, NSString* chars) {
    // Function keys
    switch (keyCode) {
        case 0x7A: return 0x70; // F1
        case 0x78: return 0x71; // F2
        case 0x63: return 0x72; // F3
        case 0x76: return 0x73; // F4
        case 0x60: return 0x74; // F5
        case 0x61: return 0x75; // F6
        case 0x62: return 0x76; // F7
        case 0x64: return 0x77; // F8
        case 0x65: return 0x78; // F9
        case 0x6D: return 0x79; // F10
        case 0x67: return 0x7A; // F11
        case 0x6F: return 0x7B; // F12
        // Navigation
        case 0x7B: return 0x25; // left arrow
        case 0x7C: return 0x27; // right arrow
        case 0x7E: return 0x26; // up arrow
        case 0x7D: return 0x28; // down arrow
        case 0x31: return 0x20; // space
        case 0x35: return 0x1B; // escape
        case 0x24: return 0x0D; // return
        case 0x33: return 0x08; // backspace
        case 0x30: return 0x09; // tab
        default:   break;
    }
    if (chars.length > 0) {
        unichar c = [chars characterAtIndex:0];
        if (c >= 'a' && c <= 'z') return (WPARAM)(c - 32); // uppercase VK
        if (c >= 'A' && c <= 'Z') return (WPARAM)c;
        if (c >= '0' && c <= '9') return (WPARAM)c;
    }
    return 0;
}

- (void)keyDown:(NSEvent*)event {
    WPARAM vk = NSKeyToVK(event.keyCode, event.characters);
    if (!vk) return;

    // Modifier flags → Windows WM_KEYDOWN
    LPARAM lParam = 0;
    if (event.modifierFlags & NSEventModifierFlagControl) lParam |= (1 << 29);

    g_plugin.MyWindowProc(nullptr, 0x0100 /*WM_KEYDOWN*/, vk, lParam);

    // Also send WM_CHAR for printable keys
    if (event.characters.length > 0) {
        unichar c = [event.characters characterAtIndex:0];
        if (c >= 0x20 && c < 0x7F)
            g_plugin.MyWindowProc(nullptr, 0x0102 /*WM_CHAR*/, (WPARAM)c, 0);
    }
}

- (void)keyUp:(NSEvent*)event {
    WPARAM vk = NSKeyToVK(event.keyCode, event.characters);
    if (vk) g_plugin.MyWindowProc(nullptr, 0x0101 /*WM_KEYUP*/, vk, 0);
}

// ── Mouse events ─────────────────────────────────────────────────────────────
- (NSPoint)milkDropPoint:(NSEvent*)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    p.y = self.bounds.size.height - p.y; // flip Y
    return p;
}

- (void)mouseDown:(NSEvent*)event {
    NSPoint p = [self milkDropPoint:event];
    LPARAM lp = ((int)p.y << 16) | (int)p.x;
    g_plugin.MyWindowProc(nullptr, 0x0201 /*WM_LBUTTONDOWN*/, 0, lp);
}
- (void)mouseUp:(NSEvent*)event {
    NSPoint p = [self milkDropPoint:event];
    LPARAM lp = ((int)p.y << 16) | (int)p.x;
    g_plugin.MyWindowProc(nullptr, 0x0202 /*WM_LBUTTONUP*/, 0, lp);
}
- (void)rightMouseDown:(NSEvent*)event {
    NSPoint p = [self milkDropPoint:event];
    LPARAM lp = ((int)p.y << 16) | (int)p.x;
    g_plugin.MyWindowProc(nullptr, 0x0204 /*WM_RBUTTONDOWN*/, 0, lp);
}
- (void)rightMouseUp:(NSEvent*)event {
    NSPoint p = [self milkDropPoint:event];
    LPARAM lp = ((int)p.y << 16) | (int)p.x;
    g_plugin.MyWindowProc(nullptr, 0x0205 /*WM_RBUTTONUP*/, 0, lp);
}

@end

// ──────────────────────────────────────────────────────────────────────────────
// AppDelegate
// ──────────────────────────────────────────────────────────────────────────────
@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification*)note {
    // ── Create Metal device ────────────────────────────────────────────────────
    id<MTLDevice> metalDevice = MTLCreateSystemDefaultDevice();
    g_device = new IDirect3DDevice9();

    // ── Determine initial window size ─────────────────────────────────────────
    NSScreen* screen = [NSScreen mainScreen];
    NSRect    frame  = NSMakeRect(0, 0,
                                  screen.frame.size.width  * 0.75,
                                  screen.frame.size.height * 0.75);

    // ── Create window ─────────────────────────────────────────────────────────
    NSWindowStyleMask style = NSWindowStyleMaskTitled
                            | NSWindowStyleMaskClosable
                            | NSWindowStyleMaskMiniaturizable
                            | NSWindowStyleMaskResizable;
    self.window = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:style
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    self.window.title = @"MilkDrop 3";
    [self.window center];

    // ── Create MTKView ─────────────────────────────────────────────────────────
    self.milkDropView = [[MilkDropView alloc] initWithFrame:frame
                                                     device:metalDevice];
    self.milkDropView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.milkDropView.plugin           = &g_plugin;
    self.milkDropView.d3dDevice        = g_device;

    self.window.contentView = self.milkDropView;
    [self.window makeFirstResponder:self.milkDropView];
    [self.window makeKeyAndOrderFront:nil];

    // ── Start audio capture ────────────────────────────────────────────────────
    g_audioCapture = new CoreAudioCapture();
    self.milkDropView.audioCapture = g_audioCapture;

    g_audioCapture->Start([](const uint8_t* left, const uint8_t* right, int count) {
        std::lock_guard<std::mutex> lk(g_pcmMutex);
        memcpy(g_pcmL, left,  std::min(count, 576));
        memcpy(g_pcmR, right, std::min(count, 576));
    });

    // ── Full-screen on launch (optional – press F7 to toggle) ────────────────
    // [self.window toggleFullScreen:nil];
}

- (void)applicationWillTerminate:(NSNotification*)note {
    g_plugin.PluginQuit();
    g_audioCapture->Stop();
    delete g_audioCapture;
    delete g_device;
    IniParser::FlushAll();
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)app {
    return YES;
}

// ── Full-screen toggle support ─────────────────────────────────────────────────
- (void)toggleFullScreen {
    [self.window toggleFullScreen:nil];
}

@end
