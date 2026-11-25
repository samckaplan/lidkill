#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOMessage.h>
#include <IOKit/pwr_mgt/IOPM.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

static int last_state = -1;

static bool report_state(bool closed)
{
    if (last_state == closed)
        return true;

    last_state = closed;
    return puts(closed ? "closed" : "open") != EOF && fflush(stdout) == 0;
}

static void lid_changed(void *context, io_service_t service, natural_t message, void *argument)
{
    (void)context;
    (void)service;
    if (message == kIOMessageServiceIsTerminated ||
        (message == kIOPMMessageClamshellStateChange &&
         !report_state(((uintptr_t)argument & kClamshellStateBit) != 0)))
        CFRunLoopStop(CFRunLoopGetCurrent());
}

int main(void)
{
    int status = 1;
    io_service_t domain = IOServiceGetMatchingService(MACH_PORT_NULL,
                                                      IOServiceMatching("IOPMrootDomain"));
    if (!domain)
        return status;

    IONotificationPortRef port = IONotificationPortCreate(MACH_PORT_NULL);
    io_object_t notification = IO_OBJECT_NULL;
    if (port && IOServiceAddInterestNotification(port, domain, kIOGeneralInterest,
                                                 lid_changed, NULL, &notification) == KERN_SUCCESS) {
        CFRunLoopSourceRef source = IONotificationPortGetRunLoopSource(port);
        CFTypeRef initial = IORegistryEntryCreateCFProperty(domain, CFSTR(kAppleClamshellStateKey),
                                                            kCFAllocatorDefault, 0);
        if (source && initial && CFGetTypeID(initial) == CFBooleanGetTypeID() &&
            report_state(CFBooleanGetValue((CFBooleanRef)initial))) {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);
            CFRunLoopRun();
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);
            status = 0;
        }
        if (initial)
            CFRelease(initial);
    }
    if (notification)
        IOObjectRelease(notification);
    if (port)
        IONotificationPortDestroy(port);
    IOObjectRelease(domain);
    return status;
}
