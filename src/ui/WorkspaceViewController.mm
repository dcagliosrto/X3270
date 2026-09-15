#import "WorkspaceViewController.h"

@implementation WorkspaceViewController

- (instancetype)initWithWorkspace:(DXWorkspace *)workspace {
    if (self = [super initWithNibName:nil bundle:nil]) {
        _workspace = workspace;
    }
    return self;
}

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1024, 768)];
    self.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    
    // 1. Init the Tabs
    _tabViewController = [[NSTabViewController alloc] init];
    _tabViewController.tabStyle = NSTabViewControllerTabStyleToolbar;
    // (Riga canPanTabs rimossa definitivamente!)
    
    // 2. Init the Sidebar
    WorkspaceSidebarViewController *sidebarVC = [[WorkspaceSidebarViewController alloc] initWithWorkspace:_workspace];
    sidebarVC.delegate = self; // Diventiamo noi i gestori del doppio clic
    
    // 3. Create the horizontal divider (SplitView)
    _mainSplitController = [[NSSplitViewController alloc] init];
    
    NSSplitViewItem *sidebarItem = [NSSplitViewItem sidebarWithViewController:sidebarVC];
    sidebarItem.canCollapse = YES;
    
    NSSplitViewItem *tabsItem = [NSSplitViewItem splitViewItemWithViewController:_tabViewController];
    
    [_mainSplitController addSplitViewItem:sidebarItem];
    [_mainSplitController addSplitViewItem:tabsItem];
    
    // 4. Display the SplitViewController
    [self addChildViewController:_mainSplitController];
    _mainSplitController.view.frame = self.view.bounds;
    _mainSplitController.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.view addSubview:_mainSplitController.view];
    
    // Load any default sessions
    [self buildTabsFromWorkspace];
}


- (void)buildTabsFromWorkspace {
    // At the moment, we don't open anything automatically to avoid chaos.
    // Let the user choose what to launch from the Sidebar!
}

#pragma mark - WorkspaceSidebarDelegate

// This triggers when the user double-clicks in the left Sidebar
- (void)sidebarDidRequestConnectionToSession:(DXSessionConfig *)sessionConfig {
    NSString *tabTitle = sessionConfig.name.length > 0 ? sessionConfig.name : [NSString stringWithFormat:@"%@:%d", sessionConfig.host, sessionConfig.port];
    
    // 1. ANTI-CLONE: Check if the tab is already open. If so, select it and exit!
    for (NSUInteger i = 0; i < _tabViewController.tabViewItems.count; i++) {
        NSTabViewItem *item = _tabViewController.tabViewItems[i];
        if ([item.label isEqualToString:tabTitle]) {
            _tabViewController.selectedTabViewItemIndex = i;
            return; 
        }
    }
    
    // 2. ANTI-CLONE: If it doesn't exist, create the new connection as before
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
    
    NSTabViewItem *tabItem = [NSTabViewItem tabViewItemWithViewController:termVC];
    tabItem.label = tabTitle;
    tabItem.image = [NSImage imageWithSystemSymbolName:@"terminal" accessibilityDescription:@"Terminal"];
    
    [_tabViewController addTabViewItem:tabItem];
    _tabViewController.selectedTabViewItemIndex = _tabViewController.tabViewItems.count - 1;
}

- (void)disconnectAllSessions {
    for (NSTabViewItem *item in _tabViewController.tabViewItems) {
        if ([item.viewController isKindOfClass:[TerminalViewController class]]) {
            TerminalViewController *termVC = (TerminalViewController *)item.viewController;
            [termVC disconnectSession];
        }
    }
}

@end