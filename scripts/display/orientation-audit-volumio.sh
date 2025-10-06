#!/bin/bash
# orientation-audit-volumio.sh
#
# sys-hw-probe: Display orientation & input audit for Linux kiosks (x86 & Raspberry Pi).
#
# Intent:
#   - Report kernel/X compositor orientation, DRM connectors, EDID presence,
#     input devices, and Raspberry Pi config (config.txt family).
#   - Highlight conflicts (fbcon vs panel vs compositor) and provide hints.
#
# Author: sys-hw-probe contributors
# License: MIT (see repository LICENSE)
# Safe by default: read-only; `--install-deps` only installs missing tools.
#
# Usage:
#   orientation-audit-volumio.sh [--install-deps] [--no-root]
#   sudo orientation-audit-volumio.sh --install-deps   # install helper packages
#
# Notes:
#   - Wayland sessions show Xwayland views under `xrandr`.
#   - Raspberry Pi support detects vc4 KMS/FKMS/legacy and common DSI/DPI panels.
#   - EDID summary prints if `edid-decode` is present.
#
#!/bin/bash
# orientation-audit-volumio.sh
# Volumio Bookworm rotation and input audit for x86 and Raspberry Pi kiosks.
# Adds Pi config parsing for hdmi_group/mode, hdmi_cvt, DPI overlays with rotation,
# DSI/SPI panel overlays detection, and EDID collection/decoding per connector.

set -u
set -o pipefail

INSTALL_DEPS=0
NO_ROOT=0

for arg in "$@"; do
  case "$arg" in
    --install-deps) INSTALL_DEPS=1 ;;
    --no-root) NO_ROOT=1 ;;
    -h|--help)
      echo "Usage: $0 [--install-deps] [--no-root]"
      exit 0
      ;;
    *) ;;
  esac
done

have() { command -v "$1" >/dev/null 2>&1; }
# Avoid noisy output if dpkg is missing (non-Debian) or the status file isn't there
pkg_present() {
  if ! have dpkg; then return 0; fi
  dpkg -s "$1" >/dev/null 2>&1
}

need_sudo() {
  if [ "$INSTALL_DEPS" -eq 1 ] && [ "$NO_ROOT" -eq 0 ] && [ "${EUID:-1}" -ne 0 ]; then
    echo "Please run with sudo for --install-deps, or drop the flag."
    exit 1
  fi
}

maybe_install() {
  local pkgs=()
  for p in "$@"; do
    if ! pkg_present "$p"; then pkgs+=("$p"); fi
  done
  if [ "$INSTALL_DEPS" -eq 1 ] && [ "${#pkgs[@]}" -gt 0 ]; then
    if have apt-get; then
      apt-get update -y
      DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs[@]}"
    fi
  fi
}

hr()  { printf "%s\n" "----------------------------------------"; }
say() { printf "%s\n" "$*"; }

# Declare arrays so set -u does not fail later
declare -A CONN_STATUS
declare -A CONN_MODES
declare -A CONN_PANEL_ORIENT
declare -A CONN_PANEL_DEG
declare -A XRANDR_ROT_STR
declare -A XRANDR_ROT_DEG
declare -A CONN_EDID_SUMMARY

deg_from_fbcon() {
  case "${1:-}" in
    0) echo 0;;
    1) echo 90;;
    2) echo 180;;
    3) echo 270;;
    *) echo unknown;;
  esac
}

deg_from_panel_orientation() {
  case "${1,,}" in
    normal) echo 0;;
    left_side_up|left-up|left_up) echo 90;;
    upside_down|inverted|bottom_up) echo 180;;
    right_side_up|right-up|right_up) echo 270;;
    *) echo unknown;;
  esac
}

deg_from_xrandr() {
  case "${1,,}" in
    normal) echo 0;;
    left) echo 90;;
    inverted) echo 180;;
    right) echo 270;;
    *) echo unknown;;
  esac
}

