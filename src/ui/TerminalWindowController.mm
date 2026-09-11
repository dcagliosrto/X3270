#import <Security/Security.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "TerminalWindowController.h"
#import "TransferDockViewController.h"
#import "CommandDockViewController.h"
#import "TerminalView.h"
#import "DebugWindowController.h"
#include "ITerminalSession.h"
#include "TN3270Session.h"
#include "TN5250Session.h"
#include "DataStreamParser.h"
#include "DataStream5250Parser.h"
#include "KeyboardState.h"
#include "KeyboardState5250.h"
#include "ScreenBuffer.h"
#include "GraphicsBuffer.h"
#include "EbcdicCodec.h"
#include "TerminalProtocol.h"
#include <memory>
#include <thread>
#include <string>

// Broadcast notification constants
static NSString * const kDX3270BroadcastISPFNotification = @"DX3270BroadcastISPFNotification";
static NSString * const kDX3270BroadcastOOBNotification  = @"DX3270BroadcastOOBNotification";

@interface TerminalWindowController () <NSWindowDelegate, CommandDockDelegate>
@property (nonatomic, strong) NSSplitViewController *splitViewController;
@property (nonatomic, strong) NSSplitViewItem *sidebarSplitItem;

- (NSString *)getPasswordForUser:(NSString *)user host:(NSString *)host;
- (void)savePasswordToKeychain:(NSString *)password forUser:(NSString *)user host:(NSString *)host;
- (NSString *)promptForPasswordForUser:(NSString *)user host:(NSString *)host;
@end

@implementation TerminalWindowController {
    TerminalView*   _termView;
    DebugWindowController *_debugWC;
    TransferDockViewController *_transferDockVC;

    // Core engine objects
    std::unique_ptr<x3270::ScreenBuffer>          _screen;
    std::unique_ptr<x3270::GraphicsBuffer>        _graphics;  // 3270 only
    std::unique_ptr<x3270::EbcdicCodec>           _codec;
    std::unique_ptr<x3270::DataStreamParser>      _parser3270;  // 3270 only
    std::unique_ptr<x3270::DataStream5250Parser>  _parser5250;  // 5250 only
    std::unique_ptr<x3270::KeyboardState>         _kbd3270;     // 3270 only
    std::unique_ptr<x3270::KeyboardState5250>     _kbd5250;     // 5250 only
    std::unique_ptr<x3270::ITerminalSession>      _session;     // either

    std::thread _networkThread;
    BOOL        _userClosed;

    NSString  *_host;
    uint16_t   _port;
    BOOL       _useSSL;
    BOOL       _verifyCert;
    NSString  *_caBundle;
    x3270::CodePage       _codePage;
    x3270::TerminalModel  _model;
    x3270::TerminalProtocol _protocol;
}

- (instancetype)initWithHost:(NSString*)host
                        port:(uint16_t)port
                      useSSL:(BOOL)useSSL
                    verifyCert:(BOOL)verifyCert
                    caBundle:(NSString*)caBundle
                    codePage:(x3270::CodePage)codePage
                       model:(x3270::TerminalModel)model
                    protocol:(x3270::TerminalProtocol)protocol {
    NSString *protoLabel = (protocol == x3270::TerminalProtocol::TN5250) ? @" [5250]" : @"";
    NSWindow *win = [[NSWindow alloc]
                     initWithContentRect:NSMakeRect(0, 0, 640, 420)
                               styleMask:NSWindowStyleMaskTitled
                                        |NSWindowStyleMaskClosable
                                        |NSWindowStyleMaskMiniaturizable
                                        |NSWindowStyleMaskResizable
                               backing:NSBackingStoreBuffered
                                  defer:NO];
    win.title = [NSString stringWithFormat:@"%@:%d%@ — DX3270", host, port, protoLabel];
    win.releasedWhenClosed = NO;
    [win center];

    if ((self = [super initWithWindow:win])) {
        win.delegate = self;
        _host     = [host copy];
        _port     = port;
        _useSSL   = useSSL;
        _verifyCert = verifyCert;
        _caBundle = [caBundle copy];
        _codePage = codePage;
        _model    = model;
        _protocol = protocol;

        [self buildEngineObjects];
        [self buildUI];
        [self startNetworkConnection];

        // Register default preferences observer
        [[NSNotificationCenter defaultCenter]
            addObserver:self
               selector:@selector(userDefaultsDidChange:)
                   name:NSUserDefaultsDidChangeNotification
                 object:nil];

        // Register inter-window broadcast observers directly in init
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleBroadcastISPFCommand:)
                                                     name:kDX3270BroadcastISPFNotification
                                                   object:nil];
                                                   
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleBroadcastOOBCommand:)
                                                     name:kDX3270BroadcastOOBNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (_session) _session->disconnect();
    if (_networkThread.joinable()) _networkThread.detach();
    _debugWC = nil;
}

