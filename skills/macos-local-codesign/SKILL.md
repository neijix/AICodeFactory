---
name: macos-local-codesign
description: "Use when a locally built Swift/Xcode macOS app dies instantly at launch; dyld says 'Library not loaded: @rpath/<App>.debug.dylib', 'different Team IDs' or 'code signature not valid for use in process'; macOS re-prompts for the keychain password every build; TCC grants (Full Disk Access, Screen Recording, Accessibility) reset each rebuild; or a script runs codesign/security."
compatibility: macOS. Requires codesign + security (system), openssl (system LibreSSL or Homebrew OpenSSL 3 — the script handles both). Xcode only needed to produce the app.
---

# Local macOS code signing that doesn't fight you

Signing a locally-built app looks like a one-liner and isn't. The naive command
succeeds, prints nothing alarming, and then the app dies at launch with a dyld
error that never mentions signing — or it works but re-prompts for your password
forever. This skill exists because each of those failures costs an hour to
diagnose from the symptom alone.

## Why sign a local dev build at all

macOS TCC (Full Disk Access, Screen Recording, Accessibility, Automation) keys
its grants on the app's **designated requirement** — essentially bundle
identifier plus certificate anchor. `xcodebuild` ad-hoc signs (identity `-`),
which has no certificate anchor, so the requirement falls back to the CDHash.
Every rebuild changes the CDHash, macOS decides it is a different app, and the
user re-grants Full Disk Access after every single build.

A self-signed certificate fixes this: the anchor stays constant, so the
requirement stays constant, so the grant sticks. That is the whole motivation —
if the app needs no TCC permissions, ad-hoc signing is fine and you can skip
this entirely.

## Set up the identity

Run the bundled script. It is idempotent — it exits fast once a usable identity
exists, so a launcher can call it on every run:

```bash
IDENTITY="$(bash scripts/ensure-signing-identity.sh)"
```

Copy it into the project (e.g. `scripts/`) and commit it, so the setup travels
with the repo rather than living only in one machine's keychain. **Commit it
with its executable bit** (`chmod +x`, `git update-index --chmod=+x`) — see the
silent-skip trap below.

## Sign the app

Order and flags both matter:

```bash
# 1. Nested Mach-O first, each keeping its OWN identifier.
while IFS= read -r macho; do
    codesign --sign "$IDENTITY" --force "$macho"
done < <(find "$APP/Contents" -type f -name '*.dylib')

# 2. The bundle last, with the stable identifier TCC keys on.
codesign --sign "$IDENTITY" --identifier "com.example.myapp" --force "$APP"

# 3. Verify — this catches most mistakes before launch does.
codesign --verify --deep --strict "$APP"
```

Note what is absent: no `--deep`, no `--options runtime`. Both are the traps.

## The traps

Each of these produces a symptom that points somewhere other than signing.

### `--deep --identifier` breaks app launch

**Symptom:** the app dies instantly and silently when opened from Finder. Run
the binary directly and dyld says:

```
Library not loaded: @rpath/MyApp.debug.dylib
Reason: ... code signature ... not valid for use in process:
        mapping process and mapped file (non-platform) have different Team IDs
```

**Cause:** Xcode 16+ Swift Debug builds emit a `MyApp.debug.dylib` next to the
main binary in `Contents/MacOS/`. `--deep` descends into it, and `--identifier`
applies to *everything* it touches — so the nested dylib is stamped with the
app's bundle id instead of its own. dyld refuses the mismatched pairing.

**Fix:** sign nested Mach-O individually without `--identifier`, bundle last
with it. Apple deprecated `--deep` for signing anyway; it was never meant for
this.

### `--options runtime` breaks app launch the same way

**Symptom:** identical dyld error, even after fixing the identifier problem.
Confusing, because the identifiers now look correct under `codesign -dv`.

**Cause:** the hardened runtime enables **library validation**, which requires
every loaded library to carry the same Team ID as the process. A self-signed
certificate has no Team ID at all (`TeamIdentifier=not set`), so validation
rejects the dylib.

