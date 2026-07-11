#pragma once

#include <stddef.h>
#include <stdint.h>

struct OuiPrefix {
    uint8_t bytes[3];
};

struct TextPattern {
    const char* value;
};

/*
 * Wi-Fi OUI prefixes documented by colonelpanichacks/flock-you README,
 * credited there to @NitekryDPaul research, with 82:6b:f2 credited to
 * DeFlockJoplin wildcard-probe field testing.
 */
static constexpr OuiPrefix FLOCK_WIFI_OUIS[] = {
    {{0x70, 0xc9, 0x4e}}, {{0x3c, 0x91, 0x80}}, {{0xd8, 0xf3, 0xbc}},
    {{0x80, 0x30, 0x49}}, {{0xb8, 0x35, 0x32}}, {{0x14, 0x5a, 0xfc}},
    {{0x74, 0x4c, 0xa1}}, {{0x08, 0x3a, 0x88}}, {{0x9c, 0x2f, 0x9d}},
    {{0xc0, 0x35, 0x32}}, {{0x94, 0x08, 0x53}}, {{0xe4, 0xaa, 0xea}},
    {{0xf4, 0x6a, 0xdd}}, {{0xf8, 0xa2, 0xd6}}, {{0x24, 0xb2, 0xb9}},
    {{0x00, 0xf4, 0x8d}}, {{0xd0, 0x39, 0x57}}, {{0xe8, 0xd0, 0xfc}},
    {{0xe0, 0x4f, 0x43}}, {{0xb8, 0x1e, 0xa4}}, {{0x70, 0x08, 0x94}},
    {{0x58, 0x8e, 0x81}}, {{0xec, 0x1b, 0xbd}}, {{0x3c, 0x71, 0xbf}},
    {{0x58, 0x00, 0xe3}}, {{0x90, 0x35, 0xea}}, {{0x5c, 0x93, 0xa2}},
    {{0x64, 0x6e, 0x69}}, {{0x48, 0x27, 0xea}}, {{0xa4, 0xcf, 0x12}},
    {{0x82, 0x6b, 0xf2}},
    /*
     * Additional Flock Safety registered OUI documented in ReconGrunt/FlipDeFlock
     * helpers/flock_db.c as "Flock Safety's own registered OUI (GainSec)".
     */
    {{0xb4, 0x1e, 0x52}},
};

static constexpr size_t FLOCK_WIFI_OUI_COUNT =
    sizeof(FLOCK_WIFI_OUIS) / sizeof(FLOCK_WIFI_OUIS[0]);

/*
 * BLE OUI prefixes documented by NSM-Barii/flock-back src/signatures.py under
 * "FS Ext Battery devices". OUI-only BLE matches are deliberately low
 * confidence because the prefixes can belong to modules used elsewhere.
 */
static constexpr OuiPrefix FLOCK_BLE_OUIS[] = {
    {{0x58, 0x8e, 0x81}}, {{0xcc, 0xcc, 0xcc}}, {{0xec, 0x1b, 0xbd}},
    {{0x90, 0x35, 0xea}}, {{0x04, 0x0d, 0x84}}, {{0xf0, 0x82, 0xc0}},
    {{0x1c, 0x34, 0xf1}}, {{0x38, 0x5b, 0x44}}, {{0x94, 0x34, 0x69}},
    {{0xb4, 0xe3, 0xf9}},
};

static constexpr size_t FLOCK_BLE_OUI_COUNT =
    sizeof(FLOCK_BLE_OUIS) / sizeof(FLOCK_BLE_OUIS[0]);

/*
 * Wi-Fi SSID patterns documented by:
 * - NSM-Barii/flock-back src/signatures.py: flock, FS Ext Battery, Penguin,
 *   Pigvision.
 * - zmattmanz/flock-detection README: FlockOS, flocksafety, FS_.
 * - ReconGrunt/FlipDeFlock helpers/flock_db.c: test_flck.
 */
static constexpr TextPattern FLOCK_WIFI_SSID_PATTERNS[] = {
    {"flock"},
    {"FS Ext Battery"},
    {"Penguin"},
    {"Pigvision"},
    {"FlockOS"},
    {"flocksafety"},
    {"FS_"},
    {"test_flck"},
};

static constexpr size_t FLOCK_WIFI_SSID_PATTERN_COUNT =
    sizeof(FLOCK_WIFI_SSID_PATTERNS) / sizeof(FLOCK_WIFI_SSID_PATTERNS[0]);

/*
 * BLE advertisement name patterns documented by:
 * - NSM-Barii/flock-back src/signatures.py: FS Ext Battery, Penguin, Flock,
 *   Pigvision.
 * - zmattmanz/flock-detection README: FlockCam and FS-.
 */
static constexpr TextPattern FLOCK_BLE_NAME_PATTERNS[] = {
    {"FS Ext Battery"},
    {"Penguin"},
    {"Flock"},
    {"Pigvision"},
    {"FlockCam"},
    {"FS-"},
};

static constexpr size_t FLOCK_BLE_NAME_PATTERN_COUNT =
    sizeof(FLOCK_BLE_NAME_PATTERNS) / sizeof(FLOCK_BLE_NAME_PATTERNS[0]);

/*
 * BLE manufacturer company ID documented by colonelpanichacks/flock-you README
 * and zmattmanz/flock-detection README as 0x09C8 / XUNTONG.
 */
static constexpr uint16_t FLOCK_BLE_MANUFACTURER_ID = 0x09C8;

/*
 * No Flock Safety camera/accessory service UUIDs were included here because the
 * referenced UUID datasets are for Raven/SoundThinking devices, which are not
 * Flock Safety camera hardware. The classifier still supports service UUID
 * matching, but this table intentionally ships empty until a Flock-specific
 * UUID is documented.
 */
static constexpr const char* FLOCK_BLE_SERVICE_UUIDS[] = {};
static constexpr size_t FLOCK_BLE_SERVICE_UUID_COUNT = 0;
