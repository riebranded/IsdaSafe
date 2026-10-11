"""Provision an IsdaSafe device for QR-code claiming.

Run once per device, after flashing its firmware, with the device plugged into
this computer over USB:

    pip install -r tools/requirements.txt
    python tools/provision_device.py --port COM5 --app-url https://isdasafe.example.com

It:
  1. reads the device's ID from its serial output (`ID=<12 hex>`),
  2. generates a random 64-hex secret and a claim code,
  3. writes the secret into the device (`PROVISION <secret>` -> `PROVISIONED OK`),
  4. registers both with Supabase (register_device_credentials(), which only
     the service-role key may call; only hashes are stored),
  5. saves a printable QR label to labels/<device id>.png.

The label's QR code opens <app-url>/?claim=<device id>.<claim code>; the app
also scans it directly (Pair a device -> Scan QR code). The claim code is
printed under the QR code for typing in by hand.

Needs SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in the environment or in
tools/.env. Never put the service-role key in the app or the firmware.
"""

from __future__ import annotations

import argparse
import os
import re
import secrets
import sys
import time
from pathlib import Path

import qrcode
import requests
import serial
from PIL import Image, ImageDraw, ImageFont

BAUD = 115200
ID_RE = re.compile(r"\bID=([0-9A-F]{12})\b")
# No 0/O or 1/I/L: easy to read off a label and type.
CLAIM_ALPHABET = "23456789ABCDEFGHJKMNPQRSTUVWXYZ"
CLAIM_LENGTH = 12


def load_env() -> None:
    env_file = Path(__file__).with_name(".env")
    if not env_file.exists():
        return
    for line in env_file.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


def new_claim_code() -> str:
    return "".join(secrets.choice(CLAIM_ALPHABET) for _ in range(CLAIM_LENGTH))


def pretty_code(code: str) -> str:
    return "-".join(code[i : i + 4] for i in range(0, len(code), 4))


def read_device_id(port: serial.Serial, timeout: float) -> str:
    """Waits for a line with ID=... (printed at boot and with every reading)."""
    # Pulse RESET (EN) through the USB adapter so the boot line comes quickly.
    port.dtr = False
    port.rts = True
    time.sleep(0.1)
    port.rts = False
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        line = port.readline().decode("utf-8", errors="replace").strip()
        if line:
            print(f"  << {line}")
        match = ID_RE.search(line)
        if match:
            return match.group(1)
    raise SystemExit(
        "No device ID seen. Check the port, close the Arduino Serial Monitor, "
        "and make sure the board runs the IsdaSafe firmware."
    )


RESEND_EVERY = 20  # seconds


def send_secret(port: serial.Serial, secret: str, timeout: float) -> None:
    """Writes the secret and waits for the firmware to confirm it.

    The firmware only reads commands from its main loop (between readings),
    not while setup() connects to WiFi and checks the sensors, which can take
    a minute or more after a reset. So this waits for the first reading line
    (`DO=... ID=...`) before sending, and sends again every RESEND_EVERY
    seconds until the device answers.
    """
    deadline = time.monotonic() + timeout
    loop_running = False
    next_send = 0.0
    sends = 0
    print("Waiting for the device to finish starting up (its first reading)...")
    while time.monotonic() < deadline:
        now = time.monotonic()
        if loop_running and now >= next_send:
            port.write(f"PROVISION {secret}\n".encode())
            port.flush()
            sends += 1
            print(f"  >> PROVISION (secret hidden){' again' if sends > 1 else ''}")
            next_send = now + RESEND_EVERY
        line = port.readline().decode("utf-8", errors="replace").strip()
        if not line:
            continue
        print(f"  << {line}")
        if line == "PROVISIONED OK":
            return
        if line.startswith("PROVISION ERROR"):
            raise SystemExit(f"The device rejected the secret: {line}")
        if not loop_running and "DO=" in line and "ID=" in line:
            loop_running = True
            next_send = 0.0
    if not loop_running:
        raise SystemExit(
            "The device never printed a reading, so it never got the secret. "
            "Check its output above for errors, or try again with a longer "
            "--timeout."
        )
    raise SystemExit(
        "The device didn't confirm the secret. Make sure it runs firmware with "
        "the PROVISION command (firmware/isdasafe_pairing.h) and that the sketch "
        "calls pollSerialCommands() while it waits between readings, then try "
        "again."
    )


