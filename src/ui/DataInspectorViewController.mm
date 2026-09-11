#import "DataInspectorViewController.h"

@implementation DataInspectorViewController {
    NSData *_rawBytes;
    NSString *_decodedString;
    NSData *_verticalHex;
    NSString *_verticalDecodedString;
    NSTextView *_textView;
}

- (instancetype)initWithRawBytes:(NSData *)bytes decodedString:(NSString *)text verticalHex:(NSData *)vertBytes verticalDecodedString:(NSString *)vertText {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _rawBytes = bytes;
        _decodedString = text;
        _verticalHex = vertBytes;
        _verticalDecodedString = vertText;
    }
    return self;
}

- (instancetype)initWithRawBytes:(NSData *)bytes {
    return [self initWithRawBytes:bytes decodedString:nil verticalHex:nil verticalDecodedString:nil];
}

- (void)loadView {
    // Standardized window size
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 420, 380)];
    
    // Wrapped in a ScrollView to elegantly handle all 3 engines
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSInsetRect(self.view.bounds, 10, 10)];
    scrollView.hasVerticalScroller = YES;
    scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    
    _textView = [[NSTextView alloc] initWithFrame:scrollView.bounds];
    _textView.autoresizingMask = NSViewWidthSizable;
    _textView.drawsBackground = NO;
    _textView.editable = NO;
    _textView.selectable = YES;
    _textView.font = [NSFont userFixedPitchFontOfSize:11.0];
    
    scrollView.documentView = _textView;
    [self.view addSubview:scrollView];
    
    [self decodeData];
}

- (void)decodeData {
    if (_rawBytes.length == 0) return;
    NSMutableString *outStr = [NSMutableString string];
    
    // --- 1. HORIZONTAL SCREEN TEXT (For IPCS and standard Hex strings) ---
    NSData *parsedHex = [self parseHexString:_decodedString];
    if (parsedHex.length > 0) {
        [outStr appendString:@"=== PARSED SCREEN TEXT (HEX) ===\n"];
        [outStr appendString:[self analyzeBytes:(const uint8_t *)parsedHex.bytes length:parsedHex.length]];
        [outStr appendString:@"\n"];
    }
    
    // --- 2. ISPF VERTICAL HEX ---
    if (_verticalHex.length > 0) {
        [outStr appendString:@"=== ISPF VERTICAL HEX ===\n"];
        [outStr appendString:[self analyzeBytes:(const uint8_t *)_verticalHex.bytes length:_verticalHex.length]];
        [outStr appendFormat:@"EBCDIC : %@\n\n", _verticalDecodedString ?: @""];
    }
    
    // --- 3. RAW TERMINAL BUFFER ---
    [outStr appendString:@"=== RAW TERMINAL BUFFER ===\n"];
    [outStr appendString:[self analyzeBytes:(const uint8_t *)_rawBytes.bytes length:_rawBytes.length]];
    [outStr appendFormat:@"EBCDIC : %@\n", _decodedString ?: @""];
    
    _textView.string = outStr;
}

