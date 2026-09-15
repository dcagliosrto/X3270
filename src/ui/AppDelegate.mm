#import "AppDelegate.h"
#import "ConnectionWindowController.h"
#import "PreferencesWindowController.h"
#import "ShortcutsWindowController.h"

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self buildMenuBar];
    _connectionWindowController = [[ConnectionWindowController alloc] init];
    [_connectionWindowController showWindow:nil];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

#pragma mark - Menu Bar

- (void)buildMenuBar {
    NSMenu *menuBar = [[NSMenu alloc] init];
    [NSApp setMainMenu:menuBar];

    // Application menu
    NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
    [menuBar addItem:appMenuItem];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"DX3270"];
    appMenuItem.submenu = appMenu;
    [appMenu addItemWithTitle:@"About DX3270" action:@selector(showAbout:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Preferences..." action:@selector(openPreferences:) keyEquivalent:@","];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Keyboard Shortcuts" action:@selector(openShortcuts:) keyEquivalent:@"/"];
    [appMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *quitItem = [appMenu addItemWithTitle:@"Quit DX3270" action:@selector(terminate:) keyEquivalent:@"q"];
    quitItem.target = NSApp;

    // File menu
    NSMenuItem *fileMenuItem = [[NSMenuItem alloc] init];
    [menuBar addItem:fileMenuItem];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    fileMenuItem.submenu = fileMenu;
    [fileMenu addItemWithTitle:@"New Connection..." action:@selector(newConnection:) keyEquivalent:@"n"];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *transferItem = [fileMenu addItemWithTitle:@"z/OS File Transfer Dock" action:@selector(openTransferDock:) keyEquivalent:@"U"];
    transferItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [fileMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *screenshotItem = [fileMenu addItemWithTitle:@"Save Screenshot..." action:@selector(saveScreenshot:) keyEquivalent:@"P"];
    screenshotItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    NSMenuItem *exportItem = [fileMenu addItemWithTitle:@"Export as Text..." action:@selector(exportText:) keyEquivalent:@"T"];
    exportItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;

    // New video command (Cmd + Shift + V)
    [fileMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *videoItem = [fileMenu addItemWithTitle:@"Start Video Recording..." action:@selector(toggleVideoRecording:) keyEquivalent:@"V"];
    videoItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;

    // View menu (Time-Machine)
    NSMenuItem *viewMenuItem = [[NSMenuItem alloc] init];
    [menuBar addItem:viewMenuItem];
    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
    viewMenuItem.submenu = viewMenu;
    NSMenuItem *timeMachineItem = [viewMenu addItemWithTitle:@"3270 Time-Machine" action:@selector(toggleTimeMachine:) keyEquivalent:@"t"];
    timeMachineItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;

    // Edit menu
    NSMenuItem *editMenuItem = [[NSMenuItem alloc] init];
    [menuBar addItem:editMenuItem];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    editMenuItem.submenu = editMenu;
    [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];

    // ==========================================
    // Macro menu
    // ==========================================
    NSMenuItem *macroMenuItem = [[NSMenuItem alloc] init];
    [menuBar addItem:macroMenuItem];
    NSMenu *macroMenu = [[NSMenu alloc] initWithTitle:@"Macro"];
    macroMenuItem.submenu = macroMenu;
    
    NSMenuItem *recordItem = [macroMenu addItemWithTitle:@"Record Macro" 
                                                  action:@selector(startRecordingMacro:) 
                                           keyEquivalent:@"r"];
    recordItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagControl;
    
    NSMenuItem *stopItem = [macroMenu addItemWithTitle:@"Stop & Save Macro..." 
                                                action:@selector(stopRecordingMacro:) 
                                         keyEquivalent:@"s"];
    stopItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagControl;
    
    [macroMenu addItem:[NSMenuItem separatorItem]];
    
    NSMenuItem *playItem = [macroMenu addItemWithTitle:@"Play Macro..." 
                                                action:@selector(playMacro:) 
                                         keyEquivalent:@"p"];
    playItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagControl;

    // Debug menu
    NSMenuItem *debugMenuItem = [[NSMenuItem alloc] init];
    [menuBar addItem:debugMenuItem];
    NSMenu *debugMenu = [[NSMenu alloc] initWithTitle:@"Debug"];
    debugMenuItem.submenu = debugMenu;
    NSMenuItem *trafficItem = [debugMenu addItemWithTitle:@"Traffic Monitor" action:@selector(openDebugWindow:) keyEquivalent:@"D"];
    trafficItem.keyEquivalentModifierMask = NSEventModifierFlagCommand;
}

#pragma mark - Actions

- (void)toggleTimeMachine:(id)sender {
    NSWindowController *activeWC = NSApp.keyWindow.windowController;
    if ([activeWC respondsToSelector:@selector(toggleTimeMachine:)]) {
        [activeWC performSelector:@selector(toggleTimeMachine:) withObject:sender];
    }
}

- (void)toggleVideoRecording:(id)sender {
    NSWindowController *activeWC = NSApp.keyWindow.windowController;
    if ([activeWC respondsToSelector:@selector(toggleVideoRecording:)]) {
        [activeWC performSelector:@selector(toggleVideoRecording:) withObject:sender];
    }
}

- (void)newConnection:(id)sender {
    ConnectionWindowController *cwc = [[ConnectionWindowController alloc] init];
    [cwc showWindow:nil];
}

- (void)showAbout:(id)sender {
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    NSString *version  = info[@"CFBundleShortVersionString"] ?: @"1.7.6";
    NSString *build    = info[@"CFBundleVersion"]            ?: @"1";
    NSString *credits = @"Free TN3270/TN3270E terminal emulator for macOS.\n\n"
                         "Native Cocoa · CoreText · OpenSSL\n"
                         "Supports ISPF, TSO and z/OS on IBM Mainframes.\n\n"
                         "Written by Swen Skalski\n"
                         "https://github.com/skalski/X3270";
    [NSApp orderFrontStandardAboutPanelWithOptions:@{
        @"ApplicationVersion": [NSString stringWithFormat:@"%@ (Build %@)", version, build],
        @"Credits": [[NSAttributedString alloc] initWithString:credits attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:11]}],
        @"Copyright": @"Copyright © 2026 Swen Skalski",
    }];
}

- (void)openPreferences:(id)sender {
    [[PreferencesWindowController sharedController] showWindow:nil];
}

- (void)openShortcuts:(id)sender {
    [[ShortcutsWindowController sharedController] showWindow:nil];
}

- (void)openTransferDock:(id)sender {
    NSWindowController *activeWC = NSApp.keyWindow.windowController;
    if ([activeWC respondsToSelector:@selector(toggleTransferSidebar:)]) {
        [activeWC performSelector:@selector(toggleTransferSidebar:) withObject:sender];
    }
}

@end