def register(device_id: str, secret: str, claim_code: str) -> None:
    url = os.environ.get("SUPABASE_URL", "").rstrip("/")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    if not url or not key:
        raise SystemExit(
            "Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY (environment or tools/.env)."
        )
    response = requests.post(
        f"{url}/rest/v1/rpc/register_device_credentials",
        headers={
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
        },
        json={"p_device_id": device_id, "p_secret": secret, "p_claim_code": claim_code},
        timeout=30,
    )
    if response.status_code not in (200, 204):
        raise SystemExit(
            f"Supabase rejected the registration ({response.status_code}): {response.text}"
        )


def font(size: int) -> ImageFont.ImageFont:
    for name in ("arialbd.ttf", "DejaVuSans-Bold.ttf", "Arial Bold.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def claim_payload(device_id: str, claim_code: str, app_url: str) -> str:
    """What the QR code holds (the app's parseClaimPayload reads it)."""
    return f"{app_url.rstrip('/')}/?claim={device_id}.{claim_code}"


def make_label(device_id: str, claim_code: str, app_url: str, out_dir: Path) -> Path:
    qr = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_M, border=2)
    qr.add_data(claim_payload(device_id, claim_code, app_url))
    qr.make(fit=True)
    qr_img = qr.make_image(fill_color="black", back_color="white").convert("RGB")
    qr_img = qr_img.resize((480, 480), Image.NEAREST)

    width, height = 560, 680
    label = Image.new("RGB", (width, height), "white")
    draw = ImageDraw.Draw(label)
    draw.text((width / 2, 28), "IsdaSafe", font=font(34), fill="black", anchor="mm")
    label.paste(qr_img, ((width - 480) // 2, 52))
    draw.text(
        (width / 2, 560), "Scan in the IsdaSafe app to pair",
        font=font(20), fill="black", anchor="mm",
    )
    draw.text(
        (width / 2, 600), f"Device {device_id}", font=font(22), fill="black", anchor="mm"
    )
    draw.text(
        (width / 2, 640), f"Code {pretty_code(claim_code)}",
        font=font(26), fill="black", anchor="mm",
    )

    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / f"{device_id}.png"
    label.save(path)
    return path


def main() -> None:
    parser = argparse.ArgumentParser(description="Provision an IsdaSafe device for QR-code claiming.")
    parser.add_argument("--port", required=True, help="Serial port, e.g. COM5 or /dev/ttyUSB0")
    parser.add_argument(
        "--app-url", required=True,
        help="The IsdaSafe website's address; the QR code opens it to claim the device",
    )
    parser.add_argument("--out", default="labels", help="Folder for the label images")
    parser.add_argument(
        "--timeout", type=float, default=300,
        help="Seconds to wait for the device's ID and for PROVISIONED OK",
    )
    args = parser.parse_args()
    load_env()

    print(f"Opening {args.port} at {BAUD} baud...")
    try:
        port = serial.Serial(args.port, BAUD, timeout=1)
    except serial.SerialException as e:
        if "Access is denied" in str(e) or "PermissionError" in str(e):
            raise SystemExit(
                f"{args.port} is in use by another program. Close the IsdaSafe "
                "website tab (it reconnects to the device automatically), the "
                "Arduino Serial Monitor and any other serial terminal, then try "
                "again. If it still fails, unplug the board and plug it back in."
            )
        raise SystemExit(
            f"Couldn't open {args.port}: {e}\n"
            "List the available ports with: py -m serial.tools.list_ports -v"
        )
    with port:
        device_id = read_device_id(port, args.timeout)
        print(f"Device ID: {device_id}")
        secret = secrets.token_hex(32)
        claim_code = new_claim_code()
        send_secret(port, secret, args.timeout)

    register(device_id, secret, claim_code)
    path = make_label(device_id, claim_code, args.app_url, Path(args.out))
    print()
    print(f"Provisioned {device_id}.")
    print(f"  Claim code: {pretty_code(claim_code)}")
    print(f"  Label:      {path}")
    print("Print the label and stick it on the device. Running this again replaces")
    print("the secret and claim code; the old label then stops working.")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(1)
