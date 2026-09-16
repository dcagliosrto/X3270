#import "WorkspaceViewController.h"

@implementation WorkspaceViewController {
    NSScrollView *_tabBarScrollView;
    NSStackView *_tabBarStackView;
    NSTextField *_emptyStateLabel;
}

- (instancetype)initWithWorkspace:(DXWorkspace *)workspace {
    if (self = [super initWithNibName:nil bundle:nil]) {
        _workspace = workspace;
    }
    return self;
}

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1024, 768)];
    self.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    
    NSView *rightContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, 768)];
    rightContainer.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    
    // --- TAB BAR CUSTOM ---
    _tabBarScrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 732, 800, 36)];
    _tabBarScrollView.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    _tabBarScrollView.hasHorizontalScroller = NO;
    _tabBarScrollView.hasVerticalScroller = NO;
    _tabBarScrollView.drawsBackground = NO;
    _tabBarScrollView.borderType = NSNoBorder;
    
    _tabBarStackView = [[NSStackView alloc] initWithFrame:_tabBarScrollView.bounds];
    _tabBarStackView.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    _tabBarStackView.spacing = 6;
    _tabBarStackView.edgeInsets = NSEdgeInsetsMake(4, 10, 4, 10);
    _tabBarStackView.alignment = NSLayoutAttributeCenterY;
    
    _tabBarScrollView.documentView = _tabBarStackView;
    [rightContainer addSubview:_tabBarScrollView];
    
    // --- CONTENUTO TERMINALE ---
    _tabView = [[NSTabView alloc] initWithFrame:NSMakeRect(0, 0, 800, 730)];
    _tabView.tabViewType = NSNoTabsNoBorder;
    _tabView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [rightContainer addSubview:_tabView];
    
    // --- ETICHETTA DI STATO VUOTO ---
    _emptyStateLabel = [NSTextField labelWithString:@"No active sessions\nDouble-click a system in the sidebar to connect"];
    _emptyStateLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    _emptyStateLabel.textColor = [NSColor tertiaryLabelColor];
    _emptyStateLabel.alignment = NSTextAlignmentCenter;
    _emptyStateLabel.frame = NSMakeRect(200, 350, 400, 40);
    _emptyStateLabel.autoresizingMask = NSViewMinXMargin | NSViewMaxXMargin | NSViewMinYMargin | NSViewMaxYMargin;
    [rightContainer addSubview:_emptyStateLabel];
    
    // Sidebar
    WorkspaceSidebarViewController *sidebarVC = [[WorkspaceSidebarViewController alloc] initWithWorkspace:_workspace];
    sidebarVC.delegate = self;
    
    NSViewController *rightVC = [[NSViewController alloc] init];
    rightVC.view = rightContainer;
    
    _mainSplitController = [[NSSplitViewController alloc] init];
    
    NSSplitViewItem *sidebarItem = [NSSplitViewItem sidebarWithViewController:sidebarVC];
    sidebarItem.canCollapse = YES;
    
    NSSplitViewItem *tabsItem = [NSSplitViewItem splitViewItemWithViewController:rightVC];
    
    [_mainSplitController addSplitViewItem:sidebarItem];
    [_mainSplitController addSplitViewItem:tabsItem];
    
    [self addChildViewController:_mainSplitController];
    _mainSplitController.view.frame = self.view.bounds;
    _mainSplitController.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.view addSubview:_mainSplitController.view];
    
    [self updateCustomTabBar];
}

#pragma mark - Custom Tab Bar Rendering

