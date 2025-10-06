# WiFi Diagnostics Script

This script helps identify and support WiFi hardware on Linux systems such as Volumio.  
It collects details about wireless interfaces, bus type, drivers, and capabilities.

## Features

- Detects WiFi interfaces (USB, PCI, SDIO, SDIO-over-SD, etc.)
- Prints vendor and device IDs (VID:PID) from `modalias`
- Shows active kernel driver and related `modinfo`
- Summarizes supported PHY modes, bands, and HT/VHT/HE/EHT capabilities
- Works on Volumio Bookworm builds, Raspberry Pi, x86, and generic Debian/Ubuntu systems

## Usage

1. Download and extract the script:

   ```bash
   wget https://github.com/YOURUSER/sys-hw-probe/raw/main/scripts/network/wifi-info.sh -O wifi-info.sh
   chmod +x wifi-info.sh
````

2. Run the script with root permissions:

   ```bash
   sudo ./wifi-info.sh
   ```

3. View the output:

   The script writes detailed information to:

   ```
   /tmp/wifi-info.log
   ```

## What to Attach or Share

To request support, please upload or paste the full contents of:

```
/tmp/wifi-info.log
```

This log will help us determine:

* Your WiFi interface type (USB, PCI, SDIO)
* Vendor and device ID (VID:PID)
* Active kernel module (e.g. `brcmfmac`, `rtl8821ce`)
* Whether the driver is supported in-tree or requires an external module
* Supported bands, PHY capabilities, and firmware details

## Sharing the Log

You can share your log file using Pastebin:

1. Install `pastebinit`:

   ```bash
   sudo apt-get install pastebinit
   ```

2. Upload the log:

   ```bash
   pastebinit /tmp/wifi-info.log
   ```

3. The command will return a link. Paste this link in your support request.

Alternatively, you can manually copy the file contents and paste them into [https://pastebin.com](https://pastebin.com).

## Example

Example snippet from `/tmp/wifi-info.log`:

```
--- Interface: wlan0 ---
Device path: /sys/devices/pci0000:00/0000:00:14.3
Bus info: pci
Modalias: pci:v00008086d000024FDsv00008086sd00009000bc02sc80i00
Extracted PCI VID:PID = 8086:24FD
Active kernel module: iwlwifi
filename:       /lib/modules/6.1.0-volumio/kernel/drivers/net/wireless/intel/iwlwifi/iwlwifi.ko
version:        5.19.2
Supported PHY modes:
   * managed
   * AP
Supported bands:
   Band 1: 2.4 GHz
Capabilities:
   HT, VHT, HE
```
