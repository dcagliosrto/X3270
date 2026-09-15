#import "TerminalWindowController.h"

@interface TerminalWindowController () <NSWindowDelegate>
@end

@implementation TerminalWindowController

- (instancetype)initWithHost:(NSString*)host
                        port:(uint16_t)port
                      useSSL:(BOOL)useSSL
                  verifyCert:(BOOL)verifyCert
                    caBundle:(NSString*)caBundle
                    codePage:(x3270::CodePage)codePage
                       model:(x3270::TerminalModel)model
                    protocol:(x3270::TerminalProtocol)protocol {
    
    // Create the Window Shell
    NSWindow *win = [[NSWindow alloc]
                     initWithContentRect:NSMakeRect(0, 0, 640, 420)
                               styleMask:NSWindowStyleMaskTitled
                                        |NSWindowStyleMaskClosable
                                        |NSWindowStyleMaskMiniaturizable
                                        |NSWindowStyleMaskResizable
                                 backing:NSBackingStoreBuffered
                                   defer:NO];
    
    if (self = [super initWithWindow:win]) {
        self.window.delegate = self;
        self.window.releasedWhenClosed = NO;

        self.window.minSize = NSMakeSize(800, 500);
        
        [self.window center];
        
        // 1. Initialize the reusable View Controller
        _terminalVC = [[TerminalViewController alloc] initWithHost:host port:port useSSL:useSSL verifyCert:verifyCert caBundle:caBundle codePage:codePage model:model protocol:protocol];
        
        // 2. Bind the Window Title to the ViewController's dynamic Title
        [self.window bind:@"title" toObject:_terminalVC withKeyPath:@"title" options:nil];
        
        // 3. Set the content
        self.window.contentViewController = _terminalVC;
    }
    return self;
}

// Forward the connection callbacks set by ConnectionWindowController down to the VC
- (void)setOnConnected:(void (^)(void))onConnected {
    _onConnected = onConnected;
    _terminalVC.onConnected = onConnected;
}

- (void)setOnConnectError:(void (^)(NSString *))onConnectError {
    _onConnectError = onConnectError;
    __weak typeof(self) weakSelf = self;
    _terminalVC.onConnectError = ^(NSString *err) {
        if (onConnectError) onConnectError(err);
        [weakSelf close];
    };
}

- (void)setOnClosed:(void (^)(void))onClosed {
    _onClosed = onClosed;
    _terminalVC.onClosed = onClosed;
}

// Cleanup when the user clicks the red traffic light (X)
- (void)windowWillClose:(NSNotification *)notification {
    [_terminalVC disconnectSession];
}

// Forward Actions triggered from the Menu Bar
- (IBAction)saveScreenshot:(id)sender { [_terminalVC saveScreenshot:sender]; }
- (IBAction)exportText:(id)sender { [_terminalVC exportText:sender]; }
- (IBAction)toggleVideoRecording:(id)sender { [_terminalVC toggleVideoRecording:sender]; }
- (void)toggleTransferSidebar:(id)sender { [_terminalVC toggleTransferSidebar:sender]; }
- (void)toggleTimeMachine:(id)sender { [_terminalVC toggleTimeMachine:sender]; }

@end