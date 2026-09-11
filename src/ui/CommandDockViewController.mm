#import "CommandDockViewController.h"
#import "OOBPopoverViewController.h"

@interface CommandDockViewController () <NSSearchFieldDelegate, NSTableViewDelegate, NSTableViewDataSource>
@property (nonatomic, strong) NSPopUpButton *linkGroupPopUp;
@property (nonatomic, strong) NSSearchField *ispfCommandField;
@property (nonatomic, strong) NSSearchField *oobCommandField;
@property (nonatomic, strong) NSPopover *oobPopover; // <--- Ripristinata qui

@property (nonatomic, strong) NSArray<NSDictionary *> *availableCommands;
@property (nonatomic, assign) BOOL isAutocompleting;

// Properties of the Autocompletion Popover
@property (nonatomic, strong) NSPopover *completionPopover;
@property (nonatomic, strong) NSTableView *completionTableView;
@property (nonatomic, strong) NSArray<NSDictionary *> *currentMatches;
@property (nonatomic, weak) NSTextField *activeSearchField;
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

    // Ruler Toggle Button
    NSButton *rulerBtn = [NSButton buttonWithTitle:@"\u253C Ruler" target:self action:@selector(rulerButtonClicked:)];
    rulerBtn.toolTip = @"Toggle Crosshair Ruler for this session";
    rulerBtn.bezelStyle = NSBezelStyleInline;
    rulerBtn.controlSize = NSControlSizeSmall;
    [mainStack addArrangedSubview:rulerBtn];

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
    [self.oobCommandField.widthAnchor constraintEqualToConstant:300].active = YES;
    [oobStack addArrangedSubview:self.oobCommandField];

    [mainStack addArrangedSubview:oobStack];

    [effectView addSubview:mainStack];
    self.view = effectView;

    // ==========================================
    // Load Autocomplete Commands from JSON
    // ==========================================
    NSString *jsonPath = [[NSBundle mainBundle] pathForResource:@"commands" ofType:@"json"];
    if (jsonPath) {
        NSData *jsonData = [NSData dataWithContentsOfFile:jsonPath];
        if (jsonData) {
            NSError *error = nil;
            self.availableCommands = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
            if (error) {
                NSLog(@"[DX3270] Failed to parse commands.json: %@", error.localizedDescription);
            }
        }
    }
    
    // Fallback to empty array if file is missing or invalid
    if (!self.availableCommands) {
        self.availableCommands = @[];
    }
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
                NSString *rawInput = [textField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                NSString *resolvedCmd = rawInput; // Fallback se il comando non è nel JSON

                // Data-Driven Engine to translate the OOB template
                NSArray *parts = [rawInput componentsSeparatedByString:@" "];
                if (parts.count > 0) {
                    NSString *baseCmd = [parts.firstObject uppercaseString];
                    NSString *arg = (parts.count > 1) ? [[parts subarrayWithRange:NSMakeRange(1, parts.count - 1)] componentsJoinedByString:@" "] : @"";

                    for (NSDictionary *cmdDict in self.availableCommands) {
                        NSString *target = cmdDict[@"target"] ?: @"all";
                        if ([target isEqualToString:@"oob"] || [target isEqualToString:@"all"]) {
                            if ([[cmdDict[@"cmd"] uppercaseString] isEqualToString:baseCmd]) {
                                NSString *execTemplate = cmdDict[@"exec"];
                                if (execTemplate && execTemplate.length > 0) {
                                    resolvedCmd = [execTemplate stringByReplacingOccurrencesOfString:@"{arg}" withString:arg];
                                }
                                break;
                            }
                        }
                    }
                }
                
                [self.delegate commandDockDidRequestOutOdBandCommand:resolvedCmd targetGroup:self.linkGroup];
            }
        }
        textField.stringValue = @"";
    }
}

- (void)controlTextDidChange:(NSNotification *)obj {
    NSTextField *textField = obj.object;
    if (textField != self.ispfCommandField && textField != self.oobCommandField) return;

    // Determine the type of text field in use
    NSString *currentFieldTarget = (textField == self.ispfCommandField) ? @"ispf" : @"oob";

    // Do not trigger autocomplete on Backspace / Delete keys
    NSEvent *event = [NSApp currentEvent];
    if (event.type == NSEventTypeKeyDown && (event.keyCode == 51 || event.keyCode == 117)) {
        [self.completionPopover close];
        return;
    }

    NSString *text = textField.stringValue;
    if (text.length == 0) {
        [self.completionPopover close];
        return;
    }

    // Filter commands by prefix and target (destination)
    NSMutableArray<NSDictionary *> *matches = [NSMutableArray array];
    for (NSDictionary *cmdDict in self.availableCommands) {
        NSString *cmdTarget = cmdDict[@"target"] ?: @"all";
        
        // Check if the command belongs to the active category or 'all'
        if ([cmdTarget isEqualToString:@"all"] || [cmdTarget isEqualToString:currentFieldTarget]) {
            NSString *cmd = cmdDict[@"cmd"];
            if ([cmd.uppercaseString hasPrefix:text.uppercaseString]) {
                [matches addObject:cmdDict];
            }
        }
    }

    if (matches.count > 0) {
        self.currentMatches = matches;
        self.activeSearchField = textField;
        
        [self setupCompletionPopover];
        [self.completionTableView reloadData];

        CGFloat rowHeight = 42.0;
        CGFloat totalHeight = MIN(matches.count * rowHeight + 8, 160.0);
        self.completionPopover.contentSize = NSMakeSize(480, totalHeight);

        if (!self.completionPopover.isShown) {
            [self.completionPopover showRelativeToRect:textField.bounds
                                                 ofView:textField
                                          preferredEdge:NSRectEdgeMaxY];
        }
    } else {
        [self.completionPopover close];
    }
}

