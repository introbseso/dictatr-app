#!/bin/bash
# Instalador de Dictatr. Compila desde el fuente si hay Xcode Command Line Tools;
# si no, descarga el binario precompilado de la última Release.
# La API key de Groq se pasa por entorno (GROQ_API_KEY=...) o se pregunta.
set -euo pipefail
cd "$(dirname "$0")"

REPO="introbseso/dictatr-app"
APP="/Applications/Dictatr.app"

echo "› Dictatr — instalación"

# 1. Requisitos
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "✗ Dictatr solo funciona en macOS." >&2; exit 1
fi
if [[ "$(uname -m)" != "arm64" ]]; then
  echo "✗ Dictatr requiere un Mac con Apple Silicon (M1 o posterior)." >&2; exit 1
fi
if (( $(sw_vers -productVersion | cut -d. -f1) < 14 )); then
  echo "✗ Dictatr requiere macOS 14 (Sonoma) o posterior." >&2; exit 1
fi

# 2. Compilar o descargar binario
if xcode-select -p &>/dev/null; then
  echo "› Command Line Tools detectadas — compilando desde el fuente…"
  ./build.sh install
else
  echo "› Sin Xcode Command Line Tools. Descargando binario precompilado…"
  tmp="$(mktemp -d)"
  if curl -fsSL "https://github.com/$REPO/releases/latest/download/Dictatr.app.zip" -o "$tmp/Dictatr.zip"; then
    ditto -x -k "$tmp/Dictatr.zip" "$tmp"
    pkill -x Dictatr 2>/dev/null || true
    rm -rf "$APP"
    ditto "$tmp/Dictatr.app" "$APP"
    xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
    echo "✓ Instalado desde Release en $APP"
  else
    echo "✗ No pude descargar el binario. Instala las Command Line Tools:" >&2
    echo "    xcode-select --install" >&2
    echo "  y vuelve a ejecutar ./install.sh" >&2
    exit 1
  fi
fi

# 3. API key en ~/.dictatr/config.json
DICTATR_DIR="$HOME/.dictatr"
CONFIG="$DICTATR_DIR/config.json"
mkdir -p "$DICTATR_DIR"

has_key=false
if [[ -f "$CONFIG" ]] && grep -q '"groq_api_key"[[:space:]]*:[[:space:]]*"gsk' "$CONFIG"; then
  has_key=true
fi

key="${GROQ_API_KEY:-}"
if [[ "$has_key" == false && -z "$key" ]]; then
  if [[ -t 0 ]]; then
    echo ""
    echo "› Necesitas una API key gratuita de Groq: https://console.groq.com/keys"
    read -r -p "  Pega tu key de Groq (gsk_...): " key
  else
    # Sin terminal interactiva (p. ej. un agente ejecutando el script): no bloquear
    echo "⚠ Sin GROQ_API_KEY y sin terminal interactiva — la key no se guardó."
    echo "  Re-ejecuta con: GROQ_API_KEY=gsk_... ./install.sh"
  fi
fi

if [[ "$has_key" == true ]]; then
  echo "✓ API key ya presente en $CONFIG"
elif [[ -n "$key" ]]; then
  if [[ ! "$key" =~ ^[A-Za-z0-9_-]+$ ]]; then
    echo "⚠ La key contiene caracteres inesperados — no se guardó. Añádela a mano en $CONFIG."
  elif [[ -f "$CONFIG" ]]; then
    # La app pudo crear el config con key vacía (si se abrió antes de instalar): insertarla in situ
    if grep -qE '"groq_api_key"[[:space:]]*:[[:space:]]*""' "$CONFIG"; then
      sed -i '' -E 's|"groq_api_key"([[:space:]]*):([[:space:]]*)""|"groq_api_key"\1:\2"'"$key"'"|' "$CONFIG"
      chmod 600 "$CONFIG"
      echo "✓ API key añadida a $CONFIG"
    else
      echo "⚠ Existe $CONFIG con formato no reconocido. Añade la key a mano: menú de Dictatr → Abrir carpeta de configuración."
    fi
  else
    printf '{\n  "groq_api_key": "%s"\n}\n' "$key" > "$CONFIG"
    chmod 600 "$CONFIG"
    echo "✓ API key guardada en $CONFIG (600). La app completa el resto del config al arrancar."
  fi
fi

# 4. Abrir la app y recordar los pasos manuales
open "$APP" || true
cat <<'EOF'

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Dictatr instalado y abierto (icono de micro en la barra de menús).
Faltan 3 pasos que macOS obliga a hacer a mano:

1. TECLA 🌐/fn: Ajustes → Teclado → "Pulsar tecla 🌐 para" → "No hacer nada".
2. ACCESIBILIDAD: Ajustes → Privacidad y seguridad → Accesibilidad → activa
   Dictatr. Luego RELÁNZALA (sal por el menú del micro y vuelve a abrirla).
3. MICRÓFONO: acepta el diálogo la primera vez que dictes.

Prueba: cursor en un campo de texto, MANTÉN fn, habla, SUELTA.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
