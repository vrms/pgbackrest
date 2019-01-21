/***********************************************************************************************************************************
Time Management
***********************************************************************************************************************************/
#ifndef COMMON_TIME_H
#define COMMON_TIME_H

#include <stdint.h>

/***********************************************************************************************************************************
Time types
***********************************************************************************************************************************/
typedef uint64_t TimeMSec;

/***********************************************************************************************************************************
Constants describing number of sub-units in an interval
***********************************************************************************************************************************/
#define MSEC_PER_SEC                                                ((TimeMSec)1000)

/***********************************************************************************************************************************
Functions
***********************************************************************************************************************************/
void sleepMSec(TimeMSec sleepMSec);
TimeMSec timeMSec(void);

/***********************************************************************************************************************************
Macros for function logging
***********************************************************************************************************************************/
#define FUNCTION_LOG_TIME_MSEC_TYPE                                                                                                \
    TimeMSec
#define FUNCTION_LOG_TIME_MSEC_FORMAT(value, buffer, bufferSize)                                                                   \
    cvtUInt64ToZ(value, buffer, bufferSize)

#endif
