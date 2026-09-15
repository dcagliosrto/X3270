#import <Security/Security.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "TerminalViewController.h"
#import "TransferDockViewController.h"
#import "TerminalView.h"
#import "DebugWindowController.h"

// Include your C++ engine headers here...
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

// Broadcast notification constants
static NSString * const kDX3270BroadcastISPFNotification = @"DX3270BroadcastISPFNotification";
static NSString * const kDX3270BroadcastOOBNotification  = @"DX3270BroadcastOOBNotification";

@interface TerminalViewController ()
@property (nonatomic, strong) NSSplitViewController *splitViewController;
@property (nonatomic, strong) NSSplitViewItem *sidebarSplitItem;
- (NSString *)getPasswordForUser:(NSString *)user host:(NSString *)host;
- (void)savePasswordToKeychain:(NSString *)password forUser:(NSString *)user host:(NSString *)host;
- (NSString *)promptForPasswordForUser:(NSString *)user host:(NSString *)host;
@end

@implementation TerminalViewController {
    TerminalView* _termView;
    DebugWindowController *_debugWC;
    TransferDockViewController *_transferDockVC;
    
    // C++ Engine Objects
    std::unique_ptr<x3270::ScreenBuffer>          _screen;
    std::unique_ptr<x3270::GraphicsBuffer>        _graphics;
    std::unique_ptr<x3270::EbcdicCodec>           _codec;
    std::unique_ptr<x3270::DataStreamParser>      _parser3270;
    std::unique_ptr<x3270::DataStream5250Parser>  _parser5250;
    std::unique_ptr<x3270::KeyboardState>         _kbd3270;
    std::unique_ptr<x3270::KeyboardState5250>     _kbd5250;
    std::unique_ptr<x3270::ITerminalSession>      _session;
    
    std::thread _networkThread;
    BOOL        _userClosed;
    
    // Config
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
    
    if (self = [super initWithNibName:nil bundle:nil]) {
        _host = [host copy];
        _port = port;
        _useSSL = useSSL;
        _verifyCert = verifyCert;
        _caBundle = [caBundle copy];
        _codePage = codePage;
        _model = model;
        _protocol = protocol;
        
        // Observers
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(userDefaultsDidChange:) name:NSUserDefaultsDidChangeNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleBroadcastISPFCommand:) name:kDX3270BroadcastISPFNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleBroadcastOOBCommand:) name:kDX3270BroadcastOOBNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self disconnectSession];
}

- (void)disconnectSession {
    _userClosed = YES;
    if (_session) _session->disconnect();
    if (_networkThread.joinable()) _networkThread.detach();
    if (self.onClosed) self.onClosed();
}