mod360_add() {
  local a="$1" b="$2"
  if [[ "$a" == "unknown" || "$b" == "unknown" ]]; then
    echo unknown
  else
    echo $(( (a + b) % 360 ))
  fi
}

summarize_group_mode() {
  # Input: group, mode, cvt_line(optional)
  # Output: human note like: Group CEA mode 16 or DMT mode 82, or CVT custom
  local g="${1:-}" m="${2:-}" cvt="${3:-}"
  if [ -n "$cvt" ]; then
    # Example hdmi_cvt=1366 768 60 3 0 0 1
    local w h r a marg i rb
    w="$(echo "$cvt" | awk -F= '{print $2}' | awk '{print $1}')"
    h="$(echo "$cvt" | awk -F= '{print $2}' | awk '{print $2}')"
    r="$(echo "$cvt" | awk -F= '{print $2}' | awk '{print $3}')"
    a="$(echo "$cvt" | awk -F= '{print $2}' | awk '{print $4}')"
    marg="$(echo "$cvt" | awk -F= '{print $2}' | awk '{print $5}')"
    i="$(echo "$cvt" | awk -F= '{print $2}' | awk '{print $6}')"
    rb="$(echo "$cvt" | awk -F= '{print $2}' | awk '{print $7}')"
    echo "CVT custom ${w}x${h}@${r} aspect=${a} margins=${marg} interlace=${i} reduced-blanking=${rb}"
    return
  fi
  case "$g" in
    1) echo "Group CEA mode ${m} (HDMI TV timings)";;
    2) echo "Group DMT mode ${m} (PC monitor timings)";;
    0|"") echo "Auto group/mode";;
    *) echo "Group ${g} mode ${m}";;
  esac
}

