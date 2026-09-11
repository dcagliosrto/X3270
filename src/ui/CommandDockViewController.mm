#import "CommandDockViewController.h"

@interface CommandDockViewController () <NSSearchFieldDelegate>
@property (nonatomic, strong) NSPopUpButton *linkGroupPopUp;
@property (nonatomic, strong) NSSearchField *ispfCommandField;
@property (nonatomic, strong) NSSearchField *oobCommandField;
@end

@implementation CommandDockViewController

- (void)loadView {
    NSVisualEffectView *effectView = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(0, 0, 900, 36)];
    effectView.material = NSVisualEffectMaterialHeaderView;
    effectView.appearance = [NSAppearance appearanceNamed:NSAppearanceNameVibrantDark];
    effectView.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    effectView.state = NSVisualEffectStateActive;
    effectView.autoresizingMask = NSViewWidthSizable;

    NSStackView *mainStack = [[NSStackView alloc] initWithFrame:effectView.bounds];
    mainStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    mainStack.alignment = NSLayoutAttributeCenterY;
    mainStack.edgeInsets = NSEdgeInsetsMake(4, 12, 4, 12);
    mainStack.spacing = 12;
    mainStack.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    // ==========================================
    // Selective Link Group Selector
    // ==========================================
    self.linkGroupPopUp = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.linkGroupPopUp.controlSize = NSControlSizeSmall;
    [self.linkGroupPopUp addItemsWithTitles:@[@"🔗 Only This", @"🔗 Group A", @"🔗 Group B"]];
    self.linkGroupPopUp.target = self;
    self.linkGroupPopUp.action = @selector(linkGroupChanged:);
    [mainStack addArrangedSubview:self.linkGroupPopUp];

    NSBox *sep0 = [[NSBox alloc] init];
    sep0.boxType = NSBoxSeparator;
    [sep0.heightAnchor constraintEqualToConstant:16].active = YES;
    [mainStack addArrangedSubview:sep0];

    // ==========================================
    // 1. ISPF Navigation & Fast Paths
    // ==========================================
    NSStackView *ispfStack = [[NSStackView alloc] init];
    ispfStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    ispfStack.spacing = 4;

    NSArray *navTitles = @[@"◀ Prev", @"Next ▶", @"List ≡", @"New +"];
    NSArray *navCommands = @[@"SWAP PREV", @"SWAP NEXT", @"SWAP LIST", @"START"];
    
    for (NSUInteger i = 0; i < navTitles.count; i++) {
        NSButton *btn = [NSButton buttonWithTitle:navTitles[i] target:self action:@selector(ispfButtonClicked:)];
        btn.bezelStyle = NSBezelStyleInline;
        btn.controlSize = NSControlSizeSmall;
        btn.identifier = navCommands[i];
        [ispfStack addArrangedSubview:btn];
    }
    
    NSBox *sep1 = [[NSBox alloc] init];
    sep1.boxType = NSBoxSeparator;
    [sep1.heightAnchor constraintEqualToConstant:16].active = YES;
    [ispfStack addArrangedSubview:sep1];

    // Dynamic Fast Paths
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSArray *fastPaths = [defaults arrayForKey:@"DX3270_FastPaths"];
    if (!fastPaths) {
        fastPaths = @[
            @{@"title": @"=3.4",  @"cmd": @"=3.4"},
            @{@"title": @"=SDSF", @"cmd": @"=S;ST"},
            @{@"title": @"=2",    @"cmd": @"=2"},
            @{@"title": @"=X",    @"cmd": @"=X"}
        ];
    }
    for (NSDictionary *path in fastPaths) {
        NSButton *btn = [NSButton buttonWithTitle:path[@"title"] target:self action:@selector(ispfButtonClicked:)];
        btn.bezelStyle = NSBezelStyleInline;
        btn.controlSize = NSControlSizeSmall;
        btn.identifier = path[@"cmd"];
        [ispfStack addArrangedSubview:btn];
    }

    [mainStack addArrangedSubview:ispfStack];
    
    // ISPF Direct Input
    self.ispfCommandField = [[NSSearchField alloc] init];
    self.ispfCommandField.placeholderString = @"ISPF Cmd...";
    self.ispfCommandField.delegate = self;
    self.ispfCommandField.controlSize = NSControlSizeSmall;
    [self.ispfCommandField.widthAnchor constraintEqualToConstant:90].active = YES;
    [mainStack addArrangedSubview:self.ispfCommandField];

    // Spacer
    NSView *spacer = [[NSView alloc] init];
    [spacer setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [mainStack addArrangedSubview:spacer];

    // ==========================================
    // Out-of-Band SSH Executor
    // ==========================================
    NSStackView *oobStack = [[NSStackView alloc] init];
    oobStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    oobStack.spacing = 6;

    NSTextField *oobLabel = [NSTextField labelWithString:@"SSH/OOB:"];
    oobLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    oobLabel.textColor = [NSColor colorWithWhite:0.7 alpha:1.0];
    [oobStack addArrangedSubview:oobLabel];

    self.oobCommandField = [[NSSearchField alloc] init];
    self.oobCommandField.placeholderString = @"TSO / System...";
    self.oobCommandField.delegate = self;
    self.oobCommandField.controlSize = NSControlSizeSmall;
    [self.oobCommandField.widthAnchor constraintEqualToConstant:130].active = YES;
    [oobStack addArrangedSubview:self.oobCommandField];

    [mainStack addArrangedSubview:oobStack];

    [effectView addSubview:mainStack];
    self.view = effectView;
}

#pragma mark - Group Selection & Actions

- (void)linkGroupChanged:(NSPopUpButton *)sender {
    NSInteger index = sender.indexOfSelectedItem;
    if (index == 1) {
        self.linkGroup = @"GroupA";
    } else if (index == 2) {
        self.linkGroup = @"GroupB";
    } else {
        self.linkGroup = nil; // Standalone / Solo window
    }
}

- (void)ispfButtonClicked:(NSButton *)sender {
    if (self.delegate && sender.identifier) {
        [self.delegate commandDockDidRequestISPFCommand:sender.identifier targetGroup:self.linkGroup];
    }
}

- (void)controlTextDidEndEditing:(NSNotification *)obj {
    NSTextField *textField = obj.object;
    NSInteger movement = [[[obj userInfo] objectForKey:@"NSTextMovement"] integerValue];
    
    if (movement == NSReturnTextMovement && textField.stringValue.length > 0) {
        if (textField == self.ispfCommandField) {
            if (self.delegate) {
                [self.delegate commandDockDidRequestISPFCommand:textField.stringValue targetGroup:self.linkGroup];
            }
        } else if (textField == self.oobCommandField) {
            if (self.delegate) {
                [self.delegate commandDockDidRequestOutOdBandCommand:textField.stringValue targetGroup:self.linkGroup];
            }
        }
        textField.stringValue = @"";
    }
}

@end