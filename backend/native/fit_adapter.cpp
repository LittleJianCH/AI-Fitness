#include "fit_adapter.h"

#include <array>
#include <limits>
#include <memory>
#include <sstream>
#include <vector>

#include "fit_decode.hpp"
#include "fit_file_id_mesg.hpp"
#include "fit_record_mesg.hpp"
#include "fit_session_mesg.hpp"

struct af_fit_result {
    std::array<double, 6> summary{};
    std::vector<double> records;
};

namespace {
constexpr size_t max_bytes = 16 * 1024 * 1024;
constexpr size_t max_records = 100000;
constexpr size_t max_messages = 250000;
constexpr double missing = std::numeric_limits<double>::quiet_NaN();

// This is a local control-flow exception, never exposed across the C ABI.
struct Rejected {
    af_fit_status status;
};

double utc_time(bool valid, FIT_DATE_TIME time) {
    if (!valid || time < FIT_DATE_TIME_MIN || time == FIT_DATE_TIME_INVALID)
        throw Rejected{AF_FIT_MISSING_TIME};
    return time;
}

class Listener final : public fit::MesgListener {
  public:
    af_fit_result result;
    size_t sessions = 0;
    size_t files = 0;
    size_t messages = 0;

    void OnMesg(fit::Mesg &message) override {
        if (++messages > max_messages)
            throw Rejected{AF_FIT_LIMIT};
        switch (message.GetNum()) {
        case FIT_MESG_NUM_FILE_ID: {
            fit::FileIdMesg file(message);
            if (++files != 1 || !file.IsTypeValid() || file.GetType() != FIT_FILE_ACTIVITY)
                throw Rejected{AF_FIT_UNSUPPORTED};
            break;
        }
        case FIT_MESG_NUM_SESSION: {
            fit::SessionMesg session(message);
            if (++sessions != 1 || !session.IsSportValid() ||
                (session.GetSport() != FIT_SPORT_CYCLING &&
                 session.GetSport() != FIT_SPORT_RUNNING))
                throw Rejected{AF_FIT_UNSUPPORTED};
            result.summary = {
                utc_time(session.IsStartTimeValid(), session.GetStartTime()),
                utc_time(session.IsTimestampValid(), session.GetTimestamp()),
                session.IsTotalElapsedTimeValid() ? session.GetTotalElapsedTime() : missing,
                session.IsTotalTimerTimeValid() ? session.GetTotalTimerTime() : missing,
                session.IsTotalDistanceValid() ? session.GetTotalDistance() : missing,
                session.GetSport() == FIT_SPORT_CYCLING ? 1.0 : 2.0};
            break;
        }
        case FIT_MESG_NUM_RECORD: {
            if (result.records.size() / 9 >= max_records)
                throw Rejected{AF_FIT_LIMIT};
            fit::RecordMesg record(message);
            result.records.insert(
                result.records.end(),
                {utc_time(record.IsTimestampValid(), record.GetTimestamp()),
                 record.IsHeartRateValid() ? record.GetHeartRate() : missing,
                 record.IsPowerValid() ? record.GetPower() : missing,
                 record.IsEnhancedSpeedValid() ? record.GetEnhancedSpeed()
                 : record.IsSpeedValid()       ? record.GetSpeed()
                                               : missing,
                 record.IsDistanceValid() ? record.GetDistance() : missing,
                 record.IsCadence256Valid() ? record.GetCadence256()
                 : record.IsCadenceValid()
                     ? record.GetCadence() +
                           (record.IsFractionalCadenceValid() ? record.GetFractionalCadence() : 0.0)
                     : missing,
                 record.IsEnhancedAltitudeValid() ? record.GetEnhancedAltitude()
                 : record.IsAltitudeValid()       ? record.GetAltitude()
                                                  : missing,
                 record.IsPositionLatValid() ? record.GetPositionLat() : missing,
                 record.IsPositionLongValid() ? record.GetPositionLong() : missing});
            break;
        }
        default:
            break;
        }
    }
};
} // namespace

extern "C" int af_fit_decode(const uint8_t *bytes, size_t length, af_fit_result **out) {
    if (!out)
        return AF_FIT_INVALID;
    *out = nullptr;
    if (length > max_bytes)
        return AF_FIT_LIMIT;
    if (!bytes || length < 14)
        return AF_FIT_INVALID;
    // Reject trailing bytes/concatenated files and unknown header layouts.
    const size_t header = bytes[0];
    const uint32_t data = uint32_t(bytes[4]) | (uint32_t(bytes[5]) << 8) |
                          (uint32_t(bytes[6]) << 16) | (uint32_t(bytes[7]) << 24);
    if ((header != 12 && header != 14) || uint64_t(header) + data + 2 != length)
        return AF_FIT_INVALID;
    try {
        std::istringstream stream(std::string(reinterpret_cast<const char *>(bytes), length),
                                  std::ios::in | std::ios::binary);
        fit::Decode integrity;
        if (!integrity.CheckIntegrity(stream))
            return AF_FIT_INVALID;
        stream.clear();
        stream.seekg(0);
        fit::Decode decode;
        Listener listener;
        if (!decode.Read(stream, listener))
            return AF_FIT_INVALID;
        if (listener.files != 1 || listener.sessions != 1)
            return AF_FIT_UNSUPPORTED;
        auto result = std::make_unique<af_fit_result>(std::move(listener.result));
        *out = result.release();
        return AF_FIT_OK;
    } catch (const Rejected &failure) {
        return failure.status;
    } catch (const std::bad_alloc &) {
        return AF_FIT_LIMIT;
    } catch (const fit::RuntimeException &) {
        return AF_FIT_INVALID;
    } catch (...) {
        return AF_FIT_INTERNAL;
    }
}

extern "C" void af_fit_free(af_fit_result *result) { delete result; }
extern "C" const double *af_fit_summary(const af_fit_result *result) {
    return result->summary.data();
}
extern "C" size_t af_fit_record_count(const af_fit_result *result) {
    return result->records.size() / 9;
}
extern "C" const double *af_fit_records(const af_fit_result *result) {
    return result->records.data();
}