# ---------- Raspberry Pi helpers (extended) ----------
detect_pi_stack() {
  # Gather Pi config files if present (quiet on non-Pi hosts)
  local files=()
  for f in /boot/config.txt /boot/userconfig.txt /boot/volumioconfig.txt; do
    [ -f "$f" ] && files+=("$f")
  done

  if [ ${#files[@]} -eq 0 ]; then
    echo "No Pi config files found; likely not Raspberry Pi OS (or configs not mounted)."
    return 0
  fi

  # Lowercased, comments stripped
  local cfg
  cfg="$(sed -e 's/#.*$//' "${files[@]}" 2>/dev/null | tr '[:upper:]' '[:lower:]')"

  # Extract overlay names (base token before any comma/params)
  local overlays
  overlays="$(printf "%s\n" "$cfg" | sed -nE 's/.*\bdtoverlay=([^,[:space:]]*).*/\1/p')"

  # Determine graphics stack
  local stack="Legacy/Unknown (no vc4 overlay)"
  local stack_detail=""
  if printf "%s\n" "$overlays" | grep -Eq '^vc4-kms-v3d(-pi4|-pi5)?$'; then
    stack="KMS"
    stack_detail="$(printf "%s\n" "$overlays" | grep -Eo '^vc4-kms-v3d(-pi4|-pi5)?$' | head -n1)"
  elif printf "%s\n" "$overlays" | grep -Eq '^vc4-fkms-v3d$'; then
    stack="FKMS"
    stack_detail="vc4-fkms-v3d"
  fi

  # DSI panel hints
  local dsi_matches
  dsi_matches="$(printf "%s\n" "$overlays" | grep -E \
    '(^|^,)(vc4-kms-dsi|panel-|rpi-ft5406|rpi_touchscreen|rpi-backlight|tc3587(62|68)|ili9(881|401|406)|st77(01|89)|otm8009a|nt35510|s6e3|jd[0-9]+|khadas-ts050|waveshare.*dsi)' \
    || true)"

  # DPI (parallel RGB) hints
  local dpi_overlay dpi_keys dpi_enabled="no"
  dpi_overlay="$(printf "%s\n" "$overlays" | grep -E '(^|^,)(dpi|rpi-dpi|ltn101nt05|auo_|raspberrypi-dpi)' || true)"
  dpi_keys="$(printf "%s\n" "$cfg" | grep -E '(^|\s)enable_dpi_lcd=1|(^|\s)dpi_[a-z_]+=|(^|\s)display_default_lcd=1' || true)"
  [ -n "$dpi_overlay" ] || [ -n "$dpi_keys" ] && dpi_enabled="yes"

  # SPI/fbtft style panels
  local spi_matches
  spi_matches="$(printf "%s\n" "$overlays" | grep -E \
    '(waveshare|pitft|fbtft|fb_ili9341|ili93(41|28)|st77(35|89)|st7789|ssd13(06|11)|gc9a01|hx8357|ili9486|ili9488|adafruit.*tft)' \
    || true)"

  # HDMI timing hints
  local hdmi_keys="no"
  printf "%s\n" "$cfg" | grep -Eq '(^|\s)hdmi_(group|mode|cvt|timings)=' && hdmi_keys="yes"

  # Helper: dedupe preserving order
  summarize_list() {
    awk 'NF && !seen[$0]++' | tr '\n' ',' | sed -e 's/,$//'
  }

  local dsi_list dpi_list spi_list
  dsi_list="$(printf "%s\n" "$dsi_matches" | summarize_list)"
  dpi_list="$(printf "%s\n" "$dpi_overlay" | summarize_list)"
  spi_list="$(printf "%s\n" "$spi_matches" | summarize_list)"

  local parts=()
  parts+=("Stack: ${stack}${stack_detail:+ [$stack_detail]}")
  parts+=("DSI overlays: ${dsi_list:-none}")
  parts+=("DPI: ${dpi_enabled}${dpi_list:+ (overlays: $dpi_list)}")
  parts+=("SPI panels: ${spi_list:-none}")
  parts+=("HDMI timing keys: ${hdmi_keys}")

  echo "${parts[*]//  / }"
}

parse_pi_overlays_and_rotation() {
  local file="$1"
  [ -f "$file" ] || return
  local lines
  lines="$(grep -Ei '^\s*dtoverlay=' "$file" 2>/dev/null | sed -E 's/#.*$//; s/^[ \t]+//; s/[ \t]+$//' | sed '/^$/d')"
  [ -n "$lines" ] || return
  echo "Overlays with potential rotation from $file:"
  echo "$lines" | while IFS= read -r l; do
    local ov params rot orient
    ov="$(echo "$l" | cut -d= -f2 | cut -d, -f1)"
    params="$(echo "$l" | cut -d= -f2- | cut -d, -f2-)"
    rot="$(echo "$params" | grep -o 'rotate=[^, ]*' || true)"
    orient="$(echo "$params" | grep -o 'orientation=[^, ]*' || true)"
    if echo "$ov" | grep -Eq '^dpi|^tc358|^ili|^waveshare|^tinylcd|^goodix|^edt-ft5x06|^rpi-dpi|^panel'; then
      echo "  overlay=$ov params=$params $rot $orient"
    elif echo "$params" | grep -Eq 'rotate=|orientation='; then
      echo "  overlay=$ov params=$params $rot $orient"
    fi
  done
}

parse_pi_hdmi_section() {
  local file="$1"
  [ -f "$file" ] || return
  local g m cvt
  g="$(grep -E '^\s*hdmi_group\s*=' "$file" 2>/dev/null | tail -n1 | awk -F= '{gsub(/[ \t]/,"",$2); print $2}')"
  m="$(grep -E '^\s*hdmi_mode\s*='  "$file" 2>/dev/null | tail -n1 | awk -F= '{gsub(/[ \t]/,"",$2); print $2}')"
  cvt="$(grep -E '^\s*hdmi_cvt\s*='   "$file" 2>/dev/null | tail -n1)"
  if [ -n "${g}${m}${cvt}" ]; then
    local note
    note="$(summarize_group_mode "$g" "$m" "$cvt")"
    echo "  $(basename "$file"): ${note}"
  fi
}

need_sudo

# Minimal but useful tools
maybe_install drm-info libdrm-tests x11-xserver-utils xinput libinput-tools evtest usbutils pciutils udev jq edid-decode

CMDLINE="$(cat /proc/cmdline 2>/dev/null || true)"
SESSION_TYPE="${XDG_SESSION_TYPE:-}"
if [ "${SESSION_TYPE:-}" = "wayland" ] && have xrandr; then
  echo "Note: Wayland session detected; xrandr shows Xwayland views, not compositor transforms."
fi

DISPLAY_VAR="${DISPLAY:-}"
WAYLAND_VAR="${WAYLAND_DISPLAY:-}"

FBCON_ROT_RAW="$(grep -o 'fbcon=rotate:[0-3]' <<<"$CMDLINE" | head -n1 || true)"
FBCON_ROT_IDX="${FBCON_ROT_RAW#fbcon=rotate:}"
FBCON_ROT_DEG="$(deg_from_fbcon "${FBCON_ROT_IDX:-}")"
VIDEO_PARAMS="$(grep -o 'video=[^ ]*' <<<"$CMDLINE" | tr '\n' ' ' || true)"

if have plymouth-set-default-theme; then
  PLYMOUTH_MODE="$(plymouth-set-default-theme 2>/dev/null | awk '/theme/{print $NF}' || echo unknown)"
  echo "Plymouth theme:"
  echo "  ${PLYMOUTH_MODE:-unknown}"
else
  echo "Plymouth:"
  echo "  plymouth not installed"
  PLYMOUTH_MODE="unknown"
fi

DMESG_PANEL="$(dmesg 2>/dev/null | grep -i 'panel_orientation' || true)"
DMESG_QUIRK="$(dmesg 2>/dev/null | grep -i 'quirk' | grep -Ei 'panel|backlight' || true)"
DMESG_FB="$(dmesg 2>/dev/null | grep -E 'efifb|simpledrm|drmfb|fbcon' | tail -n 50 || true)"

# Enumerate DRM connectors via sysfs
for st in /sys/class/drm/*/status; do
  [ -e "$st" ] || continue
  conn="$(basename "$(dirname "$st")")"
  status="$(cat "$st" 2>/dev/null || echo unknown)"
  CONN_STATUS["$conn"]="$status"
  if [ -f "/sys/class/drm/$conn/modes" ]; then
    CONN_MODES["$conn"]="$(head -n 5 /sys/class/drm/$conn/modes 2>/dev/null | tr '\n' ' ' )"
  else
    CONN_MODES["$conn"]="n/a"
  fi
done

# Panel orientation from drm_info or modetest
if have drm_info; then
  JSON="$(drm_info 2>/dev/null || true)"
  for conn in "${!CONN_STATUS[@]}"; do
    block="$(printf "%s\n" "$JSON" | awk -v c="$conn" 'BEGIN{RS=""} $0 ~ c {print; exit}')"
    ori="$(printf "%s\n" "$block" | grep -i 'panel orientation' | head -n1 | awk -F: '{gsub(/^[ \t]+/,"",$2); print $2}')"
    [ -n "$ori" ] || ori="unknown"
    CONN_PANEL_ORIENT["$conn"]="$ori"
    CONN_PANEL_DEG["$conn"]="$(deg_from_panel_orientation "$ori")"
  done
elif have modetest; then
  MT="$(modetest -c 2>/dev/null || true)"
  for conn in "${!CONN_STATUS[@]}"; do
    block="$(printf "%s\n" "$MT" | awk -v c="$conn" 'BEGIN{RS=""} $0 ~ c {print; exit}')"
    ori="$(printf "%s\n" "$block" | grep -i 'panel.*orientation' | head -n1 | awk -F: '{print $NF}' | tr -d ' ')"
    [ -n "$ori" ] || ori="unknown"
    CONN_PANEL_ORIENT["$conn"]="$ori"
    CONN_PANEL_DEG["$conn"]="$(deg_from_panel_orientation "$ori")"
  done
else
  for conn in "${!CONN_STATUS[@]}"; do
    CONN_PANEL_ORIENT["$conn"]="unknown"
    CONN_PANEL_DEG["$conn"]="unknown"
  done
fi

# --- EDID collection and decoding (robust & quiet) ---
TMP_EDID_DIR="$(mktemp -d /tmp/edid-XXXXXX)"

# Scan any 'edid' file up to 3 levels below /sys/class/drm
mapfile -t EDID_FILES < <(find /sys/class/drm -maxdepth 3 -type f -name edid 2>/dev/null || true)

if [ "${#EDID_FILES[@]}" -gt 0 ]; then
  for ed in "${EDID_FILES[@]}"; do
    conn="$(basename "$(dirname "$ed")")"
    if [ -s "$ed" ]; then
      if have edid-decode; then
        sum="$(edid-decode "$ed" 2>/dev/null | awk '
          /Preferred mode:/ {pref=$0}
          /Detailed mode:/  {det=$0}
          /Manufacturer:/   {man=$0}
          END {
            if(pref!=""){print pref}
            else if(det!=""){print det}
            if(man!=""){print man}
          }')"
        [ -n "$sum" ] || sum="edid present, could not parse summary"
        CONN_EDID_SUMMARY["$conn"]="$sum"
      else
        out="$TMP_EDID_DIR/$conn.bin"
        cat "$ed" > "$out" 2>/dev/null || true
        CONN_EDID_SUMMARY["$conn"]="edid present (install edid-decode for details)"
      fi
    else
      if [ -e "$ed" ]; then
        CONN_EDID_SUMMARY["$conn"]="edid node present but empty"
      else
        CONN_EDID_SUMMARY["$conn"]="no edid node"
      fi
    fi
  done
fi

# Xorg state via xrandr (if available)
if [ -n "${DISPLAY_VAR:-}" ] && have xrandr; then
  XR="$(xrandr --verbose 2>/dev/null || true)"
  while read -r name rest; do
    [[ "$rest" =~ connected ]] || continue
    rot="$(printf "%s\n" "$XR" | awk -v n="$name" '
      $0 ~ "^"n" " && $0 ~ /connected/ {
        for(i=1;i<=NF;i++){
          if($i ~ /^(normal|left|right|inverted)$/){print $i; exit}
        }
      }')"
    [ -n "$rot" ] || rot="unknown"
    XRANDR_ROT_STR["$name"]="$rot"
    XRANDR_ROT_DEG["$name"]="$(deg_from_xrandr "$rot")"
  done < <(printf "%s\n" "$XR" | awk '/ connected/{print $1" "$0}')
fi

# Inputs: libinput, xinput, evdev, udev
LIBINPUT_LIST="$(libinput list-devices 2>/dev/null || true)"
XINPUT_LIST="$(xinput --list 2>/dev/null || true)"
EVDEV_DEVICES="$(grep -H "" /proc/bus/input/devices 2>/dev/null || true)"
UDEV_TOUCH=""
if [ -d /dev/input/by-path ]; then
  for n in $(ls /dev/input/by-path 2>/dev/null | grep -E 'event|mouse' || true); do
    UDEV_TOUCH+=$(udevadm info -q property -n "/dev/input/by-path/$n" 2>/dev/null; echo -e "\n")
  done
fi

# Chromium kiosk hints
CHROMIUM_CMD="$(ps -eo pid,cmd | grep -E 'chromium|chrome' | grep -v grep || true)"

# Raspberry Pi specific
PI_CFG_DIR="/boot"
PI_FILES=("$PI_CFG_DIR/config.txt" "$PI_CFG_DIR/volumioconfig.txt" "$PI_CFG_DIR/userconfig.txt")

parse_pi_file_core() {
  local f="$1"
  [ -f "$f" ] || return
  echo "File: $f"
  grep -Ei '^\s*(dtoverlay|display_rotate|lcd_rotate|hdmi_group|hdmi_mode|hdmi_cvt|hdmi_drive|disable_overscan|overscan_|framebuffer_(width|height)|enable_dpi_lcd|dpi_|gpu_mem)\s*=' "$f" 2>/dev/null \
    | sed -E 's/#.*$//; s/^[ \t]+//; s/[ \t]+$//' \
    | sed '/^$/d'
  echo
  parse_pi_hdmi_section "$f"
  parse_pi_overlays_and_rotation "$f"
}

# Helper: map sysfs connector (cardX-FOO-Y) to plain name (FOO-Y) for display
plain_conn_name() {
  echo "${1#card*-}"
}

# Output
echo
hr
say "Orientation audit for Volumio Bookworm"
hr
say "Kernel cmdline:"
say "  $CMDLINE"
hr
say "fbcon:"
say "  fbcon=rotate index: ${FBCON_ROT_IDX:-none}"
say "  fbcon degrees:      $FBCON_ROT_DEG"
hr
say "video= parameters:"
say "  ${VIDEO_PARAMS:-none}"
hr
say "Plymouth:"
if [ "${PLYMOUTH_MODE:-unknown}" = "unknown" ]; then
  say "  plymouth not installed"
else
  say "  ${PLYMOUTH_MODE}"
fi
hr
say "dmesg orientation and quirk hints:"
if [ -n "$DMESG_PANEL" ]; then echo "$DMESG_PANEL"; else say "  no panel_orientation messages"; fi
if [ -n "$DMESG_QUIRK" ]; then echo "$DMESG_QUIRK"; else say "  no panel/backlight quirk messages"; fi
hr
say "Framebuffer and DRM handoff (last lines):"
echo "$DMESG_FB"
hr
say "DRM connectors:"
for c in "${!CONN_STATUS[@]}"; do
  printf "%-20s status=%-12s panel_orientation=%-14s (%s deg) modes: %s\n" \
    "$c" "${CONN_STATUS[$c]}" "${CONN_PANEL_ORIENT[$c]}" "${CONN_PANEL_DEG[$c]}" "${CONN_MODES[$c]}"
done
hr
say "EDID per connector:"
if [ "${#EDID_FILES[@]}" -eq 0 ]; then
  say "  no EDID nodes found under /sys/class/drm"
else
  # Show EDID summary for known connectors; if missing, say so
  for c in "${!CONN_STATUS[@]}"; do
    if [ -n "${CONN_EDID_SUMMARY[$c]+x}" ]; then
      echo "  $c:"
      echo "    ${CONN_EDID_SUMMARY[$c]}"
    fi
  done
  # Also show any EDID nodes that belong to connectors we didn't enumerate (rare)
  for ed in "${EDID_FILES[@]}"; do
    conn="$(basename "$(dirname "$ed")")"
    if [ -z "${CONN_STATUS[$conn]+x}" ]; then
      echo "  $conn:"
      if [ -n "${CONN_EDID_SUMMARY[$conn]+x}" ]; then
        echo "    ${CONN_EDID_SUMMARY[$conn]}"
      else
        echo "    edid present (no summary)"
      fi
    fi
  done
fi
hr
if [ -n "${DISPLAY_VAR:-}" ] && [ "${#XRANDR_ROT_DEG[@]}" -gt 0 ]; then
  say "Xorg xrandr rotation:"
  for n in "${!XRANDR_ROT_DEG[@]}"; do
    printf "  %-16s rotation=%-10s (%s deg)\n" "$n" "${XRANDR_ROT_STR[$n]}" "${XRANDR_ROT_DEG[$n]}"
  done
else
  say "Xorg xrandr rotation: not available or no DISPLAY"
fi
hr
say "Input devices via libinput:"
if [ -n "$LIBINPUT_LIST" ]; then
  echo "$LIBINPUT_LIST"
else
  say "  libinput list-devices not available"
fi
hr
say "Input devices via xinput:"
if [ -n "$XINPUT_LIST" ]; then
  echo "$XINPUT_LIST"
else
  say "  xinput not available or no X session"
fi
hr
say "Evdev devices summary:"
if [ -n "$EVDEV_DEVICES" ]; then
  echo "$EVDEV_DEVICES"
else
  say "  evdev device list not available"
fi
hr
say "Udev properties for inputs (by-path):"
if [ -n "$UDEV_TOUCH" ]; then
  echo "$UDEV_TOUCH"
else
  say "  no /dev/input/by-path entries found"
fi
hr
say "Chromium kiosk processes (if any):"
if [ -n "$CHROMIUM_CMD" ]; then
  echo "$CHROMIUM_CMD"
else
  say "  chromium not detected"
fi
hr

# Raspberry Pi files section
say "Raspberry Pi stack detection:"
say "  $(detect_pi_stack)"
hr
say "Parsing Raspberry Pi config files:"
for f in "${PI_FILES[@]}"; do
  parse_pi_file_core "$f"
done
hr
say "Raspberry Pi rotation guidance:"
say "  - On KMS or FKMS, prefer kernel panel_orientation and xrandr over legacy display_rotate or lcd_rotate."
say "  - Legacy keys can conflict with KMS rotation paths."
say "  - If dpi overlays specify rotate or orientation, treat them as kernel-level hints."

# Heuristic summary and suggestions
PRIMARY="eDP-1"
if [ -z "${CONN_STATUS[$PRIMARY]+x}" ]; then
  for c in "${!CONN_STATUS[@]}"; do
    if [ "${CONN_STATUS[$c]}" = "connected" ]; then PRIMARY="$c"; break; fi
  done
fi

# Also compute a plain xrandr-style name hint
PRIMARY_XORG="$(plain_conn_name "$PRIMARY")"

KERNEL_DEG="${CONN_PANEL_DEG[$PRIMARY]:-unknown}"
COMPOSITOR_DEG="unknown"
if [ -n "${DISPLAY_VAR:-}" ] && [ -n "${XRANDR_ROT_DEG[$PRIMARY_XORG]+x}" ]; then
  COMPOSITOR_DEG="${XRANDR_ROT_DEG[$PRIMARY_XORG]}"
fi
NET_CONSOLE_DEG="$FBCON_ROT_DEG"
NET_GUI_DEG="$(mod360_add "$KERNEL_DEG" "$COMPOSITOR_DEG")"

hr
say "Effective orientation summary:"
printf "  Primary connector: %s (xorg name: %s)\n" "$PRIMARY" "$PRIMARY_XORG"
printf "  Console (fbcon):   %s deg\n" "$NET_CONSOLE_DEG"
printf "  GUI (kernel panel_orientation + compositor): %s deg\n" "$NET_GUI_DEG"
hr
say "Suggestions:"
if [ "$KERNEL_DEG" != "unknown" ] && [ "$FBCON_ROT_DEG" != "unknown" ] && [ "$KERNEL_DEG" != "$FBCON_ROT_DEG" ]; then
  say "  - Kernel panel_orientation and fbcon differ. Align values to avoid boot mismatch."
fi
if [ "$KERNEL_DEG" != "unknown" ] && [ "$COMPOSITOR_DEG" != "unknown" ] && [ "$COMPOSITOR_DEG" != "0" ]; then
  say "  - Compositor is rotating on top of kernel orientation. Remove compositor rotation or clear panel_orientation."
fi
if [ -z "$DMESG_PANEL" ] && [ "${CONN_PANEL_ORIENT[$PRIMARY]:-unknown}" = "unknown" ]; then
  say "  - No orientation property found. If device is known rotated, check drm_panel_orientation_quirks.c or set via video=<conn>:panel_orientation=..."
fi
say "  - On Raspberry Pi, remove legacy display_rotate or lcd_rotate when using KMS to prevent conflicts."
say "  - Touch calibration: prefer a single 3x3 coordinate transformation matrix and derive other angles."
say "  - Backlight quirks: if brightness behaves oddly, check drm_panel_backlight_quirks.c and prefer DRM native backlight path."

# Cleanup temp
rm -rf "$TMP_EDID_DIR" 2>/dev/null || true

exit 0
