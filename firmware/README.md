# IsdaSafe firmware: pairing and uploads

`isdasafe_pairing.h` makes each device belong to one account. Each device
is provisioned with its own secret and a QR label (see "QR labels" below);
the owner pairs it by scanning the label in the app, and from then on the
database files its readings under that account only (see
`supabase/migrations/20261009111614_device_qr_claim.sql`).

## Setup

1. Copy `isdasafe_pairing.h` into the same folder as your `.ino` sketch.
2. In `isdasafe_pairing.h`, set `SUPABASE_ANON_KEY` to the `SUPABASE_ANON_KEY`
   value from the app's `.env`.
3. Make the edits below, then flash the board.

Keep WiFi passwords and keys out of git.

## Sketch edits

**Includes.** Add this after the other `#include` lines:

```cpp
#include "isdasafe_pairing.h"
```

**`setup()`.** Call `pairingBegin()` right after `Serial.begin(115200);`:

```cpp
  Serial.begin(115200);
  pairingBegin();
```

**`handleAppSerialCommand()`.** The header passes serial commands it doesn't
know on to the sketch. Define it (it can be empty):

```cpp
void handleAppSerialCommand(const String &line) {
  // The sketch's own serial commands, if any.
}
```

**`delayPollingDht()`.** Listen for the website's commands while waiting.
Replace the whole function with:

```cpp
void delayPollingDht(unsigned long ms) {
  unsigned long start = millis();
  while (millis() - start < ms) {
    pollSerialCommands();
#if ENABLE_DHT_CONTINUOUS
    if (pollDht()) updateLcd();
#endif
    delay(20);
  }
}
```

**`runReadingCycle()`.** Add the device ID to the summary line, and upload
with the token instead of `sendReadingsToServer()`:

```cpp
  Serial.printf(
    "DO=%.2f mg/L  pH=%.2f  NH3=%.2f mg/L  WaterT=%.1fC  AirT=%.1fC  Hum=%.0f%%  ID=%s\n",
    readings.dissolvedOxygen_mgL, readings.ph, readings.ammonia_mgL,
    readings.waterTemp_C, readings.ambientTemp_C, readings.humidity_pct,
    deviceId().c_str()
  );
  uploadReading(readings.dissolvedOxygen_mgL, readings.ph, readings.ammonia_mgL,
                readings.waterTemp_C, readings.ambientTemp_C, readings.humidity_pct);
```

Missing values (`nan`) are uploaded as `null`, so a failed pH/ammonia probe
no longer blocks the dissolved oxygen and humidity readings.

**`loop()`.** In the testing branch (`ENABLE_DEEP_SLEEP 0`), nothing else is
needed, since `delayPollingDht()` already polls. With deep sleep on, the board
only listens during its ~20 s awake window. To pair it, press RESET and pair
while the LCD is cycling.

## Serial commands

| Sent by                        | Command           | Device replies                    |
|--------------------------------|-------------------|-----------------------------------|
| (older app versions only)      | `PAIR <token>`    | `PAIRED OK` or `PAIR ERROR …`     |
| Website (device removed)       | `UNPAIR`          | `UNPAIRED OK`                     |
| `tools/provision_device.py`    | `PROVISION <secret>` | `PROVISIONED OK` or `PROVISION ERROR …` |

At boot the device prints `ID=<chip id>  PAIRED=yes|no`, then
`PROVISIONED=yes|no`. Commands are read only from the main loop (between
readings), so right after a reset the device answers once it has connected to
WiFi, checked its sensors and printed its first reading.

## QR labels (how devices are paired)

The app pairs devices only by their QR label. Provision each device once,
after flashing it:

```sh
py -m pip install -r tools/requirements.txt
py tools/provision_device.py --port COM9 --app-url https://isdasafe.vercel.app
```

(`py -m serial.tools.list_ports -v` lists the ports; close the IsdaSafe
website and the Arduino Serial Monitor first, since only one program can use
the port. The script waits for the device's first reading before sending the
secret, so it can take a minute or two.)

The script reads the device's ID, writes a random secret into it (`PROVISION`),
registers the secret and a claim code with Supabase, and saves a printable
label to `labels/<device id>.png`. Stick the label on the device. It needs
`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` (Supabase dashboard → Project
Settings → API) in the environment or in `tools/.env`. The service-role key
can do anything in the project: keep it on the provisioning computer, never
in the app or the firmware.

A provisioned device uploads with its secret, which the database accepts once
the label has been scanned in the app (Pair a device). Until then its uploads
are rejected (`Upload rejected: HTTP 403 … device not paired`). After it's
removed from a pond, the same label pairs it again.

A device that was already paired over USB by an older version of the app
keeps its pond: once provisioned it uploads with the secret, which the
database accepts for a device that's already linked.

Anyone who can see the label can claim an unclaimed device, so keep spare
labelled devices out of reach. Once claimed, someone else scanning it can
only *request* a transfer, which the owner approves or declines in the app.
