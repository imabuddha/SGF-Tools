// The CFPlugIn glue that makes this bundle a Spotlight importer (an .mdimporter).
//
// Spotlight's worker process loads the bundle, asks the factory named in Info.plist for an
// importer, and calls GetMetadataForURL for each SGF file. The work is done in Swift, by
// SGFToolsImporterGetMetadata in Importer.swift. This follows Apple's template for
// MDImporterURLInterfaceStruct importers.

#include <stdlib.h>
#include <string.h>

#include <CoreFoundation/CoreFoundation.h>
#include <CoreFoundation/CFPlugInCOM.h>
#include <CoreServices/CoreServices.h>

// The factory's UUID, as in Info.plist (CFPlugInFactories and CFPlugInTypes).
#define FACTORY_ID "DA206B34-DC8F-4465-BEC9-DD4F20309542"

// Implemented in Importer.swift.
extern Boolean SGFToolsImporterGetMetadata(CFMutableDictionaryRef attributes, CFURLRef url);

static Boolean GetMetadataForURL(void *thisInterface, CFMutableDictionaryRef attributes,
                                 CFStringRef contentTypeUTI, CFURLRef urlForFile) {
    return SGFToolsImporterGetMetadata(attributes, urlForFile);
}

// MARK: - COM plumbing

typedef struct {
    MDImporterURLInterfaceStruct *conduitInterface;
    CFUUIDRef factoryID;
    UInt32 refCount;
} Importer;

static HRESULT QueryInterface(void *thisInstance, REFIID iid, LPVOID *ppv);
static ULONG AddRef(void *thisInstance);
static ULONG Release(void *thisInstance);

static MDImporterURLInterfaceStruct interfaceTable = {
    NULL, QueryInterface, AddRef, Release, GetMetadataForURL
};

static Importer *AllocImporter(CFUUIDRef factoryID) {
    Importer *instance = calloc(1, sizeof(Importer));
    if (instance == NULL) return NULL;
    instance->conduitInterface = malloc(sizeof(MDImporterURLInterfaceStruct));
    if (instance->conduitInterface == NULL) {
        free(instance);
        return NULL;
    }
    memcpy(instance->conduitInterface, &interfaceTable, sizeof(MDImporterURLInterfaceStruct));
    instance->factoryID = CFRetain(factoryID);
    CFPlugInAddInstanceForFactory(factoryID);
    instance->refCount = 1;
    return instance;
}

static void DeallocImporter(Importer *instance) {
    CFUUIDRef factoryID = instance->factoryID;
    free(instance->conduitInterface);
    free(instance);
    if (factoryID) {
        CFPlugInRemoveInstanceForFactory(factoryID);
        CFRelease(factoryID);
    }
}

static HRESULT QueryInterface(void *thisInstance, REFIID iid, LPVOID *ppv) {
    CFUUIDRef interfaceID = CFUUIDCreateFromUUIDBytes(kCFAllocatorDefault, iid);
    HRESULT result = E_NOINTERFACE;
    *ppv = NULL;
    if (CFEqual(interfaceID, kMDImporterURLInterfaceID) || CFEqual(interfaceID, IUnknownUUID)) {
        AddRef(thisInstance);
        *ppv = thisInstance;
        result = S_OK;
    }
    CFRelease(interfaceID);
    return result;
}

static ULONG AddRef(void *thisInstance) {
    return ++((Importer *)thisInstance)->refCount;
}

static ULONG Release(void *thisInstance) {
    Importer *instance = thisInstance;
    instance->refCount -= 1;
    if (instance->refCount == 0) {
        DeallocImporter(instance);
        return 0;
    }
    return instance->refCount;
}

// The factory named in Info.plist.
void *MetadataImporterPluginFactory(CFAllocatorRef allocator, CFUUIDRef typeID) {
    if (!CFEqual(typeID, kMDImporterTypeID)) return NULL;
    CFUUIDRef factoryID = CFUUIDCreateFromString(kCFAllocatorDefault, CFSTR(FACTORY_ID));
    Importer *importer = AllocImporter(factoryID);
    CFRelease(factoryID);
    return importer;
}