- (void)toggleTransferSidebar:(id)sender {
    if (!self.sidebarSplitItem) return;
    
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.25;
        self.sidebarSplitItem.animator.collapsed = !self.sidebarSplitItem.isCollapsed;
    } completionHandler:^{
        [self->_termView setNeedsDisplay:YES];
    }];
}

- (void)userDefaultsDidChange:(NSNotification *)note {
    BOOL hb = [[NSUserDefaults standardUserDefaults] boolForKey:kPrefHerculesBrackets];
    if (_codec) {
        _codec->setHerculesBrackets(hb);
    }
    [_debugWC configureCodePage:(int)_codePage herculesBrackets:hb];
}

// ── Engine ────────────────────────────────────────────────────────────────────
- (void)buildEngineObjects {
    _screen = std::make_unique<x3270::ScreenBuffer>(_model);
    _codec  = std::make_unique<x3270::EbcdicCodec>(_codePage);
    _codec->setHerculesBrackets([[NSUserDefaults standardUserDefaults] boolForKey:kPrefHerculesBrackets]);
    _debugWC = [[DebugWindowController alloc] init];
    [_debugWC configureCodePage:(int)_codePage
               herculesBrackets:[[NSUserDefaults standardUserDefaults] boolForKey:kPrefHerculesBrackets]];

    __weak TerminalWindowController *weakSelf = self;

    if (_protocol == x3270::TerminalProtocol::TN5250) {
        auto* session5250 = new x3270::TN5250Session();
        session5250->setModel(_model);
        _session.reset(session5250);

        _parser5250 = std::make_unique<x3270::DataStream5250Parser>(*_screen);
        _kbd5250    = std::make_unique<x3270::KeyboardState5250>(*_screen, *_codec);

        _parser5250->setUnlockCallback([weakSelf]() {
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong auto s = weakSelf;
                if (s) s->_kbd5250->unlock();
            });
        });
        _parser5250->setAlarmCallback([]() {
            dispatch_async(dispatch_get_main_queue(), ^{ NSBeep(); });
        });
        _parser5250->setSendCallback([weakSelf](const std::vector<uint8_t>& payload) {
            __strong auto s = weakSelf;
            if (s) s->_session->sendRecord(payload);
        });
        _parser5250->setQueryReplyCallback([weakSelf, session5250](const std::vector<uint8_t>& payload) {
            __strong auto s = weakSelf;
            if (s) session5250->sendGdsRecord(payload, x3270::GDS_OP_NO_OP);
        });

        _kbd5250->setSendCallback([weakSelf](const std::vector<uint8_t>& record) -> bool {
            __strong auto s = weakSelf;
            return s ? s->_session->sendRecord(record) : false;
        });

        _session->setDataCallback([weakSelf](const std::vector<uint8_t>& record) {
            __strong auto s = weakSelf;
            if (!s) return;

            if (!record.empty()) {
                uint8_t b0 = record.size()>0 ? record[0] : 0;
                uint8_t b1 = record.size()>1 ? record[1] : 0;
                uint8_t b2 = record.size()>2 ? record[2] : 0;
                uint8_t b3 = record.size()>3 ? record[3] : 0;
                uint8_t b4 = record.size()>4 ? record[4] : 0;
                uint8_t b5 = record.size()>5 ? record[5] : 0;
                NSLog(@"[5250] record %zu bytes  GDS hdr: %02X %02X %02X %02X  opcode=%02X flags=%02X",
                      record.size(), b0, b1, b2, b3, b4, b5);
            }

            if (record.size() >= 10) {
                uint8_t opcode = record[9];
                if (opcode == 0x01 || opcode == 0x03) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        __strong auto s2 = weakSelf;
                        if (s2) s2->_kbd5250->unlock();
                    });
                }
            }

            s->_parser5250->processRecord(record);
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong auto s2 = weakSelf;
                if (s2) [s2->_termView screenDidUpdate];
            });
        });

    } else {
        _graphics = std::make_unique<x3270::GraphicsBuffer>();
        auto* session3270 = new x3270::TN3270Session();
        session3270->setModel(_model);
        _session.reset(session3270);

        _parser3270 = std::make_unique<x3270::DataStreamParser>(*_screen, *_codec);
        _parser3270->setGraphicsBuffer(*_graphics);
        _kbd3270    = std::make_unique<x3270::KeyboardState>(*_screen, *_codec);

        _parser3270->setGraphicsUpdateCallback([weakSelf]() {
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong auto s = weakSelf;
                if (s) [s->_termView graphicsDidUpdate];
            });
        });
        _parser3270->setUnlockCallback([weakSelf]() {
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong auto s = weakSelf;
                if (s) s->_kbd3270->unlock();
            });
        });
        _parser3270->setAlarmCallback([]() {
            dispatch_async(dispatch_get_main_queue(), ^{ NSBeep(); });
        });
        _parser3270->setSendCallback([weakSelf](const std::vector<uint8_t>& data) {
            __strong auto s = weakSelf;
            if (s) s->_session->sendRecord(data);
        });

        _kbd3270->setSendCallback([weakSelf](const std::vector<uint8_t>& record) -> bool {
            __strong auto s = weakSelf;
            return s ? s->_session->sendRecord(record) : false;
        });

        _session->setDataCallback([weakSelf](const std::vector<uint8_t>& record) {
            __strong auto s = weakSelf;
            if (!s) return;
            auto* s3270 = static_cast<x3270::TN3270Session*>(s->_session.get());
            const std::vector<uint8_t>* payload = &record;
            std::vector<uint8_t> stripped;
            if (s3270->tn3270eActive() && record.size() >= 5) {
                if (record[0] != 0x00) return;
                stripped.assign(record.begin() + 5, record.end());
                payload = &stripped;
            }
            s->_parser3270->processRecord(*payload);
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong auto s2 = weakSelf;
                if (s2) [s2->_termView screenDidUpdate];
            });
        });
    }

    // ── Common callbacks ──────────────────────────────────────────────────────
    _session->setConnectedCallback([weakSelf]() {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong auto s = weakSelf;
            if (s) {
                if (s->_kbd3270) s->_kbd3270->unlock();
                if (s->_kbd5250)
                    s->_kbd5250->lock(x3270::KeyboardState5250::LockReason::System);
                [s->_termView screenDidUpdate];
                if (s.onConnected) s.onConnected();
            }
        });
    });

    _session->setErrorCallback([weakSelf](const std::string& msg) {
        NSString *nsMsg = [NSString stringWithUTF8String:msg.c_str()];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong auto s = weakSelf;
            if (!s) return;
            if (s->_userClosed) return;
            if (s.onConnectError) s.onConnectError(nsMsg);
            [s close];
        });
    });

    _session->setTrafficCallback([weakSelf](bool tx, const std::vector<uint8_t>& data) {
        __strong auto s = weakSelf;
        if (s) {
            [s->_debugWC appendBytes:data.data()
                              length:data.size()
                          isOutgoing:tx ? YES : NO];
        }
    });
}

