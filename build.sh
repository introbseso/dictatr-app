#!/bin/bash
# Compila Dictatr y monta Dictatr.app. Con "install" lo copia a /Applications.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=dist/Dictatr.app
rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Dictatr "$APP/Contents/MacOS/Dictatr"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

echo "✓ Bundle creado en $APP"

if [[ "${1:-}" == "install" ]]; then
    # Cerrar instancia anterior si existe
    pkill -x Dictatr 2>/dev/null || true
    rm -rf /Applications/Dictatr.app
    ditto "$APP" /Applications/Dictatr.app
    echo "✓ Instalado en /Applications/Dictatr.app"
    echo "  Nota: tras reinstalar, re-concede Accesibilidad Y Micrófono (la firma cambia)."
    echo "  Si el micro no pregunta de nuevo: tccutil reset Microphone com.dictatr.app"
fi
