# sys-hw-probe

Portable, vendor-neutral diagnostics and helper scripts for Linux kiosks and media-player systems  
(e.g., Volumio builds) — focusing on **display orientation**, **audio (DACs/HATs)**,  
**Wi-Fi/BT**, **input devices**, and **power**.

---

## Features

- Zero-config, read-only probes that print actionable state and hints
- Works on x86 and Raspberry Pi stacks (KMS/FKMS/legacy, DSI/DPI panels)
- Clear summaries for DRM connectors, EDID, input devices, and compositor rotation
- Friendly guidance to resolve common conflicts (fbcon vs kernel vs compositor)
- CI-ready: ShellCheck, shfmt, and BATS smoke tests

---

## Quick start

```bash
git clone https://github.com/foonerd/sys-hw-probe.git
cd sys-hw-probe
./install.sh   # symlinks scripts into /usr/local/bin and checks basic deps
````

> Most probes are read-only. The optional `--install-deps` flag installs user-space tools (apt).

---

## Usage

### Display orientation audit

```bash
orientation-audit-volumio.sh --help
sudo orientation-audit-volumio.sh
sudo orientation-audit-volumio.sh --install-deps
```

What it reports (abridged):

* Kernel cmdline flags (`fbcon=rotate`, `video=`), Plymouth presence
* DRM connectors (status, modes, kernel panel_orientation)
* EDID presence and summary (if `edid-decode` is installed)
* Xorg/Xwayland rotation (via `xrandr`)
* Input devices via `libinput`, `xinput`, evdev, and udev
* Raspberry Pi stack detection (KMS/FKMS/legacy, DSI/DPI overlays) and config parsing

---

## Dependencies

The scripts try to degrade gracefully. For best results:

* Core: `bash`, `grep`, `awk`, `sed`, `jq`
* Display: `drm-info` or `libdrm-tests` (`modetest`), `x11-xserver-utils` (`xrandr`), `edid-decode`
* Input: `libinput-tools`, `xinput`, `evtest`, `udev`
* Misc: `usbutils`, `pciutils`

Install helpers automatically:

```bash
sudo orientation-audit-volumio.sh --install-deps
```

---

## Repository layout

```
sys-hw-probe/
├─ scripts/
│  ├─ display/
│  │  └─ orientation-audit-volumio.sh
│  ├─ audio/      # DACs/HATs, HDMI/DP audio (coming)
│  ├─ network/    # Wi-Fi/BT, regulatory (coming)
│  ├─ input/      # touch matrices, libinput/xinput (coming)
│  └─ power/      # backlight, governors (coming)
├─ tests/
│  ├─ test_smoke.bats
│  └─ fixtures/
├─ .github/
│  ├─ ISSUE_TEMPLATE/
│  └─ workflows/ci.yml
├─ install.sh
├─ CONTRIBUTING.md
├─ CODE_OF_CONDUCT.md
├─ SECURITY.md
├─ LICENSE
└─ README.md
```

---

## Contributing

PRs are welcome! Please:

1. Run `make fmt lint test` (requires `shfmt`, `shellcheck`, `bats`)
2. Include a short description, platform(s) tested, and sample (redacted) output
3. Keep scripts readable, POSIX/Bash-friendly, and safe (no destructive defaults)

See [CONTRIBUTING.md](CONTRIBUTING.md) for details.

---

## Security

These tools are read-mostly. If you find a vulnerability, please open a private report
(see [SECURITY.md](SECURITY.md)) instead of a public issue.

---

## License

MIT © 2025 sys-hw-probe contributors — see [LICENSE](LICENSE).
