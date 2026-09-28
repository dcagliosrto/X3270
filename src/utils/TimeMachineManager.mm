#import "TimeMachineManager.h"

static const NSUInteger kMaxSnapshots = 50;

@implementation ScreenSnapshot
@end

@interface TimeMachineManager ()
@property (nonatomic, strong) NSMutableArray<ScreenSnapshot *> *history;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *internalPinnedIndices; // Internal set for managing pinned indices
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
        _internalPinnedIndices = [NSMutableSet set];
        _baselinePinIndex = -1;
    }
    return self;
}

// Baseline Pin Management
- (void)setBaselinePinIndex:(NSInteger)index {
    _baselinePinIndex = index;
}

// Read-only property for external access
- (NSSet<NSNumber *> *)pinnedIndices {
    return [_internalPinnedIndices copy];
}

- (void)captureSnapshotWithRows:(int)rows
                           cols:(int)cols
                          chars:(const unichar *)chars
                     attributes:(const uint32_t *)attrs
                      cursorRow:(int)cursorRow
                      cursorCol:(int)cursorCol {
    if (!chars || rows <= 0 || cols <= 0) return;

    // Avoid duplicates if the buffer hasn't changed compared to the last snapshot
    NSData *charData = [NSData dataWithBytes:chars length:sizeof(unichar) * rows * cols];
    if (self.history.count > 0) {
        ScreenSnapshot *last = self.history.lastObject;
        if ([last.characterBuffer isEqualToData:charData]) {
            return; // No visible screen change
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
    
    // Handle the maximum limit: discard the oldest and "shift" the PINs to keep them consistent
    if (self.history.count > kMaxSnapshots) {
        [self.history removeObjectAtIndex:0];
        
        NSMutableSet<NSNumber *> *shiftedPins = [NSMutableSet set];
        for (NSNumber *pin in self.internalPinnedIndices) {
            NSInteger val = pin.integerValue;
            if (val > 0) {
                [shiftedPins addObject:@(val - 1)]; // Shift to the left. If it was 0, it disappears along with the  snapshot.
            }
        }
        self.internalPinnedIndices = shiftedPins;
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
    [self.internalPinnedIndices removeAllObjects];
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

#pragma mark - Pinned Bookmarks Engine

- (void)togglePinAtIndex:(NSInteger)index {
    NSNumber *idx = @(index);
    if ([self.internalPinnedIndices containsObject:idx]) {
        [self.internalPinnedIndices removeObject:idx];
    } else {
        [self.internalPinnedIndices addObject:idx];
    }
}

- (BOOL)isPinnedAtIndex:(NSInteger)index {
    return [self.internalPinnedIndices containsObject:@(index)];
}

- (NSInteger)nextPinnedIndexAfter:(NSInteger)index {
    // Sort the indices to find the next one in chronological order
    NSArray *sortedPins = [[self.internalPinnedIndices allObjects] sortedArrayUsingSelector:@selector(compare:)];
    for (NSNumber *pin in sortedPins) {
        if (pin.integerValue > index) return pin.integerValue;
    }
    return -1; // Reached the end of the pins
}

- (NSInteger)prevPinnedIndexBefore:(NSInteger)index {
    // Sort and iterate in reverse order
    NSArray *sortedPins = [[self.internalPinnedIndices allObjects] sortedArrayUsingSelector:@selector(compare:)];
    for (NSNumber *pin in [sortedPins reverseObjectEnumerator]) {
        if (pin.integerValue < index) return pin.integerValue;
    }
    return -1; // Reached the beginning of the pins
}

@end