- (void)loadView {
    // 1. Create the root container view
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 640, 420)];
    
    // 2. Set the dynamic Title for Tabs/Windows
    NSString *protoLabel = (_protocol == x3270::TerminalProtocol::TN5250) ? @" [5250]" : @"";
    self.title = [NSString stringWithFormat:@"%@:%d%@ - DX3270", _host, _port, protoLabel];
    
    // 3. Initialize the Engine
    [self buildEngineObjects];
    
    // 4. Build the UI
    _termView = [[TerminalView alloc] initWithFrame:NSZeroRect];
    [_termView setCodePage:_codePage];
    
    if (_kbd3270) {
        [_termView setScreenBuffer:_screen.get() keyboardState:_kbd3270.get()];
        [_termView setGraphicsBuffer:_graphics.get()];
    } else {
        [_termView setScreenBuffer:_screen.get() keyboardState5250:_kbd5250.get()];
    }
    
    self.commandDock = [[CommandDockViewController alloc] init];
    self.commandDock.delegate = self;
    
    NSStackView *terminalStack = [[NSStackView alloc] init];
    terminalStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    terminalStack.spacing = 0;
    terminalStack.alignment = NSLayoutAttributeWidth;
    
    [_termView setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationVertical];
    [terminalStack addArrangedSubview:_termView];
    
    NSView *dockView = self.commandDock.view;
    [dockView setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
    [terminalStack addArrangedSubview:dockView];
    
    NSViewController *terminalHostVC = [[NSViewController alloc] init];
    terminalHostVC.view = terminalStack;
    
    _transferDockVC = [[TransferDockViewController alloc] init];
    _transferDockVC.currentHost = _host;
    
    self.splitViewController = [[NSSplitViewController alloc] init];
    NSSplitViewItem *mainItem = [NSSplitViewItem splitViewItemWithViewController:terminalHostVC];
    mainItem.holdingPriority = 200;
    
    self.sidebarSplitItem = [NSSplitViewItem splitViewItemWithViewController:_transferDockVC];
    self.sidebarSplitItem.holdingPriority = 260;
    self.sidebarSplitItem.canCollapse = YES;
    self.sidebarSplitItem.collapsed = YES;
    self.sidebarSplitItem.minimumThickness = 280;
    
    [self.splitViewController addSplitViewItem:mainItem];
    [self.splitViewController addSplitViewItem:self.sidebarSplitItem];
    
    // 5. Embed the SplitView into this ViewController
    [self addChildViewController:self.splitViewController];
    
    // IL FIX VERO È QUI: 
    // Usiamo AutoLayout per dire a TUTTO il blocco di rispettare la Safe Area in alto!
    self.splitViewController.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.splitViewController.view];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.splitViewController.view.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.splitViewController.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.splitViewController.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.splitViewController.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]
    ]];
}

- (void)viewDidAppear {
    [super viewDidAppear];
    if (!_session || !_session->isConnected()) {
        [self startNetworkConnection]; // <-- Your existing network thread start
    }
}

// =========================================================================
// PASTE YOUR EXISTING METHODS BELOW THIS LINE
// -> buildEngineObjects
// -> startNetworkConnection
// -> toggleTransferSidebar
// -> saveScreenshot, exportText, toggleVideoRecording
// -> commandDockDidRequest... and ALL handleBroadcast... logic
// NOTE: Replace `self.window.title` with `self.title`
// =========================================================================

- (void)userDefaultsDidChange:(NSNotification *)note {
    BOOL brackets = [[NSUserDefaults standardUserDefaults] boolForKey:kPrefHerculesBrackets];
    if (_codec) _codec->setHerculesBrackets(brackets);
    [_debugWC configureCodePage:(int)_codePage herculesBrackets:brackets];
}

