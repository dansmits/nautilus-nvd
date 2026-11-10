#!/bin/bash
# Nautilus (Navy NVD) for Linux: one-command setup for a CAC.
#
# Works on Debian-family systems (Ubuntu, Linux Mint, Debian, Pop!_OS...). It:
#   1. installs the packages needed (smart card stack, NSS tools, build tools)
#   2. builds FreeRDP from upstream source (signature-verified) into /opt/freerdp3
#   3. downloads DISA's current "DoD PKI Only" certificate bundle, verifies it, and adds it to the
#      system store (see bin/nautilus-fetch-certs for exactly what is checked)
#   4. adds the same certificates + the OpenSC CAC module to Chrome's certificate database
#   5. installs the launcher (headset and microphone are redirected automatically; webcam is opt-in)
#      and a desktop shortcut for each connection file you give it
#
# Usage:  ./install.sh [--rdp FILE.rdp ...] [--certs <folder|bundle.zip|https-url>]
#   --rdp    your NVD connection file(s); see README for how to get them
#   --certs  use your own certificate source instead of DISA's bundle
# Run as your normal user, not with sudo. It asks for your password when needed. Safe to re-run.
set -euo pipefail

FREERDP_VERSION=3.33.0
# Fingerprint of the FreeRDP release signing key (Armin Novak, "akallabeth"). The release is
# rejected unless it is signed by exactly this key.
FREERDP_KEY_FPR=7703B333420E0AEF995EB4B3A49454A3FC909FD5
PREFIX=/opt/freerdp3
# Local fixes applied to the FreeRDP source (see patches/). A checksum of them is stored in the install
# so an older build without the fixes is detected and rebuilt.
PATCHES=("$(cd "$(dirname "$0")" && pwd)"/patches/*.patch)
PATCH_ID="$(cat "${PATCHES[@]}" | sha256sum | cut -d' ' -f1)"

KIT="$(cd "$(dirname "$0")" && pwd)"
say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33mWARNING:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -ne 0 ] || die "Run this as your normal user, not with sudo."
command -v apt-get >/dev/null || die "This installer needs an apt-based system (Ubuntu, Mint, Debian). See README.md for other distributions."

TMPROOT="$(mktemp -d)"; trap 'rm -rf "$TMPROOT"' EXIT

RDPS=(); CERTS_SRC=""
while [ $# -gt 0 ]; do
  case "$1" in
    --rdp)   shift; while [ $# -gt 0 ] && [[ "$1" != --* ]]; do RDPS+=("$1"); shift; done ;;
    --certs) [ $# -ge 2 ] || die "--certs needs a folder, .zip file or https URL"; CERTS_SRC="$2"; shift 2 ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done
for f in "$KIT"/connections/*.rdp "$KIT"/connections/*.rdpw; do [ -f "$f" ] && RDPS+=("$f"); done
[ "${#RDPS[@]}" -gt 0 ] || warn "No connection files given. Re-run with --rdp FILE.rdp (see README), or later run: nautilus-add-connection FILE.rdp"

# --- 1. Packages -----------------------------------------------------------
say "Installing packages (needs your password)"
sudo apt-get update || warn "apt update reported errors (often an unrelated repository); continuing."
sudo apt-get install -y \
  pcscd opensc opensc-pkcs11 libnss3-tools pcsc-tools openssl ca-certificates curl gnupg \
  python3 xdg-utils desktop-file-utils \
  build-essential cmake ninja-build pkg-config patch \
  libssl-dev libkrb5-dev libpcsclite-dev libcjson-dev liburiparser-dev libicu-dev \
  libavcodec-dev libavutil-dev libswscale-dev libswresample-dev \
  libpulse-dev libasound2-dev libv4l-dev libcups2-dev libusb-1.0-0-dev libudev-dev libsystemd-dev uuid-dev zlib1g-dev \
  libx11-dev libxext-dev libxfixes-dev libxi-dev libxrender-dev libxrandr-dev libxinerama-dev \
  libxcursor-dev libxkbfile-dev libxv-dev libxtst-dev libxkbcommon-dev
sudo systemctl enable --now pcscd.socket >/dev/null 2>&1 || true

# --- 1b. DoD certificates: download and verify (before the long build, so problems show up early) --
say "Fetching and verifying the DoD PKI certificates"
CERTDIR="$TMPROOT/certs"
"$KIT/bin/nautilus-fetch-certs" "$CERTDIR" ${CERTS_SRC:+"$CERTS_SRC"} \
  || die "Could not get verified DoD certificates. You can supply your own with --certs <folder|bundle.zip|https-url>."

# --- 2. FreeRDP ------------------------------------------------------------
have_freerdp() {
  [ -x "$PREFIX/bin/xfreerdp" ] || return 1
  "$PREFIX/bin/xfreerdp" --version 2>&1 | grep -q "version $FREERDP_VERSION" || return 1
  "$PREFIX/bin/xfreerdp" +buildconfig 2>&1 | tr ' ' '\n' | grep -q '^WITH_XDG_AAD_AUTH_HELPER=ON$' || return 1
  "$PREFIX/bin/xfreerdp" /help 2>&1 | grep -q 'dvc:rdpecam' || return 1   # webcam redirection built in
  [ "$(cat "$PREFIX/.nautilus-patches" 2>/dev/null)" = "$PATCH_ID" ] || return 1   # camera crash fix applied
}
if have_freerdp; then
  say "FreeRDP $FREERDP_VERSION already installed in $PREFIX"
else
  say "Building FreeRDP $FREERDP_VERSION (takes a few minutes)"
  WORK="$TMPROOT/freerdp"; mkdir -p "$WORK"
  BASE="https://github.com/FreeRDP/FreeRDP/releases/download/$FREERDP_VERSION"
  curl -fsSL -o "$WORK/src.tar.gz"     "$BASE/freerdp-$FREERDP_VERSION.tar.gz"
  curl -fsSL -o "$WORK/src.tar.gz.asc" "$BASE/freerdp-$FREERDP_VERSION.tar.gz.asc"
  curl -fsSL -o "$WORK/key.gpg"        "https://github.com/akallabeth.gpg"
  export GNUPGHOME="$WORK/gnupg"; mkdir -m 700 "$GNUPGHOME"
  gpg --quiet --import "$WORK/key.gpg" 2>/dev/null
  gpg --status-fd 1 --verify "$WORK/src.tar.gz.asc" "$WORK/src.tar.gz" 2>/dev/null \
    | grep -q "^\[GNUPG:\] VALIDSIG .* $FREERDP_KEY_FPR\$" \
    || die "FreeRDP source signature check FAILED. Not building."
  echo "  signature OK (key $FREERDP_KEY_FPR)"
  unset GNUPGHOME
  tar -xzf "$WORK/src.tar.gz" -C "$WORK"
  SRC="$WORK/freerdp-$FREERDP_VERSION"
  for pf in "${PATCHES[@]}"; do
    echo "  applying $(basename "$pf")"
    patch -d "$SRC" -p1 --quiet < "$pf" || die "Could not apply $(basename "$pf") to the FreeRDP source."
  done
  cmake -S "$SRC" -B "$WORK/build" -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_INSTALL_LIBDIR=lib \
    -DWITH_X11=ON -DWITH_CLIENT_SDL=OFF -DWITH_WAYLAND=OFF -DWITH_SERVER=OFF -DWITH_SHADOW=OFF \
    -DWITH_PROXY=OFF -DWITH_SAMPLE=OFF -DWITH_PLATFORM_SERVER=OFF \
    -DWITH_AAD=ON -DWITH_XDG_AAD_AUTH_HELPER=ON -DWITH_QT_AAD_AUTH_HELPER=OFF \
    -DWITH_WEBVIEW_AAD_AUTH_HELPER=OFF -DWITH_WEBVIEW=OFF \
    -DWITH_PCSC=ON -DWITH_SMARTCARD_PCSC=ON -DWITH_PKCS11=ON -DWITH_KRB5=ON \
    -DWITH_FFMPEG=ON -DWITH_DSP_FFMPEG=ON -DWITH_SWSCALE=ON -DWITH_VIDEO_FFMPEG=ON \
    -DWITH_PULSE=ON -DWITH_ALSA=ON -DWITH_CUPS=ON -DWITH_FUSE=OFF -DWITH_CAIRO=OFF -DWITH_MANPAGES=OFF \
    -DWITH_OPUS=OFF -DWITH_JPEG=OFF -DWITH_SDL_IMAGE_DIALOGS=OFF -DCHANNEL_RDPECAM_CLIENT=ON \
    -DWITH_CJSON_REQUIRED=ON -DWITH_URIPARSER=ON -DBUILD_TESTING=OFF >/dev/null
  ninja -C "$WORK/build" -j"$(nproc)"
  DESTDIR="$WORK/stage" ninja -C "$WORK/build" install >/dev/null
  sudo rm -rf "$PREFIX"
  sudo cp -a "$WORK/stage$PREFIX" "$PREFIX"
  sudo chown -R root:root "$PREFIX"
  echo "$PATCH_ID" | sudo tee "$PREFIX/.nautilus-patches" >/dev/null
  have_freerdp || die "FreeRDP was built but the xdg sign-in helper is missing from it."
fi
sudo install -m 755 "$KIT/bin/nautilus-connect"        /usr/local/bin/nautilus-connect
sudo install -m 755 "$KIT/bin/nautilus-add-connection" /usr/local/bin/nautilus-add-connection

# --- 3. DoD certificates: system store ---------------------------------------
say "Adding DoD certificates to the system trust store"
sudo mkdir -p /usr/local/share/ca-certificates/dod
sudo rm -f /usr/local/share/ca-certificates/dod/*.crt   # drop certificates from an older bundle
sudo cp "$CERTDIR"/*.crt /usr/local/share/ca-certificates/dod/
sudo update-ca-certificates >/dev/null

# --- 4. Chrome (NSS): DoD certificates + OpenSC CAC module ---------------------
say "Setting up Chrome's certificate database (~/.pki/nssdb)"
DB="sql:$HOME/.pki/nssdb"
mkdir -p "$HOME/.pki/nssdb"
[ -f "$HOME/.pki/nssdb/cert9.db" ] || certutil -N -d "$DB" --empty-password
echo "  importing certificates (each takes a moment if a CAC is inserted)..."
for f in "$CERTDIR"/*.crt; do
  cn="$(openssl x509 -in "$f" -noout -subject -nameopt multiline | sed -n 's/^ *commonName *= *//p')"
  case "$cn" in "DoD Root CA "*) trust="CT,C,C" ;; *) trust=",," ;; esac
  if certutil -d "$DB" -L -n "$cn" >/dev/null 2>&1; then
    certutil -d "$DB" -M -t "$trust" -n "$cn"          # already there: just make sure the trust flags are right
  else
    certutil -d "$DB" -A -t "$trust" -n "$cn" -i "$f"
  fi
