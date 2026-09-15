#import "SessionEditViewController.h"

@implementation SessionEditViewController {
    DXSessionConfig *_session;
    BOOL _isNew;
    
    NSTextField *_nameField;
    NSTextField *_hostField;
    NSTextField *_portField;
    NSButton *_sslCheckbox;
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

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)];
    
    NSTextField *titleLabel = [NSTextField labelWithString:_isNew ? @"Add New Session" : @"Edit Session"];
    titleLabel.font = [NSFont boldSystemFontOfSize:14];
    titleLabel.frame = NSMakeRect(20, 160, 260, 20);
    [self.view addSubview:titleLabel];
    
    // Name
    [self.view addSubview:[self label:@"Name:" y:130]];
    _nameField = [NSTextField textFieldWithString:_session.name ?: @""];
    _nameField.frame = NSMakeRect(80, 126, 200, 22);
    [self.view addSubview:_nameField];
    
    // Host
    [self.view addSubview:[self label:@"Host:" y:100]];
    _hostField = [NSTextField textFieldWithString:_session.host ?: @""];
    _hostField.placeholderString = @"e.g. 10.134.49.215";
    _hostField.frame = NSMakeRect(80, 96, 200, 22);
    [self.view addSubview:_hostField];
    
    // Port
    [self.view addSubview:[self label:@"Port:" y:70]];
    _portField = [NSTextField textFieldWithString:[NSString stringWithFormat:@"%d", _session.port]];
    _portField.frame = NSMakeRect(80, 66, 60, 22);
    [self.view addSubview:_portField];
    
    // SSL
    _sslCheckbox = [NSButton checkboxWithTitle:@"Use SSL (port 992)" target:nil action:nil];
    _sslCheckbox.state = _session.useSSL ? NSControlStateValueOn : NSControlStateValueOff;
    _sslCheckbox.frame = NSMakeRect(150, 66, 150, 22);
    [self.view addSubview:_sslCheckbox];
    
    // Buttons
    NSButton *cancelBtn = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancelClicked:)];
    cancelBtn.frame = NSMakeRect(130, 20, 80, 24);
    [self.view addSubview:cancelBtn];
    
    NSButton *saveBtn = [NSButton buttonWithTitle:@"Save" target:self action:@selector(saveClicked:)];
    saveBtn.frame = NSMakeRect(210, 20, 70, 24);
    saveBtn.keyEquivalent = @"\r"; // Push Enter to save
    [self.view addSubview:saveBtn];
}

- (NSTextField *)label:(NSString *)text y:(CGFloat)y {
    NSTextField *lbl = [NSTextField labelWithString:text];
    lbl.alignment = NSTextAlignmentRight;
    lbl.frame = NSMakeRect(20, y, 50, 20);
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
    
    if (self.delegate) [self.delegate sessionEditorDidSave:_session isNew:_isNew];
}

@end