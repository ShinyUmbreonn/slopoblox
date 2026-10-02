/* Video memory size for Roblox. Roblox's macOS client reads IOFBMemorySize
 * from the display's IOKit registry entry to size its graphics budget.
 * Darling has no such entry, so Roblox assumed 64 MB of video memory, which
 * turned off MSAA (antialiasing) and other quality features whatever the
 * graphics level. Answer it with the host GPU's real VRAM, passed by the
 * launcher as MACOBLOX_VRAM_BYTES (read from sysfs), defaulting to 4 GB. */

typedef const void *CFTypeRef;
typedef const void *CFStringRef;
typedef const void *CFAllocatorRef;
typedef unsigned int io_registry_entry_t;
typedef unsigned int IOOptionBits;

extern char *getenv(const char *);
extern unsigned char CFStringGetCString(CFStringRef, char *, long, unsigned int);
extern CFTypeRef CFNumberCreate(CFAllocatorRef, long, const void *);
extern int snprintf(char *, unsigned long, const char *, ...);
extern long write(int, const void *, unsigned long);
__attribute__((weak_import)) extern unsigned int CGDisplayIOServicePort(unsigned int);
__attribute__((weak_import)) extern const void *IOServiceMatching(const char *);
__attribute__((weak_import)) extern CFTypeRef IORegistryEntryCreateCFProperty(io_registry_entry_t, CFStringRef,
                                                                               CFAllocatorRef, IOOptionBits);

#define DYLD_INTERPOSE(_replacement, _replacee) \
    __attribute__((used)) static struct { const void *replacement; const void *replacee; } \
    _interpose_##_replacee __attribute__((section("__DATA,__interpose"))) = \
        {(const void *)(unsigned long)&_replacement, (const void *)(unsigned long)&_replacee};

static long long vram_bytes(void) {
    const char *text = getenv("MACOBLOX_VRAM_BYTES");
    long long value = 0;
    for (const char *c = text; c && *c >= '0' && *c <= '9'; c++)
        value = value * 10 + (*c - '0');
    return value >= (64LL << 20) ? value : (4LL << 30);
}

static int key_is(CFStringRef key, const char *expected) {
    char text[64];
    if (!key || !CFStringGetCString(key, text, sizeof text, 0x08000100 /* UTF-8 */))
        return 0;
    for (int i = 0;; i++) {
        if (text[i] != expected[i])
            return 0;
        if (!text[i])
            return 1;
    }
}

static int tracing(void) {
    const char *text = getenv("MACOBLOX_TRACE_IOKIT");
    return text && text[0];
}

static void trace(const char *what, const char *detail, unsigned long value) {
    if (!tracing())
        return;
    char line[200];
    int length = snprintf(line, sizeof line, "[MacOBlox IOKit] %s %s -> 0x%lx\n", what, detail ? detail : "", value);
    if (length > 0) write(2, line, (unsigned long)length);
}

static CFTypeRef macoblox_IORegistryEntryCreateCFProperty(io_registry_entry_t entry, CFStringRef key,
                                                          CFAllocatorRef allocator, IOOptionBits options) {
    if (tracing()) {
        char text[64] = "?";
        if (key) CFStringGetCString(key, text, sizeof text, 0x08000100);
        trace("IORegistryEntryCreateCFProperty", text, entry);
    }
    if (key_is(key, "IOFBMemorySize")) {
        long long bytes = vram_bytes();
        return CFNumberCreate(allocator, 4 /* kCFNumberSInt64Type */, &bytes);
    }
    return IORegistryEntryCreateCFProperty(entry, key, allocator, options);
}
DYLD_INTERPOSE(macoblox_IORegistryEntryCreateCFProperty, IORegistryEntryCreateCFProperty)

/* Physical screen size. Darling's CGDisplayScreenSize returns the display's
 * pixel size as millimetres (a two-metre-wide screen), and 0x0 for a
 * display ID that is not one of its screens: its IDs are 1-based positions
 * in NSDisplay's screen list, not the CGDirectDisplayIDs Roblox may derive
 * elsewhere. Roblox scales its interface by it, and a zero size sent a
 * Fedora KDE user's client into an endless updateSurfaceLuaApp loop until
 * the stack overflowed. Answer the size at 96 DPI of the display's bounds,
 * of the main display for an unknown ID, or of 1920x1080 before AppKit has
 * screens. Unknown IDs get the main display's bounds too. */