done
OPENSC=""
for p in /usr/lib/*/pkcs11/opensc-pkcs11.so /usr/lib64/pkcs11/opensc-pkcs11.so /usr/lib/pkcs11/opensc-pkcs11.so; do
  [ -f "$p" ] && { OPENSC="$p"; break; }
done
[ -n "$OPENSC" ] || die "Could not find opensc-pkcs11.so"
if modutil -dbdir "$DB" -list 2>/dev/null | grep -q "$OPENSC"; then
  echo "  OpenSC module already registered"
else
  modutil -dbdir "$DB" -add "OpenSC" -libfile "$OPENSC" -force >/dev/null
  echo "  OpenSC module registered"
fi

# --- 5. Connections and shortcuts ---------------------------------------------
if [ "${#RDPS[@]}" -gt 0 ]; then
  say "Installing connections and shortcuts"
  /usr/local/bin/nautilus-add-connection "${RDPS[@]}"
fi

# --- Done -----------------------------------------------------------------
say "Done"
browser="$(xdg-settings get default-web-browser 2>/dev/null || true)"
case "$browser" in
  google-chrome*) ;;
  *) warn "Default browser is '${browser:-unknown}', not Google Chrome. The Microsoft sign-in opens in the
         default browser, and only Chrome is set up for the CAC. Install Chrome and make it the default." ;;
esac
command -v google-chrome >/dev/null || warn "Google Chrome is not installed (google.com/chrome)."
cat <<'EOF'

Next steps:
  1. Quit Chrome completely and reopen it (it loads the CAC module at startup).
  2. Insert your CAC and double-click a Nautilus shortcut on the desktop.
  3. On the Microsoft page enter your username first, then pick the PIV Authentication
     certificate and your PIN. When Chrome asks to open "FreeRDP AAD redirect handler",
     click Open.

Troubleshooting: run from a terminal to see errors, e.g.
  nautilus-connect ~/Documents/Nautilus/<file>.rdp
EOF
