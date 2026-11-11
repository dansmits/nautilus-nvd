# Nautilus NVD for Linux

One-command setup to connect a Linux computer to **Navy Nautilus Virtual Desktop (NVD)** with a **CAC**.
Tested on Linux Mint 21.3 and 22.3 (Ubuntu 22.04 / 24.04 bases).

This is an installer, not a fork of FreeRDP. It builds upstream FreeRDP from its signed release,
with the options NVD needs, and wires up Chrome, the DoD certificates and desktop shortcuts.

## Before you start
- A CAC reader plugged in, with your CAC inserted
- **Google Chrome** installed and set as the default browser (https://www.google.com/chrome)

You do **not** need your NVD connection files (`.rdp`/`.rdpw`) up front. Downloading them needs a
working CAC in Chrome, so the installer sets that up first, then walks you through it.

## Install
```bash
git clone https://github.com/dansmits/nautilus-nvd.git
cd nautilus-nvd
./install.sh
```
Run it as your normal user (not `sudo`). On a desktop it opens a setup window with a progress bar and
asks for your password in a dialog (`./install.sh --text` runs it in the terminal instead). It takes several
minutes because FreeRDP is compiled on your machine. It is safe to re-run.

The installer then:
1. sets up the smart card service, DoD certificates, Chrome's certificate database and FreeRDP;
2. checks that it can see your CAC reader and card (and waits while you plug them in);
3. shows the NVD web client link (`https://rdweb.wvd.azure.us/arm/webclient/`, or use the one NVD gave
   you) and tells you how to download the RDP file(s): sign in with your CAC, click the gear icon, under
   *Resources launch method* choose **Download the RDP file**, then click each desktop (for example East
   and West);
4. waits for the `.rdp`/`.rdpw` files to appear in the script's folder or `~/Downloads`, then creates a
   desktop shortcut for each.

If you already have the files, click **Browse...** in the setup window (or type a file's path in the
terminal installer) to add them. You can also pass files yourself: `./install.sh --rdp "FILE.rdp" "OTHER.rdp"` (quote names with spaces).

Then quit Chrome completely, reopen it, insert your CAC and double-click the **Nautilus** shortcut on
your desktop. On the Microsoft page enter your username first; Chrome then offers your *PIV
Authentication* certificate. When Chrome asks to open "FreeRDP AAD redirect handler", click Open.

Add more connections later with `nautilus-add-connection FILE.rdp`.

## What it does
| Step | Result |
|---|---|
| Packages | `pcscd`, OpenSC, NSS tools and the build dependencies, via apt |
| FreeRDP | 3.33.0 built from the upstream release (plus the small camera fix in `patches/`) into `/opt/freerdp3`. The source's GPG signature must match the maintainer key `7703 B333 420E 0AEF 995E B4B3 A494 54A3 FC90 9FD5` or the build is refused |
| DoD certificates | Downloaded fresh from DISA each time you run the installer (see below), then added to the system store and Chrome's database (`~/.pki/nssdb`), plus the OpenSC CAC module |
| Launcher | `/usr/local/bin/nautilus-connect`, which sets the Azure Government sign-in options and redirects your headset and microphone (webcam is opt-in) |

Only apt-based systems (Ubuntu, Mint, Debian) are supported by the script. On Fedora or Arch, follow
the same steps by hand; see `CLAUDE.md`.

## Headset, microphone and webcam
- **Headset and microphone** are redirected automatically: your default audio devices are sent to the
  session (`/sound:sys:pulse /microphone:sys:pulse`, which also covers PipeWire). Set your headset as
  the default input and output in your sound settings before you connect. In the session it appears as
  *Remote Audio*. Opt out with `NAUTILUS_NO_AUDIO=1`.
- **Webcam** redirection is built in but **off by default** while it gets more testing. Stock FreeRDP
  3.33.0's camera channel can crash the whole session when the remote app stops or restarts the
  camera (it aborts in `ecam_dev_send_pending`). The installer applies a small fix
  (`patches/freerdp-3.33.0-rdpecam-stop-stream.patch`) that has held up in Teams so far. To use the
  camera: `NAUTILUS_CAMERA=1 nautilus-connect FILE.rdp`. It
  redirects any Video4Linux camera (`/dev/video*`; check with `ls /dev/video*`) through
  `/dvc:rdpecam,sys:v4l`. It only appears if your host pool allows camera redirection.
- Both are standard audio and camera redirection, not raw USB passthrough, so they work with any
  headset or webcam Linux can already see.

Options you add on the command line come last and override the defaults.

**Upgrading:** re-run `./install.sh`. It detects a FreeRDP built without the camera channel and rebuilds
it (a few minutes), then updates the launcher.

## DoD certificates: where they come from and how they're checked
The installer downloads DISA's **"PKI CA Certificate Bundles: PKCS#7 for DoD PKI Only"** from
`https://dl.dod.cyber.mil/wp-content/uploads/pki-pke/zip/unclass-certificates_pkcs7_DoD.zip`. That is the
file behind the Download button on https://www.cyber.mil/pki-pke/tools-configuration-files (the page is
built with JavaScript, so the script uses the file's fixed address instead of scraping the page).
DISA replaces that file when a new version is released, so you always get the current one.

Nothing is trusted just because it downloaded. `bin/nautilus-fetch-certs` refuses the bundle unless:
1. the signer chain starts with a self-signed **DoD Root CA** whose SHA-1 fingerprint is pinned in the
   script (Root CA 6 is `D3:7E:CF:61:C0:B4:ED:88:68:1E:F3:63:0C:4E:2F:C7:87:B3:7A:EF`, as in DISA's README);
2. DISA's signed checksum file verifies against that root, and every file in the bundle matches it;
3. every certificate is a CA certificate under `O=U.S. Government, OU=DoD, OU=PKI` that chains to a pinned root.

It also refuses the look-alike WCF, ECA and JITC bundles. If DoD ever issues a new root, the script stops
with a message instead of trusting it. Add the new fingerprint to `PINNED_ROOTS` after checking it at
https://crl.disa.mil.

### Using your own certificate source
```bash
./install.sh --certs ~/my-certs/          # a folder of your own .crt/.pem/.cer CA certificates
./install.sh --certs ~/Downloads/bundle.zip   # a DISA-format bundle zip you downloaded yourself
./install.sh --certs https://example.mil/bundle.zip   # another https URL serving a DISA-format bundle
```
A bundle zip gets the same checks as above. A **folder is not verified**: you are choosing what to trust,
so the script only requires CA certificates (no personal certificates, no private keys) and warns you.
You can also run the checker alone: `bin/nautilus-fetch-certs OUTPUT_DIR [source]`.

## Notes
- Only Chrome is set up for the CAC (not Firefox, and not Chrome from Flatpak or Snap).
- The certificates are never copied from this repo; they always come from DISA (or your `--certs` source).
  The installer needs internet access to reach `dl.dod.cyber.mil`; offline, use `--certs`.
- Not affiliated with or endorsed by the U.S. Navy, DoD or the FreeRDP project.

## License
Scripts: MIT (see `LICENSE`). FreeRDP is Apache-2.0 and is downloaded and built at install time.
