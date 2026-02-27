#import <Foundation/Foundation.h>

#define DAYS_TO_SUBTRACT 1000

%hook NSDate

+ (instancetype)date {
    NSDate *realDate = %orig;
    
    NSTimeInterval offset = DAYS_TO_SUBTRACT * 24 * 60 * 60;
    
    return [realDate dateByAddingTimeInterval:-offset];
}

- (instancetype)init {
    NSDate *realDate = %orig;
    NSTimeInterval offset = DAYS_TO_SUBTRACT * 24 * 60 * 60;
    return [realDate dateByAddingTimeInterval:-offset];
}

%end