typedef struct { double x, y, width, height; } macoblox_rect; /* CGRect */
typedef struct { double width, height; } macoblox_size;       /* CGSize */
__attribute__((weak_import)) extern macoblox_rect CGDisplayBounds(unsigned int);
__attribute__((weak_import)) extern macoblox_size CGDisplayScreenSize(unsigned int);
__attribute__((weak_import)) extern unsigned int CGMainDisplayID(void);

static macoblox_rect macoblox_CGDisplayBounds(unsigned int display) {
    macoblox_rect bounds = CGDisplayBounds(display);
    if (bounds.width <= 0 || bounds.height <= 0) {
        unsigned int main_display = CGMainDisplayID();
        if (main_display && main_display != display)
            bounds = CGDisplayBounds(main_display);
        static int reported;
        if (!reported++)
            write(2, "[MacOBlox] CGDisplayBounds: unknown display, using the main display\n", 68);
    }
    return bounds;
}
DYLD_INTERPOSE(macoblox_CGDisplayBounds, CGDisplayBounds)

static macoblox_size macoblox_CGDisplayScreenSize(unsigned int display) {
    macoblox_rect bounds = macoblox_CGDisplayBounds(display);
    double width = bounds.width > 0 ? bounds.width : 1920;
    double height = bounds.height > 0 ? bounds.height : 1080;
    macoblox_size size = {width * 25.4 / 96.0, height * 25.4 / 96.0};
    return size;
}
DYLD_INTERPOSE(macoblox_CGDisplayScreenSize, CGDisplayScreenSize)

/* Darling's CGDisplayIOServicePort returns 0, and Roblox then never asks for
 * IOFBMemorySize. Hand out a stand-in entry; the property hook above answers
 * IOFBMemorySize for it, other IOKit calls on it simply fail. */
#define FAKE_DISPLAY_SERVICE 0x4d4f4231u
static unsigned int macoblox_CGDisplayIOServicePort(unsigned int display) {
    unsigned int port = CGDisplayIOServicePort(display);
    if (!port)
        port = FAKE_DISPLAY_SERVICE;
    trace("CGDisplayIOServicePort", 0, port);
    return port;
}
DYLD_INTERPOSE(macoblox_CGDisplayIOServicePort, CGDisplayIOServicePort)

static const void *macoblox_IOServiceMatching(const char *name) {
    const void *result = IOServiceMatching(name);
    trace("IOServiceMatching", name, (unsigned long)result);
    return result;
}
DYLD_INTERPOSE(macoblox_IOServiceMatching, IOServiceMatching)

/* Roblox may read the display's properties as one dictionary, or go to the
 * parent (framebuffer) entry first; cover both for the stand-in entry. */
typedef void *CFMutableDictionaryRef;
extern CFMutableDictionaryRef CFDictionaryCreateMutable(CFAllocatorRef, long, const void *, const void *);
extern void CFDictionarySetValue(CFMutableDictionaryRef, const void *, const void *);
extern void CFRelease(CFTypeRef);
extern CFStringRef CFStringCreateWithCString(CFAllocatorRef, const char *, unsigned int);
extern const char kCFTypeDictionaryKeyCallBacks[];
extern const char kCFTypeDictionaryValueCallBacks[];
__attribute__((weak_import)) extern int IORegistryEntryCreateCFProperties(io_registry_entry_t, CFMutableDictionaryRef *,
                                                                         CFAllocatorRef, IOOptionBits);
__attribute__((weak_import)) extern int IORegistryEntryGetParentEntry(io_registry_entry_t, const char *,
                                                                     io_registry_entry_t *);

static int macoblox_IORegistryEntryCreateCFProperties(io_registry_entry_t entry, CFMutableDictionaryRef *properties,
                                                      CFAllocatorRef allocator, IOOptionBits options) {
    trace("IORegistryEntryCreateCFProperties", 0, entry);
    if (entry == FAKE_DISPLAY_SERVICE && properties) {
        CFMutableDictionaryRef dictionary = CFDictionaryCreateMutable(
            allocator, 0, kCFTypeDictionaryKeyCallBacks, kCFTypeDictionaryValueCallBacks);
        long long bytes = vram_bytes();
        CFTypeRef number = CFNumberCreate(allocator, 4 /* kCFNumberSInt64Type */, &bytes);
        CFStringRef key = CFStringCreateWithCString(allocator, "IOFBMemorySize", 0x08000100);
        CFDictionarySetValue(dictionary, key, number);
        CFRelease(key);
        CFRelease(number);
        *properties = dictionary;
        return 0;
    }
    return IORegistryEntryCreateCFProperties(entry, properties, allocator, options);
}
DYLD_INTERPOSE(macoblox_IORegistryEntryCreateCFProperties, IORegistryEntryCreateCFProperties)

