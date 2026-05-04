/**
 * AppDelegate.h
 *
 * macOS application delegate + MTKView render loop for MilkDrop3.
 *
 * Responsibilities:
 *   - Create and manage the main NSWindow + MTKView.
 *   - Drive the MilkDrop render loop via MTKViewDelegate callbacks.
 *   - Bridge SDL2 keyboard/mouse events to MilkDrop's MyWindowProc.
 *   - Manage the CoreAudioCapture instance and feed PCM data to the plugin.
 */

#pragma once

#import <Cocoa/Cocoa.h>
#import <MetalKit/MetalKit.h>

#include "render/MetalDevice.h"
#include "audio/CoreAudioCapture.h"

// Forward-declare the MilkDrop plugin class (defined in vis_milk2/plugin.h).
// We include the header in the .mm file where the full Windows compat layer
// is active.
class CPlugin;

@interface MilkDropView : MTKView <MTKViewDelegate>
@property (nonatomic, assign) IDirect3DDevice9* d3dDevice;
@property (nonatomic, assign) CPlugin*          plugin;
@property (nonatomic, assign) CoreAudioCapture* audioCapture;
- (instancetype)initWithFrame:(NSRect)frame device:(id<MTLDevice>)device;
@end

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (strong) NSWindow*      window;
@property (strong) MilkDropView*  milkDropView;
- (void)applicationDidFinishLaunching:(NSNotification*)note;
@end
