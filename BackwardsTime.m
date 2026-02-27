#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <sys/time.h>
#import <time.h>

typedef double CFAbsoluteTime;
extern CFAbsoluteTime CFAbsoluteTimeGetCurrent(void);

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

static CFAbsoluteTime (*orig_CFAbsoluteTimeGetCurrent)(void);
static CFAbsoluteTime bt_CFAbsoluteTimeGetCurrent(void) {
    if (!orig_CFAbsoluteTimeGetCurrent) {
        orig_CFAbsoluteTimeGetCurrent = (CFAbsoluteTime (*)(void))dlsym(RTLD_NEXT, "CFAbsoluteTimeGetCurrent");
    }
    CFAbsoluteTime now = orig_CFAbsoluteTimeGetCurrent ? orig_CFAbsoluteTimeGetCurrent() : 0;
    return now - BackwardsTimeOffsetSeconds();
}

static time_t (*orig_time)(time_t *);
static time_t bt_time(time_t *t) {
    if (!orig_time) {
        orig_time = (time_t (*)(time_t *))dlsym(RTLD_NEXT, "time");
    }
    time_t now = orig_time ? orig_time(NULL) : 0;
    time_t adjusted = now - (time_t)BackwardsTimeOffsetSeconds();
    if (t) {
        *t = adjusted;
    }
    return adjusted;
}

static int (*orig_gettimeofday)(struct timeval *, void *);
static int bt_gettimeofday(struct timeval *tv, void *tz) {
    if (!orig_gettimeofday) {
        orig_gettimeofday = (int (*)(struct timeval *, void *))dlsym(RTLD_NEXT, "gettimeofday");
    }
    int result = orig_gettimeofday ? orig_gettimeofday(tv, tz) : -1;
    if (result == 0 && tv) {
        long long usec = (long long)tv->tv_sec * 1000000LL + (long long)tv->tv_usec;
        usec -= (long long)(BackwardsTimeOffsetSeconds() * 1000000.0);
        tv->tv_sec = (time_t)(usec / 1000000LL);
        tv->tv_usec = (suseconds_t)(usec % 1000000LL);
        if (tv->tv_usec < 0) {
            tv->tv_usec += 1000000;
            tv->tv_sec -= 1;
        }
    }
    return result;
}

static int (*orig_clock_gettime)(clockid_t, struct timespec *);
static int bt_clock_gettime(clockid_t clk_id, struct timespec *tp) {
    if (!orig_clock_gettime) {
        orig_clock_gettime = (int (*)(clockid_t, struct timespec *))dlsym(RTLD_NEXT, "clock_gettime");
    }
    int result = orig_clock_gettime ? orig_clock_gettime(clk_id, tp) : -1;
    if (result == 0 && tp) {
        if (clk_id == CLOCK_REALTIME
#ifdef CLOCK_REALTIME_COARSE
            || clk_id == CLOCK_REALTIME_COARSE
#endif
        ) {
            long long nsec = (long long)tp->tv_sec * 1000000000LL + (long long)tp->tv_nsec;
            nsec -= (long long)(BackwardsTimeOffsetSeconds() * 1000000000.0);
            tp->tv_sec = (time_t)(nsec / 1000000000LL);
            tp->tv_nsec = (long)(nsec % 1000000000LL);
            if (tp->tv_nsec < 0) {
                tp->tv_nsec += 1000000000L;
                tp->tv_sec -= 1;
            }
        }
    }
    return result;
}

#define DYLD_INTERPOSE(_replacement, _replacee) \
    __attribute__((used)) static struct { \
        const void *replacement; \
        const void *replacee; \
    } _interpose_##_replacee __attribute__((section("__DATA,__interpose"))) = { \
        (const void *)(unsigned long)&_replacement, \
        (const void *)(unsigned long)&_replacee \
    };

DYLD_INTERPOSE(bt_CFAbsoluteTimeGetCurrent, CFAbsoluteTimeGetCurrent)
DYLD_INTERPOSE(bt_time, time)
DYLD_INTERPOSE(bt_gettimeofday, gettimeofday)
DYLD_INTERPOSE(bt_clock_gettime, clock_gettime)

__attribute__((constructor))
static void BackwardsTimeInit(void) {
    @autoreleasepool {
        NSString *markerPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"backwardstime_loaded"];
        if (![[NSFileManager defaultManager] fileExistsAtPath:markerPath]) {
            [@"1" writeToFile:markerPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }

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