static int macoblox_IORegistryEntryGetParentEntry(io_registry_entry_t entry, const char *plane,
                                                  io_registry_entry_t *parent) {
    trace("IORegistryEntryGetParentEntry", plane, entry);
    if (entry == FAKE_DISPLAY_SERVICE && parent) {
        *parent = FAKE_DISPLAY_SERVICE;
        return 0;
    }
    return IORegistryEntryGetParentEntry(entry, plane, parent);
}
DYLD_INTERPOSE(macoblox_IORegistryEntryGetParentEntry, IORegistryEntryGetParentEntry)

/* Log multisample buffer creation (a handful of calls, at resize) to see
 * whether Roblox enables MSAA and with how many samples. */
extern void glRenderbufferStorageMultisample(unsigned int, int, unsigned int, int, int);
static void macoblox_glRenderbufferStorageMultisample(unsigned int target, int samples, unsigned int format,
                                                      int width, int height) {
    char line[160];
    int length = snprintf(line, sizeof line,
                          "[MacOBlox GL] multisample renderbuffer samples=%d format=0x%x %dx%d\n",
                          samples, format, width, height);
    if (length > 0) write(2, line, (unsigned long)length);
    glRenderbufferStorageMultisample(target, samples, format, width, height);
}
DYLD_INTERPOSE(macoblox_glRenderbufferStorageMultisample, glRenderbufferStorageMultisample)

/* Metal off: Roblox renders with OpenGL here.
 *
 * Roblox prefers Metal and only falls back to OpenGL when it finds no Metal
 * device. With the Darling release this is tested with, on most GPUs,
 * Darling's Metal (Indium on Vulkan) returns none, and that is why OpenGL is
 * what runs. Other Darling builds and drivers do return a device (a source
 * build on Mesa: the log starts with "Validation layer requested but not
 * available"); Roblox then starts its Metal renderer, which Darling cannot
 * carry: an exception from the device ("-[MTLDev..."), then a crash in
 * -[RBXWindow setTitlebarAppearsTransparent:]. So the answer is always "no
 * device". MACOBLOX_METAL=1 keeps Darling's answer (the Vulkan work). */
typedef struct objc_object *macoblox_id;
extern macoblox_id objc_msgSend(macoblox_id, void *, ...);
extern void *sel_registerName(const char *);
extern void *objc_getClass(const char *);
__attribute__((weak_import)) extern macoblox_id MTLCreateSystemDefaultDevice(void);
__attribute__((weak_import)) extern macoblox_id MTLCopyAllDevices(void);

static int metal_allowed(void) {
    const char *value = getenv("MACOBLOX_METAL");
    return value && value[0] == '1';
}

static void metal_off_once(void) {
    static int said;
    if (!__sync_bool_compare_and_swap(&said, 0, 1))
        return;
    write(2, "[MacOBlox] Metal device hidden, Roblox renders with OpenGL\n", 59);
}

static macoblox_id macoblox_MTLCreateSystemDefaultDevice(void) {
    if (metal_allowed())
        return MTLCreateSystemDefaultDevice();
    metal_off_once();
    return 0;
}
DYLD_INTERPOSE(macoblox_MTLCreateSystemDefaultDevice, MTLCreateSystemDefaultDevice)

static macoblox_id macoblox_MTLCopyAllDevices(void) {
    if (metal_allowed())
        return MTLCopyAllDevices();
    metal_off_once();
    /* An empty array the caller owns, as the Copy in the name promises. */
    macoblox_id array = ((macoblox_id (*)(void *, void *))objc_msgSend)(objc_getClass("NSArray"), sel_registerName("alloc"));
    return ((macoblox_id (*)(macoblox_id, void *))objc_msgSend)(array, sel_registerName("init"));
}
DYLD_INTERPOSE(macoblox_MTLCopyAllDevices, MTLCopyAllDevices)
