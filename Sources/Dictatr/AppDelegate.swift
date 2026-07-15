import AppKit
import DictatrCore
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum State { case idle, recording, processing }
    private enum Mode { case dictation, rewrite }

    private let paths = DictatrPaths()
    private var hotkey: HotkeyMonitor!
    private var hotkeySpec = HotkeySpec.from("fn")
    private var mode: Mode = .dictation
    private var rewriteEnabled = false
    private var rewriteSpec = HotkeySpec.from("right_option")
    private let notifier = Notifier()
    private var recorder: Recorder!
    private var statusItem: NSStatusItem!
    private var state: State = .idle { didSet { updateIcon() } }
    private var lastError: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Config.bootstrap(paths: paths)
        recorder = Recorder(tmpDir: paths.tmpDir)
        let config = Config.load(paths: paths)
        notifier.soundsEnabled = config.sounds
        hotkeySpec = HotkeySpec.from(config.hotkey)  // cambiar de tecla requiere relanzar
        rewriteSpec = HotkeySpec.from(config.rewriteHotkey)
        rewriteEnabled = config.rewriteHotkey != config.hotkey
        // Un único monitor: primaria sola = dictar; primaria + acorde = reescribir.
        // El modificador de acorde (⇧ der) no hace nada por sí solo.
        hotkey = HotkeyMonitor(spec: hotkeySpec, chord: rewriteEnabled ? rewriteSpec : nil)

        setupStatusItem()
        notifier.requestPermission()

        if !HotkeyMonitor.ensureAccessibilityPermission() {
            // El diálogo del sistema ya se mostró; el monitor no funcionará hasta conceder + relanzar
            lastError = "Concede Accesibilidad en Ajustes → Privacidad y relanza Dictatr"
            rebuildMenu()
        }
        Recorder.requestMicPermission { ok in
            if !ok {
                self.lastError = "Sin permiso de micrófono (Ajustes → Privacidad → Micrófono)"
                self.rebuildMenu()
            }
        }

        hotkey.onKeyDown = { [weak self] in
            guard let self else { return }
            if self.hotkey.chordIsDown { self.startRewrite() } else { self.startDictation() }
        }
        hotkey.onKeyUp = { [weak self] in
            guard let self else { return }
            if self.mode == .rewrite { self.finishRewrite() } else { self.finishDictation() }
        }
        hotkey.onChordDown = { [weak self] in
            // Escalada a mitad de dictado: añadir el acorde convierte el gesto en
            // reescritura. Pegajoso: soltar el acorde no lo revierte.
            guard let self, self.state == .recording, self.mode == .dictation else { return }
            self.mode = .rewrite
            self.updateIcon()
        }
        hotkey.onOtherKeyWhileDown = { [weak self] in self?.cancelDictation() }
        hotkey.start()

        if !rewriteEnabled {
            lastError = "rewrite_hotkey coincide con hotkey — reescritura desactivada"
        }

        // Rotación de historial y failed/ según history_days
        HistoryLog(file: paths.historyFile).prune(olderThanDays: config.historyDays, failedDir: paths.failedDir)
        rebuildMenu()
    }

    // MARK: - Dictado

    private func startDictation() {
        guard state == .idle else { return }
        mode = .dictation
        guard recorder.start() else {
            fail("No se pudo empezar a grabar", "¿Permiso de micrófono concedido?")
            return
        }
        state = .recording
        notifier.playStart()
    }

    private func startRewrite() {
        guard state == .idle else { return }
        mode = .rewrite
        guard recorder.start() else {
            fail("No se pudo empezar a grabar", "¿Permiso de micrófono concedido?")
            return
        }
        state = .recording
        notifier.playStart()
    }

    // Fin de ciclo común: borra el WAV temporal (privacidad) y vuelve a reposo
    private func finishCycle() {
        recorder.removeTempFile()
        state = .idle
        rebuildMenu()
    }

    private func cancelDictation() {
        guard state == .recording else { return }
        recorder.cancel()
        state = .idle
    }

    private func finishDictation() {
        guard state == .recording, mode == .dictation else { return }
        guard let (wav, duration) = recorder.stop(), duration >= 0.5 else {
            finishCycle()  // pulsación accidental: descarte silencioso
            return
        }
        guard !WavAnalyzer.isSilent(wav: wav) else {
            // Buffers a cero = permiso de micro invalidado (típico tras recompilar)
            fail("El micrófono no captó audio", "Re-concede Micrófono en Ajustes → Privacidad y relanza")
            finishCycle()
            return
        }
        state = .processing
        let config = Config.load(paths: paths)  // se relee en cada dictado: editable sin reiniciar
        notifier.soundsEnabled = config.sounds
        let dictionary = Config.loadDictionary(paths: paths)
        let client = GroqClient(apiKey: config.groqApiKey)
        // La app con foco decide el tono; se captura antes de procesar
        let frontApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        Task { @MainActor in
            do {
                let raw = try await client.transcribe(wav: wav, dictionary: dictionary, language: config.language)
                let tone = Tones.toneFor(bundleId: frontApp, appTones: config.appTones)
                let result: (text: String, rejected: String?)
                if tone == "verbatim" {
                    result = (raw, nil)
                } else {
                    result = await client.cleanup(text: raw, dictionary: dictionary, tone: tone)
                }
                Paster.paste(result.text)
                HistoryLog(file: self.paths.historyFile).append(raw: raw, clean: result.text, app: frontApp ?? "?", tone: tone, rejected: result.rejected)
                self.notifier.playSuccess()
                self.lastError = nil
            } catch GroqError.emptyTranscription {
                self.fail("No se entendió nada", "El audio no contenía voz reconocible")
            } catch {
                self.recorder.preserveFailed(in: self.paths.failedDir)
                self.fail("Dictado fallido — audio guardado en ~/.dictatr/failed/", error.localizedDescription)
            }
            self.finishCycle()
        }
    }

    private func finishRewrite() {
        guard state == .recording, mode == .rewrite else { return }
        guard let (wav, duration) = recorder.stop(), duration >= 0.5 else {
            finishCycle()
            return
        }
        guard !WavAnalyzer.isSilent(wav: wav) else {
            fail("El micrófono no captó audio", "Re-concede Micrófono en Ajustes → Privacidad y relanza")
            finishCycle()
            return
        }
        state = .processing
        let config = Config.load(paths: paths)
        notifier.soundsEnabled = config.sounds
        let dictionary = Config.loadDictionary(paths: paths)
        let client = GroqClient(apiKey: config.groqApiKey)
        let frontApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        Task { @MainActor in
            do {
                let previousClipboard = NSPasteboard.general.string(forType: .string)
                guard let selection = await SelectionGrabber.grab(),
                      !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    self.fail("No había texto seleccionado", "Selecciona texto antes de mantener la tecla de reescritura")
                    self.finishCycle()
                    return
                }
                let instruction = try await client.transcribe(wav: wav, dictionary: dictionary, language: config.language)
                let result = try await client.rewrite(text: selection, instruction: instruction, model: config.rewriteModel)
                if let text = result.text {
                    Paster.paste(text, restoring: previousClipboard)
                    HistoryLog(file: self.paths.historyFile).append(raw: instruction, clean: text, app: frontApp ?? "?", tone: "rewrite", selection: selection)
                    self.notifier.playSuccess()
                    self.lastError = nil
                } else {
                    // Guardarraíl: no pegar; devolver el clipboard original al usuario
                    if let previousClipboard {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(previousClipboard, forType: .string)
                    }
                    HistoryLog(file: self.paths.historyFile).append(raw: instruction, clean: selection, app: frontApp ?? "?", tone: "rewrite", rejected: result.rejected, selection: selection)
                    self.fail("Reescritura descartada — tu texto está intacto", "El modelo se negó o devolvió algo sospechoso; mira history.jsonl")
                }
            } catch GroqError.emptyTranscription {
                self.fail("No se entendió la instrucción", "El audio no contenía voz reconocible")
            } catch {
                self.fail("Reescritura fallida", error.localizedDescription)
            }
            self.finishCycle()
        }
    }

    private func fail(_ title: String, _ detail: String) {
        lastError = "\(title): \(detail)"
        notifier.playError()
        notifier.notify(title: title, body: detail)
        state = .idle
        rebuildMenu()
    }

    // MARK: - UI

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateIcon()
        rebuildMenu()
    }

    private func updateIcon() {
        let (symbol, desc): (String, String)
        switch state {
        case .idle: (symbol, desc) = ("mic", "Dictatr listo")
        case .recording: (symbol, desc) = mode == .rewrite ? ("pencil.circle.fill", "Grabando instrucción") : ("mic.fill", "Grabando")
        case .processing: (symbol, desc) = ("ellipsis.circle", "Procesando")
        }
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: desc)
        img?.isTemplate = true
        statusItem.button?.image = img
        statusItem.button?.toolTip = desc
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let config = Config.load(paths: paths)

        menu.addItem(withTitle: "Dictatr — mantén \(hotkeySpec.label) para dictar", action: nil, keyEquivalent: "")
        if rewriteEnabled {
            menu.addItem(withTitle: "Mantén \(hotkeySpec.label) + \(rewriteSpec.label) sobre una selección para reescribir", action: nil, keyEquivalent: "")
        }
        if config.groqApiKey.isEmpty {
            menu.addItem(withTitle: "⚠️ Falta API key en config.json", action: nil, keyEquivalent: "")
        }
        if let lastError {
            menu.addItem(withTitle: "⚠️ \(String(lastError.prefix(70)))", action: nil, keyEquivalent: "")
        }
        menu.addItem(.separator())

        let sounds = NSMenuItem(title: "Sonidos", action: #selector(toggleSounds), keyEquivalent: "")
        sounds.target = self
        sounds.state = config.sounds ? .on : .off
        menu.addItem(sounds)

        let login = NSMenuItem(title: "Arrancar al iniciar sesión", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let copyBundle = NSMenuItem(title: "Copiar bundle ID de la app activa", action: #selector(copyFrontBundleId), keyEquivalent: "")
        copyBundle.target = self
        menu.addItem(copyBundle)
        let keyDiag = NSMenuItem(title: "Diagnóstico de teclas (10 s)", action: #selector(runKeyDiagnostic), keyEquivalent: "")
        keyDiag.target = self
        menu.addItem(keyDiag)
        let openCfg = NSMenuItem(title: "Abrir carpeta de configuración", action: #selector(openConfigFolder), keyEquivalent: "")
        openCfg.target = self
        menu.addItem(openCfg)
        let openHist = NSMenuItem(title: "Ver historial", action: #selector(openHistory), keyEquivalent: "")
        openHist.target = self
        menu.addItem(openHist)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Salir de Dictatr", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        statusItem.menu = menu
    }

    @objc private func toggleSounds() {
        var config = Config.load(paths: paths)
        config.sounds.toggle()
        notifier.soundsEnabled = config.sounds
        Config.setValue("sounds", config.sounds, paths: paths)
        rebuildMenu()
    }

    private var diagMonitor: Any?

    // Registra los keyCodes de los modificadores pulsados durante 10 s.
    // Para teclados externos que reportan códigos no estándar (Logi, etc.).
    @objc private func runKeyDiagnostic() {
        guard diagMonitor == nil else { return }
        let logURL = paths.root.appendingPathComponent("diagnostico-teclas.txt")
        try? "Pulsa ahora los modificadores que quieras probar (10 s)…\n".write(to: logURL, atomically: true, encoding: .utf8)
        notifier.notify(title: "Diagnóstico de teclas activo", body: "Pulsa los modificadores del teclado (10 s)")
        diagMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { event in
            let known = ["54": "⌘ der", "55": "⌘ izq", "56": "⇧ izq", "60": "⇧ der",
                         "58": "⌥ izq", "61": "⌥ der", "59": "⌃ izq", "62": "⌃ der", "63": "fn"]
            let name = known[String(event.keyCode)] ?? "desconocida"
            let line = "keyCode=\(event.keyCode) (\(name)) flags=\(event.modifierFlags.rawValue)\n"
            if let handle = try? FileHandle(forWritingTo: logURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: Data(line.utf8))
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            if let m = self?.diagMonitor { NSEvent.removeMonitor(m) }
            self?.diagMonitor = nil
            self?.notifier.notify(title: "Diagnóstico terminado", body: "Abriendo el resultado…")
            NSWorkspace.shared.open(logURL)
        }
    }

    @objc private func copyFrontBundleId() {
        let front = NSWorkspace.shared.frontmostApplication
        let id = front?.bundleIdentifier ?? "desconocido"
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(id, forType: .string)
        notifier.notify(title: front?.localizedName ?? "App activa", body: "Bundle ID copiado: \(id)")
    }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            fail("No se pudo cambiar el arranque al login", error.localizedDescription)
        }
        rebuildMenu()
    }

    @objc private func openConfigFolder() { NSWorkspace.shared.open(paths.root) }
    @objc private func openHistory() { NSWorkspace.shared.open(paths.historyFile) }
}