- (void)buildEngineObjects {
    _screen = std::make_unique<x3270::ScreenBuffer>(_model);
    _codec = std::make_unique<x3270::EbcdicCodec>(_codePage);
    BOOL brackets = [[NSUserDefaults standardUserDefaults] boolForKey:kPrefHerculesBrackets];
    _codec->setHerculesBrackets(brackets);
    _debugWC = [[DebugWindowController alloc] init];
    [_debugWC configureCodePage:(int)_codePage herculesBrackets:brackets];

    __weak TerminalViewController *weakSelf = self;
    if (_protocol == x3270::TerminalProtocol::TN5250) {
        auto *session5250 = new x3270::TN5250Session();
        session5250->setModel(_model);
        _session.reset(session5250);
        _parser5250 = std::make_unique<x3270::DataStream5250Parser>(*_screen);
        _kbd5250 = std::make_unique<x3270::KeyboardState5250>(*_screen, *_codec);
        _parser5250->setUnlockCallback([weakSelf]() { dispatch_async(dispatch_get_main_queue(), ^{ __strong auto s = weakSelf; if (s) s->_kbd5250->unlock(); }); });
        _parser5250->setAlarmCallback([]() { dispatch_async(dispatch_get_main_queue(), ^{ NSBeep(); }); });
        _parser5250->setSendCallback([weakSelf](const std::vector<uint8_t> &payload) { __strong auto s = weakSelf; if (s) s->_session->sendRecord(payload); });
        _parser5250->setQueryReplyCallback([weakSelf, session5250](const std::vector<uint8_t> &payload) { __strong auto s = weakSelf; if (s) session5250->sendGdsRecord(payload, x3270::GDS_OP_NO_OP); });
        _kbd5250->setSendCallback([weakSelf](const std::vector<uint8_t> &record) -> bool { __strong auto s = weakSelf; return s ? s->_session->sendRecord(record) : false; });
        _session->setDataCallback([weakSelf](const std::vector<uint8_t> &record) {
            __strong auto s = weakSelf; if (!s) return;
            if (record.size() >= 10 && (record[9] == 0x01 || record[9] == 0x03)) dispatch_async(dispatch_get_main_queue(), ^{ __strong auto s2 = weakSelf; if (s2) s2->_kbd5250->unlock(); });
            s->_parser5250->processRecord(record);
            dispatch_async(dispatch_get_main_queue(), ^{ __strong auto s2 = weakSelf; if (s2) [s2->_termView screenDidUpdate]; });
        });
    } else {
        _graphics = std::make_unique<x3270::GraphicsBuffer>();
        auto *session3270 = new x3270::TN3270Session();
        session3270->setModel(_model);
        _session.reset(session3270);
        _parser3270 = std::make_unique<x3270::DataStreamParser>(*_screen, *_codec);
        _parser3270->setGraphicsBuffer(*_graphics);
        _kbd3270 = std::make_unique<x3270::KeyboardState>(*_screen, *_codec);
        _parser3270->setGraphicsUpdateCallback([weakSelf]() { dispatch_async(dispatch_get_main_queue(), ^{ __strong auto s = weakSelf; if (s) [s->_termView graphicsDidUpdate]; }); });
        _parser3270->setUnlockCallback([weakSelf]() { dispatch_async(dispatch_get_main_queue(), ^{ __strong auto s = weakSelf; if (s) s->_kbd3270->unlock(); }); });
        _parser3270->setAlarmCallback([]() { dispatch_async(dispatch_get_main_queue(), ^{ NSBeep(); }); });
        _parser3270->setSendCallback([weakSelf](const std::vector<uint8_t> &data) { __strong auto s = weakSelf; if (s) s->_session->sendRecord(data); });
        _kbd3270->setSendCallback([weakSelf](const std::vector<uint8_t> &record) -> bool { __strong auto s = weakSelf; return s ? s->_session->sendRecord(record) : false; });
        _session->setDataCallback([weakSelf](const std::vector<uint8_t> &record) {
            __strong auto s = weakSelf; if (!s) return;
            auto *session = static_cast<x3270::TN3270Session *>(s->_session.get());
            const std::vector<uint8_t> *payload = &record;
            std::vector<uint8_t> stripped;
            if (session->tn3270eActive() && record.size() >= 5) { if (record[0] != 0x00) return; stripped.assign(record.begin() + 5, record.end()); payload = &stripped; }
            s->_parser3270->processRecord(*payload);
            dispatch_async(dispatch_get_main_queue(), ^{ __strong auto s2 = weakSelf; if (s2) [s2->_termView screenDidUpdate]; });
        });
    }
    _session->setConnectedCallback([weakSelf]() { dispatch_async(dispatch_get_main_queue(), ^{ __strong auto s = weakSelf; if (!s) return; if (s->_kbd3270) s->_kbd3270->unlock(); if (s->_kbd5250) s->_kbd5250->lock(x3270::KeyboardState5250::LockReason::System); [s->_termView screenDidUpdate]; if (s.onConnected) s.onConnected(); }); });
    _session->setErrorCallback([weakSelf](const std::string &message) { NSString *error = [NSString stringWithUTF8String:message.c_str()]; dispatch_async(dispatch_get_main_queue(), ^{ __strong auto s = weakSelf; if (!s || s->_userClosed) return; if (s.onConnectError) s.onConnectError(error); [s disconnectSession]; }); });
    _session->setTrafficCallback([weakSelf](bool outgoing, const std::vector<uint8_t> &data) { __strong auto s = weakSelf; if (s) [s->_debugWC appendBytes:data.data() length:data.size() isOutgoing:outgoing ? YES : NO]; });
}