**Fix:** drop `--options runtime`. It is only needed for notarised
distribution. TCC stability comes from the bundle id and certificate anchor,
which do not depend on it. If you genuinely need the hardened runtime locally,
add the `com.apple.security.cs.disable-library-validation` entitlement instead.

### The identity in `login.keychain` prompts forever

**Symptom:** macOS asks for the keychain or login password on *every* signature.
Signing three Mach-O files means three prompts per build. It never stops asking,
and "Always Allow" doesn't survive.

**Cause:** `codesign` may use a private key without a GUI prompt only if the
key's **partition list** authorises it. Setting that list requires the
keychain's password:

```bash
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASS" "$KEYCHAIN"
```

For `login.keychain` that password is the user's *login password*, which a
script cannot supply and must never ask for. So the call fails, the partition
list stays empty, and the prompts are permanent. Scripts that paper over this
with `|| true` hide the failure and leave the user re-typing their password
forever.

**Fix:** put the identity in a **dedicated keychain** whose password you choose.
Then the partition list can be set non-interactively and the prompts stop. The
bundled script does this. The keychain password is not a secret — it guards a
self-signed certificate that signs local Debug builds and grants nothing off the
machine.

### `openssl pkcs12 -legacy` doesn't exist on system openssl

**Symptom:** `unknown option '-legacy'` followed by a usage dump, but only
sometimes — it works when run from a launcher and fails from a plain shell.

**Cause:** `/usr/bin/openssl` is LibreSSL and has no `-legacy`. Homebrew's
OpenSSL 3 has it, and needs it, because `security import` cannot read the
AES-256-CBC PKCS12 that OpenSSL 3 emits by default. Which binary you get depends
on `PATH` order, so the script works or breaks depending on who invoked it.

**Fix:** probe instead of assuming — `openssl pkcs12 -help 2>&1 | grep -q -- '-legacy'`.

### `CSSMERR_TP_NOT_TRUSTED` is a red herring

`security find-identity -p codesigning -v` reports **0 valid identities** and
the cert shows `CSSMERR_TP_NOT_TRUSTED`. This looks fatal and usually is not:
`codesign` signs fine with an untrusted self-signed certificate. Only the
`-v` (valid-only) listing filters it out.

Confirm with a real signature rather than trusting the listing:

```bash
T=$(mktemp); printf '#!/bin/sh\nexit 0\n' > "$T"; chmod +x "$T"
codesign --sign "$IDENTITY" --identifier probe --force "$T" && echo OK
```

`add-trusted-cert` can promote it, but writing user trust settings triggers its
own GUI prompt — usually not worth it.

### A missing executable bit disables signing silently

**Symptom:** none. Signing simply never happens, and the user notices weeks
later when Full Disk Access keeps resetting.

**Cause:** launchers commonly guard with `[ -x scripts/ensure-signing-identity.sh ]`.
If the file lost its executable bit, the guard is false and the whole block is
skipped without a word.

**Fix:** guard on `-f` and invoke via `bash script.sh`, and `else` into a
visible warning. A guard whose failure mode is silence will eventually fail
silently.

## Verifying it actually worked

`codesign --verify` passing is necessary but not sufficient — it does not catch
the dylib pairing failure. Launch the app and confirm it survives:

```bash
open "$APP"
sleep 8   # after a re-sign, first-launch Gatekeeper validation adds delay
pgrep -x MyApp >/dev/null && echo "alive" || echo "died — run the binary directly"
```

Give it more time than feels necessary. Probing at 3–5 seconds produces false
"it died" reports on a freshly re-signed bundle. If it did die, run
`"$APP/Contents/MacOS/MyApp"` directly — dyld prints the real reason to stderr,
which `open` swallows entirely. Check `~/Library/Logs/DiagnosticReports/` too:
*absence* of a new `.ips` means the process exited rather than crashed, which
points at a different problem than a signing failure.

## Bash gotcha in these scripts

macOS ships bash 3.2, where an empty array under `set -u` counts as unbound and
aborts the script. Building codesign flags conditionally hits this immediately:

```bash
flags=()
cmd ${flags[@]+"${flags[@]}"}   # expands to nothing instead of aborting
```
