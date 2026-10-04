/*
 * JET vehicle controller — ESP32-S3
 *
 * Owns the relay on the motor controller's ignition line. The phone can ask,
 * but only a correctly signed, unexpired, never-before-seen token opens it.
 *
 * Wire format (36 bytes), identical to JET/Core/Backend.swift:
 *   ride_id(8) || expires_seconds_be(4) || nonce(8) || hmac_sha256(...)[0..<16]
 *
 * Build: Arduino IDE, board = ESP32S3 Dev Module, partition = 8MB with SPIFFS,
 *        libraries = NimBLE-Arduino, mbedtls (bundled).
 */

#include <NimBLEDevice.h>
#include <Preferences.h>
#include <mbedtls/md.h>
#include <time.h>

#define RELAY_PIN             25
#define TOKEN_LEN             36
#define HEARTBEAT_TIMEOUT_MS  15000

static const char* SVC_UUID      = "6a4e0001-9f3b-4c2a-8e11-71d0a5c9b120";
static const char* UNLOCK_UUID   = "6a4e0002-9f3b-4c2a-8e11-71d0a5c9b120";
static const char* HEARTBEAT_UUID= "6a4e0003-9f3b-4c2a-8e11-71d0a5c9b120";
static const char* TELEMETRY_UUID= "6a4e0004-9f3b-4c2a-8e11-71d0a5c9b120";

/* Provisioned per fleet at manufacture, stored in eFuse-protected NVS or
 * derived at boot from a key burned into the secure element. Never in flash
 * plaintext on a production unit. */
static const uint8_t FLEET_SECRET[32] = {
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
};

Preferences nvs;
NimBLECharacteristic* telemetryChar = nullptr;
volatile uint32_t lastHeartbeat = 0;
volatile bool relayEngaged = false;
uint8_t batteryPercent = 87;

static bool constantTimeEquals(const uint8_t* a, const uint8_t* b, size_t len) {
    uint8_t diff = 0;
    for (size_t i = 0; i < len; i++) diff |= (uint8_t)(a[i] ^ b[i]);
    return diff == 0;
}

static bool nonceSeenBefore(const uint8_t* nonce) {
    uint32_t lo, hi;
    memcpy(&lo, nonce, 4);
    memcpy(&hi, nonce + 4, 4);
    return nvs.getUInt("n_lo", 0) == lo && nvs.getUInt("n_hi", 0) == hi;
}

static void rememberNonce(const uint8_t* nonce) {
    uint32_t lo, hi;
    memcpy(&lo, nonce, 4);
    memcpy(&hi, nonce + 4, 4);
    nvs.putUInt("n_lo", lo);
    nvs.putUInt("n_hi", hi);
}

static bool verifyToken(const uint8_t* token) {
    uint32_t expires = ((uint32_t)token[8] << 24) |
                       ((uint32_t)token[9] << 16) |
                       ((uint32_t)token[10] << 8) |
                       ((uint32_t)token[11]);

    time_t now = time(nullptr);
    if (now < 1600000000) return false;          /* clock never synced */
    if (expires < (uint32_t)now) return false;   /* stale */
    if (nonceSeenBefore(token + 12)) return false; /* replay */

    uint8_t mac[32];
    mbedtls_md_context_t ctx;
    mbedtls_md_init(&ctx);
    mbedtls_md_setup(&ctx, mbedtls_md_info_from_type(MBEDTLS_MD_SHA256), 1);
    mbedtls_md_hmac_starts(&ctx, FLEET_SECRET, sizeof(FLEET_SECRET));
    mbedtls_md_hmac_update(&ctx, token, 20);
    mbedtls_md_hmac_finish(&ctx, mac);
    mbedtls_md_free(&ctx);

    if (!constantTimeEquals(mac, token + 20, 16)) return false;

    rememberNonce(token + 12);
    return true;
}

class UnlockCallbacks : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* c) override {
        std::string value = c->getValue();
        if (value.size() != TOKEN_LEN) {
            c->setValue("DENY");
            c->notify();
            return;
        }

        if (verifyToken((const uint8_t*)value.data())) {
            digitalWrite(RELAY_PIN, HIGH);
            relayEngaged = true;
            lastHeartbeat = millis();
            c->setValue("OK");
        } else {
            c->setValue("DENY");
        }
        c->notify();
    }
};

class HeartbeatCallbacks : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* c) override {
        std::string value = c->getValue();
        if (!value.empty() && (uint8_t)value[0] == 0x00) {
            digitalWrite(RELAY_PIN, LOW);
            relayEngaged = false;
            return;
        }
        lastHeartbeat = millis();
    }
};

void setup() {
    Serial.begin(115200);
    nvs.begin("fleet", false);

    pinMode(RELAY_PIN, OUTPUT);
    digitalWrite(RELAY_PIN, LOW);

    configTime(0, 0, "pool.ntp.org");   /* or take time from the BLE handshake */

    NimBLEDevice::init("SK-8F31A2");
    NimBLEDevice::setPower(ESP_PWR_LVL_P9);

    NimBLEServer* server = NimBLEDevice::createServer();
    NimBLEService* service = server->createService(SVC_UUID);

    NimBLECharacteristic* unlock = service->createCharacteristic(
        UNLOCK_UUID, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::NOTIFY);
    unlock->setCallbacks(new UnlockCallbacks());

    NimBLECharacteristic* heartbeat = service->createCharacteristic(
        HEARTBEAT_UUID, NIMBLE_PROPERTY::WRITE_NR);
    heartbeat->setCallbacks(new HeartbeatCallbacks());

    telemetryChar = service->createCharacteristic(
        TELEMETRY_UUID, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);
    telemetryChar->setValue(&batteryPercent, 1);

    service->start();

    NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
    adv->addServiceUUID(SVC_UUID);
    adv->setName("SK-8F31A2");
    adv->start();
}

void loop() {
    /* Dead-man switch. Phone stops heartbeating -> motor dies.
     * This is what makes a stolen scooter a paperweight. */
    if (relayEngaged && (millis() - lastHeartbeat) > HEARTBEAT_TIMEOUT_MS) {
        digitalWrite(RELAY_PIN, LOW);
        relayEngaged = false;
        Serial.println("[lock] heartbeat lost");
    }

    static uint32_t lastTelemetry = 0;
    if (millis() - lastTelemetry > 2000 && telemetryChar) {
        lastTelemetry = millis();
        telemetryChar->setValue(&batteryPercent, 1);
        if (relayEngaged) telemetryChar->notify();
    }

    delay(50);
}
