#!/usr/bin/env bash
# wifi-info.sh — probe Wi-Fi interfaces: bus/ids, modalias, driver, PHY/bands/caps
# Author: sys-hw-probe contributors
# License: MIT
# Intent: Read-only diagnostics for Linux Wi-Fi (good for kiosks/media-player builds)

set -Eeuo pipefail

LOGFILE="/tmp/wifi-info.log"
JSON=0
IFACE_FILTER=""
APT=0

usage() {
  cat <<'USAGE'
wifi-info.sh — probe Wi-Fi interfaces: bus/ids, modalias, driver, PHY/bands/caps

Usage:
  wifi-info.sh [--iface IFACE] [--log FILE] [--json]
               [--install-deps] [--help]

Options:
  --iface IFACE       Only inspect this interface (e.g., wlan0)
  --log FILE          Write report to FILE (default: /tmp/wifi-info.log)
  --json              Emit JSON to stdout (log is still written)
  --install-deps      Install recommended user-space tools via apt (Debian/Ubuntu)
  --help              Show this help

Notes:
- Read-only. Needs: bash, grep, awk, sed. Better output if iw/udevadm/modinfo present.
- Falls back to /sys/class/net/*/wireless if 'iw dev' has no interfaces.
USAGE
}

have() { command -v "$1" >/dev/null 2>&1; }

install_deps() {
  if ! have apt-get; then
    echo "Requested --install-deps but apt-get not found; skipping." >&2
    return
  fi
  sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq || true
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    iw libinput-tools usbutils pciutils udev kmod 2>/dev/null || true
}

# Parse args
while (( $# )); do
  case "${1:-}" in
    --iface) IFACE_FILTER="${2:-}"; shift 2;;
    --log) LOGFILE="${2:-}"; shift 2;;
    --json) JSON=1; shift;;
    --install-deps) APT=1; shift;;
    --help|-h) usage; exit 0;;
    *) echo "Unknown option: $1" >&2; usage; exit 2;;
  esac
done

(( APT == 1 )) && install_deps

# Collect interfaces (prefer iw; fall back to /sys)
declare -a ifaces=()
if have iw && iw dev 2>/dev/null | grep -q '^Interface'; then
  while IFS= read -r line; do
    ifaces+=("$line")
  done < <(iw dev | awk '$1=="Interface"{print $2}')
else
  # /sys fallback: interfaces that have a 'wireless' dir
  while IFS= read -r d; do
    ifaces+=("$(basename "$d")")
  done < <(find /sys/class/net -maxdepth 2 -type d -name wireless -printf '%h\n' 2>/dev/null)
fi

# Filter if requested
if [[ -n "${IFACE_FILTER}" ]]; then
  tmp=()
  for i in "${ifaces[@]:-}"; do
    [[ "$i" == "$IFACE_FILTER" ]] && tmp+=("$i")
  done
  ifaces=("${tmp[@]:-}")
fi

# De-dup / sanity
declare -A seen=()
uniq_ifaces=()
for i in "${ifaces[@]:-}"; do
  [[ -n "${i:-}" && -z "${seen[$i]:-}" ]] || continue
  seen["$i"]=1
  uniq_ifaces+=("$i")
done
ifaces=("${uniq_ifaces[@]:-}")

# Helpers
read_modalias() {
  local devpath="$1"
  [[ -f "$devpath/modalias" ]] && cat "$devpath/modalias" || echo ""
}

bus_from_devpath() {
  local devpath="$1"
  if [[ -e "$devpath/subsystem" ]]; then
    basename "$(readlink -f "$devpath/subsystem")"
  else
    echo "unknown"
  fi
}

extract_vid_pid() {
  # args: modalias
  local m="$1" vid="" pid=""
  case "$m" in
    usb:*) vid="$(sed -n 's/.*v\([0-9A-Fa-f]\{4\}\).*/\1/p' <<<"$m")"
           pid="$(sed -n 's/.*p\([0-9A-Fa-f]\{4\}\).*/\1/p' <<<"$m")" ;;
    pci:*) vid="$(sed -n 's/.*v\([0-9A-Fa-f]\{4\}\).*/\1/p' <<<"$m")"
           pid="$(sed -n 's/.*d\([0-9A-Fa-f]\{4\}\).*/\1/p' <<<"$m")" ;;
    sdio:*) vid="$(sed -n 's/.*v\([0-9A-Fa-f]\{4\}\).*/\1/p' <<<"$m")"
            pid="$(sed -n 's/.*d\([0-9A-Fa-f]\{4\}\).*/\1/p' <<<"$m")" ;;
  esac
  printf '%s:%s\n' "${vid:-}" "${pid:-}"
}

active_driver() {
  local devpath="$1"
  if [[ -L "$devpath/driver" ]]; then
    basename "$(readlink -f "$devpath/driver")"
  else
    echo ""
  fi
}

modinfo_brief() {
  local drv="$1"
  if [[ -n "$drv" ]] && have modinfo; then
    modinfo "$drv" 2>/dev/null | grep -E '^(filename|version|description|srcversion|author|license):'
  fi
}

phy_of_iface() {
  local iface="$1"
  if have iw; then
    iw dev "$iface" info 2>/dev/null | awk '/wiphy/ {print "phy"$2; exit}'
  fi
}

phy_modes() {
  local phy="$1"
  have iw || return 0
  iw phy "$phy" info 2>/dev/null | awk '
    /Supported interface modes:/, /^[^ ]/ { if ($0 ~ /^\t\t/) print $0 }
  '
}

