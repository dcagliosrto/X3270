#import "PreferencesWindowController.h"
#import "TerminalView.h"

@implementation PreferencesWindowController {
    NSButton *_use3270FontCheckbox;
    NSButton *_herculesBracketsCheckbox;
    
    // Fast Paths UI properties
    NSTableView *_fastPathsTable;
    NSMutableArray<NSMutableDictionary*> *_fastPaths;
}

+ (instancetype)sharedController {
    static PreferencesWindowController *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Increased window height to 580 to fit the new Fast Paths section
        NSWindow *win = [[NSWindow alloc]
                         initWithContentRect:NSMakeRect(0, 0, 420, 580)
                                   styleMask:NSWindowStyleMaskTitled
                                            |NSWindowStyleMaskClosable
                                     backing:NSBackingStoreBuffered
                                       defer:NO];
        win.title = @"DX3270 - Preferences";
        win.releasedWhenClosed = NO;
        [win center];
        shared = [[PreferencesWindowController alloc] initWithWindow:win];
        [shared loadFastPaths];
        [shared buildUI];
    });
    return shared;
}

#pragma mark - Fast Paths Data Management

- (void)loadFastPaths {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSArray *saved = [defaults arrayForKey:@"DX3270_FastPaths"];
    _fastPaths = [NSMutableArray array];
    
    if (saved && saved.count > 0) {
        for (NSDictionary *dict in saved) {
            [_fastPaths addObject:[dict mutableCopy]];
        }
    } else {
        // Default mappings if never configured
        [_fastPaths addObject:[@{@"title": @"=3.4", @"cmd": @"=3.4"} mutableCopy]];
        [_fastPaths addObject:[@{@"title": @"=SDSF", @"cmd": @"=S;ST"} mutableCopy]];
        [_fastPaths addObject:[@{@"title": @"=2", @"cmd": @"=2"} mutableCopy]];
        [_fastPaths addObject:[@{@"title": @"=X", @"cmd": @"=X"} mutableCopy]];
        [self saveFastPaths];
    }
}

- (void)saveFastPaths {
    [[NSUserDefaults standardUserDefaults] setObject:_fastPaths forKey:@"DX3270_FastPaths"];
}

#pragma mark - UI Setup

