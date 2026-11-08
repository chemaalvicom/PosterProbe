import Contacts
import SwiftUI

@main
struct PosterProbeApp: App {
    init() {
        // Si la app muere, deja la causa y el último paso en Documents/ultimo_cierre.txt
        let crash = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ultimo_cierre.txt")
        ObjCCatch.installCrashHandler(path: crash.path)
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

@MainActor
final class Model: ObservableObject {
    @Published var status = "Listo"
    @Published var lines: [String] = []
    @Published var running = false
    @Published var done = 0
    @Published var total = 0
    @Published var output: URL?
    @Published var zipURL: URL?
    @Published var lastCrash: String?

    private let probe = Probe()
    private let crashURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ultimo_cierre.txt")

    init() {
        if let t = try? String(contentsOf: crashURL, encoding: .utf8), !t.isEmpty {
            lastCrash = t
            // Se conserva una copia con fecha y se libera el fichero para el siguiente intento
            let df = DateFormatter(); df.dateFormat = "yyyyMMdd_HHmmss"
            let copy = crashURL.deletingLastPathComponent()
                .appendingPathComponent("cierre_\(df.string(from: Date())).txt")
            try? FileManager.default.moveItem(at: crashURL, to: copy)
        }
    }

    func start(full: Bool) {
        guard !running else { return }
        running = true
        lines = []
        output = nil
        zipURL = nil
        Task {
            status = "Pidiendo permiso…"
            let auth = await probe.requestAccess()
            if auth == .denied || auth == .restricted || auth == .notDetermined {
                status = "Sin permiso. Ajustes › Privacidad › Contactos › PosterProbe"
                running = false
                return
            }
            if #available(iOS 18.0, *), auth == .limited {
                append("⚠︎ Acceso LIMITADO: solo verás los contactos elegidos. Activa «Acceso completo» en Ajustes.")
            }
            status = "Analizando…"
            let probe = self.probe
            let result: Result<URL, Error> = await Task.detached(priority: .userInitiated) {
                Result {
                    try probe.run(
                        full: full,
                        log: { msg in Task { @MainActor in self.append(msg) } },
                        progress: { d, t in Task { @MainActor in self.done = d; self.total = t } })
                }
            }.value
            switch result {
            case .success(let url):
                output = url
                status = "Comprimiendo…"
                zipURL = await Task.detached { Probe.zip(url) }.value
                status = "Terminado. Archivos › En mi iPhone › PosterProbe"
                ObjCCatch.mark("terminado")
            case .failure(let e):
                status = "Error: \(e.localizedDescription)"
            }
            running = false
        }
    }

    func append(_ s: String) {
        lines.append(s)
        if lines.count > 400 { lines.removeFirst(lines.count - 400) }
    }
}

struct ContentView: View {
    @StateObject private var m = Model()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Extrae los Pósters de Contacto de tu agenda y los guarda en Archivos › En mi iPhone › PosterProbe. No envía nada fuera del iPhone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        m.start(full: false)
                    } label: {
                        Label("1 · Solo diagnóstico (rápido)", systemImage: "stethoscope")
                    }
                    .disabled(m.running)
                    Button {
                        m.start(full: true)
                    } label: {
                        Label(m.running ? "Analizando…" : "2 · Extraer pósters de toda la agenda",
                              systemImage: "person.crop.rectangle.stack")
                    }
                    .disabled(m.running)
                    if m.total > 0 {
                        ProgressView(value: Double(m.done), total: Double(max(m.total, 1)))
                        Text("\(m.done) / \(m.total)").font(.caption).monospacedDigit()
                    }
                    Text(m.status).font(.callout)
                }
                if let crash = m.lastCrash {
                    Section("⚠︎ La app se cerró en el intento anterior") {
                        Text(crash).font(.caption.monospaced()).textSelection(.enabled)
                        Button("Copiar") { UIPasteboard.general.string = crash }
                    }
                }
                if let zip = m.zipURL {
                    Section("Resultado") {
                        ShareLink(item: zip) {
                            Label("Compartir \(zip.lastPathComponent)", systemImage: "square.and.arrow.up")
                        }
                    }
                }
                if !m.lines.isEmpty {
                    Section("Registro") {
                        ForEach(Array(m.lines.enumerated()), id: \.offset) { _, l in
                            Text(l).font(.caption.monospaced())
                        }
                    }
                }
            }
            .navigationTitle("PosterProbe")
        }
    }
}
