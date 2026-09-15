#pragma once
#import <AppKit/AppKit.h>
#import "TerminalViewController.h"
#import "WorkspaceSidebarViewController.h"
#import "../utils/WorkspaceManager.h"

NS_ASSUME_NONNULL_BEGIN

@interface WorkspaceViewController : NSViewController <WorkspaceSidebarDelegate>

@property (nonatomic, strong) DXWorkspace *workspace;
@property (nonatomic, strong) NSTabViewController *tabViewController;
@property (nonatomic, strong) NSSplitViewController *mainSplitController;

- (instancetype)initWithWorkspace:(DXWorkspace *)workspace;
- (void)disconnectAllSessions;

@end

NS_ASSUME_NONNULL_END