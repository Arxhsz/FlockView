#pragma once

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

/*
    FlockOuiDatabase.h

    Separate database of community-observed MAC prefixes associated with
    Flock Safety infrastructure.

    Accuracy warning:
    - These prefixes are not guaranteed to be Flock-exclusive.
    - Many may belong to component/module vendors used in unrelated products.
    - Treat OUI-only matches as low-confidence evidence.
    - Require corroboration from probe behavior, SSID/name patterns,
      BLE manufacturer data, service UUIDs, or IE fingerprints.

    Verified source basis:
    - colonelpanichacks/flock-you
    - datasets/NitekryDPaul_wifi_ouis.md
    - README "OUI target list"
*/

namespace FlockOuiDatabase {

enum class EvidenceTier : uint8_t {
    CommunityObserved = 1,
    Corroborated = 2,
    StronglyCorroborated = 3
};

enum class RadioScope : uint8_t {
    Wifi = 1,
    Ble = 2,
    WifiAndBle = 3
};

struct MacPrefix {
    uint8_t octets[3];
    const char* text;
    EvidenceTier tier;
    RadioScope scope;
    const char* source;
    const char* notes;
};

static constexpr MacPrefix kPrefixes[] = {
    {{0x70,0xC9,0x4E},"70:C9:4E",EvidenceTier::CommunityObserved,RadioScope::WifiAndBle,"NitekryDPaul/flock-you","Observed in Flock-related infrastructure; not exclusive."},
    {{0x3C,0x91,0x80},"3C:91:80",EvidenceTier::CommunityObserved,RadioScope::WifiAndBle,"NitekryDPaul/flock-you","Observed in Flock-related infrastructure; not exclusive."},
    {{0xD8,0xF3,0xBC},"D8:F3:BC",EvidenceTier::CommunityObserved,RadioScope::WifiAndBle,"NitekryDPaul/flock-you","Observed in Flock-related infrastructure; not exclusive."},
    {{0x80,0x30,0x49},"80:30:49",EvidenceTier::CommunityObserved,RadioScope::WifiAndBle,"NitekryDPaul/flock-you","Observed in Flock-related infrastructure; not exclusive."},
    {{0xB8,0x35,0x32},"B8:35:32",EvidenceTier::CommunityObserved,RadioScope::WifiAndBle,"NitekryDPaul/flock-you","Observed in Flock-related infrastructure; not exclusive."},
    {{0x14,0x5A,0xFC},"14:5A:FC",EvidenceTier::CommunityObserved,RadioScope::WifiAndBle,"NitekryDPaul/flock-you","Observed in Flock-related infrastructure; not exclusive."},
    {{0x74,0x4C,0xA1},"74:4C:A1",EvidenceTier::CommunityObserved,RadioScope::WifiAndBle,"NitekryDPaul/flock-you","Observed in Flock-related infrastructure; not exclusive."},
    {{0x08,0x3A,0x88},"08:3A:88",EvidenceTier::CommunityObserved,RadioScope::WifiAndBle,"NitekryDPaul/flock-you","Known false-positive risk; module vendor is broadly used."},
    {{0x9C,0x2F,0x9D},"9C:2F:9D",EvidenceTier::CommunityObserved,RadioScope::WifiAndBle,"NitekryDPaul/flock-you","Observed in Flock-related infrastructure; not exclusive."},
    {{0xC0,0x35,0x32},"C0:35:32",EvidenceTier::CommunityObserved,RadioScope::WifiAndBle,"NitekryDPaul/flock-you","Observed in Flock-related infrastructure; not exclusive."},
    {{0x94,0x08,0x53},"94:08:53",EvidenceTier::CommunityObserved,RadioScope::WifiAndBle,"NitekryDPaul/flock-you","Observed in Flock-related infrastructure; not exclusive."},
    {{0xE4,0xAA,0xEA},"E4:AA:EA",EvidenceTier::CommunityObserved,RadioScope::WifiAndBle,"NitekryDPaul/flock-you","Observed in Flock-related infrastructure; not exclusive."},
    {{0xF4,0x6A,0xDD},"F4:6A:DD",EvidenceTier::CommunityObserved,RadioScope::WifiAndBle,"NitekryDPaul/flock-you","Observed in Flock-related infrastructure; not exclusive."},
    {{0xF8,0xA2,0xD6},"F8:A2:D6",EvidenceTier::CommunityObserved,RadioScope::WifiAndBle,"NitekryDPaul/flock-you","Observed in Flock-related infrastructure; not exclusive."},
    {{0x24,0xB2,0xB9},"24:B2:B9",EvidenceTier::CommunityObserved,RadioScope::WifiAndBle,"NitekryDPaul/flock-you","Observed in Flock-related infrastructure; not exclusive."},
    {{0x00,0xF4,0x8D},"00:F4:8D",EvidenceTier::CommunityObserved,RadioScope::WifiAndBle,"NitekryDPaul/flock-you","Observed in Flock-related infrastructure; not exclusive."},
    {{0xD0,0x39,0x57},"D0:39:57",EvidenceTier::CommunityObserved,RadioScope::WifiAndBle,"NitekryDPaul/flock-you","Observed in Flock-related infrastructure; not exclusive."},
    {{0xE8,0xD0,0xFC},"E8:D0:FC",EvidenceTier::CommunityObserved,RadioScope::WifiAndBle,"NitekryDPaul/flock-you","Observed in Flock-related infrastructure; not exclusive."},
    {{0xE0,0x4F,0x43},"E0:4F:43",EvidenceTier::CommunityObserved,RadioScope::WifiAndBle,"NitekryDPaul/flock-you","Observed in Flock-related infrastructure; not exclusive."},
    {{0xB8,0x1E,0xA4},"B8:1E:A4",EvidenceTier::CommunityObserved,RadioScope::WifiAndBle,"NitekryDPaul/flock-you","Observed in Flock-related infrastructure; not exclusive."},
    {{0x70,0x08,0x94},"70:08:94",EvidenceTier::CommunityObserved,RadioScope::WifiAndBle,"NitekryDPaul/flock-you","Observed in Flock-related infrastructure; not exclusive."},
    {{0x58,0x8E,0x81},"58:8E:81",EvidenceTier::CommunityObserved,RadioScope::WifiAndBle,"NitekryDPaul/flock-you","Observed in Flock-related infrastructure; not exclusive."},
    {{0xEC,0x1B,0xBD},"EC:1B:BD",EvidenceTier::CommunityObserved,RadioScope::WifiAndBle,"NitekryDPaul/flock-you","Observed in Flock-related infrastructure; not exclusive."},
    {{0x3C,0x71,0xBF},"3C:71:BF",EvidenceTier::CommunityObserved,RadioScope::WifiAndBle,"NitekryDPaul/flock-you","Observed in Flock-related infrastructure; not exclusive."},
    {{0x58,0x00,0xE3},"58:00:E3",EvidenceTier::CommunityObserved,RadioScope::WifiAndBle,"NitekryDPaul/flock-you","Observed in Flock-related infrastructure; not exclusive."},
    {{0x90,0x35,0xEA},"90:35:EA",EvidenceTier::CommunityObserved,RadioScope::WifiAndBle,"NitekryDPaul/flock-you","Observed in Flock-related infrastructure; not exclusive."},
    {{0x5C,0x93,0xA2},"5C:93:A2",EvidenceTier::CommunityObserved,RadioScope::WifiAndBle,"NitekryDPaul/flock-you","Observed in Flock-related infrastructure; not exclusive."},
    {{0x64,0x6E,0x69},"64:6E:69",EvidenceTier::CommunityObserved,RadioScope::WifiAndBle,"NitekryDPaul/flock-you","Observed in Flock-related infrastructure; not exclusive."},
    {{0x48,0x27,0xEA},"48:27:EA",EvidenceTier::CommunityObserved,RadioScope::WifiAndBle,"NitekryDPaul/flock-you","Observed in Flock-related infrastructure; not exclusive."},
    {{0xA4,0xCF,0x12},"A4:CF:12",EvidenceTier::CommunityObserved,RadioScope::WifiAndBle,"NitekryDPaul/flock-you","Observed in Flock-related infrastructure; not exclusive."},
    {{0x82,0x6B,0xF2},"82:6B:F2",EvidenceTier::Corroborated,RadioScope::Wifi,"DeFlockJoplin/flock-you","31st prefix added from DeFlock Joplin observations."}
};

static constexpr size_t kPrefixCount = sizeof(kPrefixes) / sizeof(kPrefixes[0]);

struct MatchResult {
    bool matched;
    size_t index;
    const MacPrefix* record;
};

inline bool prefixEquals(const uint8_t mac[6], const MacPrefix& prefix) {
    return mac != nullptr &&
           mac[0] == prefix.octets[0] &&
           mac[1] == prefix.octets[1] &&
           mac[2] == prefix.octets[2];
}

inline MatchResult match(const uint8_t mac[6]) {
    if (mac == nullptr) return {false, 0, nullptr};
    for (size_t i = 0; i < kPrefixCount; ++i) {
        if (prefixEquals(mac, kPrefixes[i])) return {true, i, &kPrefixes[i]};
    }
    return {false, 0, nullptr};
}

inline bool matches(const uint8_t mac[6]) {
    return match(mac).matched;
}

inline const char* matchedPrefixText(const uint8_t mac[6]) {
    const MatchResult result = match(mac);
    return result.matched ? result.record->text : nullptr;
}

inline uint8_t ouiOnlyConfidenceScore(const uint8_t mac[6]) {
    const MatchResult result = match(mac);
    if (!result.matched) return 0;
    switch (result.record->tier) {
        case EvidenceTier::StronglyCorroborated: return 35;
        case EvidenceTier::Corroborated: return 30;
        case EvidenceTier::CommunityObserved:
        default: return 20;
    }
}

inline bool parseMac(const char* text, uint8_t outMac[6]) {
    if (text == nullptr || outMac == nullptr) return false;

    unsigned int values[6] = {};
    int parsed = sscanf(text, "%2x:%2x:%2x:%2x:%2x:%2x",
                        &values[0], &values[1], &values[2],
                        &values[3], &values[4], &values[5]);
    if (parsed != 6) {
        parsed = sscanf(text, "%2x-%2x-%2x-%2x-%2x-%2x",
                        &values[0], &values[1], &values[2],
                        &values[3], &values[4], &values[5]);
    }
    if (parsed != 6) return false;

    for (size_t i = 0; i < 6; ++i) {
        if (values[i] > 0xFFU) return false;
        outMac[i] = static_cast<uint8_t>(values[i]);
    }
    return true;
}

inline bool matchesText(const char* macText) {
    uint8_t mac[6] = {};
    return parseMac(macText, mac) && matches(mac);
}

/*
    Recommended classifier use:

        auto result = FlockOuiDatabase::match(mac);
        if (result.matched) {
            score += FlockOuiDatabase::ouiOnlyConfidenceScore(mac);
            methods.add(DetectionMethod::KnownWifiOui);
        }

    Then add independent evidence:
      - wildcard probe request
      - empty SSID information element
      - documented IE fingerprint
      - BLE name pattern
      - manufacturer ID
      - service UUID

    Never promote OUI-only to HIGH or CONFIRMED.
*/

} // namespace FlockOuiDatabase