- (void)startNetworkConnection {
    std::string host = [_host UTF8String];
    uint16_t port = _port;
    bool useSSL = _useSSL == YES;
    bool verifyCert = _verifyCert == YES;
    std::string caBundle = _caBundle ? [_caBundle UTF8String] : "";
    _networkThread = std::thread([self, host, port, useSSL, verifyCert, caBundle]() { @autoreleasepool { if (_session->connect(host, port, useSSL, verifyCert, caBundle)) _session->readLoop(); } });
    _networkThread.detach();
}

- (void)toggleTransferSidebar:(id)sender {
    if (!self.sidebarSplitItem) return;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) { context.duration = 0.25; self.sidebarSplitItem.animator.collapsed = !self.sidebarSplitItem.isCollapsed; } completionHandler:^{ [self->_termView setNeedsDisplay:YES]; }];
}

- (NSString *)getPasswordForUser:(NSString *)user host:(NSString *)host {
    if (user.length == 0 || host.length == 0) return nil;
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: [NSString stringWithFormat:@"DX3270_Mainframe_%@", host],
        (__bridge id)kSecAttrAccount: user,
        (__bridge id)kSecReturnData: @YES,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne
    };
    CFTypeRef value = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)query, &value) != errSecSuccess) return nil;
    NSData *data = (__bridge_transfer NSData *)value;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

- (void)savePasswordToKeychain:(NSString *)password forUser:(NSString *)user host:(NSString *)host {
    if (password.length == 0 || user.length == 0 || host.length == 0) return;
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: [NSString stringWithFormat:@"DX3270_Mainframe_%@", host],
        (__bridge id)kSecAttrAccount: user
    };
    SecItemDelete((__bridge CFDictionaryRef)query);
    NSMutableDictionary *attributes = [query mutableCopy];
    attributes[(__bridge id)kSecValueData] = [password dataUsingEncoding:NSUTF8StringEncoding];
    SecItemAdd((__bridge CFDictionaryRef)attributes, NULL);
}

- (NSString *)promptForPasswordForUser:(NSString *)user host:(NSString *)host {
    __block NSString *password;
    dispatch_sync(dispatch_get_main_queue(), ^{
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = [NSString stringWithFormat:@"Autenticazione SSH OOB per %@", host];
        alert.informativeText = [NSString stringWithFormat:@"Inserisci la password SSH per l'utente '%@':", user];
        NSSecureTextField *input = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(0, 0, 260, 24)];
        alert.accessoryView = input;
        [alert addButtonWithTitle:@"OK"];
        [alert addButtonWithTitle:@"Annulla"];
        [alert.window makeFirstResponder:input];
        if ([alert runModal] == NSAlertFirstButtonReturn) password = input.stringValue;
    });
    if (password.length) [self savePasswordToKeychain:password forUser:user host:host];
    return password;
}

- (IBAction)saveScreenshot:(id)sender {
    NSSavePanel *panel = [NSSavePanel savePanel];
    if (@available(macOS 11.0, *)) panel.allowedContentTypes = @[UTTypePNG];
    else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        panel.allowedFileTypes = @[@"png"];
#pragma clang diagnostic pop
    }
    panel.nameFieldStringValue = @"DX3270_screenshot.png";
    [panel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK) return;
        NSRect bounds = self->_termView.bounds;
        NSBitmapImageRep *bitmap = [self->_termView bitmapImageRepForCachingDisplayInRect:bounds];
        if (!bitmap) return;
        [self->_termView cacheDisplayInRect:bounds toBitmapImageRep:bitmap];
        NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        [png writeToURL:panel.URL atomically:YES];
    }];
}

