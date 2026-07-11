#pragma once

#include "ScannerTypes.h"

class RssiTracker {
public:
    explicit RssiTracker(float alpha = DEFAULT_RSSI_ALPHA);

    void setAlpha(float alpha);
    float alpha() const;

    void update(RssiState& state, int8_t newestRssi) const;
    Proximity proximityFor(int8_t rssi, int8_t closeThreshold, int8_t mediumThreshold) const;

private:
    float _alpha;
};
