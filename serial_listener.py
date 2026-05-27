import json
import logging
import os
import queue
import re
import threading
import time
import uuid
from dataclasses import dataclass, field
from typing import Any, Dict, Optional, Tuple
from urllib.parse import urlparse

import requests
import serial
from flask import Flask, jsonify, request

# --- Configuration ---
SERIAL_PORT = os.getenv("SERIAL_PORT", "/dev/ttyACM1")
BAUD_RATE = int(os.getenv("BAUD_RATE", "115200"))
DEVICE_ID = os.getenv("DEVICE_ID", "ETHIOBIO_01")

LARAVEL_API_URL = os.getenv(
    "LARAVEL_API_URL", "http://127.0.0.1:8000/api/health-data"
)
LARAVEL_EVENTS_URL = os.getenv(
    "LARAVEL_EVENTS_URL", "http://127.0.0.1:8000/api/measurement-events"
)
LARAVEL_USER_API_URL = os.getenv("LARAVEL_USER_API_URL", "")

TOKEN_CACHE_PATH = os.getenv("TOKEN_CACHE_PATH", "last_token.json")

SERIAL_READ_TIMEOUT = float(os.getenv("SERIAL_READ_TIMEOUT", "1"))
SERIAL_RECONNECT_DELAY = float(os.getenv("SERIAL_RECONNECT_DELAY", "2"))
SERIAL_RECONNECT_MAX_DELAY = float(os.getenv("SERIAL_RECONNECT_MAX_DELAY", "12"))

LINE_QUEUE_MAX = int(os.getenv("LINE_QUEUE_MAX", "200"))

HEARTBEAT_INTERVAL = float(os.getenv("HEARTBEAT_INTERVAL", "6"))
HEARTBEAT_GRACE = float(os.getenv("HEARTBEAT_GRACE", "2"))

SEND_LIVE_TO_LEGACY = os.getenv("SEND_LIVE_TO_LEGACY", "false").lower() == "true"
SEND_RESULT_TO_LEGACY = os.getenv("SEND_RESULT_TO_LEGACY", "true").lower() == "true"

HTTP_TIMEOUT_SECONDS = float(os.getenv("HTTP_TIMEOUT_SECONDS", "5"))
HTTP_RETRY_COUNT = int(os.getenv("HTTP_RETRY_COUNT", "2"))
HTTP_RETRY_BACKOFF = float(os.getenv("HTTP_RETRY_BACKOFF", "0.6"))


def build_user_profile_url(health_data_url: str) -> str:
    """Convert .../api/health-data into .../api/user for token identity checks."""
    parsed = urlparse(health_data_url)
    path = parsed.path or ""
    if path.endswith("/health-data"):
        path = path[: -len("/health-data")] + "/user"
    elif path.endswith("health-data"):
        path = path[: -len("health-data")] + "user"
    else:
        path = "/api/user"

    return f"{parsed.scheme}://{parsed.netloc}{path}"


def resolve_user_api_url() -> str:
    if LARAVEL_USER_API_URL:
        return LARAVEL_USER_API_URL
    return build_user_profile_url(LARAVEL_API_URL)


class PacketType:
    STATUS = "STATUS"
    LIVE = "LIVE"
    RESULT = "RESULT"
    PROGRESS = "PROGRESS"
    ERROR = "ERROR"
    HEARTBEAT = "HEARTBEAT"
    LEGACY = "LEGACY"


@dataclass
class Packet:
    packet_type: str
    raw: str
    data: Dict[str, Any] = field(default_factory=dict)
    error: Optional[str] = None


@dataclass
class SessionState:
    session_id: str
    device_id: str
    state: str = "IDLE"
    started_at: float = field(default_factory=time.time)
    last_update_at: float = field(default_factory=time.time)
    progress: Optional[int] = None
    last_live: Optional[Dict[str, Any]] = None
    last_result: Optional[Dict[str, Any]] = None
    error_code: Optional[str] = None
    completed: bool = False


