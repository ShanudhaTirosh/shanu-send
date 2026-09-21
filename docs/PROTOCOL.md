# ShanuSend Wire Protocol & API Specification (v2.1)

This document serves as the single source of truth for ShanuSend's network wire protocols across Rust (`shanusend-core`) and Dart (`flutter_app`).

---

## 1. LocalSend Protocol v2.1 (LAN File Transfer)

### Multicast Discovery
- **Group Address**: `224.0.0.167`
- **UDP Port**: `53317`
- **Payload Format**: JSON
```json
{
  "alias": "ShanuSend Desktop",
  "version": "2.1",
  "deviceModel": "Desktop",
  "deviceType": "desktop",
  "fingerprint": "a1b2c3...",
  "port": 53317,
  "protocol": "https",
  "download": false,
  "announcement": true
}
```

### HTTP/HTTPS REST Endpoints
Default Port: `53317`

#### `GET /api/localsend/v2/info` & `POST /api/localsend/v2/register`
Returns local device info object matching discovery format.

#### `POST /api/localsend/v2/prepare-upload`
- **Request**:
```json
{
  "info": {
    "alias": "Sender Device",
    "version": "2.1",
    "deviceModel": "Mobile",
    "deviceType": "mobile",
    "fingerprint": "xyz123..."
  },
  "files": {
    "file_id_1": {
      "id": "file_id_1",
      "fileName": "photo.jpg",
      "size": 1048576,
      "fileType": "image/jpeg"
    }
  }
}
```
- **Response** (`200 OK` on accept):
```json
{
  "sessionId": "uuid-session-123",
  "files": {
    "file_id_1": "token-abc-456"
  }
}
```

#### `POST /api/localsend/v2/upload?sessionId={id}&fileId={id}&token={token}`
- **Body**: Binary byte stream of file content.
- **Response**: `200 OK` upon hash & size verification.

---

## 2. ShanuConnect / KDE Connect Protocol v7 (Device Sync)

### Discovery & Control Ports
- **TCP Port**: `1716` (TLS Encrypted Handshake)
- **UDP Port**: `1716` (Discovery Broadcasts)

### Core Envelope
All ShanuConnect messages are JSON lines terminated by `\n`:
```json
{
  "id": 1695000000000,
  "type": "shanuconnect.pair",
  "body": {
    "pair": true
  }
}
```

### Security & Pairing Rule
- **Identity Exchange**: Sent over plaintext (`shanuconnect.identity`).
- **TLS Upgrade**: Triggered immediately following identity exchange.
- **Pairing Enforcement**: Remote control commands (`shanuconnect.runcommand`, `shanuconnect.lockdevice`, `shanuconnect.mousepad`, `shanuconnect.findmyphone`, `shanuconnect.sftp`) **MUST** verify device paired status before execution.

---

## 3. WebDrop & AirDrop Gateway Portal

- **Web Portal Route**: `GET /webdrop` (Serves responsive HTML upload/download interface)
- **Direct Upload Route**: `POST /api/webdrop/upload` (Multipart form-data)
- **File Download Route**: `GET /api/webdrop/download/:filename`
