#pragma once
#import <AppKit/AppKit.h>
#import "CommandDockViewController.h"
#include "TerminalModel.h"
#include "TerminalProtocol.h"
#include "EbcdicCodec.h"

NS_ASSUME_NONNULL_BEGIN

/// Reusable View Controller hosting a complete 3270/5250 session.
/// Can be embedded in a standalone window or as a tab in a Workspace.
@interface TerminalViewController : NSViewController <CommandDockDelegate>

// Session parameters
@property (nonatomic, copy, readonly) NSString *host;
@property (nonatomic, assign, readonly) uint16_t port;

// Lifecycle Callbacks
@property (nonatomic, copy, nullable) void(^onConnected)(void);
@property (nonatomic, copy, nullable) void(^onConnectError)(NSString*);
@property (nonatomic, copy, nullable) void(^onClosed)(void);

// Exposed for broadcast/OOB routing
@property (nonatomic, strong) CommandDockViewController *commandDock;

// Initializer
- (instancetype)initWithHost:(NSString*)host
                        port:(uint16_t)port
                      useSSL:(BOOL)useSSL
                  verifyCert:(BOOL)verifyCert
                    caBundle:(NSString*)caBundle
                    codePage:(x3270::CodePage)codePage
                       model:(x3270::TerminalModel)model
                    protocol:(x3270::TerminalProtocol)protocol;

/// Safely disconnects the session and stops network threads.
- (void)disconnectSession;

// Native Actions
- (IBAction)saveScreenshot:(id)sender;
- (IBAction)exportText:(id)sender;
- (IBAction)toggleVideoRecording:(id)sender;
- (IBAction)toggleTimeMachine:(id)sender;
- (void)toggleTransferSidebar:(id)sender;

@end

NS_ASSUME_NONNULL_END