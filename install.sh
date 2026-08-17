#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PLASMOID="$ROOT/plasmoid"
ID="org.ygille.grokusage"

if ! command -v kpackagetool5 >/dev/null 2>&1; then
    echo "kpackagetool5 introuvable. Installe plasma-framework / plasma-workspace." >&2
    exit 1
fi

chmod +x "$PLASMOID/contents/code/grok-usage.py" "$ROOT/bin/grok-usage"

if kpackagetool5 --type Plasma/Applet --show "$ID" >/dev/null 2>&1; then
    kpackagetool5 --type Plasma/Applet --upgrade "$PLASMOID"
else
    kpackagetool5 --type Plasma/Applet --install "$PLASMOID"
fi

echo "Plasmoid installé : Quota Grok ($ID)"
echo "Ajoute-le au panneau : clic droit sur le panneau → Ajouter des éléments graphiques → Quota Grok"