class PacketParser:
    def parse(self, line: str) -> Optional[Packet]:
        cleaned = (line or "").strip()
        if not cleaned:
            return None

        if "BPM:" in cleaned:
            payload = self._parse_legacy_line(cleaned)
            return Packet(packet_type=PacketType.LEGACY, raw=cleaned, data=payload)

        parts = [part.strip() for part in cleaned.split("|") if part.strip()]
        if not parts:
            return None

        packet_type = parts[0].upper()
        if packet_type not in {
            PacketType.STATUS,
            PacketType.LIVE,
            PacketType.RESULT,
            PacketType.PROGRESS,
            PacketType.ERROR,
        }:
            return Packet(
                packet_type="UNKNOWN",
                raw=cleaned,
                error=f"Unknown packet type: {packet_type}",
            )

        if packet_type == PacketType.STATUS:
            return self._parse_status(cleaned, parts)
        if packet_type == PacketType.PROGRESS:
            return self._parse_progress(cleaned, parts)
        if packet_type == PacketType.ERROR:
            return self._parse_error(cleaned, parts)
        if packet_type == PacketType.LIVE:
            return self._parse_vitals(cleaned, parts, is_result=False)
        if packet_type == PacketType.RESULT:
            return self._parse_vitals(cleaned, parts, is_result=True)

        return Packet(
            packet_type="UNKNOWN",
            raw=cleaned,
            error=f"Unhandled packet: {packet_type}",
        )

    def _parse_status(self, raw: str, parts: list[str]) -> Packet:
        if len(parts) < 2:
            return Packet(
                packet_type=PacketType.STATUS,
                raw=raw,
                error="Missing STATUS state",
            )

        return Packet(
            packet_type=PacketType.STATUS,
            raw=raw,
            data={"state": parts[1].upper()},
        )

    def _parse_progress(self, raw: str, parts: list[str]) -> Packet:
        if len(parts) < 2:
            return Packet(
                packet_type=PacketType.PROGRESS,
                raw=raw,
                error="Missing PROGRESS value",
            )

        try:
            percent = int(float(parts[1]))
            percent = max(0, min(100, percent))
            return Packet(
                packet_type=PacketType.PROGRESS,
                raw=raw,
                data={"percent": percent},
            )
        except ValueError:
            return Packet(
                packet_type=PacketType.PROGRESS,
                raw=raw,
                error=f"Invalid PROGRESS value: {parts[1]}",
            )

    def _parse_error(self, raw: str, parts: list[str]) -> Packet:
        if len(parts) < 2:
            return Packet(
                packet_type=PacketType.ERROR,
                raw=raw,
                error="Missing ERROR code",
            )

        return Packet(
            packet_type=PacketType.ERROR,
            raw=raw,
            data={"code": parts[1].upper()},
        )

    def _parse_vitals(self, raw: str, parts: list[str], is_result: bool) -> Packet:
        if len(parts) == 2 and re.match(r"^[A-Z_]+$", parts[1], re.IGNORECASE):
            # Header line like LIVE|BPM|SpO2|TEMP|SBP|DBP
            return Packet(
                packet_type=PacketType.RESULT if is_result else PacketType.LIVE,
                raw=raw,
                error="Header line ignored",
            )

        if len(parts) < 6:
            return Packet(
                packet_type=PacketType.RESULT if is_result else PacketType.LIVE,
                raw=raw,
                error="Missing vital values",
            )

        try:
            bpm = float(parts[1])
            spo2 = float(parts[2])
            temperature = float(parts[3])
            systolic = float(parts[4])
            diastolic = float(parts[5])
        except ValueError:
            return Packet(
                packet_type=PacketType.RESULT if is_result else PacketType.LIVE,
                raw=raw,
                error="Non-numeric vitals",
            )

        return Packet(
            packet_type=PacketType.RESULT if is_result else PacketType.LIVE,
            raw=raw,
            data={
                "heart_rate": bpm,
                "oxygen_saturation": spo2,
                "body_temperature": temperature,
                "systolic_bp": systolic,
                "diastolic_bp": diastolic,
            },
        )

    def _parse_legacy_line(self, line: str) -> Dict[str, Any]:
        """Parse legacy BPM/SPO2/TEMP lines into vitals payload."""
        pretty_match = re.search(
            r"BPM:\s*([0-9]+(?:\.[0-9]+)?)\s*\|\s*"
            r"SpO2:\s*([0-9]+(?:\.[0-9]+)?)%\s*\|\s*"
            r"Temp:\s*([0-9]+(?:\.[0-9]+)?)\s*C\s*\|\s*"
            r"BP:\s*(\d+)\s*/\s*(\d+)",
            line,
            flags=re.IGNORECASE,
        )

        if pretty_match:
            return {
                "heart_rate": float(pretty_match.group(1)),
                "oxygen_saturation": float(pretty_match.group(2)),
                "body_temperature": float(pretty_match.group(3)),
                "systolic_bp": float(pretty_match.group(4)),
                "diastolic_bp": float(pretty_match.group(5)),
            }

        parts = {}
        for item in re.split(r"[,|]", line):
            if ":" not in item:
                continue
            key, value = item.split(":", 1)
            parts[key.strip().upper()] = value.strip()

        required = ["BPM", "SPO2", "TEMP"]
        if not all(key in parts for key in required):
            raise ValueError(f"Missing keys in legacy serial data: {list(parts.keys())}")

        heart_rate = float(parts["BPM"])
        spo2 = float(parts["SPO2"].replace("%", "").strip())
        temp_value = parts["TEMP"].strip()
        if temp_value.upper().endswith("C"):
            temp_value = temp_value[:-1].strip()
        temperature = float(temp_value)

        payload = {
            "heart_rate": heart_rate,
            "oxygen_saturation": spo2,
            "body_temperature": temperature,
        }

        bp_raw = parts.get("BP")
        if bp_raw:
            bp_match = re.search(r"(\d+)\s*/\s*(\d+)", bp_raw)
            if bp_match:
                payload["systolic_bp"] = float(bp_match.group(1))
                payload["diastolic_bp"] = float(bp_match.group(2))

        return payload


