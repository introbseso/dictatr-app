# Dictatr

Clon minimalista de [Wispr Flow](https://wisprflow.ai/) para macOS. **Mantén pulsada la tecla fn, habla, suelta** — y el texto transcrito y limpio aparece en la app donde tengas el foco.

- STT: Groq `whisper-large-v3-turbo` (autodetección español/inglés)
- Limpieza ligera: Groq `llama-3.3-70b-versatile` (quita muletillas, corrige puntuación, respeta tus palabras)
- Latencia típica: 1.5–2.5s desde que sueltas fn
- Coste: free tier de Groq — uso personal ≈ $0

## Requisitos

- macOS 14+ (Apple Silicon)
- Command Line Tools de Xcode para compilar (opcional: sin ellas, `install.sh` usa el binario precompilado)
- API key gratuita de [console.groq.com](https://console.groq.com/keys)

## Instalación

Necesitas un Mac con Apple Silicon (macOS 14+) y una API key gratuita de [Groq](https://console.groq.com/keys).

### Opción A — con Claude Code (recomendada)

Clona el repo, ábrelo con Claude Code y dile **"instálalo"**. Te guía por todo (compilar, permisos, key).

### Opción B — a mano

```bash
git clone https://github.com/introbseso/dictatr-app.git
cd dictatr-app
./install.sh
```

`install.sh` compila desde el fuente si tienes las Command Line Tools de Xcode (`xcode-select --install`), o baja el binario precompilado de la última Release si no. Luego pide la key de Groq e imprime los 3 pasos manuales (tecla 🌐, Accesibilidad, Micrófono) — detallados abajo.

## Setup único (5 minutos)

1. **Tecla 🌐/fn del sistema:** Ajustes → Teclado → "Pulsar tecla 🌐 para" → **"No hacer nada"**. Si no, cada pulsación abrirá el selector de emojis o el dictado nativo de macOS.
2. **Micrófono:** acepta el diálogo la primera vez que Dictatr intente grabar.
3. **Accesibilidad:** Ajustes → Privacidad y seguridad → Accesibilidad → activa Dictatr. Necesario para escuchar la tecla fn y simular Cmd+V. **Relanza la app después de concederlo.**
4. **Configuración:** `install.sh` ya guardó tu API key. Para cambiarla o ajustar opciones: menú de Dictatr (icono de micro en la barra) → "Abrir carpeta de configuración" → edita `config.json`:

```json
{
  "groq_api_key": "gsk_...",
  "sounds": true,
  "language": null,
  "hotkey": "fn",
  "app_tones": {
    "net.whatsapp.WhatsApp": "casual",
    "com.apple.mail": "profesional"
  },
  "rewrite_hotkey": "right_option",
  "history_days": 30
}
```

`rewrite_hotkey` = modificador de **acorde** para reescribir: se mantiene junto a `hotkey` (mismos valores posibles; si coinciden, la reescritura se desactiva). Solo, no hace nada. `history_days` = rotación del historial y de `failed/` (0 = conservar todo).

Al arrancar, la app añade automáticamente cualquier campo nuevo que falte (auto-migración): nunca hay que reconstruir el config a mano.

`language: null` = autodetección por dictado. Fuerza `"es"` o `"en"` si la autodetección te falla en dictados muy cortos.

`hotkey` = tecla de dictado: `"fn"`, `"right_command"` (⌘ derecha), `"right_option"` (⌥ derecha), `"right_shift"` (⇧ derecha) o `"right_control"` (⌃ derecha). **Los teclados externos (Logitech, etc.) procesan fn en su firmware y macOS nunca la ve** — si usas teclado externo, usa un modificador derecho. Ojo: algunos teclados externos tampoco distinguen izquierda/derecha en ciertos modificadores (⌥ es la que más falla); si una tecla no responde, prueba otra. Cambiar de tecla requiere relanzar la app. Los mismos valores sirven para `rewrite_hotkey`.

5. **Arranque automático:** menú de Dictatr → "Arrancar al iniciar sesión".

## Uso

Pon el cursor donde quieras escribir, **mantén fn**, habla, **suelta fn**. Sonido "pop" al empezar a grabar, "glass" cuando el texto se pega.

- Pulsaciones de fn de menos de 0.5s se ignoran (anti-accidentes).
- fn+otra tecla (fn+flecha, etc.) cancela la grabación: se trata como atajo, no como dictado.
- El clipboard anterior se restaura solo tras el pegado (solo texto plano).

## Tonos por app (v0.2)

El texto se limpia con un registro distinto según la app con foco al soltar la tecla. `app_tones` mapea bundle ID → tono:

| Tono | Comportamiento |
|---|---|
| `neutral` | El estándar (apps no mapeadas) |
| `casual` | Mensajería: conserva coloquialismos, no formaliza |
| `profesional` | Email: puntuación completa, sin inventar saludos |
| `tecnico` | Prompts/terminal: términos técnicos y rutas tal cual, sin cortesías |
| `verbatim` | Pega la transcripción cruda, sin LLM (los comandos de formato no aplican) |

Para mapear una app nueva: menú de Dictatr → **"Copiar bundle ID de la app activa"** (copia el de la app donde estabas) y añádelo a `app_tones`. Limitación: las web apps comparten el bundle ID del navegador — Gmail web no se distingue de otra pestaña.

## Comandos de formato (v0.2)

Dictables en español o inglés; el LLM interpreta la intención.

**Comandos siempre activos:**

| Dices | Produce |
|---|---|
| punto y aparte · nuevo párrafo · new paragraph | párrafo nuevo |
| nueva línea · salto de línea · new line | salto de línea |
| punto final · punto seguido · full stop | `.` |
| punto y coma | `;` |
| puntos suspensivos · dot dot dot | `…` |
| abre comillas … cierra comillas · entre comillas X · open/close quote · in quotes | `"X"` |
| abre paréntesis … cierra paréntesis · entre paréntesis X · open/close parenthesis | `(X)` |
| interrogante · signo de interrogación · question mark | `¿…?` |
| exclamación · signo de exclamación · exclamation mark | `¡…!` |
| guion bajo · underscore | `_` |
| arroba · at sign | `@` |
| almohadilla · hashtag | `#` |
| en mayúsculas X · all caps X | `X` en mayúsculas |

**Solo si el contexto deja claro que dictas puntuación** (son palabras comunes): "punto"/"period", "coma"/"comma", "dos puntos"/"colon", "guion"/"dash", "barra"/"slash".

**Automáticos:** enumeraciones dictadas ("primero…, segundo…") → lista con guiones; emails y dominios ("ana arroba gmail punto com" → ana@gmail.com).

Para ampliar el vocabulario: añadir la frase a `commandPhrases` en `GroqAPI.swift` **y** al prompt de la misma función — un test de sincronía obliga a que ambos estén alineados.

## Reescritura de selección (v0.3)

Selecciona texto en cualquier app, **mantén ⌘ derecha + ⇧ derecha** (dictado + acorde), dicta la instrucción y suelta: el resultado reemplaza la selección. Tu clipboard se restaura solo.

- El acorde funciona en cualquier orden, e incluso a mitad de dictado: si ya grabas con ⌘ y añades ⇧, el gesto escala a reescritura (icono lápiz). Una vez escalado es pegajoso: puedes soltar ⇧ y seguir con solo ⌘.
- El modificador de acorde **no hace nada por sí solo** — pulsar ⇧ derecha fuera del gesto ni suena ni graba.

- Casos de uso: tono ("hazlo más formal"), corrección ("corrige la ortografía"), traducción ES/EN/CAT ("tradúcelo al catalán").
- Sin texto seleccionado → sonido de error + notificación; nada se pega.
- Icono de lápiz en la barra mientras grabas la instrucción.
- Guardarraíl propio: si el resultado supera 3× las palabras de la selección (+40), se descarta (queda en `history.jsonl` con `guard_rejected`).
- Deshacer: Cmd+Z en la app restaura el texto original (y queda en `selection` dentro del historial).
- **Contenido adulto:** el prompt deja claro que editar texto existente del usuario no es generarlo, lo que elimina la mayoría de rechazos del modelo. Si aun así el modelo se niega, Dictatr lo detecta: tu selección queda intacta (nunca la reemplaza una disculpa), suena error y el rechazo queda en el historial. Puedes probar otro modelo con `"rewrite_model"` en config (p. ej. `"qwen/qwen3-32b"`) sin recompilar.

## Privacidad (v0.3)

- `config.json` (API key) e `history.jsonl` con permisos 600 — solo tu usuario.
- El WAV temporal de cada dictado se borra al terminar de procesarlo.
- Historial y `failed/` rotan a los `history_days` días (default 30).
- El pasteboard va marcado como `ConcealedType`: los gestores de portapapeles (Raycast, Paste…) no archivan tus dictados.

## Ficheros (`~/.dictatr/`)

| Fichero | Qué es |
|---|---|
| `config.json` | API key, sonidos, idioma. Se relee en cada dictado (editable sin reiniciar) |
| `dictionary.txt` | Un término por línea (nombres propios, siglas…). Whisper y la limpieza los escriben tal cual |
| `history.jsonl` | Historial: timestamp, transcripción cruda y versión limpia |
| `failed/` | WAVs de dictados cuya transcripción falló — nada se pierde |

## Troubleshooting

| Síntoma | Causa probable |
|---|---|
| No pasa nada al pulsar fn | Falta permiso de Accesibilidad, o no relanzaste la app tras concederlo |
| fn no funciona en teclado externo | El firmware del teclado se queda la tecla; usa `"hotkey": "right_command"` |
| Se come palabras o repeticiones | La limpieza LLM se pasó de agresiva; hay guardarraíl (si pierde >40% de palabras se pega la transcripción cruda). Compara `raw` vs `clean` en `history.jsonl` para confirmar el culpable |
| El tono no cambia según la app | Bundle ID no mapeado en `app_tones` — usa el menú "Copiar bundle ID de la app activa" |
| La reescritura no hace nada | ¿Hay texto seleccionado? ¿Accesibilidad concedida tras la última recompilación? ¿`rewrite_hotkey` distinto de `hotkey`? |
| La reescritura pegó algo raro | Mira la entrada `tone: "rewrite"` en `history.jsonl`: `selection` (original), `raw` (instrucción) y `clean` (resultado) |
| fn abre el selector de emojis | Paso 1 del setup pendiente |
| Suena el pop pero no pega texto | Falta API key en `config.json`, o sin internet (mira el menú: muestra el último error) |
| No graba / "No se pudo empezar a grabar" | Falta permiso de Micrófono |
| Tras recompilar dejó de funcionar | La firma ad-hoc cambia con cada build: re-concede Accesibilidad |
| Transcribe "www.feyyaz.tv" u otra frase fantasma | El micro grabó silencio (alucinación de Whisper). Causa típica: permiso de Micrófono invalidado tras recompilar — macOS no re-pregunta, entrega silencio. Fix: `tccutil reset Microphone com.dictatr.app` y relanzar. La app ahora detecta el silencio y avisa en vez de alucinar |

## Desarrollo

```bash
swift build              # compilar
swift run DictatrTests   # tests (aserciones simples, sin XCTest)
./build.sh               # bundle en dist/ sin instalar
```

## Parking lot (ideas futuras, fuera del MVP)

Modo toggle, selector de idioma fn+ctrl, comandos de voz ("punto y aparte"), reescritura IA de texto seleccionado, historial con UI, overlay flotante, key en Keychain, reprocesado de `failed/`.
