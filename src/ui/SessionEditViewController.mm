#import "SessionEditViewController.h"
#include "TerminalModel.h"
#include "TerminalProtocol.h"
#include "EbcdicCodec.h"

@implementation SessionEditViewController {
    DXSessionConfig *_session;
    BOOL _isNew;
    
    NSTextField *_nameField;
    NSTextField *_hostField;
    NSTextField *_portField;
    NSButton *_sslCheckbox;
    NSButton *_verifyCertCheckbox;
    NSTextField *_caField;
    
    NSPopUpButton *_protocolPopup;
    NSPopUpButton *_modelPopup;
    NSPopUpButton *_codepagePopup;
}

- (instancetype)initWithSession:(DXSessionConfig *)session {
    if (self = [super initWithNibName:nil bundle:nil]) {
        if (session) {
            _session = session;
            _isNew = NO;
        } else {
            _session = [[DXSessionConfig alloc] init];
            _isNew = YES;
        }
    }
    return self;
}

#pragma mark - Enum Helpers

- (x3270::CodePage)selectedCodePage {
    switch (_codepagePopup.indexOfSelectedItem) {
        case 1:  return x3270::CodePage::CP500;
        case 2:  return x3270::CodePage::CP1047;
        case 3:  return x3270::CodePage::CP280;
        case 4:  return x3270::CodePage::CP273;
        case 5:  return x3270::CodePage::CP284;
        case 6:  return x3270::CodePage::CP285;
        default: return x3270::CodePage::CP037;
    }
}

- (NSInteger)indexForCodePage:(x3270::CodePage)cp {
    switch (cp) {
        case x3270::CodePage::CP500:  return 1;
        case x3270::CodePage::CP1047: return 2;
        case x3270::CodePage::CP280:  return 3;
        case x3270::CodePage::CP273:  return 4;
        case x3270::CodePage::CP284:  return 5;
        case x3270::CodePage::CP285:  return 6;
        default:                      return 0;
    }
}

- (x3270::TerminalModel)selectedModel {
    BOOL is5250 = (_protocolPopup.indexOfSelectedItem == 1);
    if (is5250) {
        return (_modelPopup.indexOfSelectedItem == 1) ? x3270::TerminalModel::Model5 : x3270::TerminalModel::Model2;
    }
    switch (_modelPopup.indexOfSelectedItem) {
        case 1:  return x3270::TerminalModel::Model3;
        case 2:  return x3270::TerminalModel::Model4;
        case 3:  return x3270::TerminalModel::Model5;
        case 4:  return x3270::TerminalModel::LargeCustom;
        default: return x3270::TerminalModel::Model2;
    }
}

- (NSInteger)indexForModel:(x3270::TerminalModel)model is5250:(BOOL)is5250 {
    if (is5250) return (model == x3270::TerminalModel::Model5) ? 1 : 0;
    switch (model) {
        case x3270::TerminalModel::Model3:      return 1;
        case x3270::TerminalModel::Model4:      return 2;
        case x3270::TerminalModel::Model5:      return 3;
        case x3270::TerminalModel::LargeCustom: return 4;
        default:                                 return 0;
    }
}

