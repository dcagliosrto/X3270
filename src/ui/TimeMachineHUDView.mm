#import "TimeMachineHUDView.h"

@interface TimeMachineHUDView ()
@property (nonatomic, strong) NSButton *prevButton;
@property (nonatomic, strong) NSButton *nextButton;
@property (nonatomic, strong) NSSlider *slider;
@property (nonatomic, strong) NSTextField *infoLabel;
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
    // Pulsante Prev
    _prevButton = [NSButton buttonWithTitle:@"◀" target:self action:@selector(onPrevPressed:)];
    _prevButton.bezelStyle = NSBezelStyleInline;
    
    // Pulsante Next
    _nextButton = [NSButton buttonWithTitle:@"▶" target:self action:@selector(onNextPressed:)];
    _nextButton.bezelStyle = NSBezelStyleInline;
    
    // Timeline Slider
    _slider = [[NSSlider alloc] init];
    _slider.minValue = 0;
    _slider.maxValue = 1;
    _slider.numberOfTickMarks = 0;
    _slider.target = self;
    _slider.action = @selector(onSliderChanged:);
    
    // Info Label (Es: "14:28:12 (#12/50)")
    _infoLabel = [NSTextField labelWithString:@"--:--:-- (#0/0)"];
    _infoLabel.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightMedium];
    _infoLabel.alignment = NSTextAlignmentCenter;
    
    // Toggle DIFF
    _diffButton = [NSButton buttonWithTitle:@"DIFF" target:self action:@selector(onDiffToggled:)];
    [_diffButton setButtonType:NSButtonTypeToggle];
    _diffButton.bezelStyle = NSBezelStyleInline;
    
    // Pulsante LIVE
    _liveButton = [NSButton buttonWithTitle:@"LIVE 🔴" target:self action:@selector(onLivePressed:)];
    _liveButton.bezelStyle = NSBezelStyleInline;
    
    // Layout orizzontale
    NSStackView *stack = [NSStackView stackViewWithViews:@[_prevButton, _nextButton, _slider, _infoLabel, _diffButton, _liveButton]];
    stack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    stack.alignment = NSLayoutAttributeHeight;
    stack.spacing = 10;
    stack.edgeInsets = NSEdgeInsetsMake(6, 12, 6, 12);
    
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:stack];
    
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:self.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_slider.widthAnchor constraintGreaterThanOrEqualToConstant:180]
    ]];
}

- (void)updateWithSnapshotsCount:(NSInteger)count currentIndex:(NSInteger)index timestamp:(NSTimeInterval)timestamp {
    if (count <= 0) return;
    
    self.slider.maxValue = count - 1;
    self.slider.integerValue = index;
    
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"HH:mm:ss";
    NSString *timeStr = [fmt stringFromDate:[NSDate dateWithTimeIntervalSince1970:timestamp]];
    
    self.infoLabel.stringValue = [NSString stringWithFormat:@"%@ (#%ld/%ld)", timeStr, (long)(index + 1), (long)count];
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