class TokenStore:
    def __init__(self, path: str) -> None:
        self._path = path
        self._lock = threading.Lock()
        self._token: Optional[str] = None
        self._user_profile: Optional[Dict[str, Any]] = None

    def set_token(self, token: str, profile: Optional[Dict[str, Any]]) -> None:
        with self._lock:
            self._token = token
            self._user_profile = profile

    def get_token(self) -> Optional[str]:
        with self._lock:
            return self._token

    def get_profile(self) -> Optional[Dict[str, Any]]:
        with self._lock:
            return self._user_profile

    def load_cache(self) -> Tuple[Optional[str], Optional[str]]:
        if not os.path.exists(self._path):
            return None, None
        try:
            with open(self._path, "r", encoding="utf-8") as handle:
                data = json.load(handle)
            if not isinstance(data, dict):
                return None, None
            tokens = data.get("tokens", {})
            last_user_id = data.get("last_user_id")
            if not isinstance(tokens, dict):
                return None, None
            cached_token = tokens.get(str(last_user_id)) if last_user_id else None
            return cached_token, str(last_user_id) if last_user_id else None
        except Exception:
            return None, None

    def persist_token_for_user(self, user_id: Optional[str], token: str) -> None:
        if not user_id:
            return
        try:
            cache = {"tokens": {}, "last_user_id": None}
            if os.path.exists(self._path):
                with open(self._path, "r", encoding="utf-8") as handle:
                    data = json.load(handle)
                if isinstance(data, dict):
                    cache["tokens"] = data.get("tokens") or {}
            if not isinstance(cache.get("tokens"), dict):
                cache["tokens"] = {}
            cache["tokens"][str(user_id)] = token
            cache["last_user_id"] = str(user_id)
            with open(self._path, "w", encoding="utf-8") as handle:
                json.dump(cache, handle)
        except Exception:
            pass


class LaravelClient:
    def __init__(self) -> None:
        self._session = requests.Session()

    def _headers(self, token: Optional[str]) -> Dict[str, str]:
        headers = {"Accept": "application/json", "Content-Type": "application/json"}
        if token:
            headers["Authorization"] = f"Bearer {token}"
        return headers

    def _post_with_retry(
        self,
        url: str,
        token: Optional[str],
        payload: Dict[str, Any],
        label: str,
    ) -> None:
        if not url:
            return
        for attempt in range(HTTP_RETRY_COUNT + 1):
            try:
                response = self._session.post(
                    url,
                    json=payload,
                    headers=self._headers(token),
                    timeout=HTTP_TIMEOUT_SECONDS,
                )
                if response.status_code < 200 or response.status_code >= 300:
                    logging.warning(
                        "%s error: %s | %s",
                        label,
                        response.status_code,
                        response.text[:200],
                    )
                return
            except requests.RequestException as exc:
                if attempt >= HTTP_RETRY_COUNT:
                    logging.warning("%s request failed: %s", label, exc)
                    return
                backoff = HTTP_RETRY_BACKOFF * (2**attempt)
                time.sleep(backoff)

    def post_event(self, token: Optional[str], payload: Dict[str, Any]) -> None:
        self._post_with_retry(LARAVEL_EVENTS_URL, token, payload, "Laravel events")

    def post_legacy(self, token: Optional[str], payload: Dict[str, Any]) -> None:
        self._post_with_retry(LARAVEL_API_URL, token, payload, "Laravel legacy")

    def fetch_user_profile(self, token: str) -> Optional[Dict[str, Any]]:
        try:
            response = self._session.get(
                resolve_user_api_url(),
                headers=self._headers(token),
                timeout=5,
            )
            if response.status_code < 200 or response.status_code >= 300:
                return None

            body = response.json()
            if isinstance(body, dict) and isinstance(body.get("data"), dict):
                body = body["data"]
            if not isinstance(body, dict):
                return None

            return {
                "id": body.get("id"),
                "email": body.get("email"),
                "first_name": body.get("first_name"),
                "last_name": body.get("last_name"),
            }
        except Exception:
            return None


