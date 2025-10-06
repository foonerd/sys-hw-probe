# sys-hw-probe

Portable, vendor-neutral diagnostics and helper scripts for Linux kiosks and media-player systems  
(e.g., Volumio builds) - focusing on **display orientation**, **audio (DACs/HATs)**,  
**Wi-Fi/BT**, **input devices**, and **power**.

---

## Features

- Zero-config, read-only probes that print actionable state and hints
- Works on x86 and Raspberry Pi stacks (KMS/FKMS/legacy, DSI/DPI panels)
- Clear summaries for DRM connectors, EDID, input devices, and compositor rotation
- Wi-Fi hardware inspection: bus type, vendor/device IDs, kernel driver, PHY bands
- Friendly guidance to resolve common conflicts (fbcon vs kernel vs compositor, driver vs firmware)
- CI-ready: ShellCheck, shfmt, and BATS smoke tests

---

## Quick start

```
git clone https://github.com/foonerd/sys-hw-probe.git
cd sys-hw-probe
./install.sh   # symlinks scripts into /usr/local/bin and checks basic deps
````

> Most probes are read-only. The optional `--install-deps` flag installs user-space tools (apt).

---

## Usage

### Display orientation audit

```
orientation-audit-volumio --help
sudo orientation-audit-volumio
sudo orientation-audit-volumio --install-deps
```

Redirect full output to a log file for sharing:

```
sudo orientation-audit-volumio > orientation.log 2>&1
```

Then either upload `orientation.log` directly, or copy it to a pastebin service:

```
curl -F 'file=@orientation.log' https://0x0.st
```

---

### Wi-Fi diagnostics

```
sudo wifi-info
```

Redirect full output to a log file for sharing:

```
sudo wifi-info > wifi.log 2>&1
```

Then upload `wifi.log` or copy it to a pastebin:

```
curl -F 'file=@wifi.log' https://0x0.st
```

What it reports (abridged):

* Bus type (USB / PCI / SDIO)
* Device VID:PID and modalias
* Bound kernel module and `modinfo` metadata
* PHY interface modes, supported bands
* HT/VHT/HE/EHT capabilities

---

## Dependencies

The scripts try to degrade gracefully. For best results:

* Core: `bash`, `grep`, `awk`, `sed`, `jq`
* Display: `drm-info` or `libdrm-tests` (`modetest`), `x11-xserver-utils` (`xrandr`), `edid-decode`
* Input: `libinput-tools`, `xinput`, `evtest`, `udev`
* Wi-Fi: `iw`, `pciutils`, `usbutils`
* Misc: `curl` (for pastebin upload)

Install helpers automatically:

```
sudo orientation-audit-volumio --install-deps
```

---

## Repository layout

```
sys-hw-probe/
├─ scripts/
│  ├─ display/
│  │  └─ orientation-audit-volumio.sh
│  ├─ network/
│  │  └─ wifi-info.sh
│  ├─ audio/      # DACs/HATs, HDMI/DP audio (coming)
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

MIT © 2025 sys-hw-probe contributors - see [LICENSE](LICENSE).
