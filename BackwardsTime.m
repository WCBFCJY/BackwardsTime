#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static NSTimeInterval BackwardsTimeOffsetSeconds(void) {
    return 1000.0 * 24.0 * 60.0 * 60.0;
}

static NSDate *(*orig_NSDate_date)(id self, SEL _cmd);
static NSDate *bt_NSDate_date(id self, SEL _cmd) {
    NSDate *realDate = orig_NSDate_date(self, _cmd);
    return [realDate dateByAddingTimeInterval:-BackwardsTimeOffsetSeconds()];
}

static NSDate *(*orig_NSDate_now)(id self, SEL _cmd);
static NSDate *bt_NSDate_now(id self, SEL _cmd) {
    NSDate *realDate = orig_NSDate_now(self, _cmd);
    return [realDate dateByAddingTimeInterval:-BackwardsTimeOffsetSeconds()];
}

static void HookClassMethod(Class cls, SEL selector, IMP replacement, IMP *originalOut) {
    Method method = class_getClassMethod(cls, selector);
    if (!method) {
        return;
    }

    IMP previous = method_setImplementation(method, replacement);
    if (originalOut) {
        *originalOut = previous;
    }
}

__attribute__((constructor))
static void BackwardsTimeInit(void) {
    @autoreleasepool {
        Class nsDateClass = objc_getClass("NSDate");
        if (!nsDateClass) {
            return;
        }

        HookClassMethod(nsDateClass, @selector(date), (IMP)bt_NSDate_date, (IMP *)&orig_NSDate_date);

        Class meta = object_getClass((id)nsDateClass);
        if (meta && class_respondsToSelector(meta, @selector(now))) {
            HookClassMethod(nsDateClass, @selector(now), (IMP)bt_NSDate_now, (IMP *)&orig_NSDate_now);
        }
    }
}