class MeasurementSessionManager:
    def __init__(self, device_id: str) -> None:
        self._device_id = device_id
        self._session: Optional[SessionState] = None

    def get_session(self) -> Optional[SessionState]:
        return self._session

    def reset(self) -> None:
        self._session = None

    def ensure_session(self) -> SessionState:
        if self._session is None or self._session.completed:
            self._session = SessionState(
                session_id=str(uuid.uuid4()),
                device_id=self._device_id,
                state="WAITING_FOR_FINGER",
            )
        return self._session

    def update_state(self, state: str) -> SessionState:
        session = self.ensure_session()
        session.state = state
        session.last_update_at = time.time()
        if state in {"READY", "WAITING_FOR_FINGER"} and session.completed:
            session = self.ensure_session()
        return session

    def update_progress(self, percent: int) -> SessionState:
        session = self.ensure_session()
        session.progress = percent
        session.last_update_at = time.time()
        return session

    def update_live(self, vitals: Dict[str, Any]) -> SessionState:
        session = self.ensure_session()
        session.last_live = vitals
        session.last_update_at = time.time()
        return session

    def complete_with_result(self, vitals: Dict[str, Any]) -> SessionState:
        session = self.ensure_session()
        session.last_result = vitals
        session.completed = True
        session.state = "COMPLETE"
        session.last_update_at = time.time()
        return session

    def update_error(self, code: str) -> SessionState:
        session = self.ensure_session()
        session.error_code = code
        session.state = "ERROR"
        session.last_update_at = time.time()
        return session


