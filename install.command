#!/bin/bash
# Double-click this in Finder to install lidkill.
cd "$(dirname "$0")" || exit 1

clear
printf '\n  lidkill installer\n'
printf '  -----------------\n\n'

./lidkill install || { echo; read -n 1 -s -r -p "Press any key to close."; exit 1; }

echo
printf 'Arm it now? Closing the lid will power this Mac off. [y/N] '
read -r ans
case "$ans" in
    y|Y|yes|YES) ./lidkill on ;;
    *) echo "Skipped. You can arm it later with:  lidkill on" ;;
esac

echo
read -n 1 -s -r -p "Press any key to close this window."
