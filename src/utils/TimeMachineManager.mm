#import "TimeMachineManager.h"

static const NSUInteger kMaxSnapshots = 50;

@implementation ScreenSnapshot
@end

@interface TimeMachineManager ()
@property (nonatomic, strong) NSMutableArray<ScreenSnapshot *> *history;
@end

@implementation TimeMachineManager

+ (instancetype)sharedManager {
    static TimeMachineManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[TimeMachineManager alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _history = [NSMutableArray array];
    }
    return self;
}

- (void)captureSnapshotWithRows:(int)rows
                           cols:(int)cols
                          chars:(const unichar *)chars
                     attributes:(const uint32_t *)attrs
                      cursorRow:(int)cursorRow
                      cursorCol:(int)cursorCol {
    if (!chars || rows <= 0 || cols <= 0) return;

    // Evita duplicati se il buffer non è cambiato rispetto all'ultimo snapshot
    NSData *charData = [NSData dataWithBytes:chars length:sizeof(unichar) * rows * cols];
    if (self.history.count > 0) {
        ScreenSnapshot *last = self.history.lastObject;
        if ([last.characterBuffer isEqualToData:charData]) {
            return; // Nessun cambio schermo visibile
        }
    }

    ScreenSnapshot *snap = [[ScreenSnapshot alloc] init];
    snap.timestamp = [[NSDate date] timeIntervalSince1970];
    snap.rows = rows;
    snap.cols = cols;
    snap.characterBuffer = charData;
    snap.attributeBuffer = [NSData dataWithBytes:attrs length:sizeof(uint32_t) * rows * cols];
    snap.cursorRow = cursorRow;
    snap.cursorCol = cursorCol;

    [self.history addObject:snap];
    if (self.history.count > kMaxSnapshots) {
        [self.history removeObjectAtIndex:0];
    }
}

- (NSArray<ScreenSnapshot *> *)allSnapshots {
    return [self.history copy];
}

- (ScreenSnapshot *)snapshotAtIndex:(NSInteger)index {
    if (index < 0 || (NSUInteger)index >= self.history.count) return nil;
    return self.history[index];
}

- (void)clearHistory {
    [self.history removeAllObjects];
}

- (NSArray<NSNumber *> *)compareSnapshot:(ScreenSnapshot *)snapA withSnapshot:(ScreenSnapshot *)snapB {
    if (!snapA || !snapB || snapA.rows != snapB.rows || snapA.cols != snapB.cols) {
        return @[];
    }

    NSUInteger totalCells = snapA.rows * snapA.cols;
    NSMutableArray<NSNumber *> *diffMap = [NSMutableArray arrayWithCapacity:totalCells];

    const unichar *bufA = (const unichar *)snapA.characterBuffer.bytes;
    const unichar *bufB = (const unichar *)snapB.characterBuffer.bytes;

    for (NSUInteger i = 0; i < totalCells; i++) {
        unichar cA = bufA[i];
        unichar cB = bufB[i];

        BOOL isAEmpty = (cA == 0 || cA == ' ' || cA == 0x20 || cA == 0x40);
        BOOL isBEmpty = (cB == 0 || cB == ' ' || cB == 0x20 || cB == 0x40);

        if (isAEmpty && isBEmpty) {
            [diffMap addObject:@(CellDiffUnchanged)];
        } else if (cA == cB) {
            [diffMap addObject:@(CellDiffUnchanged)];
        } else {
            [diffMap addObject:@(CellDiffModified)];
        }
    }

    return [diffMap copy];
}

@end