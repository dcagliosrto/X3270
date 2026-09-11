#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@protocol CommandDockDelegate <NSObject>
// ISPF Screen Navigation
- (void)commandDockDidRequestISPFCommand:(NSString *)command;

// Out-of-Band Execution (SSH / zOSMF)
- (void)commandDockDidRequestOutOdBandCommand:(NSString *)command;
@end

@interface CommandDockViewController : NSViewController
@property (nonatomic, weak) id<CommandDockDelegate> delegate;
@end

NS_ASSUME_NONNULL_END