// Unified analysis engine
- (NSString *)analyzeBytes:(const uint8_t *)bytes length:(NSUInteger)len {
    NSMutableString *outStr = [NSMutableString string];
    NSMutableString *hexStr = [NSMutableString string];
    NSMutableString *asciiStr = [NSMutableString string];
    NSMutableString *binStr = [NSMutableString string];
    
    for (NSUInteger i = 0; i < len; i++) {
        [hexStr appendFormat:@"%02X ", bytes[i]];
        if (bytes[i] >= 0x20 && bytes[i] <= 0x7E) {
            [asciiStr appendFormat:@"%c", bytes[i]];
        } else {
            [asciiStr appendString:@"."];
        }
    }
    
    NSUInteger binLen = MIN(len, 4UL);
    for (NSUInteger i = 0; i < binLen; i++) {
        uint8_t b = bytes[i];
        for (int j = 7; j >= 0; j--) {
            [binStr appendFormat:@"%d", (b >> j) & 1];
        }
        if (i < binLen - 1) [binStr appendString:@" "];
    }
    
    [outStr appendFormat:@"HEX    : %@\n", hexStr];
    [outStr appendFormat:@"BIN    : %@\n", binStr];
    [outStr appendFormat:@"ASCII  : %@\n", asciiStr];
    [outStr appendString:@"----------------------------------------\n"];
    
    if (len >= 2) {
        int16_t hw = (int16_t)(((uint32_t)bytes[0] << 8) | (uint32_t)bytes[1]);
        [outStr appendFormat:@"COMP-H : %d\n", hw];
    }
    if (len >= 4) {
        int32_t fw = (int32_t)(((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16) | 
                               ((uint32_t)bytes[2] << 8)  | (uint32_t)bytes[3]);
        [outStr appendFormat:@"COMP-F : %d\n", fw];
    }
    if (len >= 8) {
        uint64_t dw = 0;
        for (int i = 0; i < 8; i++) {
            dw = (dw << 8) | (uint64_t)bytes[i];
        }
        [outStr appendFormat:@"COMP-D : %lld\n", (long long)dw];
        
        uint64_t micros = dw >> 12;
        uint64_t epochOffset = 2208988800ULL * 1000000ULL;
        if (micros > epochOffset) {
            NSTimeInterval unixTime = (NSTimeInterval)(micros - epochOffset) / 1000000.0;
            NSDate *date = [NSDate dateWithTimeIntervalSince1970:unixTime];
            NSDateFormatter *df = [[NSDateFormatter alloc] init];
            df.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
            df.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
            [outStr appendFormat:@"STCK   : %@\n", [df stringFromDate:date]];
        }
    }
    
    NSUInteger comp3Len = MIN(len, 16UL);
    NSString *comp3 = [self decodeComp3:bytes length:comp3Len];
    [outStr appendFormat:@"COMP-3 : %@\n", comp3];
    
    return outStr;
}

// Parses visual hex strings from the screen (Restored)
- (NSData *)parseHexString:(NSString *)str {
    if (!str) return nil;
    NSString *cleanStr = [[str stringByReplacingOccurrencesOfString:@" " withString:@""] uppercaseString];
    NSCharacterSet *hexChars = [NSCharacterSet characterSetWithCharactersInString:@"0123456789ABCDEF"];
    NSMutableString *validHex = [NSMutableString string];
    
    for (NSUInteger i = 0; i < cleanStr.length; i++) {
        unichar c = [cleanStr characterAtIndex:i];
        if ([hexChars characterIsMember:c]) {
            [validHex appendFormat:@"%C", c];
        } else {
            break; 
        }
    }
    
    if (validHex.length % 2 != 0) {
        validHex = [[validHex substringToIndex:validHex.length - 1] mutableCopy];
    }
    if (validHex.length == 0) return nil;
    
    NSMutableData *data = [NSMutableData dataWithCapacity:validHex.length / 2];
    for (NSUInteger i = 0; i < validHex.length; i += 2) {
        NSString *byteStr = [validHex substringWithRange:NSMakeRange(i, 2)];
        NSScanner *scanner = [NSScanner scannerWithString:byteStr];
        unsigned int byteValue;
        [scanner scanHexInt:&byteValue];
        uint8_t b = (uint8_t)byteValue;
        [data appendBytes:&b length:1];
    }
    return data;
}

- (NSString *)decodeComp3:(const uint8_t *)bytes length:(NSUInteger)len {
    NSMutableString *numStr = [NSMutableString string];
    BOOL valid = YES;
    for (NSUInteger i = 0; i < len; i++) {
        uint8_t b = bytes[i];
        uint8_t high = (b & 0xF0) >> 4;
        uint8_t low  = (b & 0x0F);
        if (i < len - 1) {
            if (high > 9 || low > 9) { valid = NO; break; }
            [numStr appendFormat:@"%d%d", high, low];
        } else {
            if (high > 9) { valid = NO; break; }
            [numStr appendFormat:@"%d", high];
            if (low == 0xC || low == 0xA || low == 0xE || low == 0xF) {
                [numStr insertString:@"+" atIndex:0];
            } else if (low == 0xD || low == 0xB) {
                [numStr insertString:@"-" atIndex:0];
            } else {
                valid = NO;
            }
        }
    }
    return valid ? numStr : @"Invalid";
}
@end