// Fetches the saved password from macOS Keychain mapped to both User and Host
- (NSString *)getPasswordForUser:(NSString *)user host:(NSString *)host {
    if (!user || user.length == 0 || !host || host.length == 0) return nil;
    
    NSString *serviceName = [NSString stringWithFormat:@"DX3270_Mainframe_%@", host];
    
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: serviceName,
        (__bridge id)kSecAttrAccount: user,
        (__bridge id)kSecReturnData: @YES,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne
    };
    
    CFTypeRef dataTypeRef = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)query, &dataTypeRef) == errSecSuccess) {
        NSData *data = (__bridge_transfer NSData *)dataTypeRef;
        return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }
    return nil;
}

- (void)savePasswordToKeychain:(NSString *)password forUser:(NSString *)user host:(NSString *)host {
    if (!user.length || !password.length || !host.length) return;
    
    NSString *serviceName = [NSString stringWithFormat:@"DX3270_Mainframe_%@", host];
    NSData *passData = [password dataUsingEncoding:NSUTF8StringEncoding];
    
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: serviceName,
        (__bridge id)kSecAttrAccount: user
    };
    
    SecItemDelete((__bridge CFDictionaryRef)query);
    
    NSMutableDictionary *attributes = [query mutableCopy];
    attributes[(__bridge id)kSecValueData] = passData;
    
    SecItemAdd((__bridge CFDictionaryRef)attributes, NULL);
}

