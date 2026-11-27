#include <ApplicationServices/ApplicationServices.h>
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOMessage.h>
#include <IOKit/pwr_mgt/IOPM.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

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

/* Prints how many non-built-in displays are connected (mirrored ones included). */
static int print_external_displays(void)
{
    CGDirectDisplayID ids[16];
    uint32_t count = 0;
    int external = 0;
    if (CGGetOnlineDisplayList(16, ids, &count) != kCGErrorSuccess)
        return 1;
    for (uint32_t i = 0; i < count; i++)
        if (!CGDisplayIsBuiltin(ids[i]))
            external++;
    printf("%d\n", external);
    return 0;
}

int main(int argc, char **argv)
{
    int status = 1;
    if (argc > 1 && strcmp(argv[1], "--displays") == 0)
        return print_external_displays();
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
