# Nautilus NVD for Linux: notes for Claude Code

`install.sh` handles apt-based systems. On any other distribution, reproduce its steps by hand:
install pcscd + OpenSC + NSS tools; build FreeRDP 3 (`WITH_AAD=ON`, `WITH_XDG_AAD_AUTH_HELPER=ON`,
`WITH_PCSC=ON`, prefix `/opt/freerdp3`, verify the source signature against the fingerprint in
`install.sh`); run `bin/nautilus-fetch-certs <dir>` (downloads and verifies DISA's DoD PKI Only bundle; `--certs` in install.sh passes your own source), then add the `.crt` files from that dir to the system store and to `sql:$HOME/.pki/nssdb` (roots `CT,C,C`,
others `,,`); register OpenSC with `modutil`; install `bin/*`; add connections with
`nautilus-add-connection`. Check a build with
`xfreerdp +buildconfig | tr ' ' '\n' | grep -E 'XDG_AAD|WITH_AAD=|WITH_PCSC='`.

`sudo` does not work through Claude Code's shell: give sudo commands to the user to run in a
normal terminal, one short command per block. Never commit `.rdp`/`.rdpw` files (they hold the
organization's Azure IDs); `.gitignore` excludes them.

## Key connection parameters (Azure Government)
FreeRDP defaults to **commercial** Azure (`login.microsoftonline.com`, `www.wvd.microsoft.com`),
which fails for NVD. `nautilus-connect` builds these options from the `.rdp` file:
```
/azure:tenantid:<aadtenantid from .rdp>,use-tenantid,ad:login.microsoftonline.us,avd-scope:https%3A%2F%2Fwww.wvd.azure.us%2F.default%20openid%20profile%20offline_access,auth-helper:/opt/freerdp3/libexec/freerdp-xdg-aad-helper
/smartcard /dynamic-resolution
/sound:sys:pulse /microphone:sys:pulse        (unless NAUTILUS_NO_AUDIO)
/dvc:rdpecam,sys:v4l                            (only with NAUTILUS_CAMERA=1, if /dev/video* exists and the build has it)
```
If FreeRDP's `/azure:` syntax changes in a newer release, check `xfreerdp /help` and update the launcher.

## Headset and webcam
- Redirected through audio and camera channels, **not** `/usb` (urbdrc): AVD hosts generally don't
  support generic USB redirection, and `/smartcard` is a separate channel from it.
- The camera option is `/dvc:rdpecam,sys:v4l`, **not** `/camera`. Without `device:` it enumerates
  every V4L capture node. The build needs `libv4l-dev` and `-DCHANNEL_RDPECAM_CLIENT=ON`; check with
  `xfreerdp /help | grep rdpecam`.
- A webcam that is missing from `lsusb` and `/dev/video*` is a hardware/cabling problem (for example a
  monitor's USB upstream cable or input), not a FreeRDP one.

- **Camera is opt-in** because FreeRDP 3.33.0 aborts (WINPR_ASSERT in `Stream_ResetPosition`, from
  `ecam_dev_send_pending`) when the guest stops/restarts the stream: stop frees `sampleRespBuffer` and
  `pendingSample` while a frame request is still arriving. Preceded by `Streaming already in progress`
  errors in `~/.xsession-errors`. `patches/freerdp-3.33.0-rdpecam-stop-stream.patch` (applied by install.sh) guards those paths: no frame
  is sent without buffers, sample requests for a stopped stream are ignored, stop clears stale state.
  Tested once in Teams (stream ran, no abort); a *separate* session drop was seen from a failed
  `Cached Pointer` fastpath update (X11 cursor), unrelated to the camera. install.sh records the patch
  checksum in `/opt/freerdp3/.nautilus-patches` and rebuilds when it differs. Make the camera default-on
  once it has had more testing or upstream ships a fix.

## Pitfalls already hit (don't repeat them)
- **Wrong DoD bundle**: DISA also publishes a **WCF** bundle ("WCF B&I PKI"), which contains DoD's
  web-content-filter (TLS inspection) CAs. Don't install it; it doesn't help and lets those proxy CAs
  vouch for any website. Use "DoD PKI Only".
- **Flathub FreeRDP (`com.freerdp.FreeRDP`) doesn't work for CAC sign-in** (checked with 3.33.0):
  - its sign-in window (`freerdp-qt-aad-helper`) has no client-certificate support, so Entra shows
    **"Certificate validation failed"** without ever offering the CAC;
  - it's built with `WITH_XDG_AAD_AUTH_HELPER=OFF`, and the xdg helper can't work across the sandbox anyway;
  - its bundled `/app/lib/pkcs11/opensc-pkcs11.so` was a broken symlink.
  Don't spend time on p11-kit forwarding or `flatpak override` workarounds. Build natively instead.
- **`.rdpw` files**: FreeRDP decides whether an argument is a connection file by its extension, so
  rename (or copy) them to `.rdp`.
- **Wrong cloud**: if the log shows `login.microsoftonline.com`, the Government `/azure:` options are missing.
- **The CAC prompt only appears after entering the username** on the Microsoft page.
- **Blank Qt sign-in window** (`dma_buf acquisition failure`) only affected the Flatpak's Qt helper;
  it doesn't apply to the xdg/Chrome helper.