- (NSString *)promptForPasswordForUser:(NSString *)user host:(NSString *)host {
    __block NSString *enteredPassword = nil;
    
    dispatch_sync(dispatch_get_main_queue(), ^{
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = [NSString stringWithFormat:@"Autenticazione SSH OOB per %@", host];
        alert.informativeText = [NSString stringWithFormat:@"Inserisci la password SSH per l'utente '%@':", user];
        alert.alertStyle = NSAlertStyleInformational;
        
        NSSecureTextField *input = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(0, 0, 260, 24)];
        alert.accessoryView = input;
        
        [alert addButtonWithTitle:@"OK"];
        [alert addButtonWithTitle:@"Annulla"];
        
        [alert.window makeFirstResponder:input];
        
        NSModalResponse response = [alert runModal];
        if (response == NSAlertFirstButtonReturn) {
            enteredPassword = input.stringValue;
        }
    });
    
    if (enteredPassword.length > 0) {
        [self savePasswordToKeychain:enteredPassword forUser:user host:host];
    }
    
    return enteredPassword;
}

// ── UI ────────────────────────────────────────────────────────────────────────
- (void)buildUI {
    _termView = [[TerminalView alloc] initWithFrame:NSMakeRect(0, 0, 640, 420)];
    _termView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [_termView setCodePage:_codePage];

    if (_kbd3270) {
        [_termView setScreenBuffer:_screen.get() keyboardState:_kbd3270.get()];
        [_termView setGraphicsBuffer:_graphics.get()];
    } else {
        [_termView setScreenBuffer:_screen.get() keyboardState5250:_kbd5250.get()];
    }

    // --- Command Dock Integration ---
    self.commandDock = [[CommandDockViewController alloc] init];
    self.commandDock.delegate = self;
    
    NSStackView *terminalStack = [[NSStackView alloc] initWithFrame:_termView.frame];
    terminalStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    terminalStack.spacing = 0;
    terminalStack.alignment = NSLayoutAttributeWidth;
    
    [_termView setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationVertical];
    
    [terminalStack addArrangedSubview:_termView];
    
    NSView *dockView = self.commandDock.view;
    [dockView setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
    [terminalStack addArrangedSubview:dockView];

    NSViewController *terminalVC = [[NSViewController alloc] init];
    terminalVC.view = terminalStack;

    _transferDockVC = [[TransferDockViewController alloc] init];
    _transferDockVC.currentHost = _host;

    self.splitViewController = [[NSSplitViewController alloc] init];

    NSSplitViewItem *mainItem = [NSSplitViewItem splitViewItemWithViewController:terminalVC];
    mainItem.holdingPriority = 200;

    self.sidebarSplitItem = [NSSplitViewItem splitViewItemWithViewController:_transferDockVC];
    self.sidebarSplitItem.holdingPriority = 260;
    self.sidebarSplitItem.canCollapse = YES;
    self.sidebarSplitItem.collapsed = YES;
    self.sidebarSplitItem.minimumThickness = 280;

    [self.splitViewController addSplitViewItem:mainItem];
    [self.splitViewController addSplitViewItem:self.sidebarSplitItem];

    self.window.contentViewController = self.splitViewController;

    NSSize preferred = [_termView preferredSize];
    preferred.height += 40.0; 
    [self.window setContentSize:preferred];
    [self.window makeFirstResponder:_termView];
}

// ── Networking ────────────────────────────────────────────────────────────────
- (void)startNetworkConnection {
    std::string host      = [_host UTF8String];
    uint16_t    port      = _port;
    bool        useSSL    = _useSSL == YES;
    bool        verifyCert = _verifyCert == YES;
    std::string caBundle  = _caBundle ? [_caBundle UTF8String] : "";

    _networkThread = std::thread([self, host, port, useSSL, verifyCert, caBundle]() {
        @autoreleasepool {
            bool ok = _session->connect(host, port, useSSL, verifyCert, caBundle);
            if (ok) {
                _session->readLoop();
            }
        }
        __block TerminalWindowController *retained = self;
        dispatch_async(dispatch_get_main_queue(), ^{ retained = nil; });
    });
    _networkThread.detach();
}

- (void)windowWillClose:(NSNotification*)notification {
    if (_userClosed) return;
    _userClosed = YES;
    if (_session) _session->disconnect();

    [_termView setScreenBuffer:(x3270::ScreenBuffer*)nullptr
                keyboardState:(x3270::KeyboardState*)nullptr];
    [_termView setGraphicsBuffer:nullptr];

    if (self.onClosed) self.onClosed();
}

- (IBAction)openDebugWindow:(id)sender {
    [_debugWC showWindow:nil];
    [_debugWC.window makeKeyAndOrderFront:nil];
}

- (IBAction)saveScreenshot:(id)sender {
    NSSavePanel *panel = [NSSavePanel savePanel];
    if (@available(macOS 11.0, *)) {
        panel.allowedContentTypes = @[UTTypePNG];
    } else {
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        panel.allowedFileTypes = @[@"png"];
    #pragma clang diagnostic pop
    }
    panel.nameFieldStringValue = @"DX3270_screenshot.png";
    panel.message = @"Save a PNG image of the current terminal screen.";

    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK) return;

        NSRect bounds = self->_termView.bounds;
        NSBitmapImageRep *bitmap =
            [self->_termView bitmapImageRepForCachingDisplayInRect:bounds];
        if (!bitmap) return;
        [self->_termView cacheDisplayInRect:bounds toBitmapImageRep:bitmap];
        NSData *pngData = [bitmap representationUsingType:NSBitmapImageFileTypePNG
                                               properties:@{}];
        [pngData writeToURL:panel.URL atomically:YES];
    }];
}