- (void)buildUI {
    NSView *cv = self.window.contentView;
    CGFloat margin = 20;

    // ==========================================
    // Section: Terminal Font
    // ==========================================
    NSTextField *fontHeader = [NSTextField labelWithString:@"Terminal Font"];
    fontHeader.font = [NSFont boldSystemFontOfSize:13];
    fontHeader.frame = NSMakeRect(margin, 540, 380, 20);
    [cv addSubview:fontHeader];

    NSBox *sep1 = [[NSBox alloc] initWithFrame:NSMakeRect(margin, 534, 380, 1)];
    sep1.boxType = NSBoxSeparator;
    [cv addSubview:sep1];

    _use3270FontCheckbox = [NSButton checkboxWithTitle:@"Use IBM 3270 font (by Ricardo Bánffy)"
                                                target:self
                                                action:@selector(fontCheckboxChanged:)];
    _use3270FontCheckbox.frame = NSMakeRect(margin, 506, 380, 22);
    BOOL currentValue = [[NSUserDefaults standardUserDefaults] boolForKey:kPref3270FontEnabled];
    _use3270FontCheckbox.state = currentValue ? NSControlStateValueOn : NSControlStateValueOff;
    [cv addSubview:_use3270FontCheckbox];

    NSTextField *note = [NSTextField wrappingLabelWithString:
        @"Replaces the default Menlo font with the authentic IBM 3270 monospace font. "
         "The font is bundled with this app and designed to match the look of original "
         "IBM 3270 terminals."];
    note.textColor = [NSColor secondaryLabelColor];
    note.font = [NSFont systemFontOfSize:11];
    note.frame = NSMakeRect(margin + 18, 456, 362, 44);
    [cv addSubview:note];

    NSMutableAttributedString *linkTitle = [[NSMutableAttributedString alloc]
        initWithString:@"3270font on GitHub (github.com/rbanffy/3270font)"
            attributes:@{
                NSFontAttributeName:            [NSFont systemFontOfSize:11],
                NSForegroundColorAttributeName: [NSColor linkColor],
            }];
    NSButton *linkBtn = [[NSButton alloc] initWithFrame:NSMakeRect(margin + 18, 438, 362, 18)];
    [linkBtn setAttributedTitle:linkTitle];
    linkBtn.buttonType = NSButtonTypeMomentaryLight;
    linkBtn.bordered = NO;
    linkBtn.target = self;
    linkBtn.action = @selector(open3270FontLink:);
    linkBtn.alignment = NSTextAlignmentLeft;
    [cv addSubview:linkBtn];

    // ==========================================
    // Section: Compatibility
    // ==========================================
    NSTextField *compatHeader = [NSTextField labelWithString:@"Compatibility"];
    compatHeader.font = [NSFont boldSystemFontOfSize:13];
    compatHeader.frame = NSMakeRect(margin, 404, 380, 20);
    [cv addSubview:compatHeader];

    NSBox *sep2 = [[NSBox alloc] initWithFrame:NSMakeRect(margin, 398, 380, 1)];
    sep2.boxType = NSBoxSeparator;
    [cv addSubview:sep2];

    _herculesBracketsCheckbox = [NSButton checkboxWithTitle:@"Display Hercules-style EBCDIC brackets as [ ]"
                                                     target:self
                                                     action:@selector(herculesBracketsChanged:)];
    _herculesBracketsCheckbox.frame = NSMakeRect(margin, 370, 380, 22);
    BOOL bracketsValue = [[NSUserDefaults standardUserDefaults] boolForKey:kPrefHerculesBrackets];
    _herculesBracketsCheckbox.state = bracketsValue ? NSControlStateValueOn : NSControlStateValueOff;
    [cv addSubview:_herculesBracketsCheckbox];

    NSTextField *compatNote = [NSTextField wrappingLabelWithString:
        @"For Hercules-hosted MVS (e.g. TK5) where the host code page is CP1047. "
         "Renders inbound 0xAD/0xBD (and 0x4A/0x5A) as [ and ], and sends typed "
         "brackets as 0xAD/0xBD so the host stores them natively.\n\n"
         "Note: ISPF EDIT may still display brackets as blank in its data row "
         "because [ and ] fall outside its “displayable character set” — "
         "this is a host-side filter, not a terminal bug. Use HEX ON or BROWSE "
         "to confirm the bytes are stored correctly."];
    compatNote.textColor = [NSColor secondaryLabelColor];
    compatNote.font = [NSFont systemFontOfSize:11];
    compatNote.frame = NSMakeRect(margin + 18, 310, 362, 56);
    [cv addSubview:compatNote];

    // ==========================================
    // Section: Command Dock Fast Paths
    // ==========================================
    NSTextField *pathsHeader = [NSTextField labelWithString:@"ISPF Fast Paths"];
    pathsHeader.font = [NSFont boldSystemFontOfSize:13];
    pathsHeader.frame = NSMakeRect(margin, 270, 380, 20);
    [cv addSubview:pathsHeader];

    NSBox *sepPaths = [[NSBox alloc] initWithFrame:NSMakeRect(margin, 264, 380, 1)];
    sepPaths.boxType = NSBoxSeparator;
    [cv addSubview:sepPaths];

    NSTextField *pathsNote = [NSTextField wrappingLabelWithString:
        @"Customize the quick jump buttons for the Command Dock. Double click a row to edit. "
         "Changes will be applied to new terminal connections."];
    pathsNote.textColor = [NSColor secondaryLabelColor];
    pathsNote.font = [NSFont systemFontOfSize:11];
    pathsNote.frame = NSMakeRect(margin, 220, 380, 34);
    [cv addSubview:pathsNote];

    // Table View for Fast Paths
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(margin, 100, 380, 110)];
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    scroll.autohidesScrollers = YES;

    _fastPathsTable = [[NSTableView alloc] init];
    _fastPathsTable.dataSource = self;
    _fastPathsTable.delegate = self;
    _fastPathsTable.rowHeight = 20;

    NSTableColumn *colTitle = [[NSTableColumn alloc] initWithIdentifier:@"title"];
    colTitle.title = @"Button Label";
    colTitle.width = 120;
    [_fastPathsTable addTableColumn:colTitle];

    NSTableColumn *colCmd = [[NSTableColumn alloc] initWithIdentifier:@"cmd"];
    colCmd.title = @"ISPF Command";
    colCmd.width = 240;
    [_fastPathsTable addTableColumn:colCmd];

    scroll.documentView = _fastPathsTable;
    [cv addSubview:scroll];

   // Add / Remove buttons
    NSButton *addBtn = [NSButton buttonWithTitle:@"+" target:self action:@selector(addFastPath:)];
    addBtn.frame = NSMakeRect(margin, 70, 32, 24);
    addBtn.bezelStyle = NSBezelStyleSmallSquare;
    [cv addSubview:addBtn];

    NSButton *remBtn = [NSButton buttonWithTitle:@"-" target:self action:@selector(removeFastPath:)];
    remBtn.frame = NSMakeRect(margin + 36, 70, 32, 24);
    remBtn.bezelStyle = NSBezelStyleSmallSquare;
    [cv addSubview:remBtn];

    // Move Up / Move Down buttons
    NSButton *upBtn = [NSButton buttonWithTitle:@"↑" target:self action:@selector(moveFastPathUp:)];
    upBtn.frame = NSMakeRect(margin + 72, 70, 32, 24);
    upBtn.bezelStyle = NSBezelStyleSmallSquare;
    [cv addSubview:upBtn];

    NSButton *dnBtn = [NSButton buttonWithTitle:@"↓" target:self action:@selector(moveFastPathDown:)];
    dnBtn.frame = NSMakeRect(margin + 108, 70, 32, 24);
    dnBtn.bezelStyle = NSBezelStyleSmallSquare;
    [cv addSubview:dnBtn];

    // ==========================================
    // Footer
    // ==========================================
    NSBox *sep3 = [[NSBox alloc] initWithFrame:NSMakeRect(margin, 46, 380, 1)];
    sep3.boxType = NSBoxSeparator;
    [cv addSubview:sep3];

    NSTextField *futureLbl = [NSTextField wrappingLabelWithString:
        @"More options coming: colour scheme, code page defaults, keyboard mapping."];
    futureLbl.textColor = [NSColor tertiaryLabelColor];
    futureLbl.font = [NSFont systemFontOfSize:10];
    futureLbl.frame = NSMakeRect(margin, 22, 380, 18);
    [cv addSubview:futureLbl];
}

