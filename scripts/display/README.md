# orientation-audit-volumio.sh

Audit display orientation on Linux/Volumio systems (DRM/KMS, fbcon, xrandr/Wayland, input rotation hints, Pi stack/config parsing, etc.).

## Prerequisites

Optional helper packages (edid-decode, evtest, libinput-tools, drm-info, etc.):

```bash
sudo ./orientation-audit-volumio.sh --install-deps
````

> If your distro doesn’t have some tools, the script will still run with reduced checks.

## Run and capture output to a log

The script prints to **stdout**. To save a log, redirect output yourself:

**Option A (recommended, see output live & save it):**

```bash
sudo ./orientation-audit-volumio.sh 2>&1 | tee /tmp/orientation-audit.log
```

**Option B (quiet, only save to file):**

```bash
sudo ./orientation-audit-volumio.sh > /tmp/orientation-audit.log 2>&1
```

Your log will be at:

```
/tmp/orientation-audit.log
```

## Share your results (Pastebin)

Install a simple CLI paste tool (Debian/Ubuntu/Volumio-based):

```bash
sudo apt-get update && sudo apt-get install -y pastebinit
```

Then upload your log:

```bash
pastebinit /tmp/orientation-audit.log
```

This command prints a URL you can share on the forum.

> No log file handy? You can also stream directly:
>
> ```bash
> sudo ./orientation-audit-volumio.sh 2>&1 | pastebinit
> ```

## Notes

* On Wayland, `xrandr` rotation will show Xwayland views only (if present).
* Raspberry Pi: the script tries to detect firmware/KMS stack and parse any `config.txt` if present.
* EDID sections are best-effort; if `edid-decode` isn’t installed, that part is skipped.