- (IBAction)exportText:(id)sender {
    if (!_screen || !_codec) return;
    int rows = _screen->rows(), cols = _screen->cols();
    NSMutableString *text = [NSMutableString stringWithCapacity:(cols + 1) * rows];
    for (int row = 0; row < rows; row++) {
        for (int col = 0; col < cols; col++) {
            const x3270::Cell &cell = _screen->at(row, col);
            if (cell.isFA || cell.ch == 0x00 || cell.ch == x3270::EbcdicCodec::EBCDIC_SPACE) { [text appendString:@" "]; continue; }
            uint16_t unicode = _codec->toUnicode(cell.ch);
            if (unicode >= 0x20) { unichar character = (unichar)unicode; [text appendString:[NSString stringWithCharacters:&character length:1]]; }
            else [text appendString:@" "];
        }
        if (row + 1 < rows) [text appendString:@"\n"];
    }
    NSSavePanel *panel = [NSSavePanel savePanel];
    if (@available(macOS 11.0, *)) panel.allowedContentTypes = @[UTTypePlainText];
    else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        panel.allowedFileTypes = @[@"txt"];
#pragma clang diagnostic pop
    }
    panel.nameFieldStringValue = @"DX3270_export.txt";
    [panel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) [text writeToURL:panel.URL atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }];
}

- (IBAction)toggleVideoRecording:(id)sender {
    if ([_termView isVideoRecording]) {
        [_termView stopVideoRecording];
        self.title = [self.title stringByReplacingOccurrencesOfString:@" [RECORDING]" withString:@""];
        return;
    }
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.title = @"Save Terminal Recording";
    panel.nameFieldStringValue = @"DX3270_Demo";
    if (@available(macOS 11.0, *)) panel.allowedContentTypes = @[UTTypeMPEG4Movie, UTTypeGIF];
    else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        panel.allowedFileTypes = @[@"mp4", @"gif"];
#pragma clang diagnostic pop
    }
    [panel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK && panel.URL) {
            [self->_termView startVideoRecordingToURL:panel.URL];
            self.title = [self.title stringByAppendingString:@" [RECORDING]"];
        }
    }];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    SEL action = item.action;
    if (action == @selector(saveScreenshot:) || action == @selector(exportText:) || action == @selector(toggleVideoRecording:)) {
        if (action == @selector(toggleVideoRecording:)) item.title = [_termView isVideoRecording] ? @"Stop Video Recording" : @"Start Video Recording...";
        return _session != nullptr;
    }
    return YES;
}

- (void)commandDockDidRequestISPFCommand:(NSString *)command targetGroup:(NSString *)group {
    [self executeISPFCommandLocally:command];
    if (group.length) [[NSNotificationCenter defaultCenter] postNotificationName:kDX3270BroadcastISPFNotification object:nil userInfo:@{ @"command": command, @"group": group, @"sender": self }];
}

- (void)handleBroadcastISPFCommand:(NSNotification *)notification {
    if (notification.userInfo[@"sender"] == self) return;
    NSString *group = notification.userInfo[@"group"];
    if ([self.commandDock.linkGroup isEqualToString:group]) [self executeISPFCommandLocally:notification.userInfo[@"command"]];
}

