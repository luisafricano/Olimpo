#!/usr/bin/env bash
# Desinstalador de Olimpo para macOS/Linux.
# Uso: curl -fsSL https://raw.githubusercontent.com/luisafricano/Olimpo/main/uninstall.sh | bash
#      curl -fsSL .../uninstall.sh | bash -s -- --yes   (sin pedir confirmacion)
#
# Espejo inverso de install.sh: saca exactamente lo que ese instalador puso
# (mismo PAYLOAD, mismo shim, misma entrada de config.json) y nada mas. Si
# install.sh agrega un archivo nuevo al payload, hay que agregarlo tambien
# aca para que no quede huerfano.
#
# No toca los transcripts de sesiones reales (logs/*.md bajo el config_dir
# de OpenCode) — son contenido del usuario, no archivos de instalacion.

set -euo pipefail

OPENCODE_CONFIG="$HOME/.config/opencode"
CLAUDE_SKILLS="$HOME/.claude/skills"
LOCAL_BIN="$HOME/.local/bin"
OLIMPO_HOME="$HOME/.olimpo"

FORCE=0
for arg in "$@"; do
    case "$arg" in
        --yes|-y|--force) FORCE=1 ;;
    esac
done

declare -A PAYLOAD=(
    ["payload/bin/hermes.py"]="$LOCAL_BIN/hermes.py"
    ["payload/opencode-rules/hefesto.md"]="$OPENCODE_CONFIG/rules/hefesto.md"
    ["payload/opencode-skills/hefesto/SKILL.md"]="$OPENCODE_CONFIG/skills/hefesto/SKILL.md"
    ["payload/claude-skills/olimpo/SKILL.md"]="$CLAUDE_SKILLS/olimpo/SKILL.md"
    ["payload/claude-skills/olimpout/SKILL.md"]="$CLAUDE_SKILLS/olimpout/SKILL.md"
    ["payload/claude-skills/oloop/SKILL.md"]="$CLAUDE_SKILLS/oloop/SKILL.md"
    ["payload/claude-skills/noloop/SKILL.md"]="$CLAUDE_SKILLS/noloop/SKILL.md"
)
HERMES_SHIM="$LOCAL_BIN/hermes"

quitar_lock() { [ -e "$1" ] && chmod u+w "$1" 2>/dev/null || true; }

# hermes.py resuelve el config_dir real via 'opencode debug paths' (puede no
# coincidir con ~/.config/opencode si el usuario tiene XDG_CONFIG_HOME u
# otra config). Intentamos lo mismo; si opencode no esta disponible o falla,
# caemos al default que usa install.sh.
resolver_config_dir() {
    if command -v opencode >/dev/null 2>&1; then
        local linea
        linea="$(opencode debug paths 2>/dev/null | awk '$1=="config" {$1=""; sub(/^ /,""); print; exit}')"
        if [ -n "$linea" ]; then
            echo "$linea"
            return
        fi
    fi
    echo "$OPENCODE_CONFIG"
}

echo "[Olimpo] Se va a desinstalar lo siguiente:"
echo "  - $OLIMPO_HOME (binario hermes, shim, VERSION)"
for destino in "${PAYLOAD[@]}"; do echo "  - $destino"; done
echo "  - $CLAUDE_SKILLS/olimpo/, olimpout/, oloop/, noloop/"
echo "  - La entrada de Olimpo en config.json (instructions)"
echo "  - El estado operativo de sesiones (hermes_sessions/)"
echo ""
echo "[Olimpo] NO se va a tocar: los transcripts de sesiones (logs/*.md)."
echo ""

if [ "$FORCE" != "1" ]; then
    read -r -p "Confirmar desinstalación? (s/N) " resp
    case "$resp" in
        s|S) ;;
        *) echo "[Olimpo] Cancelado, no se borró nada."; exit 0 ;;
    esac
fi

# Archivos del payload + shim.
for destino in "${PAYLOAD[@]}"; do
    quitar_lock "$destino"
    rm -f "$destino"
done
quitar_lock "$HERMES_SHIM"
rm -f "$HERMES_SHIM"

# Carpeta de la skill de Hefesto en OpenCode.
if [ -d "$OPENCODE_CONFIG/skills/hefesto" ]; then
    chmod -R u+w "$OPENCODE_CONFIG/skills/hefesto" 2>/dev/null || true
    rm -rf "$OPENCODE_CONFIG/skills/hefesto"
fi

# Carpetas de las 4 skills de Claude.
for nombre in olimpo olimpout oloop noloop; do
    carpeta="$CLAUDE_SKILLS/$nombre"
    if [ -d "$carpeta" ]; then
        chmod -R u+w "$carpeta" 2>/dev/null || true
        rm -rf "$carpeta"
    fi
done

# ~/.olimpo completo (bin/hermes.py, bin/hermes, VERSION).
if [ -d "$OLIMPO_HOME" ]; then
    chmod -R u+w "$OLIMPO_HOME" 2>/dev/null || true
    rm -rf "$OLIMPO_HOME"
fi

# Entrada de Olimpo en config.json, sin tocar el resto (providers/modelos/
# otras instructions que el usuario haya agregado). Requiere python3 (ya es
# una dependencia del proyecto para correr hermes).
CONFIG_JSON="$OPENCODE_CONFIG/config.json"
if [ -f "$CONFIG_JSON" ]; then
    python3 - "$CONFIG_JSON" <<'PY'
import json, sys

path = sys.argv[1]
entry = "~/.config/opencode/rules/hefesto.md"

with open(path, "r", encoding="utf-8") as f:
    config = json.load(f)

instructions = config.get("instructions") or []
if entry in instructions:
    config["instructions"] = [i for i in instructions if i != entry]
    with open(path, "w", encoding="utf-8") as f:
        json.dump(config, f, indent=2)
PY
fi

# Estado operativo puro de hermes.py (no son transcripts, son solo el
# puntero a la sesion activa por proyecto). Los logs/*.md quedan intactos.
CONFIG_DIR_REAL="$(resolver_config_dir)"
SESSIONS_DIR="$CONFIG_DIR_REAL/hermes_sessions"
[ -d "$SESSIONS_DIR" ] && rm -rf "$SESSIONS_DIR"

echo ""
echo "[Olimpo] Desinstalado."
echo "[Olimpo] Los transcripts de sesiones (si los hay) quedaron en $CONFIG_DIR_REAL/logs — no se tocaron."
echo "[Olimpo] Si agregaste $LOCAL_BIN a tu PATH a mano (.bashrc/.zshrc), podés sacarlo vos — el desinstalador no lo tocó."
