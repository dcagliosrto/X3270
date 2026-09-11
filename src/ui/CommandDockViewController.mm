#import "CommandDockViewController.h"

@interface CommandDockViewController () <NSSearchFieldDelegate>
@property (nonatomic, strong) NSSearchField *ispfCommandField;
@property (nonatomic, strong) NSSearchField *oobCommandField;
@end

@implementation CommandDockViewController

- (void)loadView {
    // Dark Vibrancy background (Native macOS dark glass effect)
    NSVisualEffectView *effectView = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(0, 0, 850, 36)];
    effectView.material = NSVisualEffectMaterialHeaderView;
    effectView.appearance = [NSAppearance appearanceNamed:NSAppearanceNameVibrantDark];
    effectView.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    effectView.state = NSVisualEffectStateActive;
    effectView.autoresizingMask = NSViewWidthSizable;

    NSStackView *mainStack = [[NSStackView alloc] initWithFrame:effectView.bounds];
    mainStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    mainStack.alignment = NSLayoutAttributeCenterY;
    mainStack.edgeInsets = NSEdgeInsetsMake(4, 12, 4, 12);
    mainStack.spacing = 16;
    mainStack.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    // ==========================================
    // 1. ISPF Navigation & Fast Paths
    // ==========================================
    NSStackView *ispfStack = [[NSStackView alloc] init];
    ispfStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    ispfStack.spacing = 4;

    // Relative Navigation
    NSArray *navTitles = @[@"◀ Prev", @"Next ▶", @"List ≡", @"New +"];
    NSArray *navCommands = @[@"SWAP PREV", @"SWAP NEXT", @"SWAP LIST", @"START"];
    
    for (NSUInteger i = 0; i < navTitles.count; i++) {
        NSButton *btn = [NSButton buttonWithTitle:navTitles[i] target:self action:@selector(ispfButtonClicked:)];
        btn.bezelStyle = NSBezelStyleInline;
        btn.controlSize = NSControlSizeSmall;
        btn.identifier = navCommands[i];
        [ispfStack addArrangedSubview:btn];
    }
    
    // Separator
    NSBox *sep1 = [[NSBox alloc] init];
    sep1.boxType = NSBoxSeparator;
    [sep1.heightAnchor constraintEqualToConstant:16].active = YES;
    [ispfStack addArrangedSubview:sep1];

    // ==========================================
    // Fast Paths (Dynamic & Customizable)
    // ==========================================
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSArray *fastPaths = [defaults arrayForKey:@"DX3270_FastPaths"];
    
    // Fallback to standard defaults if the user has never configured them
    if (!fastPaths) {
        fastPaths = @[
            @{@"title": @"=3.4",  @"cmd": @"=3.4"},
            @{@"title": @"=SDSF", @"cmd": @"=S;ST"}, // Default mapped to your system
            @{@"title": @"=2",    @"cmd": @"=2"},
            @{@"title": @"=X",    @"cmd": @"=X"}
        ];
        [defaults setObject:fastPaths forKey:@"DX3270_FastPaths"];
    }
    
    for (NSDictionary *path in fastPaths) {
        NSButton *btn = [NSButton buttonWithTitle:path[@"title"] target:self action:@selector(ispfButtonClicked:)];
        btn.bezelStyle = NSBezelStyleInline;
        btn.controlSize = NSControlSizeSmall;
        btn.identifier = path[@"cmd"]; // The actual ISPF command to inject
        [ispfStack addArrangedSubview:btn];
    }

    [mainStack addArrangedSubview:ispfStack];

    // ==========================================
    // 2. ISPF Direct Command Bar
    // ==========================================
    self.ispfCommandField = [[NSSearchField alloc] init];
    self.ispfCommandField.placeholderString = @"ISPF Cmd...";
    self.ispfCommandField.delegate = self;
    self.ispfCommandField.controlSize = NSControlSizeSmall;
    [self.ispfCommandField.widthAnchor constraintEqualToConstant:100].active = YES;
    [mainStack addArrangedSubview:self.ispfCommandField];

    // --- Spacer to push the OOB executor to the right ---
    NSView *spacer = [[NSView alloc] init];
    [spacer setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [mainStack addArrangedSubview:spacer];

    // ==========================================
    // 3. Out-of-Band Background Executor
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
    [self.oobCommandField.widthAnchor constraintEqualToConstant:140].active = YES;
    [oobStack addArrangedSubview:self.oobCommandField];

    [mainStack addArrangedSubview:oobStack];

    [effectView addSubview:mainStack];
    self.view = effectView;
}

#pragma mark - Actions

- (void)ispfButtonClicked:(NSButton *)sender {
    if (self.delegate && sender.identifier) {
        [self.delegate commandDockDidRequestISPFCommand:sender.identifier];
    }
}

// Forward text on Enter (Differentiating between the two search fields)
- (void)controlTextDidEndEditing:(NSNotification *)obj {
    NSTextField *textField = obj.object;
    NSInteger movement = [[[obj userInfo] objectForKey:@"NSTextMovement"] integerValue];
    
    if (movement == NSReturnTextMovement && textField.stringValue.length > 0) {
        if (textField == self.ispfCommandField) {
            // In-Band ISPF Command (e.g., "FIND XXX", "SAVE")
            if (self.delegate) {
                [self.delegate commandDockDidRequestISPFCommand:textField.stringValue];
            }
        } else if (textField == self.oobCommandField) {
            // Out-of-Band SSH Command
            if (self.delegate) {
                [self.delegate commandDockDidRequestOutOdBandCommand:textField.stringValue];
            }
        }
        textField.stringValue = @""; // Clear the field for the next command
    }
}

@end