- (IBAction)exportText:(id)sender {
    if (!_screen || !_codec) return;

    int rows = _screen->rows();
    int cols = _screen->cols();
    NSMutableString *text = [NSMutableString stringWithCapacity:(cols + 1) * rows];

    for (int r = 0; r < rows; r++) {
        for (int c = 0; c < cols; c++) {
            const x3270::Cell &cell = _screen->at(r, c);
            if (cell.isFA || cell.ch == 0x00 ||
                cell.ch == x3270::EbcdicCodec::EBCDIC_SPACE) {
                [text appendString:@" "];
                continue;
            }
            uint16_t uc = _codec->toUnicode(cell.ch);
            if (uc >= 0x20) {
                unichar ch = (unichar)uc;
                [text appendString:[NSString stringWithCharacters:&ch length:1]];
            } else {
                [text appendString:@" "];
            }
        }
        if (r < rows - 1) [text appendString:@"\n"];
    }

    NSSavePanel *panel = [NSSavePanel savePanel];
    if (@available(macOS 11.0, *)) {
        panel.allowedContentTypes = @[UTTypePlainText];
    } else {
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        panel.allowedFileTypes = @[@"txt"];
    #pragma clang diagnostic pop
    }
    panel.nameFieldStringValue = @"DX3270_export.txt";
    panel.message = @"Export the current terminal screen as plain text.";

    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK) return;
        NSError *err = nil;
        [text writeToURL:panel.URL
              atomically:YES
                encoding:NSUTF8StringEncoding
                   error:&err];
    }];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    SEL action = item.action;
    if (action == @selector(saveScreenshot:) ||
        action == @selector(exportText:)) {
        return _session != nullptr;
    }
    return YES;
}

#pragma mark - Broadcast Dispatchers & Handlers

- (void)commandDockDidRequestISPFCommand:(NSString *)command targetGroup:(NSString *)group {
    // 1. Always execute locally on the current window
    [self executeISPFCommandLocally:command];
    
    // 2. Broadcast to other linked windows
    if (group.length > 0) {
        NSDictionary *userInfo = @{
            @"command": command,
            @"group": group,
            @"sender": self
        };
        [[NSNotificationCenter defaultCenter] postNotificationName:kDX3270BroadcastISPFNotification
                                                            object:nil
                                                          userInfo:userInfo];
    }
}

- (void)handleBroadcastISPFCommand:(NSNotification *)notification {
    TerminalWindowController *sender = notification.userInfo[@"sender"];
    
    // Ignore if this window initiated the broadcast
    if (sender == self) return;
    
    NSString *targetGroup = notification.userInfo[@"group"];
    NSString *command     = notification.userInfo[@"command"];
    
    // Check match on linkGroup
    if (self.commandDock && [self.commandDock.linkGroup isEqualToString:targetGroup]) {
        [self executeISPFCommandLocally:command];
    }
}

