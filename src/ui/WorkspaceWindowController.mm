#import "WorkspaceWindowController.h"

@interface WorkspaceWindowController () <NSWindowDelegate>
@end

@implementation WorkspaceWindowController

- (instancetype)initWithWorkspace:(DXWorkspace *)workspace {
    // Define a default larger window, designed for the 16:10 format of the MacBook 14"
    NSWindow *win = [[NSWindow alloc]
                     initWithContentRect:NSMakeRect(0, 0, 1100, 860)
                               styleMask:NSWindowStyleMaskTitled
                                        |NSWindowStyleMaskClosable
                                        |NSWindowStyleMaskMiniaturizable
                                        |NSWindowStyleMaskResizable
                                        |NSWindowStyleMaskFullSizeContentView // Allows the tabs to enter the title bar
                                 backing:NSBackingStoreBuffered
                                   defer:NO];
    
    if (self = [super initWithWindow:win]) {
        self.window.delegate = self;
        self.window.releasedWhenClosed = NO;
        
        // Avoids that the window starts too squished and breaks the layout of the Terminal+Sidebar
        self.window.minSize = NSMakeSize(800, 500); 
        
        // Sets the native behavior of Tabs on the title bar (macOS 11+)
        self.window.titleVisibility = NSWindowTitleHidden;
        self.window.toolbarStyle = NSWindowToolbarStyleUnified;
        
        [self.window center];
        
        // Initialize the internal ViewController and attach it
        _workspaceVC = [[WorkspaceViewController alloc] initWithWorkspace:workspace];
        self.window.contentViewController = _workspaceVC;
        
        // Dynamic renaming of the window based on the loaded Workspace
        self.window.title = workspace.name.length > 0 ? workspace.name : @"DX3270 Workspace";
    }
    return self;
}

- (void)windowWillClose:(NSNotification *)notification {
    // When we click the red X, disconnect all Tabs
    [_workspaceVC disconnectAllSessions];
}

// =========================================================================
// INTERCEPTION OF GLOBAL COMMANDS (From the top macOS menu)
// Forwards commands (e.g., Export Video) to the currently visible/active Tab
// =========================================================================
- (TerminalViewController *)activeTerminalTab {
    NSTabViewItem *activeItem = _workspaceVC.tabViewController.tabViewItems[_workspaceVC.tabViewController.selectedTabViewItemIndex];
    if ([activeItem.viewController isKindOfClass:[TerminalViewController class]]) {
        return (TerminalViewController *)activeItem.viewController;
    }
    return nil;
}

- (IBAction)saveScreenshot:(id)sender { [[self activeTerminalTab] saveScreenshot:sender]; }
- (IBAction)exportText:(id)sender { [[self activeTerminalTab] exportText:sender]; }
- (IBAction)toggleVideoRecording:(id)sender { [[self activeTerminalTab] toggleVideoRecording:sender]; }
- (void)toggleTransferSidebar:(id)sender { [[self activeTerminalTab] toggleTransferSidebar:sender]; }
- (void)toggleTimeMachine:(id)sender { [[self activeTerminalTab] toggleTimeMachine:sender]; }

@end