class SerialBridge:
    def __init__(self, token_store: TokenStore) -> None:
        self._token_store = token_store
        self._parser = PacketParser()
        self._client = LaravelClient()
        self._session_manager = MeasurementSessionManager(DEVICE_ID)
        self._line_queue: "queue.Queue[str]" = queue.Queue(maxsize=LINE_QUEUE_MAX)
        self._stop_event = threading.Event()
        self._last_line_at = time.time()
        self._last_heartbeat_sent = 0.0

    def start(self) -> None:
        threading.Thread(target=self._serial_reader, daemon=True).start()
        threading.Thread(target=self._processor_loop, daemon=True).start()

    def stop(self) -> None:
        self._stop_event.set()

    def reset_session(self) -> None:
        self._session_manager.reset()

    def _serial_reader(self) -> None:
        delay = SERIAL_RECONNECT_DELAY
        while not self._stop_event.is_set():
            try:
                logging.info("Connecting to Arduino on %s", SERIAL_PORT)
                with serial.Serial(
                    SERIAL_PORT,
                    BAUD_RATE,
                    timeout=SERIAL_READ_TIMEOUT,
                ) as ser:
                    time.sleep(2)
                    logging.info("Serial connection established")
                    delay = SERIAL_RECONNECT_DELAY
                    while not self._stop_event.is_set():
                        raw = ser.readline().decode("utf-8", errors="ignore")
                        if not raw:
                            continue
                        cleaned = raw.strip()
                        if not cleaned:
                            continue
                        try:
                            self._line_queue.put_nowait(cleaned)
                        except queue.Full:
                            logging.warning("Line queue full, dropping data")
            except Exception as exc:
                logging.error("Serial connection error: %s", exc)
                time.sleep(delay)
                delay = min(delay * 1.5, SERIAL_RECONNECT_MAX_DELAY)

    def _processor_loop(self) -> None:
        while not self._stop_event.is_set():
            try:
                line = self._line_queue.get(timeout=0.25)
            except queue.Empty:
                self._handle_heartbeat_if_needed()
                continue

            self._last_line_at = time.time()
            packet = self._parser.parse(line)
            if packet is None:
                continue
            if packet.error:
                logging.warning("Packet issue: %s | %s", packet.error, packet.raw)
                continue

            self._handle_packet(packet)

    def _handle_packet(self, packet: Packet) -> None:
        token = self._token_store.get_token()
        if not token:
            logging.info("Waiting for token from mobile app")
            return

        event_payload: Dict[str, Any] = {
            "device_id": DEVICE_ID,
            "captured_at": time.time(),
            "raw": packet.raw,
        }

        if packet.packet_type == PacketType.STATUS:
            session = self._session_manager.update_state(packet.data["state"])
            event_payload.update(
                {
                    "type": "status",
                    "session_id": session.session_id,
                    "state": session.state,
                }
            )
            self._client.post_event(token, event_payload)
            return

        if packet.packet_type == PacketType.PROGRESS:
            session = self._session_manager.update_progress(packet.data["percent"])
            event_payload.update(
                {
                    "type": "progress",
                    "session_id": session.session_id,
                    "progress": session.progress,
                }
            )
            self._client.post_event(token, event_payload)
            return

        if packet.packet_type == PacketType.ERROR:
            session = self._session_manager.update_error(packet.data["code"])
            event_payload.update(
                {
                    "type": "error",
                    "session_id": session.session_id,
                    "error_code": session.error_code,
                }
            )
            self._client.post_event(token, event_payload)
            return

        if packet.packet_type == PacketType.LIVE:
            session = self._session_manager.update_live(packet.data)
            event_payload.update(
                {
                    "type": "live",
                    "session_id": session.session_id,
                    "vitals": packet.data,
                }
            )
            self._client.post_event(token, event_payload)
            if SEND_LIVE_TO_LEGACY:
                self._client.post_legacy(token, packet.data)
            return

        if packet.packet_type == PacketType.RESULT:
            session = self._session_manager.complete_with_result(packet.data)
            event_payload.update(
                {
                    "type": "result",
                    "session_id": session.session_id,
                    "vitals": packet.data,
                }
            )
            self._client.post_event(token, event_payload)
            if SEND_RESULT_TO_LEGACY:
                self._client.post_legacy(token, packet.data)
            return

        if packet.packet_type == PacketType.LEGACY:
            if SEND_RESULT_TO_LEGACY:
                self._client.post_legacy(token, packet.data)
            return

        logging.warning("Unhandled packet type: %s", packet.packet_type)

    def _handle_heartbeat_if_needed(self) -> None:
        now = time.time()
        if now - self._last_line_at < (HEARTBEAT_INTERVAL + HEARTBEAT_GRACE):
            return
        if now - self._last_heartbeat_sent < HEARTBEAT_INTERVAL:
            return
        token = self._token_store.get_token()
        if not token:
            return
        session = self._session_manager.ensure_session()
        payload = {
            "type": "heartbeat",
            "device_id": DEVICE_ID,
            "session_id": session.session_id,
            "captured_at": now,
        }
        self._client.post_event(token, payload)
        self._last_heartbeat_sent = now
        logging.info("Heartbeat sent")


app = Flask(__name__)
token_store = TokenStore(TOKEN_CACHE_PATH)
serial_bridge = SerialBridge(token_store)


@app.after_request
def add_cors_headers(response):
    response.headers.setdefault("Access-Control-Allow-Origin", "*")
    response.headers.setdefault("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
    response.headers.setdefault(
        "Access-Control-Allow-Headers",
        "Content-Type, Authorization",
    )
    return response


@app.route("/set-token", methods=["POST", "OPTIONS"])
def set_token():
    if request.method == "OPTIONS":
        return jsonify({"message": "OK"}), 200
    data = request.get_json(silent=True) or {}
    token = data.get("token")
    if not token:
        return jsonify({"error": "Invalid payload"}), 400

    profile = LaravelClient().fetch_user_profile(token)
    token_store.set_token(token, profile)
    serial_bridge.reset_session()
    if profile and profile.get("id") is not None:
        token_store.persist_token_for_user(str(profile.get("id")), token)

    logging.info(
        "Token updated. System active. user_id=%s email=%s",
        profile.get("id") if profile else None,
        profile.get("email") if profile else None,
    )
    return jsonify({"message": "Token updated", "user": profile}), 200


def _configure_logging() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s | %(levelname)s | %(message)s",
    )


if __name__ == "__main__":
    _configure_logging()

    cached_token, cached_user_id = token_store.load_cache()
    if cached_token:
        profile = LaravelClient().fetch_user_profile(cached_token)
        token_store.set_token(cached_token, profile)
        logging.info(
            "Cached token loaded. user_id=%s email=%s",
            profile.get("id") if profile else cached_user_id,
            profile.get("email") if profile else None,
        )

    serial_bridge.start()
    logging.info("USB Bridge Server starting on port 5001")
    app.run(host="0.0.0.0", port=5001, debug=False)