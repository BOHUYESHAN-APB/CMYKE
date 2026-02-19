# Mobile (Android) Gateway Plan

Goal: On Android, CMYKE should still have web search + tool execution ability, but without shipping a local OpenCode runtime on the phone.

Updated: 2026-02-19

## 1) Key Decision

- Android acts as a **thin client**.
- Tool execution happens on a **PC gateway** (Rust sidecar + OpenCode).
- Mobile connects to the gateway over LAN/WAN using:
  - `toolGatewayBaseUrl`
  - `toolGatewayPairingToken`

Rationale:
- Mobile OS sandboxes make it hard/unreliable to ship and execute a full CLI toolchain (OpenCode + its dependencies).
- PC-first shipping is the current priority.

## 2) Android User Flow

1. On PC:
   - Start CMYKE desktop, enable tool gateway, ensure gateway is running.
   - Create a pairing token.
   - Copy the mobile config (JSON) from Settings.
2. On Android:
   - Enable tool gateway.
   - Set gateway base URL to the PC's LAN IP (e.g. `http://192.168.1.10:4891`).
   - Paste the pairing token.
   - Tap "Test connection".

Notes:
- `127.0.0.1` on Android points to the phone itself, not your PC.
- Android emulator can reach the host machine using `http://10.0.2.2:4891`.

## 3) Security Baseline

- Do not auto-create pairing tokens on mobile.
- Pairing creation should be done on the gateway owner (PC) side.

## 4) Future Upgrades (optional)

- QR code pairing (desktop shows QR -> mobile scans -> auto-fill baseUrl+token).
- mDNS / LAN discovery of gateway endpoints.
- Optional "remote gateway" deployment templates (Docker / home server) with TLS and auth hardening.

