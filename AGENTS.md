# AGENTS.md

## Project

Guile Scheme 3.0 daemon that polls home devices (Kostal Plenticore PV inverter, IDM heatpump) and writes metrics to TimescaleDB.

## Commands

- `make install` — installs binary to `/usr/local/bin/home-observe`, modules to `/usr/local/share/guile/site/3.0/home-observe/`, and systemd service to `/etc/systemd/system/`
- `make uninstall` — reverses install
- Root `Makefile` delegates to `systemd/` and `home-observe/` subdirectories in that order

## Config

- Read from `/etc/home-observe.cfg` as a Scheme s-expression (alist with `"plenticore"` and `"idm"` keys)
- Each section contains: `"host"` (optional, defaults to `plenticore.fritz.box` / `idm.fritz.box`), `"password"`, and `"connection"` (dbi connection spec)
- `home-observe.cfg` is gitignored (contains secrets)

## Architecture

- `home-observe/main.scm` — entry point, spawns two threads with `run-observer` wrapper (top-level crash recovery with 5s restart)
- `home-observe/plenticore.scm` — SCRAM auth + AES-GCM session encryption, polls inverter API, writes to `plenticore` hypertable
- `home-observe/idm.scm` — WebSocket-based heatpump observer, writes to `idm` hypertable
- `home-observe/aes.scm` — AES-GCM encrypt/decrypt (libgcrypt C FFI via `system foreign`)
- `home-observe/util.scm` — `with-dbi-handle` and `log-error` helpers
- `grafana/plenticore.json` — Grafana dashboard
- `systemd/home-observe.service` — runs `/usr/local/bin/home-observe`, restarts on failure

## Dependencies

Guile 3.0 modules: `dbi`, `gcrypt`, `json` (guile-json). `aes.c` provides the C FFI bindings.

## Error handling

- Each observer has a two-tier retry strategy: internal retry with exponential backoff (5s → 120s cap) for transient errors, plus `run-observer` in `main.scm` for full restart
- Plenticore: `with-rfc5802-auth` has an outer `auth-loop` that restarts full SCRAM auth if the body exits (e.g. refresh fails). The inner `guard` covers the thunk and refresh attempt; if refresh throws, it propagates and triggers full re-auth
- IDM: WebSocket connect/poll failures caught by outer `catch #t`, reconnect with same backoff pattern

## Key gotchas

- Plenticore uses a custom SCRAM-based auth flow (not standard) with AES-GCM encrypted session tokens
- `iv_digi_in` is stored as `bit(4)` — cast with `::bit(4)` in SQL
- Polling interval is hardcoded to 10 seconds in both observers
- Both tables created on first run via `CREATE TABLE IF NOT EXISTS` with TimescaleDB hypertable extension
- No test suite exists