- (void)executeISPFCommandLocally:(NSString *)command {
    if (command.length == 0 || !_kbd3270 || !_screen || !_codec) return;
    NSString *finalCommand = [command stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    for (NSDictionary *path in [[NSUserDefaults standardUserDefaults] arrayForKey:@"DX3270_FastPaths"]) {
        NSString *shortcut = path[@"cmd"];
        if ([shortcut hasPrefix:@"="] && [finalCommand isEqualToString:[shortcut substringFromIndex:1]]) { finalCommand = shortcut; break; }
    }
    NSArray *tsoCommands = @[@"TIME", @"LISTALC", @"LISTDS", @"STATUS", @"ALLOC", @"FREE", @"SUBMIT"];
    NSString *upper = finalCommand.uppercaseString;
    for (NSString *tso in tsoCommands) if ([upper isEqualToString:tso] || [upper hasPrefix:[tso stringByAppendingString:@" "]]) { if (![upper hasPrefix:@"TSO "] && ![upper hasPrefix:@"="]) finalCommand = [NSString stringWithFormat:@"TSO %@", finalCommand]; break; }
    int position = -1, size = _screen->size();
    uint8_t equals = _codec->fromAscii('='), greater = _codec->fromAscii('>');
    for (int index = 0; index < size - 4; index++) if (_screen->at(index).ch == equals && _screen->at(index + 1).ch == equals && _screen->at(index + 2).ch == equals && _screen->at(index + 3).ch == greater) { position = index + 4; if (position < size && _screen->at(position).isFA) position++; break; }
    if (position >= 0) _screen->setCursor(position); else _kbd3270->handleHome();
    _kbd3270->handleEraseEOF();
    for (NSUInteger index = 0; index < finalCommand.length; index++) _kbd3270->handleChar((uint8_t)[finalCommand characterAtIndex:index]);
    if (!_kbd3270->handleEnter()) NSBeep(); else [_termView setNeedsDisplay:YES];
}

- (void)commandDockDidRequestOutOdBandCommand:(NSString *)command targetGroup:(NSString *)group {
    [self executeOutOdBandCommandLocally:command];
    if (group.length) [[NSNotificationCenter defaultCenter] postNotificationName:kDX3270BroadcastOOBNotification object:nil userInfo:@{ @"command": command, @"group": group, @"sender": self }];
}

- (void)handleBroadcastOOBCommand:(NSNotification *)notification {
    if (notification.userInfo[@"sender"] == self) return;
    if ([self.commandDock.linkGroup isEqualToString:notification.userInfo[@"group"]]) [self executeOutOdBandCommandLocally:notification.userInfo[@"command"]];
}

- (void)executeOutOdBandCommandLocally:(NSString *)command {
    if (command.length == 0) return;
    NSString *trimmed = [command stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *user = [[NSUserDefaults standardUserDefaults] stringForKey:@"DX3270_TransferUser"];
    if (user.length == 0) user = NSUserName();
    NSString *host = [_host copy];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        NSString *password = [self getPasswordForUser:user host:host];
        if (password.length == 0) password = [self promptForPasswordForUser:user host:host];
        if (password.length == 0) return;
        NSString *target = [NSString stringWithFormat:@"%@@%@", user, host];
        NSTask *task = [[NSTask alloc] init];
        NSPipe *pipe = [NSPipe pipe], *input = [NSPipe pipe];
        task.launchPath = @"/usr/bin/expect";
        task.standardOutput = pipe;
        task.standardError = pipe;
        task.standardInput = input;
        task.arguments = @[@"-"];
        NSMutableDictionary *environment = [[NSProcessInfo processInfo].environment mutableCopy];
        environment[@"SSH_PASS"] = password;
        task.environment = environment;
        NSString *script = [NSString stringWithFormat:@"set timeout 30\nspawn ssh %@ %@\nexpect {\n  \"*yes/no*\" { send \"yes\\r\"; exp_continue }\n  \"*assword:*\" { send \"$env(SSH_PASS)\\r\"; exp_continue }\n  eof\n}\n", target, trimmed];
        [input.fileHandleForWriting writeData:[script dataUsingEncoding:NSUTF8StringEncoding]];
        [input.fileHandleForWriting closeFile];
        NSError *error;
        if (![task launchAndReturnError:&error]) return;
        NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
        [task waitUntilExit];
        NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSRange passwordPrompt = [output rangeOfString:@"password:" options:NSCaseInsensitiveSearch];
        if (passwordPrompt.location != NSNotFound) output = [output substringFromIndex:passwordPrompt.location + passwordPrompt.length];
        output = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *title = [NSString stringWithFormat:@"OOB Result [%@]: %@", host, command];
            [self.commandDock showOOBPopoverWithTitle:title content:output.length ? output : @"(Command executed successfully with no output)"];
        });
    });
}

- (void)commandDockDidToggleRuler {
    [_termView toggleCrosshairRuler];
}

- (IBAction)toggleTimeMachine:(id)sender {
    [_termView toggleTimeMachine];
}

- (void)commandDockDidToggleTimeMachine {
    [self toggleTimeMachine:self];
}

@end