phy_bands_caps() {
  local phy="$1"
  have iw || return 0
  iw phy "$phy" info 2>/dev/null | grep -E "Band [0-9]|Capabilities:"
}

phy_ht_vht_he_eht() {
  local phy="$1"
  have iw || return 0
  iw phy "$phy" info 2>/dev/null | grep -E "HT |VHT |HE |EHT "
}

# Build report
{
  echo "Writing WiFi info to $LOGFILE"
  {
    echo "=== WiFi Interface Summary ==="
    if ((${#ifaces[@]:-0}==0)); then
      echo "(no wireless interfaces found)"
    fi

    for iface in "${ifaces[@]:-}"; do
      echo ""
      echo "--- Interface: $iface ---"
      local_path="/sys/class/net/$iface"
      dev_path="$(readlink -f "$local_path/device" 2>/dev/null || true)"
      [[ -z "${dev_path:-}" ]] && dev_path="(unknown)"
      echo "Device path: $dev_path"

      bus="$(bus_from_devpath "$dev_path")"
      echo "Bus info: ${bus}"

      echo "Physical device info:"
      if [[ -e "$dev_path" ]] && have udevadm; then
        udevadm info -q all -p "$dev_path" 2>/dev/null \
          | grep -E 'ID_VENDOR_ID=|ID_MODEL_ID=|ID_VENDOR=|ID_MODEL=|MODALIAS=' \
          || echo "(udevadm info not available)"
      else
        echo "(udevadm info not available)"
      fi

      modalias="$(read_modalias "$dev_path")"
      if [[ -n "$modalias" ]]; then
        echo "Modalias: $modalias"
      else
        echo "Modalias: (not available)"
      fi

      if [[ -n "$modalias" ]]; then
        vp="$(extract_vid_pid "$modalias")"
        if [[ "$vp" == ":" ]]; then
          echo "Extracted VID:PID = (n/a for this bus)"
        else
          echo "Extracted VID:PID = $vp"
        fi
      else
        echo "VID:PID extraction skipped (no modalias)"
      fi

      drv="$(active_driver "$dev_path")"
      if [[ -n "$drv" ]]; then
        echo "Active kernel module: $drv"
        modinfo_brief "$drv" || echo "(module info not available)"
      else
        echo "Active kernel module: (none bound)"
      fi

      phy="$(phy_of_iface "$iface" || true)"
      if [[ -n "$phy" ]]; then
        echo "PHY: $phy"
        echo "Supported PHY modes:"
        phy_modes "$phy" | sed 's/^/  /' || true

        echo "Supported bands:"
        phy_bands_caps "$phy" | sed 's/^/  /' || true

        echo "HT/VHT/HE/EHT capabilities:"
        phy_ht_vht_he_eht "$phy" | sed 's/^/  /' || true
      else
        echo "PHY: (unavailable; 'iw' missing or no wiphy reported)"
      fi
    done
  } >"$LOGFILE"
  echo "Log written to $LOGFILE"
} 1>&2

# Optional JSON to stdout
if (( JSON == 1 )); then
  have iw || true
  have udevadm || true
  have modinfo || true

  # Build very simple JSON (no jq dependency)
  echo "{"
  echo '  "interfaces": ['

  first=1
  for iface in "${ifaces[@]:-}"; do
    [[ $first -eq 0 ]] && echo "    ,"
    first=0

    local_path="/sys/class/net/$iface"
    dev_path="$(readlink -f "$local_path/device" 2>/dev/null || true)"
    [[ -z "${dev_path:-}" ]] && dev_path=""

    bus="$(bus_from_devpath "$dev_path")"
    modalias="$(read_modalias "$dev_path")"
    vp="$(extract_vid_pid "$modalias")"
    vid="${vp%%:*}"; pid="${vp#*:}"
    drv="$(active_driver "$dev_path")"
    phy="$(phy_of_iface "$iface" || true)"

    # Escape function for JSON strings
    jescape() { sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }

    echo "    {"
    printf '      "iface": "%s",\n' "$(printf %s "$iface" | jescape)"
    printf '      "device_path": "%s",\n' "$(printf %s "$dev_path" | jescape)"
    printf '      "bus": "%s",\n' "$(printf %s "$bus" | jescape)"
    printf '      "modalias": "%s",\n' "$(printf %s "$modalias" | jescape)"
    printf '      "vid": "%s",\n' "$(printf %s "$vid" | jescape)"
    printf '      "pid": "%s",\n' "$(printf %s "$pid" | jescape)"
    printf '      "driver": "%s",\n' "$(printf %s "$drv" | jescape)"
    printf '      "phy": "%s",\n' "$(printf %s "$phy" | jescape)"

    # Inline summaries (shortened)
    if [[ -n "$phy" && $(have iw; echo $?) -eq 0 ]]; then
      modes="$(phy_modes "$phy" | sed 's/^[[:space:]]*//;s/"/\\"/g' | paste -sd ';' -)"
      bands="$(phy_bands_caps "$phy" | sed 's/"/\\"/g' | paste -sd ';' -)"
      caps="$(phy_ht_vht_he_eht "$phy" | sed 's/"/\\"/g' | paste -sd ';' -)"
    else
      modes=""; bands=""; caps=""
    fi
    printf '      "modes": "%s",\n' "$modes"
    printf '      "bands": "%s",\n' "$bands"
    printf '      "caps": "%s"\n' "$caps"
    echo -n "    }"
  done
  echo
  echo "  ]"
  echo "}"
fi
