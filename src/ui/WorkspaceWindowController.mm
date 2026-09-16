#import "WorkspaceWindowController.h"

// 1. Aggiungiamo NSToolbarDelegate
@interface WorkspaceWindowController () <NSWindowDelegate, NSToolbarDelegate>
@end

@implementation WorkspaceWindowController

- (instancetype)initWithWorkspace:(DXWorkspace *)workspace {
    NSWindow *win = [[NSWindow alloc]
                     initWithContentRect:NSMakeRect(0, 0, 1100, 860)
                               styleMask:NSWindowStyleMaskTitled
                                        |NSWindowStyleMaskClosable
                                        |NSWindowStyleMaskMiniaturizable
                                        |NSWindowStyleMaskResizable
                                 backing:NSBackingStoreBuffered
                                   defer:NO];
          
    if (self = [super initWithWindow:win]) {
        self.window.delegate = self;
        self.window.releasedWhenClosed = NO;
        self.window.minSize = NSMakeSize(500, 400);
        
        self.window.titleVisibility = NSWindowTitleHidden;
        self.window.toolbarStyle = NSWindowToolbarStyleUnified;
        
        // 2. Creiamo la Toolbar e le assegniamo il pulsante nativo della Sidebar
        NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"WorkspaceToolbar"];
        toolbar.displayMode = NSToolbarDisplayModeIconOnly;
        toolbar.delegate = self;
        self.window.toolbar = toolbar;
        
        [self.window center];
        
        _workspaceVC = [[WorkspaceViewController alloc] initWithWorkspace:workspace];
        self.window.contentViewController = _workspaceVC;
        
        self.window.title = workspace.name.length > 0 ? workspace.name : @"DX3270 Workspace";
    }
    return self;
}

#pragma mark - NSToolbarDelegate

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
    return @[NSToolbarToggleSidebarItemIdentifier];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    return @[NSToolbarToggleSidebarItemIdentifier];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag {
    if ([itemIdentifier isEqualToString:NSToolbarToggleSidebarItemIdentifier]) {
        return [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
    }
    return nil;
}

#pragma mark - Window Lifecycle

- (void)windowWillClose:(NSNotification *)notification {
    [_workspaceVC disconnectAllSessions];
}

- (TerminalViewController *)activeTerminalTab {
    // Now we directly use the new property exposed by the WorkspaceViewController
    return _workspaceVC.activeTerminal;
}

- (IBAction)closeTab:(id)sender {
    [_workspaceVC closeActiveTab];
}

- (IBAction)saveScreenshot:(id)sender { [[self activeTerminalTab] saveScreenshot:sender]; }
- (IBAction)exportText:(id)sender { [[self activeTerminalTab] exportText:sender]; }
- (IBAction)toggleVideoRecording:(id)sender { [[self activeTerminalTab] toggleVideoRecording:sender]; }
- (void)toggleTransferSidebar:(id)sender { [_workspaceVC toggleTransferSidebar:sender]; }
- (void)toggleTimeMachine:(id)sender { [[self activeTerminalTab] toggleTimeMachine:sender]; }
- (IBAction)reconnectActiveSession:(id)sender {[[self activeTerminalTab] reconnectSession]; }
@end