- (void)executeISPFCommandLocally:(NSString *)command {
    if (!command || command.length == 0) return;
    
    NSString *finalCommand = [command stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    // Auto-Add '=' for known Fast Paths if missing
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSArray *fastPaths = [defaults arrayForKey:@"DX3270_FastPaths"];
    for (NSDictionary *path in fastPaths) {
        NSString *cmd = path[@"cmd"];
        if ([cmd hasPrefix:@"="] && [finalCommand isEqualToString:[cmd substringFromIndex:1]]) {
            finalCommand = cmd;
            break;
        }
    }
    
    // Auto-Prefix TSO for common utility commands
    NSArray *tsoCommands = @[@"TIME", @"LISTALC", @"LISTDS", @"STATUS", @"ALLOC", @"FREE", @"SUBMIT"];
    NSString *upperCmd = finalCommand.uppercaseString;
    for (NSString *tsoCmd in tsoCommands) {
        if ([upperCmd isEqualToString:tsoCmd] || [upperCmd hasPrefix:[tsoCmd stringByAppendingString:@" "]]) {
            if (![upperCmd hasPrefix:@"TSO "] && ![upperCmd hasPrefix:@"="]) {
                finalCommand = [NSString stringWithFormat:@"TSO %@", finalCommand];
            }
            break;
        }
    }

    // Smart Locator Execution
    BOOL handled = NO;
    if (_kbd3270 && _screen && _codec) {
        int cmdPos = -1;
        int sz = _screen->size();
        uint8_t eq = _codec->fromAscii('=');
        uint8_t gt = _codec->fromAscii('>');
        
        for (int i = 0; i < sz - 4; i++) {
            if (_screen->at(i).ch == eq &&
                _screen->at(i+1).ch == eq &&
                _screen->at(i+2).ch == eq &&
                _screen->at(i+3).ch == gt) {
                
                cmdPos = i + 4;
                if (cmdPos < sz && _screen->at(cmdPos).isFA) {
                    cmdPos++;
                }
                break;
            }
        }
        
        if (cmdPos >= 0) {
            _screen->setCursor(cmdPos);
        } else {
            _kbd3270->handleHome(); 
        }
        
        _kbd3270->handleEraseEOF();
        for (NSUInteger i = 0; i < finalCommand.length; i++) {
            _kbd3270->handleChar((uint8_t)[finalCommand characterAtIndex:i]);
        }
        
        handled = _kbd3270->handleEnter();
    }
    
    if (handled) {
        [_termView setNeedsDisplay:YES];
    } else {
        NSBeep();
    }
}

#pragma mark - Out-of-Band Execution & Handlers

- (void)commandDockDidRequestOutOdBandCommand:(NSString *)command targetGroup:(NSString *)group {
    // 1. Always execute locally on the current window
    [self executeOutOdBandCommandLocally:command];
    
    // 2. Broadcast to other linked windows
    if (group.length > 0) {
        NSDictionary *userInfo = @{
            @"command": command,
            @"group": group,
            @"sender": self
        };
        [[NSNotificationCenter defaultCenter] postNotificationName:kDX3270BroadcastOOBNotification
                                                            object:nil
                                                          userInfo:userInfo];
    }
}

- (void)handleBroadcastOOBCommand:(NSNotification *)notification {
    TerminalWindowController *sender = notification.userInfo[@"sender"];
    if (sender == self) return;
    
    NSString *targetGroup = notification.userInfo[@"group"];
    NSString *command     = notification.userInfo[@"command"];
    
    if (self.commandDock && [self.commandDock.linkGroup isEqualToString:targetGroup]) {
        [self executeOutOdBandCommandLocally:command];
    }
}

- (void)executeOutOdBandCommandLocally:(NSString *)command {
    if (!command || command.length == 0) return;
    
    NSString *trimmedCmd = [command stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    // Identify the saved z/OS user or use the default environment user
    NSString *savedUser = [[NSUserDefaults standardUserDefaults] stringForKey:@"DX3270_TransferUser"];
    if (!savedUser || savedUser.length == 0) {
        savedUser = NSUserName(); // Fallback to the local macOS/z/OS user
    }
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // 1. Look for the password in the Keychain for this specific host
        NSString *savedPassword = [self getPasswordForUser:savedUser host:self->_host];
        
        // 2. If missing, show the native prompt to ask for it and save it in the Keychain
        if (!savedPassword || savedPassword.length == 0) {
            savedPassword = [self promptForPasswordForUser:savedUser host:self->_host];
            if (!savedPassword || savedPassword.length == 0) {
                return; // The user canceled the input
            }
        }
        
        NSString *targetHost = [NSString stringWithFormat:@"%@@%@", savedUser, self->_host];
        
        // ==========================================
        // Handle LOG <jobid>
        // ==========================================
// ==========================================
        // Handle LOG <jobid> (Intercettato dal JSON come DX3270_INTERNAL_LOG)
        // ==========================================
        if ([trimmedCmd.uppercaseString hasPrefix:@"DX3270_INTERNAL_LOG "]) {
            // Extract the jobTarget by bypassing the 20-character prefix ("DX3270_INTERNAL_LOG ")
            NSString *jobTarget = [[trimmedCmd substringFromIndex:20] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];            if (jobTarget.length == 0) {
                dispatch_async(dispatch_get_main_queue(), ^{ NSBeep(); });
                return;
            }

            NSTask *task = [[NSTask alloc] init];
            NSPipe *pipe = [NSPipe pipe];
            task.standardOutput = pipe;
            task.standardError = pipe;

            task.launchPath = @"/usr/bin/expect";
            NSMutableDictionary *env = [[NSProcessInfo processInfo].environment mutableCopy];
            env[@"SSH_PASS"] = savedPassword;
            task.environment = env;
            task.arguments = @[@"-"];

            NSPipe *inputPipe = [NSPipe pipe];
            task.standardInput = inputPipe;

            // 1. Scrive lo script REXX su un file temporaneo LOCALE del Mac, bypassando i limiti z/OS
            NSString *rexxScript = [NSString stringWithFormat:
                @"/* REXX */\n"
                 "parse arg target\n"
                 "rc=isfcalls('ON')\n"
                 "isfprefix='*'\n"
                 "isfowner='*'\n"
                 "isflinelim=20000\n"
                 "address SDSF 'ISFEXEC ST'\n"
                 "say '===SPOOL_START==='\n"
                 "if symbol('ISFROWS') = 'VAR' then do i=1 to ISFROWS\n"
                 "  if JOBID.i = target then do\n"
                 "    address SDSF 'ISFBROWSE ST TOKEN(''' || TOKEN.i || ''')'\n"
                 "    if symbol('ISFLINE.0') = 'VAR' then do j=1 to isfline.0\n"
                 "      say isfline.j\n"
                 "    end\n"
                 "    leave\n"
                 "  end\n"
                 "end\n"
                 "say '===SPOOL_END==='\n"
                 "rc=isfcalls('OFF')\n"];
                 
            NSString *localRexxPath = [NSString stringWithFormat:@"/tmp/dx_local_%@.rexx", jobTarget];
            [rexxScript writeToFile:localRexxPath atomically:YES encoding:NSUTF8StringEncoding error:nil];

            // 2. Crea la pipeline bash: esegue un "cat" locale e lo inietta via SSH 
            // per la scrittura ed esecuzione remota sicura
            NSString *remoteRexxPath = [NSString stringWithFormat:@"/tmp/dx_rem_%@.rexx", jobTarget];
            NSString *shCmd = [NSString stringWithFormat:@"cat %@ | ssh %@ 'cat > %@ && chmod +x %@ && %@ %@ ; rm -f %@'", 
                               localRexxPath, targetHost, remoteRexxPath, remoteRexxPath, remoteRexxPath, jobTarget, remoteRexxPath];

            NSMutableString *script = [NSMutableString string];
            [script appendString:@"set timeout 30\n"];
            // Usiamo le { } di Expect per proteggere l'intero comando shCmd
            [script appendFormat:@"spawn sh -c {%@}\n", shCmd];
            [script appendString:@"expect {\n"];
            [script appendString:@"  \"*yes/no*\" { send \"yes\\r\"; exp_continue }\n"];
            [script appendString:@"  \"*assword:*\" { send \"$env(SSH_PASS)\\r\"; exp_continue }\n"];
            [script appendString:@"  eof\n"];
            [script appendString:@"}\n"];

            NSData *inputData = [script dataUsingEncoding:NSUTF8StringEncoding];
            [inputPipe.fileHandleForWriting writeData:inputData];
            [inputPipe.fileHandleForWriting closeFile];

            if ([task launchAndReturnError:nil]) {
                // LETTURA PRIMA DEL WAIT: Evita il deadlock dell'app su Spool superiori a 64KB!
                NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
                [task waitUntilExit];
                
                // Rimuove il file temporaneo Mac dal disco locale
                [[NSFileManager defaultManager] removeItemAtPath:localRexxPath error:nil];
                
                NSString *rawContent = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

                NSString *cleanLog = rawContent;
                NSRange startRange = [rawContent rangeOfString:@"===SPOOL_START==="];
                NSRange endRange   = [rawContent rangeOfString:@"===SPOOL_END==="];

                if (startRange.location != NSNotFound && endRange.location != NSNotFound && endRange.location > startRange.location) {
                    NSUInteger start = startRange.location + startRange.length;
                    NSUInteger length = endRange.location - start;
                    cleanLog = [rawContent substringWithRange:NSMakeRange(start, length)];
                }

                cleanLog = [cleanLog stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

                if (cleanLog.length == 0) {
                    cleanLog = [NSString stringWithFormat:@"No spool output found for job %@.\n\nRaw Output:\n%@", jobTarget, rawContent];
                }

                NSString *filePath = [NSString stringWithFormat:@"/tmp/DX3270_%@.log", jobTarget];
                [cleanLog writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:nil];

                dispatch_async(dispatch_get_main_queue(), ^{
                    NSURL *fileURL = [NSURL fileURLWithPath:filePath];
                    [[NSWorkspace sharedWorkspace] openURL:fileURL];
                });
            }
            return;
        }
        
        // ==========================================
        // Handle Generic OOB Execution
        // ==========================================
        NSTask *task = [[NSTask alloc] init];
        NSPipe *pipe = [NSPipe pipe];
        task.standardOutput = pipe;
        task.standardError = pipe;
        
        task.launchPath = @"/usr/bin/expect";
        NSMutableDictionary *env = [[NSProcessInfo processInfo].environment mutableCopy];
        env[@"SSH_PASS"] = savedPassword;
        task.environment = env;
        task.arguments = @[@"-"];
        
        NSPipe *inputPipe = [NSPipe pipe];
        task.standardInput = inputPipe;
        
        NSMutableString *script = [NSMutableString string];
        [script appendString:@"set timeout 15\n"];
        [script appendFormat:@"spawn ssh %@ %@\n", targetHost, command];
        [script appendString:@"expect {\n"];
        [script appendString:@"  \"*yes/no*\" { send \"yes\\r\"; exp_continue }\n"];
        [script appendString:@"  \"*assword:*\" { send \"$env(SSH_PASS)\\r\"; exp_continue }\n"];
        [script appendString:@"  eof\n"];
        [script appendString:@"}\n"];
        
        NSData *inputData = [script dataUsingEncoding:NSUTF8StringEncoding];
        [inputPipe.fileHandleForWriting writeData:inputData];
        [inputPipe.fileHandleForWriting closeFile];
        
        NSError *error = nil;
        if ([task launchAndReturnError:&error]) {
            [task waitUntilExit];
            NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
            NSString *rawOutput = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            
            NSString *cleanOutput = rawOutput;
            NSRange passwordRange = [cleanOutput rangeOfString:@"password:" options:NSCaseInsensitiveSearch];
            if (passwordRange.location != NSNotFound) {
                NSUInteger startIndex = passwordRange.location + passwordRange.length;
                cleanOutput = [cleanOutput substringFromIndex:startIndex];
                cleanOutput = [cleanOutput stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            }
            
            NSArray<NSString *> *lines = [cleanOutput componentsSeparatedByString:@"\n"];
            if (lines.count > 1 && [[lines[0] lowercaseString] containsString:[command lowercaseString]]) {
                NSMutableArray<NSString *> *mutableLines = [lines mutableCopy];
                [mutableLines removeObjectAtIndex:0];
                cleanOutput = [mutableLines componentsJoinedByString:@"\n"];
            }
            
            cleanOutput = [cleanOutput stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

            dispatch_async(dispatch_get_main_queue(), ^{
                NSString *title = [NSString stringWithFormat:@"OOB Result [%@]: %@", self->_host, command];
                NSString *content = cleanOutput.length > 0 ? cleanOutput : @"(Command executed successfully with no output)";
                
                if (self.commandDock) {
                    [self.commandDock showOOBPopoverWithTitle:title content:content];
                }
            });
        }
    });
}

- (void)commandDockDidToggleRuler {
    if (_termView) {
        [_termView toggleCrosshairRuler];
    }
}

@end