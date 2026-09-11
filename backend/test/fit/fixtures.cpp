#include "fit_encode.hpp"
#include "fit_file_id_mesg.hpp"
#include "fit_record_mesg.hpp"
#include "fit_session_mesg.hpp"
#include <fstream>
#include <stdexcept>
#include <string>

// Entirely synthetic fixtures. Never derive these from a user's FIT file.
void write_fixture(const std::string &path, const std::string &kind) {
    std::fstream file(path, std::ios::in | std::ios::out | std::ios::binary | std::ios::trunc);
    if (!file)
        throw std::runtime_error("Could not create synthetic fixture");
    fit::Encode encoder(fit::ProtocolVersion::V20);
    encoder.Open(file);
    constexpr FIT_DATE_TIME start = 1100000000;
    fit::FileIdMesg id;
    id.SetType(kind == "course" ? FIT_FILE_COURSE : FIT_FILE_ACTIVITY);
    id.SetManufacturer(FIT_MANUFACTURER_DEVELOPMENT);
    id.SetTimeCreated(start);
    encoder.Write(id);

    const int count = kind == "limit" ? 100001 : 3;
    for (int i = 0; i < count; ++i) {
        fit::RecordMesg record;
        if (kind != "missing-record-time")
            record.SetTimestamp(kind == "relative-time" ? 10 + i
                                : (kind == "duplicate-time" || kind == "running-duplicate-time")
                                    ? start
                                    : start + i * 10);
        if (i == 0) {
            record.SetCadence(80);
            record.SetFractionalCadence(0.5);
            record.SetAltitude(-10);
            record.SetPositionLat(kind == "running-invalid-position"
                                      ? 1610612736
                                      : 536870912); // synthetic 45 degrees
            record.SetPositionLong(-1073741824);    // synthetic -90 degrees
            record.SetHeartRate(120);
            record.SetPower(0); // Zero is a real observation.
            record.SetSpeed(5.25);
            record.SetDistance(0);
        } else if (i == 1) {
            // Explicit invalid sentinels must remain absent.
            record.SetHeartRate(FIT_UINT8_INVALID);
            record.SetPower(FIT_UINT16_INVALID);
            record.SetDistance(52.5);
            record.SetFractionalCadence(0.5); // no integer cadence: still missing
            record.SetAltitude(100);
            record.SetEnhancedAltitude(120); // enhanced takes precedence
            record.SetPositionLat(FIT_SINT32_INVALID);
            record.SetPositionLong(0); // no complete coordinate pair
        } else {
            record.SetCadence256(90.25);
            record.SetHeartRate(130);
            record.SetPower(210);
            record.SetSpeed(5.0);
            record.SetEnhancedSpeed(6.25); // Enhanced value takes precedence.
            record.SetDistance(115.0);
        }
        encoder.Write(record);
    }

    fit::SessionMesg session;
    session.SetSport(kind.find("running") == 0 ? FIT_SPORT_RUNNING
                     : kind == "swimming"      ? FIT_SPORT_SWIMMING
                                               : FIT_SPORT_CYCLING);
    if (kind != "missing-session-time")
        session.SetStartTime(start);
    session.SetTimestamp(kind == "outside-range" ? start + 10 : start + 30);
    if (kind != "missing-summary") {
        session.SetTotalElapsedTime(30.0);
        session.SetTotalTimerTime(20.0);
        session.SetTotalDistance(115.0);
    }
    if (kind != "no-session")
        encoder.Write(session);
    if (kind == "multisport") {
        session.SetSport(FIT_SPORT_RUNNING);
        encoder.Write(session);
    }
    if (!encoder.Close())
        throw std::runtime_error("Could not finish synthetic fixture");
}

int main(int argc, char **argv) {
    if (argc != 2)
        return 2;
    for (const auto &kind :
         {"cycling", "running", "swimming", "running-duplicate-time", "running-invalid-position",
          "course", "missing-record-time", "missing-session-time", "relative-time",
          "duplicate-time", "outside-range", "missing-summary", "no-session", "multisport",
          "limit"})
        write_fixture(std::string(argv[1]) + "/" + kind + ".fit", kind);
}
