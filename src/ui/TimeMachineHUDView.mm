#import "TimeMachineHUDView.h"

@interface TimeMachineHUDView () <NSSearchFieldDelegate>
@property (nonatomic, strong) NSButton *prevButton;
@property (nonatomic, strong) NSButton *nextButton;
@property (nonatomic, strong) NSSlider *slider;
@property (nonatomic, strong) NSTextField *infoLabel;

// --- NEW PIN PROPERTIES ---
@property (nonatomic, strong) NSButton *prevPinButton;
@property (nonatomic, strong) NSButton *pinButton;
@property (nonatomic, strong) NSButton *nextPinButton;

// --- EXPORT & IMPORT BUTTONS ---
@property (nonatomic, strong) NSButton *exportBtn;
@property (nonatomic, strong) NSButton *importBtn;

@property (nonatomic, strong) NSSearchField *searchField;
@property (nonatomic, strong) NSButton *diffButton;
@property (nonatomic, strong) NSButton *liveButton;
@property (nonatomic, assign) BOOL isDiffActive;
@end

@implementation TimeMachineHUDView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.material = NSVisualEffectMaterialHUDWindow;
        self.blendingMode = NSVisualEffectBlendingModeWithinWindow;
        self.state = NSVisualEffectStateActive;
        self.wantsLayer = YES;
        self.layer.cornerRadius = 10.0;
        self.layer.masksToBounds = YES;
        
        [self setupUIComponents];
    }
    return self;
}

- (void)setupUIComponents {
    _prevButton = [NSButton buttonWithTitle:@"◀" target:self action:@selector(onPrevPressed:)];
    _prevButton.bezelStyle = NSBezelStyleInline;
    
    _nextButton = [NSButton buttonWithTitle:@"▶" target:self action:@selector(onNextPressed:)];
    _nextButton.bezelStyle = NSBezelStyleInline;
    
    _slider = [[NSSlider alloc] init];
    _slider.minValue = 0;
    _slider.maxValue = 1;
    _slider.numberOfTickMarks = 0;
    _slider.target = self;
    _slider.action = @selector(onSliderChanged:);
    
    _infoLabel = [NSTextField labelWithString:@"--:--:-- (#0/0)"];
    _infoLabel.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightMedium];
    _infoLabel.alignment = NSTextAlignmentCenter;

    // --- PIN GROUP / BOOKMARK ---
    _prevPinButton = [NSButton buttonWithTitle:@"⏮" target:self action:@selector(onPrevPinPressed:)];
    _prevPinButton.bezelStyle = NSBezelStyleInline;
    _prevPinButton.toolTip = @"Jump to Previous PIN";

    _pinButton = [NSButton buttonWithTitle:@"📌 PIN" target:self action:@selector(onPinPressed:)];
    [_pinButton setButtonType:NSButtonTypePushOnPushOff];
    _pinButton.bezelStyle = NSBezelStyleInline;
    _pinButton.showsBorderOnlyWhileMouseInside = NO;
    _pinButton.toolTip = @"Toggle PIN (Bookmark Current Frame)";

    _nextPinButton = [NSButton buttonWithTitle:@"⏭" target:self action:@selector(onNextPinPressed:)];
    _nextPinButton.bezelStyle = NSBezelStyleInline;
    _nextPinButton.toolTip = @"Jump to Next PIN";


    // --- EXPORT & IMPORT ---
    _exportBtn = [NSButton buttonWithTitle:@"💾 Export" target:self action:@selector(onExportPressed:)];
    _exportBtn.bezelStyle = NSBezelStyleInline;
    _exportBtn.toolTip = @"Export Current Frame";

    _importBtn = [NSButton buttonWithTitle:@"📂 Import" target:self action:@selector(onImportPressed:)];
    _importBtn.bezelStyle = NSBezelStyleInline;
    _importBtn.toolTip = @"Import Current Frame";

    // --- SEARCH BAR ---
    _searchField = [[NSSearchField alloc] init];
    _searchField.placeholderString = @"Search...";
    _searchField.delegate = self;
    _searchField.controlSize = NSControlSizeSmall;
    
    _diffButton = [NSButton buttonWithTitle:@"DIFF" target:self action:@selector(onDiffToggled:)];
    [_diffButton setButtonType:NSButtonTypeToggle];
    _diffButton.bezelStyle = NSBezelStyleInline;
    
    _liveButton = [NSButton buttonWithTitle:@"LIVE ⏏" target:self action:@selector(onLivePressed:)];
    _liveButton.bezelStyle = NSBezelStyleInline;
    
    // Add all components to the stack view
    NSStackView *stack = [NSStackView stackViewWithViews:@[
        _prevButton, 
        _nextButton, 
        _slider, 
        _infoLabel,
        _prevPinButton, 
        _pinButton, 
        _nextPinButton, 
        _exportBtn,
        _importBtn,
        _searchField, 
        _diffButton, 
        _liveButton
    ]];
    
    stack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    stack.alignment = NSLayoutAttributeHeight;
    stack.spacing = 8; // Slightly reduced spacing from 10 to 8
    stack.edgeInsets = NSEdgeInsetsMake(6, 10, 6, 10);
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    
    [self addSubview:stack];
    
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:self.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_slider.widthAnchor constraintGreaterThanOrEqualToConstant:120],
        [_searchField.widthAnchor constraintEqualToConstant:100] // Compattato a 100 per far spazio ai PIN
    ]];
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector {
    if (control == self.searchField) {
        if (commandSelector == @selector(insertNewline:)) { // È stato premuto Invio
            // Search history based on the current input and direction
            // With Shift+Invio search forwards in history
            BOOL shiftPressed = ([NSEvent modifierFlags] & NSEventModifierFlagShift) != 0;
            BOOL searchBackwards = !shiftPressed;
            
            [self.delegate timeMachineDidRequestSearch:self.searchField.stringValue searchBackward:searchBackwards];
            return YES; // Avoids the standard system "beep"
        }
    }
    return NO;
}


