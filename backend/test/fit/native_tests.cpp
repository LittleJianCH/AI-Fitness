#include "fit_adapter.h"
#include <cassert>
#include <cmath>
#include <fstream>
#include <iterator>
#include <vector>

int main(int argc, char **argv) {
    assert(argc == 2);
    std::ifstream file(argv[1], std::ios::binary);
    assert(file);
    const std::vector<uint8_t> bytes{std::istreambuf_iterator<char>(file), {}};
    assert(!bytes.empty());
    af_fit_result *result = nullptr;
    assert(af_fit_decode(nullptr, 0, &result) == AF_FIT_INVALID && result == nullptr);
    assert(af_fit_decode(bytes.data(), bytes.size(), nullptr) == AF_FIT_INVALID);
    assert(af_fit_decode(bytes.data(), 16 * 1024 * 1024 + 1, &result) == AF_FIT_LIMIT);
    af_fit_free(nullptr);
    for (int i = 0; i < 1000; ++i) {
        assert(af_fit_decode(bytes.data(), bytes.size(), &result) == AF_FIT_OK);
        assert(result != nullptr);
        assert(af_fit_record_count(result) == 3);
        assert(af_fit_summary(result)[2] == 30);
        const double *rows = af_fit_records(result);
        assert(rows[2] == 0);
        assert(std::isnan(rows[10]) && std::isnan(rows[11]) && std::isnan(rows[12]));
        af_fit_free(result);
        result = nullptr;
        const auto truncated = static_cast<size_t>(i) % bytes.size();
        assert(af_fit_decode(bytes.data(), truncated, &result) == AF_FIT_INVALID);
        assert(result == nullptr);
    }
}
