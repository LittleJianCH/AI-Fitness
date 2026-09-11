#ifndef AI_FITNESS_FIT_ADAPTER_H
#define AI_FITNESS_FIT_ADAPTER_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct af_fit_result af_fit_result;
enum af_fit_status {
    AF_FIT_OK = 0,
    AF_FIT_INVALID = 1,
    AF_FIT_UNSUPPORTED = 2,
    AF_FIT_MISSING_TIME = 3,
    AF_FIT_LIMIT = 4,
    AF_FIT_INTERNAL = 5
};

/* Input is borrowed only for this call. Maximum 16 MiB, 100,000 records and
 * 250,000 messages. Requires one complete activity file with one cycling or running session.
 * On failure *out is NULL. On success the caller owns *out and must call free.
 * All exceptions are contained. No error text or source data is logged.
 */
int af_fit_decode(const uint8_t *bytes, size_t length, af_fit_result **out);
void af_fit_free(af_fit_result *result);

/* Borrowed arrays valid until free; never modify. Six summary doubles; nine doubles per record.
 * Summary: start, end (FIT UTC seconds), elapsed seconds, timer seconds, metres, sport (1=cycling,
 * 2=running). Records: timestamp (FIT UTC seconds), bpm, watts, metres/second, metres, cadence
 * (cycles/min including fraction), altitude (metres), latitude/longitude (signed FIT semicircles).
 * Prefer cadence256, otherwise cadence + fraction. Optional absent/invalid SDK fields are quiet
 * NaN; required times are valid. SDK getters have already applied FIT scale/offset. Count is number
 * of rows. Getter precondition: non-NULL successful result. No allocation or exceptions.
 */
const double *af_fit_summary(const af_fit_result *result);
size_t af_fit_record_count(const af_fit_result *result);
const double *af_fit_records(const af_fit_result *result);

#ifdef __cplusplus
}
#endif
#endif
