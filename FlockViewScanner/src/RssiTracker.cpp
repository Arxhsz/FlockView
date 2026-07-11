#include "RssiTracker.h"

RssiTracker::RssiTracker(float alpha) : _alpha(alpha) {}

void RssiTracker::setAlpha(float alpha) {
    if (alpha < 0.05f) {
        _alpha = 0.05f;
    } else if (alpha > 1.0f) {
        _alpha = 1.0f;
    } else {
        _alpha = alpha;
    }
}

float RssiTracker::alpha() const {
    return _alpha;
}

void RssiTracker::update(RssiState& state, int8_t newestRssi) const {
    const float previousSmoothed = state.smoothedRssi;
    state.currentRssi = newestRssi;

    if (!state.initialized) {
        state.initialized = true;
        state.peakRssi = newestRssi;
        state.minimumRssi = newestRssi;
        state.smoothedRssi = static_cast<float>(newestRssi);
        state.averageRssi = static_cast<float>(newestRssi);
        state.observationCount = 1;
        state.trend = RssiTrend::Stable;
        return;
    }

    state.observationCount += 1;
    if (newestRssi > state.peakRssi) {
        state.peakRssi = newestRssi;
    }
    if (newestRssi < state.minimumRssi) {
        state.minimumRssi = newestRssi;
    }

    state.smoothedRssi = (_alpha * static_cast<float>(newestRssi)) +
        ((1.0f - _alpha) * state.smoothedRssi);
    state.averageRssi += (static_cast<float>(newestRssi) - state.averageRssi) /
        static_cast<float>(state.observationCount);

    const float delta = state.smoothedRssi - previousSmoothed;
    if (delta >= 1.5f) {
        state.trend = RssiTrend::Rising;
    } else if (delta <= -1.5f) {
        state.trend = RssiTrend::Falling;
    } else {
        state.trend = RssiTrend::Stable;
    }
}

Proximity RssiTracker::proximityFor(int8_t rssi, int8_t closeThreshold, int8_t mediumThreshold) const {
    if (rssi >= closeThreshold) {
        return Proximity::Close;
    }
    if (rssi >= mediumThreshold) {
        return Proximity::Medium;
    }
    return Proximity::Far;
}
