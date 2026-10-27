#!/bin/bash
# Ensure a stable, self-signed codesigning identity exists — WITHOUT prompting
# for the login password on every build.
#
# Usage:
#   IDENTITY="$(bash scripts/ensure-signing-identity.sh)"
#
# Configure via environment (all optional):
#   SIGN_IDENTITY_NAME   certificate common name        (default: "Local Dev (Self-Signed)")
#   SIGN_KEYCHAIN_NAME   keychain file basename         (default: derived from the identity)
#   SIGN_KEYCHAIN_PASS   dedicated keychain password    (default: "local-dev-signing")
#
# Prints the identity name on stdout so a launcher can capture it. Idempotent:
# exits 0 quickly once the identity is usable, so it is cheap to call every run.
#
# Why a stable identity: xcodebuild ad-hoc signs, so every build has a different
# CDHash and macOS TCC treats it as a NEW app — Full Disk Access and friends get
# revoked on each rebuild. A real (even self-signed) certificate keeps the app's
# designated requirement constant, so grants stick.
#
# Why a DEDICATED keychain rather than login.keychain: codesign may use a
# private key without a GUI prompt only if the key's partition list authorises
# it, and setting that list requires the keychain's password. For login.keychain
# that is the user's login password, which a script cannot supply — so the call
# fails and macOS prompts on EVERY signature, forever. A keychain we create has
# a password we know, so the partition list can be set headlessly.
#
# The keychain password is not a secret: it guards only a self-signed
# certificate that signs local builds. It grants nothing off this machine.
set -euo pipefail

IDENTITY_NAME="${SIGN_IDENTITY_NAME:-Local Dev (Self-Signed)}"

# Derive a filesystem-safe keychain name from the identity unless told otherwise.
default_kc="$(printf '%s' "$IDENTITY_NAME" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9-')"
KEYCHAIN_NAME="${SIGN_KEYCHAIN_NAME:-${default_kc:-local-dev}-signing}"
KEYCHAIN="${HOME}/Library/Keychains/${KEYCHAIN_NAME}.keychain-db"
KEYCHAIN_PASS="${SIGN_KEYCHAIN_PASS:-local-dev-signing}"

# --- Keep the keychain unlocked and in the search list ------------------------
# Both are needed on every run: a keychain relocks on reboot, and the search
# list is what lets `codesign --sign <name>` resolve the identity at all.
ensure_available() {
    [ -f "$KEYCHAIN" ] || return 1
    security unlock-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN" >/dev/null 2>&1 || return 1
    # No -t/-l: never auto-lock on timeout or sleep, so builds stay prompt-free.
    security set-keychain-settings "$KEYCHAIN" >/dev/null 2>&1 || true
    if ! security list-keychains -d user | tr -d ' "' | grep -qxF "$KEYCHAIN"; then
        local current
        current="$(security list-keychains -d user | sed -e 's/^[[:space:]]*"//' -e 's/"$//')"
        # shellcheck disable=SC2086
        security list-keychains -d user -s $current "$KEYCHAIN" >/dev/null 2>&1 || true
    fi
    return 0
}

# The only trustworthy check. `security find-identity -p codesigning -v` reports
# 0 valid identities for a self-signed cert (CSSMERR_TP_NOT_TRUSTED) even when
# codesign works perfectly, so probe with a real signature instead.
can_codesign_with_identity() {
    local tmpbin
    tmpbin="$(mktemp)"
    printf '#!/bin/sh\nexit 0\n' > "$tmpbin"
    chmod +x "$tmpbin"
    if codesign --sign "$IDENTITY_NAME" --identifier probe --force "$tmpbin" >/dev/null 2>&1; then
        rm -f "$tmpbin"
        return 0
    fi
    rm -f "$tmpbin"
    return 1
}

if ensure_available && can_codesign_with_identity; then
    echo "$IDENTITY_NAME"
    exit 0
fi

# --- Rebuild the identity from scratch ----------------------------------------
# Drop any earlier attempt, including a legacy copy in login.keychain — that one
# is exactly what causes the endless password prompts.
LOGIN_KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"
for hash in $(security find-certificate -c "$IDENTITY_NAME" -a -Z "$LOGIN_KEYCHAIN" 2>/dev/null \
                | awk '/SHA-1 hash:/{print $NF}'); do
    security delete-certificate -Z "$hash" -t "$LOGIN_KEYCHAIN" >/dev/null 2>&1 || true
done
security delete-identity -c "$IDENTITY_NAME" "$LOGIN_KEYCHAIN" >/dev/null 2>&1 || true

security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
security create-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN" >/dev/null
security set-keychain-settings "$KEYCHAIN" >/dev/null 2>&1 || true
security unlock-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN" >/dev/null

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<CNF
[ req ]
distinguished_name = dn
prompt             = no
x509_extensions    = v3

[ dn ]
CN = ${IDENTITY_NAME}

[ v3 ]
basicConstraints       = critical, CA:false
keyUsage               = critical, digitalSignature
extendedKeyUsage       = critical, codeSigning
subjectKeyIdentifier   = hash
CNF

openssl req -x509 -newkey rsa:2048 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -days 3650 -nodes -config "$TMP/cert.cnf" >/dev/null 2>&1

P12_PASS="p12-transit"
# macOS `security import` cannot read AES-256-CBC PKCS12, which OpenSSL 3+ emits
# by default — `-legacy` forces RC2/3DES instead. But `-legacy` does not exist on
# the system LibreSSL at /usr/bin/openssl, which already defaults to 3DES. Probe
# rather than assume: which binary we get depends on PATH order, so assuming
# either one makes the script work from a launcher and fail from a plain shell.
p12_legacy=()
if openssl pkcs12 -help 2>&1 | grep -q -- '-legacy'; then
    p12_legacy=(-legacy)
fi
# ${a[@]+"${a[@]}"} — bash 3.2 (macOS /bin/bash) counts an empty array as
# unbound under `set -u`; this expands to nothing instead of aborting.
openssl pkcs12 -export ${p12_legacy[@]+"${p12_legacy[@]}"} -out "$TMP/bundle.p12" \
    -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$IDENTITY_NAME" -passout "pass:$P12_PASS" >/dev/null

# -A: any application may use this key. Safe here because the key lives in its
# own keychain and only signs local builds — and it is part of what keeps builds
# free of GUI authorisation prompts.
security import "$TMP/bundle.p12" -k "$KEYCHAIN" -P "$P12_PASS" -A \
    -T /usr/bin/codesign -T /usr/bin/security >/dev/null

# Optional: promotes the cert out of CSSMERR_TP_NOT_TRUSTED. codesign does not
# need it, and writing user trust settings can raise its own GUI prompt — so
# never let a failure here abort the setup.
security add-trusted-cert -r trustAsRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem" >/dev/null 2>&1 || true

# The prompt-killer: authorise codesign to use the private key headlessly. This
# can only succeed because we own the keychain password.
security set-key-partition-list -S apple-tool:,apple:,codesign: \
    -s -k "$KEYCHAIN_PASS" "$KEYCHAIN" >/dev/null 2>&1 || true

ensure_available || true

echo "$IDENTITY_NAME"
