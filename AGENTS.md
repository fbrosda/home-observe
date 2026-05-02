# AGENTS.md

## Project

Guile Scheme 3.0 daemon that polls home devices (Kostal Plenticore PV inverter, IDM heatpump) and writes metrics to TimescaleDB.

## Commands

- `make install` — installs binary to `/usr/local/bin/home-observe`, modules to `/usr/local/share/guile/site/3.0/home-observe/`, and systemd service to `/etc/systemd/system/`
- `make uninstall` — reverses install
- Root `Makefile` delegates to `systemd/` and `home-observe/` subdirectories in that order

## Config

- Read from `/etc/home-observe.cfg` as a Scheme s-expression (alist with `"plenticore"` and `"idm"` keys)
- `"plenticore"` key contains a dbi connection spec and `"password"` for SCRAM auth
- `home-observe.cfg` is gitignored (contains secrets)

## Architecture

- `home-observe/main.scm` — entry point, spawns two threads (plenticore observer, idm observer)
- `home-observe/plenticore.scm` — SCRAM auth + AES-GCM session encryption, polls inverter API every 10s, writes to `plenticore` hypertable
- `home-observe/idm.scm` — IDM heatpump observer
- `home-observe/aes.scm` — AES-GCM encrypt/decrypt (C FFI via `aes.c`)
- `home-observe/util.scm` — dbi connection helper (`with-dbi-handle`)
- `grafana/plenticore.json` — Grafana dashboard
- `systemd/home-observe.service` — runs `/usr/local/bin/home-observe`, restarts on failure

## Dependencies

Guile 3.0 modules: `dbi`, `gcrypt`, `json` (guile-json). C file `aes.c` is compiled as a Guile extension.

## Key gotchas

- Plenticore uses a custom SCRAM-based auth flow (not standard) with AES-GCM encrypted session tokens
- `with-rfc5802-auth` has an outer `auth-loop` that restarts full SCRAM auth if the body exits (e.g. refresh-session fails)
- The retry `guard` covers both the thunk and the refresh attempt. If refresh throws (expired token, connection refused), it propagates out and triggers full re-auth
- Exponential backoff starts at 5s, doubles each retry, capped at 120s
- The `plenticore` table is created on first run via `CREATE TABLE IF NOT EXISTS` with TimescaleDB hypertable extension
- `iv_digi_in` is stored as `bit(4)` — cast with `::bit(4)` in SQL
- Polling interval is hardcoded to 10 seconds in `plenticore.scm`
- No test suite exists
