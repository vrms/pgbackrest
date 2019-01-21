/***********************************************************************************************************************************
Storage Info
***********************************************************************************************************************************/
#ifndef STORAGE_INFO_H
#define STORAGE_INFO_H

#include <sys/types.h>

/***********************************************************************************************************************************
Storage type
***********************************************************************************************************************************/
typedef enum
{
    storageTypeFile,
    storageTypePath,
    storageTypeLink,
} StorageType;

/***********************************************************************************************************************************
Object type
***********************************************************************************************************************************/
typedef struct StorageInfo
{
    bool exists;                                                    // Does the path/file/link exist?
    StorageType type;                                               // Type file/path/link)
    size_t size;                                                    // Size (path/link is 0)
    mode_t mode;                                                    // Mode of path/file/link
} StorageInfo;

/***********************************************************************************************************************************
Macros for function logging
***********************************************************************************************************************************/
#define FUNCTION_LOG_STORAGE_INFO_TYPE                                                                                             \
    StorageInfo
#define FUNCTION_LOG_STORAGE_INFO_FORMAT(value, buffer, bufferSize)                                                                \
    objToLog(&value, "StorageInfo", buffer, bufferSize)

#endif
