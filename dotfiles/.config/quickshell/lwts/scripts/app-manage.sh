#!/bin/bash
# app-manage.sh <desktop-id> uninstall|reset - run in a terminal by Settings -> Apps -> Manage.
# Uninstall = the package manager's own confirmation (pacman lists what goes with it); no --noconfirm anywhere.
id="$1"; mode="$2"
case "$id" in ""|*/*|*..*) echo "Bad id"; read -rp "Enter to close" _; exit 1;; esac
f=""
for d in /usr/share/applications /var/lib/flatpak/exports/share/applications "$HOME/.local/share/flatpak/exports/share/applications"; do
  [ -f "$d/$id.desktop" ] && { f="$d/$id.desktop"; break; }
done
if [ "$mode" = reset ]; then
  d="$HOME/.var/app/$id"
  if [ -d "$d" ]; then
    du -sh "$d"; read -rp "Delete all data of $id ($d)? [y/N] " a
    [ "$a" = y ] && rm -rf -- "$d" && echo "Done."
  else
    echo "No separate data folder: only Flatpak apps keep their data in ~/.var/app/<id>."
  fi
else
  case "$f" in
    */flatpak/*) flatpak uninstall "$id" ;;
    "")          echo "$id.desktop not found in the system folders (a per-user app?)" ;;
    *)           p=$(pacman -Qoq "$f" 2>/dev/null | head -1)
                 if [ -n "$p" ]; then sudo pacman -Rns "$p"; else echo "$f is not owned by a package"; fi ;;
  esac
fi
read -rp "Enter to close" _
