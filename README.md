# Nautilus NVD for Linux

One-command setup to connect a Linux computer to **Navy Nautilus Virtual Desktop (NVD)** with a **CAC**.
Tested on Linux Mint 21.3 and 22.3 (Ubuntu 22.04 / 24.04 bases).

This is an installer, not a fork of FreeRDP. It builds upstream FreeRDP from its signed release,
with the options NVD needs, and wires up Chrome, the DoD certificates and desktop shortcuts.

## Before you start
- A CAC reader plugged in, with your CAC inserted
- **Google Chrome** installed and set as the default browser (https://www.google.com/chrome)
- Your connection file(s) from the Nautilus portal (they end in `.rdpw`). They identify your
  organization's host pool, so this repo does not include them.

## Install
```bash
git clone https://github.com/dansmits/nautilus-nvd.git
cd nautilus-nvd
./install.sh --rdp ~/Downloads/YourConnection.rdpw
```
Run it as your normal user (not `sudo`); it asks for your password when needed. It takes several
minutes because FreeRDP is compiled on your machine. It is safe to re-run.

Then quit Chrome completely, reopen it, insert your CAC and double-click the **Nautilus** shortcut on
your desktop. On the Microsoft page enter your username first; Chrome then offers your *PIV
Authentication* certificate. When Chrome asks to open "FreeRDP AAD redirect handler", click Open.

Add more connections later with `nautilus-add-connection FILE.rdpw`.

## What it does
| Step | Result |
|---|---|
| Packages | `pcscd`, OpenSC, NSS tools and the build dependencies, via apt |
| FreeRDP | 3.33.0 built from the upstream release into `/opt/freerdp3`. The source's GPG signature must match the maintainer key `7703 B333 420E 0AEF 995E B4B3 A494 54A3 FC90 9FD5` or the build is refused |
| DoD certificates | 49 DoD PKI certificates (DoD Root CA 3-6 and intermediates, DISA bundle v5.14) in the system store and Chrome's database (`~/.pki/nssdb`), plus the OpenSC CAC module |
| Launcher | `/usr/local/bin/nautilus-connect`, which sets the Azure Government sign-in options |

Only apt-based systems (Ubuntu, Mint, Debian) are supported by the script. On Fedora or Arch, follow
the same steps by hand; see `CLAUDE.md`.

## Notes
- Only Chrome is set up for the CAC (not Firefox, and not Chrome from Flatpak or Snap).
- The certificates are DISA's public "DoD PKI Only" bundle. Verify or update them from
  https://public.cyber.mil (PKI CA Certificate Bundles). Do not use the WCF bundle.
- Not affiliated with or endorsed by the U.S. Navy, DoD or the FreeRDP project.

## License
Scripts: MIT (see `LICENSE`). FreeRDP is Apache-2.0 and is downloaded and built at install time.