#pragma mark - Table View Data Source & Delegate

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return _fastPaths.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    return _fastPaths[row][tableColumn.identifier];
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    // Save edits (double click on a cell triggers this automatically)
    _fastPaths[row][tableColumn.identifier] = object;
    [self saveFastPaths];
}

#pragma mark - Actions

- (void)addFastPath:(id)sender {
    [_fastPaths addObject:[@{@"title": @"New", @"cmd": @"=CMD"} mutableCopy]];
    [_fastPathsTable reloadData];
    [self saveFastPaths];
}

- (void)removeFastPath:(id)sender {
    NSInteger row = _fastPathsTable.selectedRow;
    if (row >= 0 && row < (NSInteger)_fastPaths.count) {
        [_fastPaths removeObjectAtIndex:row];
        [_fastPathsTable reloadData];
        [self saveFastPaths];
    }
}

- (void)moveFastPathUp:(id)sender {
    NSInteger row = _fastPathsTable.selectedRow;
    
    // Check if a valid row is selected and it's not already at the top
    if (row > 0 && row < (NSInteger)_fastPaths.count) {
        [_fastPaths exchangeObjectAtIndex:row withObjectAtIndex:row - 1];
        [_fastPathsTable reloadData];
        
        // Keep the moved row selected
        NSIndexSet *newSelection = [NSIndexSet indexSetWithIndex:row - 1];
        [_fastPathsTable selectRowIndexes:newSelection byExtendingSelection:NO];
        
        [self saveFastPaths];
    }
}

- (void)moveFastPathDown:(id)sender {
    NSInteger row = _fastPathsTable.selectedRow;
    
    // Check if a valid row is selected and it's not already at the bottom
    if (row >= 0 && row < (NSInteger)_fastPaths.count - 1) {
        [_fastPaths exchangeObjectAtIndex:row withObjectAtIndex:row + 1];
        [_fastPathsTable reloadData];
        
        // Keep the moved row selected
        NSIndexSet *newSelection = [NSIndexSet indexSetWithIndex:row + 1];
        [_fastPathsTable selectRowIndexes:newSelection byExtendingSelection:NO];
        
        [self saveFastPaths];
    }
}

- (void)fontCheckboxChanged:(NSButton *)sender {
    BOOL enabled = (sender.state == NSControlStateValueOn);
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kPref3270FontEnabled];
}

- (void)herculesBracketsChanged:(NSButton *)sender {
    BOOL enabled = (sender.state == NSControlStateValueOn);
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kPrefHerculesBrackets];
}

- (void)open3270FontLink:(id)sender {
    [[NSWorkspace sharedWorkspace]
        openURL:[NSURL URLWithString:@"https://github.com/rbanffy/3270font"]];
}

@end