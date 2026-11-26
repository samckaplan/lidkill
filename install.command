#!/bin/bash
# Double-click this in Finder to install lidkill.
cd "$(dirname "$0")" || exit 1

clear
printf '\n  lidkill installer\n'
printf '  -----------------\n\n'

./lidkill install || { echo; read -n 1 -s -r -p "Press any key to close."; exit 1; }

echo
read -n 1 -s -r -p "Press any key to close this window."