#pragma mark - UI Setup

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 420, 350)];
    
    NSTextField *titleLabel = [NSTextField labelWithString:_isNew ? @"Add New Session" : @"Edit Session"];
    titleLabel.font = [NSFont boldSystemFontOfSize:14];
    titleLabel.frame = NSMakeRect(20, 310, 260, 20);
    [self.view addSubview:titleLabel];
    
    // Name
    [self.view addSubview:[self label:@"Name:" y:270]];
    _nameField = [NSTextField textFieldWithString:_session.name ?: @""];
    _nameField.frame = NSMakeRect(110, 266, 280, 22);
    [self.view addSubview:_nameField];
    
    // Host
    [self.view addSubview:[self label:@"Host:" y:240]];
    _hostField = [NSTextField textFieldWithString:_session.host ?: @""];
    _hostField.placeholderString = @"e.g. 10.134.49.215";
    _hostField.frame = NSMakeRect(110, 236, 280, 22);
    [self.view addSubview:_hostField];
    
    // Port
    [self.view addSubview:[self label:@"Port:" y:210]];
    _portField = [NSTextField textFieldWithString:[NSString stringWithFormat:@"%d", _session.port > 0 ? _session.port : 23]];
    _portField.frame = NSMakeRect(110, 206, 60, 22);
    [self.view addSubview:_portField];
    
    // SSL & Verify Cert
    _sslCheckbox = [NSButton checkboxWithTitle:@"Use SSL" target:self action:@selector(sslToggled:)];
    _sslCheckbox.state = _session.useSSL ? NSControlStateValueOn : NSControlStateValueOff;
    _sslCheckbox.frame = NSMakeRect(180, 206, 80, 22);
    [self.view addSubview:_sslCheckbox];
    
    _verifyCertCheckbox = [NSButton checkboxWithTitle:@"Verify Cert" target:nil action:nil];
    _verifyCertCheckbox.state = _session.verifyCert ? NSControlStateValueOn : NSControlStateValueOff;
    _verifyCertCheckbox.enabled = _session.useSSL;
    _verifyCertCheckbox.frame = NSMakeRect(270, 206, 110, 22);
    [self.view addSubview:_verifyCertCheckbox];
    
    // CA Bundle
    [self.view addSubview:[self label:@"CA Bundle:" y:180]];
    _caField = [NSTextField textFieldWithString:_session.caBundle ?: @""];
    _caField.placeholderString = @"(optional) path to .pem";
    _caField.frame = NSMakeRect(110, 176, 280, 22);
    _caField.enabled = _session.useSSL;
    [self.view addSubview:_caField];
    
    // Protocol
    [self.view addSubview:[self label:@"Protocol:" y:150]];
    _protocolPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(108, 146, 284, 22) pullsDown:NO];
    [_protocolPopup addItemsWithTitles:@[@"TN3270     Mainframe (z/OS)", @"TN5250     Midrange (IBM i / AS400)"]];
    [_protocolPopup selectItemAtIndex:_session.protocol];
    [_protocolPopup setTarget:self];
    [_protocolPopup setAction:@selector(protocolChanged:)];
    [self.view addSubview:_protocolPopup];
    
    // Screen Model
    [self.view addSubview:[self label:@"Screen Model:" y:120]];
    _modelPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(108, 116, 284, 22) pullsDown:NO];
    [self updateModelItemsForProtocol:_session.protocol];
    [_modelPopup selectItemAtIndex:[self indexForModel:(x3270::TerminalModel)_session.model is5250:(_session.protocol == 1)]];
    [self.view addSubview:_modelPopup];
    
    // Code Page
    [self.view addSubview:[self label:@"Code Page:" y:90]];
    _codepagePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(108, 86, 284, 22) pullsDown:NO];
    [_codepagePopup addItemsWithTitles:@[
        @"CP037 (US/Canada)",
        @"CP500 (International)",
        @"CP1047 (Open Systems)",
        @"CP280 (Italy)",
        @"CP273 (Germany)",
        @"CP284 (Spain)",
        @"CP285 (United Kingdom)"
    ]];
    [_codepagePopup selectItemAtIndex:[self indexForCodePage:(x3270::CodePage)_session.codePage]];
    [self.view addSubview:_codepagePopup];
    
    // Buttons
    NSButton *cancelBtn = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancelClicked:)];
    cancelBtn.frame = NSMakeRect(230, 20, 80, 24);
    [self.view addSubview:cancelBtn];
    
    NSButton *saveBtn = [NSButton buttonWithTitle:@"Save" target:self action:@selector(saveClicked:)];
    saveBtn.frame = NSMakeRect(310, 20, 80, 24);
    saveBtn.keyEquivalent = @"\r";
    [self.view addSubview:saveBtn];
}

- (void)sslToggled:(id)sender {
    BOOL sslOn = (_sslCheckbox.state == NSControlStateValueOn);
    _verifyCertCheckbox.enabled = sslOn;
    _caField.enabled = sslOn;
    
    if (sslOn && [_portField.stringValue isEqualToString:@"23"]) {
        _portField.stringValue = @"992";
    } else if (!sslOn && [_portField.stringValue isEqualToString:@"992"]) {
        _portField.stringValue = @"23";
    }
}

- (void)protocolChanged:(id)sender {
    BOOL is5250 = (_protocolPopup.indexOfSelectedItem == 1);
    [self updateModelItemsForProtocol:is5250 ? 1 : 0];
}

- (void)updateModelItemsForProtocol:(NSInteger)protocol {
    [_modelPopup removeAllItems];
    if (protocol == 1) {
        [_modelPopup addItemsWithTitles:@[
            @"Standard \u2014 24\u00d780",
            @"Wide \u2014 27\u00d7132"
        ]];
    } else {
        [_modelPopup addItemsWithTitles:@[
            @"Model 2 \u2014 24\u00d780 (default)",
            @"Model 3 \u2014 32\u00d780",
            @"Model 4 \u2014 43\u00d780",
            @"Model 5 \u2014 27\u00d7132 (wide)",
            @"Large \u2014 62\u00d7160 (non-standard)"
        ]];
    }
}

- (NSTextField *)label:(NSString *)text y:(CGFloat)y {
    NSTextField *lbl = [NSTextField labelWithString:text];
    lbl.alignment = NSTextAlignmentRight;
    lbl.frame = NSMakeRect(10, y, 90, 20);
    lbl.editable = NO;
    lbl.bordered = NO;
    lbl.backgroundColor = [NSColor clearColor];
    return lbl;
}

- (void)cancelClicked:(id)sender {
    if (self.delegate) [self.delegate sessionEditorDidCancel];
}

- (void)saveClicked:(id)sender {
    _session.name = _nameField.stringValue;
    _session.host = _hostField.stringValue;
    _session.port = _portField.intValue;
    _session.useSSL = (_sslCheckbox.state == NSControlStateValueOn);
    _session.verifyCert = (_verifyCertCheckbox.state == NSControlStateValueOn);
    _session.caBundle = _session.useSSL ? _caField.stringValue : @"";
    
    _session.protocol = (int)_protocolPopup.indexOfSelectedItem;
    _session.model = (int)[self selectedModel];
    _session.codePage = (int)[self selectedCodePage];
    
    if (self.delegate) [self.delegate sessionEditorDidSave:_session isNew:_isNew];
}

@end