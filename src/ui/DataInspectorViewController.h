#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface DataInspectorViewController : NSViewController

// Initializer with Vertical Hex and its translated string
- (instancetype)initWithRawBytes:(NSData *)bytes 
                   decodedString:(nullable NSString *)text 
                     verticalHex:(nullable NSData *)vertBytes
           verticalDecodedString:(nullable NSString *)vertText;

// Fallback to satisfy the compiler
- (instancetype)initWithRawBytes:(NSData *)bytes;

@end

NS_ASSUME_NONNULL_END