#include "sclide.cpp"

#include <cctype>
#include <cstdlib>

static std::string hexColor(const char *variable, const std::string &fallback) {
    const char *value = std::getenv(variable);
    if (value == nullptr) {
        return fallback;
    }
    std::string color(value);
    bool valid = color.size() == 7 && color[0] == '#' &&
                 std::all_of(color.begin() + 1, color.end(), [](unsigned char c) { return std::isxdigit(c); });
    return valid ? color : fallback;
}

int main() {
    sclide wipe(1);
    wipe.setSclideColor(hexColor("SCLIDE_COLOR", "#00FFAA"));
    wipe.setShadeDegradingColor(hexColor("SCLIDE_FADE_COLOR", "#001A0F"));
    wipe.setSpeed(0.003);
    wipe.clean();
    return 0;
}