- (void)updateCustomTabBar {
    for (NSView *subview in [_tabBarStackView.arrangedSubviews copy]) {
        [_tabBarStackView removeArrangedSubview:subview];
        [subview removeFromSuperview];
    }
    
    NSUInteger tabCount = _tabView.tabViewItems.count;
    _emptyStateLabel.hidden = (tabCount > 0);
    _tabBarScrollView.hidden = (tabCount == 0);
    _tabView.hidden = (tabCount == 0);
    
    if (tabCount == 0) return;
    
    NSInteger selectedIndex = [_tabView indexOfTabViewItem:_tabView.selectedTabViewItem];
    
    for (NSUInteger i = 0; i < tabCount; i++) {
        NSTabViewItem *item = _tabView.tabViewItems[i];
        BOOL isActive = ((NSInteger)i == selectedIndex);
        
        NSView *tabView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 145, 28)];
        tabView.wantsLayer = YES;
        tabView.layer.cornerRadius = 6.0;
        tabView.layer.backgroundColor = isActive ? [NSColor controlAccentColor].CGColor : [NSColor colorWithWhite:0.2 alpha:0.4].CGColor;
        
        NSImageView *iconView = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:@"terminal" accessibilityDescription:nil]];
        iconView.frame = NSMakeRect(8, 6, 16, 16);
        iconView.contentTintColor = isActive ? [NSColor whiteColor] : [NSColor secondaryLabelColor];
        [tabView addSubview:iconView];
        
        NSButton *titleBtn = [NSButton buttonWithTitle:item.label target:self action:@selector(tabTitleClicked:)];
        titleBtn.tag = i;
        titleBtn.bordered = NO;
        titleBtn.font = [NSFont systemFontOfSize:11 weight:isActive ? NSFontWeightBold : NSFontWeightRegular];
        titleBtn.contentTintColor = isActive ? [NSColor whiteColor] : [NSColor labelColor];
        titleBtn.frame = NSMakeRect(26, 2, 90, 24);
        titleBtn.alignment = NSTextAlignmentLeft;
        [tabView addSubview:titleBtn];
        
        NSButton *closeBtn = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"xmark.circle.fill" accessibilityDescription:@"Close"] target:self action:@selector(tabCloseClicked:)];
        closeBtn.tag = i;
        closeBtn.bordered = NO;
        closeBtn.bezelStyle = NSBezelStyleInline;
        closeBtn.contentTintColor = isActive ? [NSColor whiteColor] : [NSColor colorWithWhite:0.6 alpha:1.0];
        closeBtn.frame = NSMakeRect(120, 6, 16, 16);
        [tabView addSubview:closeBtn];
        
        [_tabBarStackView addArrangedSubview:tabView];
        [tabView.widthAnchor constraintEqualToConstant:145].active = YES;
        [tabView.heightAnchor constraintEqualToConstant:28].active = YES;
    }
}

- (void)tabTitleClicked:(NSButton *)sender {
    NSInteger idx = sender.tag;
    if (idx >= 0 && idx < (NSInteger)_tabView.tabViewItems.count) {
        [_tabView selectTabViewItemAtIndex:idx];
        [self updateCustomTabBar];
    }
}

- (void)closeTabAtIndex:(NSInteger)idx {
    if (idx >= 0 && idx < (NSInteger)_tabView.tabViewItems.count) {
        NSTabViewItem *item = _tabView.tabViewItems[idx];
        if ([item.identifier isKindOfClass:[TerminalViewController class]]) {
            TerminalViewController *termVC = (TerminalViewController *)item.identifier;
            [termVC disconnectSession];
            [termVC removeFromParentViewController];
        }
        [_tabView removeTabViewItem:item];
        
        NSInteger remainingCount = (NSInteger)_tabView.tabViewItems.count;
        if (remainingCount > 0) {
            NSInteger newIdx = MIN(idx, remainingCount - 1);
            [_tabView selectTabViewItemAtIndex:newIdx];
        }
        [self updateCustomTabBar];
    }
}

- (void)tabCloseClicked:(NSButton *)sender {
    [self closeTabAtIndex:sender.tag];
}

- (void)closeActiveTab {
    NSTabViewItem *activeItem = _tabView.selectedTabViewItem;
    if (activeItem) {
        NSInteger idx = [_tabView indexOfTabViewItem:activeItem];
        [self closeTabAtIndex:idx];
    }
}

#pragma mark - WorkspaceSidebarDelegate

- (void)sidebarDidRequestConnectionToSession:(DXSessionConfig *)sessionConfig {
    NSString *tabTitle = sessionConfig.name.length > 0 ? sessionConfig.name : [NSString stringWithFormat:@"%@:%d", sessionConfig.host, sessionConfig.port];
    
    for (NSUInteger i = 0; i < _tabView.tabViewItems.count; i++) {
        NSTabViewItem *item = _tabView.tabViewItems[i];
        if ([item.label isEqualToString:tabTitle]) {
            [_tabView selectTabViewItemAtIndex:i];
            [self updateCustomTabBar];
            return;
        }
    }
    
    TerminalViewController *termVC = [[TerminalViewController alloc]
                                      initWithHost:sessionConfig.host
                                      port:sessionConfig.port
                                      useSSL:sessionConfig.useSSL
                                      verifyCert:sessionConfig.verifyCert
                                      caBundle:sessionConfig.caBundle
                                      codePage:(x3270::CodePage)sessionConfig.codePage
                                      model:(x3270::TerminalModel)sessionConfig.model
                                      protocol:(x3270::TerminalProtocol)sessionConfig.protocol];
    
    termVC.title = tabTitle;
    [self addChildViewController:termVC];
    
    NSTabViewItem *tabItem = [[NSTabViewItem alloc] initWithIdentifier:termVC];
    tabItem.label = tabTitle;
    tabItem.view = termVC.view;
    
    [_tabView addTabViewItem:tabItem];
    [_tabView selectTabViewItem:tabItem];
    
    [self updateCustomTabBar];
}

- (void)disconnectAllSessions {
    for (NSTabViewItem *item in _tabView.tabViewItems) {
        if ([item.identifier isKindOfClass:[TerminalViewController class]]) {
            TerminalViewController *termVC = (TerminalViewController *)item.identifier;
            [termVC disconnectSession];
        }
    }
}

@end