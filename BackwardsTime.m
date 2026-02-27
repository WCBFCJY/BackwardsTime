#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <fcntl.h>
#import <limits.h>
#import <stdint.h>
#import <stdlib.h>
#import <sys/time.h>
#import <time.h>
#import <unistd.h>

typedef double CFAbsoluteTime;
extern CFAbsoluteTime CFAbsoluteTimeGetCurrent(void);
extern time_t time(time_t *);
extern int gettimeofday(struct timeval *, void *);
extern int clock_gettime(clockid_t, struct timespec *);
extern uint64_t clock_gettime_nsec_np(clockid_t);

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

static const char *BackwardsTimeTmpDir(void) {
    const char *tmp = getenv("TMPDIR");
    if (tmp && tmp[0] != '\0') {
        return tmp;
    }
    return "/tmp/";
}

static void BackwardsTimeTouchFile(const char *fileName) {
    char path[PATH_MAX];
    const char *tmp = BackwardsTimeTmpDir();
    int written = snprintf(path, sizeof(path), "%s%s", tmp, fileName);
    if (written <= 0 || (size_t)written >= sizeof(path)) {
        return;
    }

    int fd = open(path, O_CREAT | O_WRONLY, 0644);
    if (fd < 0) {
        return;
    }
    (void)write(fd, "1", 1);
    close(fd);
}

static void BackwardsTimeTouchOnce(volatile int *flag, const char *fileName) {
    if (__sync_bool_compare_and_swap(flag, 0, 1)) {
        BackwardsTimeTouchFile(fileName);
    }
}

static CFAbsoluteTime (*orig_CFAbsoluteTimeGetCurrent)(void);
static CFAbsoluteTime bt_CFAbsoluteTimeGetCurrent(void) {
    static volatile int touched = 0;
    BackwardsTimeTouchOnce(&touched, "backwardstime_hit_CFAbsoluteTimeGetCurrent");
    if (!orig_CFAbsoluteTimeGetCurrent) {
        orig_CFAbsoluteTimeGetCurrent = (CFAbsoluteTime (*)(void))dlsym(RTLD_NEXT, "CFAbsoluteTimeGetCurrent");
    }
    CFAbsoluteTime now = orig_CFAbsoluteTimeGetCurrent ? orig_CFAbsoluteTimeGetCurrent() : 0;
    return now - BackwardsTimeOffsetSeconds();
}

static time_t (*orig_time)(time_t *);
static time_t bt_time(time_t *t) {
    static volatile int touched = 0;
    BackwardsTimeTouchOnce(&touched, "backwardstime_hit_time");
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
    static volatile int touched = 0;
    BackwardsTimeTouchOnce(&touched, "backwardstime_hit_gettimeofday");
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
    static volatile int touched = 0;
    BackwardsTimeTouchOnce(&touched, "backwardstime_hit_clock_gettime");
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

static uint64_t (*orig_clock_gettime_nsec_np)(clockid_t);
static uint64_t bt_clock_gettime_nsec_np(clockid_t clk_id) {
    static volatile int touched = 0;
    BackwardsTimeTouchOnce(&touched, "backwardstime_hit_clock_gettime_nsec_np");
    if (!orig_clock_gettime_nsec_np) {
        orig_clock_gettime_nsec_np = (uint64_t (*)(clockid_t))dlsym(RTLD_NEXT, "clock_gettime_nsec_np");
    }
    uint64_t nsec = orig_clock_gettime_nsec_np ? orig_clock_gettime_nsec_np(clk_id) : 0;
    if (clk_id == CLOCK_REALTIME
#ifdef CLOCK_REALTIME_COARSE
        || clk_id == CLOCK_REALTIME_COARSE
#endif
    ) {
        uint64_t delta = (uint64_t)(BackwardsTimeOffsetSeconds() * 1000000000.0);
        if (nsec > delta) {
            return nsec - delta;
        }
        return 0;
    }
    return nsec;
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
DYLD_INTERPOSE(bt_clock_gettime_nsec_np, clock_gettime_nsec_np)

__attribute__((constructor))
static void BackwardsTimeInit(void) {
    @autoreleasepool {
        BackwardsTimeTouchFile("backwardstime_loaded");

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
