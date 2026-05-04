/**
 * main.mm
 *
 * MilkDrop3 macOS entry point.
 */

#import <Cocoa/Cocoa.h>
#import "AppDelegate.h"

int main(int argc, const char* argv[]) {
    @autoreleasepool {
        NSApplication* app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];

        AppDelegate* delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;

        // Create a minimal menu bar so the app doesn't look headless
        NSMenu* menuBar  = [NSMenu new];
        NSMenuItem* item = [NSMenuItem new];
        [menuBar addItem:item];
        app.mainMenu = menuBar;

        NSMenu* appMenu    = [NSMenu new];
        NSString* appName  = @"MilkDrop 3";
        [appMenu addItemWithTitle:[@"Quit " stringByAppendingString:appName]
                           action:@selector(terminate:)
                    keyEquivalent:@"q"];
        item.submenu = appMenu;

        [app activateIgnoringOtherApps:YES];
        [app run];
    }
    return 0;
}
