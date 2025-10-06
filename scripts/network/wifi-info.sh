#!/bin/bash

LOGFILE="/tmp/wifi-info.log"
echo "Writing WiFi info to $LOGFILE"
echo "=== WiFi Interface Summary ===" > "$LOGFILE"

iw dev | awk '$1=="Interface"{print $2}' | while read -r iface; do
  {
    echo ""
    echo "--- Interface: $iface ---"

    IFACE_PATH="/sys/class/net/$iface"
    DEV_PATH=$(readlink -f "$IFACE_PATH/device")

    echo "Device path: $DEV_PATH"

    # Bus type (usb, pci, sdio)
    if [ -e "$DEV_PATH/subsystem" ]; then
      BUS=$(basename $(readlink -f "$DEV_PATH/subsystem"))
      echo "Bus info: $BUS"
    else
      BUS="unknown"
      echo "Bus info: (unknown)"
    fi

    echo "Physical device info:"
    if [ -e "$DEV_PATH" ]; then
      udevadm info -q all -p "$DEV_PATH" | grep -E 'ID_VENDOR_ID|ID_MODEL_ID|ID_VENDOR|ID_MODEL|MODALIAS' || echo "(udevadm info not available)"
    else
      echo "(device path not found)"
    fi

    # Extract and show modalias
    if [ -f "$DEV_PATH/modalias" ]; then
      MODALIAS=$(cat "$DEV_PATH/modalias")
      echo "Modalias: $MODALIAS"
    else
      MODALIAS=""
      echo "Modalias: (not available)"
    fi

    # Parse VID:PID for USB/PCI/SDIO
    if [[ "$MODALIAS" == usb:* ]]; then
      VID=$(echo "$MODALIAS" | sed -n 's/.*v\([0-9A-Fa-f]\{4\}\).*/\1/p')
      PID=$(echo "$MODALIAS" | sed -n 's/.*p\([0-9A-Fa-f]\{4\}\).*/\1/p')
      echo "Extracted USB VID:PID = $VID:$PID"
    elif [[ "$MODALIAS" == pci:* ]]; then
      VID=$(echo "$MODALIAS" | sed -n 's/.*v\([0-9A-Fa-f]\{4\}\).*/\1/p')
      PID=$(echo "$MODALIAS" | sed -n 's/.*d\([0-9A-Fa-f]\{4\}\).*/\1/p')
      echo "Extracted PCI VID:PID = $VID:$PID"
    elif [[ "$MODALIAS" == sdio:* ]]; then
      VID=$(echo "$MODALIAS" | sed -n 's/.*v\([0-9A-Fa-f]\{4\}\).*/\1/p')
      PID=$(echo "$MODALIAS" | sed -n 's/.*d\([0-9A-Fa-f]\{4\}\).*/\1/p')
      echo "Extracted SDIO VID:PID = $VID:$PID"
    else
      echo "VID:PID extraction not supported for modalias type"
    fi

    # Detect active kernel module
    if [ -L "$DEV_PATH/driver" ]; then
      DRIVER_NAME=$(basename "$(readlink -f "$DEV_PATH/driver")")
      echo "Active kernel module: $DRIVER_NAME"

      # Show modinfo details for active module
      modinfo "$DRIVER_NAME" 2>/dev/null | grep -E 'filename|version|description|srcversion|author|license' || echo "(module info not available)"
    else
      echo "Active kernel module: (none bound)"
    fi

    # Detect PHY and wireless capabilities
    PHY=$(iw dev $iface info | awk '/wiphy/ {print "phy"$2}')
    echo "Supported PHY modes:"
    iw phy "$PHY" info | grep -A5 "Supported interface modes" | sed 's/^/  /'

    echo "Supported bands:"
    iw phy "$PHY" info | grep -E "Band [0-9]|Capabilities:" | sed 's/^/  /'

    echo "HT/VHT/HE capabilities:"
    iw phy "$PHY" info | grep -E "HT |VHT |HE |EHT " | sed 's/^/  /'

  } >> "$LOGFILE"
done

echo "Log written to $LOGFILE"
