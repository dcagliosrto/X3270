#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@protocol CommandDockDelegate <NSObject>
// In-Band ISPF Command Injection (optional targetGroup: nil = current session only, @"A", @"B", etc. = broadcast to group)
- (void)commandDockDidRequestISPFCommand:(NSString *)command targetGroup:(nullable NSString *)group;

// Out-of-Band Execution
- (void)commandDockDidRequestOutOdBandCommand:(NSString *)command targetGroup:(nullable NSString *)group;
@end

@interface CommandDockViewController : NSViewController
@property (nonatomic, weak) id<CommandDockDelegate> delegate;
@property (nonatomic, copy, nullable) NSString *linkGroup; // Current window's assigned group
@end

NS_ASSUME_NONNULL_END