- (void)onPinPressed:(id)sender {
    if ([self.delegate respondsToSelector:@selector(timeMachineDidTogglePin)]) {
        [self.delegate timeMachineDidTogglePin];
    }
}

- (void)onPrevPinPressed:(id)sender {
    if ([self.delegate respondsToSelector:@selector(timeMachineDidRequestJumpToNextPin:)]) {
        [self.delegate timeMachineDidRequestJumpToNextPin:NO];
    }
}

- (void)onNextPinPressed:(id)sender {
    if ([self.delegate respondsToSelector:@selector(timeMachineDidRequestJumpToNextPin:)]) {
        [self.delegate timeMachineDidRequestJumpToNextPin:YES];
    }
}

- (void)onExportPressed:(id)sender {
    if ([self.delegate respondsToSelector:@selector(timeMachineDidRequestExport)]) {
        [self.delegate timeMachineDidRequestExport];
    }
}

- (void)onImportPressed:(id)sender {
    if ([self.delegate respondsToSelector:@selector(timeMachineDidRequestImport)]) {
        [self.delegate timeMachineDidRequestImport];
    }
}

- (void)updateWithSnapshotsCount:(NSInteger)count currentIndex:(NSInteger)index timestamp:(NSTimeInterval)timestamp {
    if (count <= 0) return;
    
    self.slider.maxValue = count - 1;
    self.slider.integerValue = index;
    
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"HH:mm:ss";
    NSString *timeStr = [fmt stringFromDate:[NSDate dateWithTimeIntervalSince1970:timestamp]];
    
    NSInteger baselineIdx = [TimeMachineManager sharedManager].baselinePinIndex;
    
    if (self.isDiffActive) {
        if (baselineIdx >= 0) {
            // Mostra il confronto esplicito tra il frame corrente e il PIN impostato come baseline
            self.infoLabel.stringValue = [NSString stringWithFormat:@"%@ (DIFF #%ld vs 📍PIN #%ld)", timeStr, (long)(index + 1), (long)(baselineIdx + 1)];
        } else if (index > 0) {
            self.infoLabel.stringValue = [NSString stringWithFormat:@"%@ (DIFF #%ld vs #%ld)", timeStr, (long)(index + 1), (long)index];
        }
        self.infoLabel.textColor = [NSColor systemOrangeColor];
    } else {
        self.infoLabel.stringValue = [NSString stringWithFormat:@"%@ (#%ld/%ld)", timeStr, (long)(index + 1), (long)count];
        self.infoLabel.textColor = [NSColor labelColor];
    }

    BOOL isPinned = [[TimeMachineManager sharedManager] isPinnedAtIndex:index];
    if (isPinned) {
        self.pinButton.state = NSControlStateValueOn;
        self.pinButton.title = @"📍 PINNED";
    } else {
        self.pinButton.state = NSControlStateValueOff;
        self.pinButton.title = @"📌 PIN";
    }
}

- (void)onSliderChanged:(NSSlider *)sender {
    [self.delegate timeMachineDidSelectSnapshotAtIndex:sender.integerValue];
}

- (void)onPrevPressed:(id)sender {
    if (self.slider.integerValue > 0) {
        self.slider.integerValue -= 1;
        [self onSliderChanged:self.slider];
    }
}

- (void)onNextPressed:(id)sender {
    if (self.slider.integerValue < self.slider.maxValue) {
        self.slider.integerValue += 1;
        [self onSliderChanged:self.slider];
    }
}

- (void)onDiffToggled:(NSButton *)sender {
    self.isDiffActive = (sender.state == NSControlStateValueOn);
    [self.delegate timeMachineDidToggleDiffMode:self.isDiffActive];
}

- (void)onLivePressed:(id)sender {
    [self.delegate timeMachineDidReturnToLive];
}

- (void)showInParentView:(NSView *)parentView {
    if (self.superview) return;
    
    self.translatesAutoresizingMaskIntoConstraints = NO;
    [parentView addSubview:self];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.centerXAnchor constraintEqualToAnchor:parentView.centerXAnchor],
        [self.bottomAnchor constraintEqualToAnchor:parentView.bottomAnchor constant:-45],
        [self.heightAnchor constraintEqualToConstant:36]
    ]];
}

- (void)hide {
    [self removeFromSuperview];
}

@end