#pragma mark - Native Autocomplete Delegate

- (NSArray<NSString *> *)control:(NSControl *)control
                        textView:(NSTextView *)textView
                     completions:(NSArray<NSString *> *)words
             forPartialWordRange:(NSRange)charRange
             indexOfSelectedItem:(NSInteger *)index {
    
    // Get the substring the user has typed so far
    NSString *partialString = [[textView string] substringWithRange:charRange];
    if (partialString.length == 0) {
        return @[];
    }
    
    NSMutableArray<NSString *> *matches = [NSMutableArray array];
    
    // Filter the loaded JSON commands
    for (NSDictionary *cmdDict in self.availableCommands) {
        NSString *command = cmdDict[@"cmd"];
        
        // Match the beginning of the command, case-insensitive
        if ([command.uppercaseString hasPrefix:partialString.uppercaseString]) {
            [matches addObject:command];
        }
    }
    
    // You can set *index to a specific row if you want to pre-select one,
    // otherwise leaving it untouched defaults to 0 or no selection.
    
    return matches;
}

#pragma mark - OOB Popover Presentation

- (void)showOOBPopoverWithTitle:(NSString *)title content:(NSString *)content {
    if (!self.oobPopover) {
        self.oobPopover = [[NSPopover alloc] init];
        self.oobPopover.behavior = NSPopoverBehaviorTransient;
        self.oobPopover.appearance = [NSAppearance appearanceNamed:NSAppearanceNameVibrantDark];
    }
    
    OOBPopoverViewController *popoverVC = [[OOBPopoverViewController alloc] initWithTitle:title content:content];
    self.oobPopover.contentViewController = popoverVC;
    
    [self.oobPopover showRelativeToRect:self.oobCommandField.bounds
                                 ofView:self.oobCommandField
                          preferredEdge:NSRectEdgeMinY];
}


#pragma mark - Completion Popover Setup

- (void)setupCompletionPopover {
    if (self.completionPopover) return;

    NSViewController *vc = [[NSViewController alloc] init];
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 480, 200)];
    scrollView.hasVerticalScroller = YES;

    NSTableView *tableView = [[NSTableView alloc] initWithFrame:scrollView.bounds];
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"cmdCol"];
    col.width = 460; 
    [tableView addTableColumn:col];
    tableView.headerView = nil;
    tableView.delegate = self;
    tableView.dataSource = self;
    tableView.rowHeight = 42.0; 

    scrollView.documentView = tableView;
    vc.view = scrollView;

    self.completionTableView = tableView;
    self.completionPopover = [[NSPopover alloc] init];
    self.completionPopover.contentViewController = vc;
    self.completionPopover.behavior = NSPopoverBehaviorTransient;
}

#pragma mark - Completion TableView Delegate & DataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return self.currentMatches.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSTextField *cell = [tableView makeViewWithIdentifier:@"cmdCell" owner:self];
    if (!cell) {
        cell = [NSTextField labelWithString:@""];
        cell.identifier = @"cmdCell";
        cell.usesSingleLineMode = NO;
        cell.maximumNumberOfLines = 2;
        cell.lineBreakMode = NSLineBreakByWordWrapping;
    }

    NSDictionary *dict = self.currentMatches[row];
    NSString *cmd  = dict[@"cmd"] ?: @"";
    NSString *args = dict[@"args"] ?: @"";
    NSString *desc = dict[@"desc"] ?: @"";

    // First line: COMMAND in bold, ARGUMENTS in gray
    NSMutableAttributedString *titleAttr = [[NSMutableAttributedString alloc] initWithString:cmd attributes:@{
        NSFontAttributeName: [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightBold],
        NSForegroundColorAttributeName: [NSColor labelColor]
    }];

    if (args.length > 0) {
        NSAttributedString *argsAttr = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@" %@", args] attributes:@{
            NSFontAttributeName: [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular],
            NSForegroundColorAttributeName: [NSColor systemGrayColor]
        }];
        [titleAttr appendAttributedString:argsAttr];
    }

    // Second line: DESCRIPTION
    NSAttributedString *descAttr = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"\n%@", desc] attributes:@{
        NSFontAttributeName: [NSFont systemFontOfSize:10 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: [NSColor secondaryLabelColor]
    }];
    [titleAttr appendAttributedString:descAttr];

    cell.attributedStringValue = titleAttr;
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row = self.completionTableView.selectedRow;
    if (row >= 0 && row < (NSInteger)self.currentMatches.count && self.activeSearchField) {
        NSDictionary *dict = self.currentMatches[row];
        NSString *cmd  = dict[@"cmd"] ?: @"";
        NSString *args = dict[@"args"] ?: @"";

        if (args.length > 0) {
            // Insert "COMMAND <arguments>"
            NSString *fullString = [NSString stringWithFormat:@"%@ %@", cmd, args];
            self.activeSearchField.stringValue = fullString;
            
            // AUTOMATIC HIGHLIGHTING: Select the arguments part so the user can overwrite it immediately!
            NSText *editor = [self.activeSearchField currentEditor];
            if (editor) {
                NSRange argRange = NSMakeRange(cmd.length + 1, args.length);
                [editor setSelectedRange:argRange];
            }
        } else {
            self.activeSearchField.stringValue = cmd;
        }

        [self.completionPopover close];
    }
}

- (void)rulerButtonClicked:(NSButton *)sender {
    if ([self.delegate respondsToSelector:@selector(commandDockDidToggleRuler)]) {
        [self.delegate commandDockDidToggleRuler];
    }
}

@end