#!/usr/bin/env bash
# Instalador de Olimpo para macOS/Linux.
# Uso: curl -fsSL https://raw.githubusercontent.com/luisafricano/Olimpo/main/install.sh | bash
#
# Copia los archivos de sesion compartida Zeus/Claude/Hefesto a los lugares
# donde OpenCode y Claude Code los leen, y deja `hermes` disponible en el
# PATH (~/.local/bin). Correr de nuevo este mismo script actualiza todo.

set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/luisafricano/Olimpo/main"
REPO_RAW_FALLBACK="https://brexum.ar/repos/Olimpo"
OPENCODE_CONFIG="$HOME/.config/opencode"
CLAUDE_SKILLS="$HOME/.claude/skills"
LOCAL_BIN="$HOME/.local/bin"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ES_LOCAL=0
[ -d "$SCRIPT_DIR/payload" ] && ES_LOCAL=1

obtener() {
    # obtener <ruta relativa en el repo> <destino>
    local origen="$1" destino="$2"
    mkdir -p "$(dirname "$destino")"
    if [ "$ES_LOCAL" = "1" ]; then
        cp "$SCRIPT_DIR/$origen" "$destino"
        return
    fi
    local intentos=3 i espera
    for (( i=1; i<=intentos; i++ )); do
        if curl -fsSL "$REPO_RAW/$origen" -o "$destino"; then
            return
        fi
        if [ "$i" -eq "$intentos" ]; then
            curl -fsSL "$REPO_RAW_FALLBACK/$origen" -o "$destino"
            return
        fi
        espera=$(( 2 ** i ))
        sleep "$espera"
    done
}

quitar_lock() { [ -f "$1" ] && chmod u+w "$1" 2>/dev/null || true; }
aplicar_lock() { chmod 444 "$1"; }

echo "[Olimpo] Instalando/actualizando..."

declare -A PAYLOAD=(
    ["payload/bin/hermes.py"]="$LOCAL_BIN/hermes.py"
    ["payload/opencode-rules/hefesto.md"]="$OPENCODE_CONFIG/rules/hefesto.md"
    ["payload/opencode-skills/hefesto/SKILL.md"]="$OPENCODE_CONFIG/skills/hefesto/SKILL.md"
    ["payload/claude-skills/olimpo/SKILL.md"]="$CLAUDE_SKILLS/olimpo/SKILL.md"
    ["payload/claude-skills/olimpout/SKILL.md"]="$CLAUDE_SKILLS/olimpout/SKILL.md"
    ["payload/claude-skills/oloop/SKILL.md"]="$CLAUDE_SKILLS/oloop/SKILL.md"
    ["payload/claude-skills/noloop/SKILL.md"]="$CLAUDE_SKILLS/noloop/SKILL.md"
)

mostrar_progreso() {
    # mostrar_progreso <paso actual> <total>
    # No se usa 'tr' para armar la barra: son caracteres UTF-8 de mas de un
    # byte (█/░) y 'tr' opera byte a byte, los corrompe. Se arma con un loop.
    local actual="$1" total="$2"
    local pct=$(( actual * 100 / total ))
    local llenas=$(( pct / 5 ))
    local vacias=$(( 20 - llenas ))
    local barra_llena="" barra_vacia="" i
    for (( i=0; i<llenas; i++ )); do barra_llena+="█"; done
    for (( i=0; i<vacias; i++ )); do barra_vacia+="░"; done
    printf "\r[Olimpo] [%s%s] %d%%\033[K" "$barra_llena" "$barra_vacia" "$pct"
}

total="${#PAYLOAD[@]}"
actual=0
for origen in "${!PAYLOAD[@]}"; do
    actual=$(( actual + 1 ))
    mostrar_progreso "$actual" "$total"
    destino="${PAYLOAD[$origen]}"
    quitar_lock "$destino"
    obtener "$origen" "$destino"
done
echo ""

# Registrar el archivo de instructions en la config de OpenCode sin pisar el
# resto (provider/model que ya tenga configurado el usuario). Requiere
# python3 (ya es una dependencia del proyecto para correr hermes).
CONFIG_JSON="$OPENCODE_CONFIG/config.json"
mkdir -p "$OPENCODE_CONFIG"
python3 - "$CONFIG_JSON" <<'PY'
import json, sys, os

path = sys.argv[1]
entry = os.path.expanduser("~/.config/opencode/rules/hefesto.md")
entry = "~/.config/opencode/rules/hefesto.md"

if os.path.exists(path):
    with open(path, "r", encoding="utf-8") as f:
        config = json.load(f)
else:
    config = {}

instructions = config.get("instructions") or []
if entry not in instructions:
    instructions.append(entry)
config["instructions"] = instructions

with open(path, "w", encoding="utf-8") as f:
    json.dump(config, f, indent=2)
PY

# Shim ejecutable para poder llamar "hermes" en vez de "python3 hermes.py".
HERMES_SHIM="$LOCAL_BIN/hermes"
quitar_lock "$HERMES_SHIM"
cat > "$HERMES_SHIM" <<EOF
#!/usr/bin/env bash
exec python3 "$LOCAL_BIN/hermes.py" "\$@"
EOF
chmod +x "$HERMES_SHIM"

case ":$PATH:" in
    *":$LOCAL_BIN:"*) ;;
    *) echo "[Olimpo] Agregá $LOCAL_BIN a tu PATH (no está hoy) — ej. en ~/.bashrc o ~/.zshrc: export PATH=\"$LOCAL_BIN:\$PATH\"" ;;
esac

# Lock de escritura: protege los archivos instalados de una escritura
# accidental (por ejemplo, de Hefesto mismo) fuera del flujo de instalacion.
for destino in "${PAYLOAD[@]}"; do
    aplicar_lock "$destino"
done
chmod 555 "$HERMES_SHIM"  # r-x, no w: el lock no puede sacarle el bit de ejecucion al shim

if [ "$ES_LOCAL" = "1" ]; then
    VERSION="$(cat "$SCRIPT_DIR/VERSION")"
else
    VERSION="$(curl -fsSL "$REPO_RAW/VERSION" || curl -fsSL "$REPO_RAW_FALLBACK/VERSION")"
fi
mkdir -p "$HOME/.olimpo"
echo "$VERSION" > "$HOME/.olimpo/VERSION"

echo ""
echo "[Olimpo] Instalación completada."
echo "[Olimpo] Versión instalada: $VERSION."
echo "[Olimpo] Corré 'hermes' en cualquier proyecto para arrancar."
echo "[Olimpo] Para actualizar, volvé a correr este mismo instalador."
