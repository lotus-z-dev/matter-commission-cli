# Changelog

## [1.0.0] — 2026-09-28

### Added
- Initial release of `matter_add.sh`
- Commission Matter devices via Matter Server WebSocket API
- Supports 11-digit manual pairing codes (with or without dashes) and QR codes (`MT:...`)
- Direct invocation of Python 3.13 + `websocket-client` from Nix store (no `nix-shell` overhead)
- Configurable `MATTER_WS_URL` via environment variable
- Clear success/failure/error output with exit codes
- Bilingual (FR/EN) inline documentation
