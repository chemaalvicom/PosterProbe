import Contacts
import SwiftUI

@main
struct PosterProbeApp: App {
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

    private let probe = Probe()

    func start() {
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
                        m.start()
                    } label: {
                        Label(m.running ? "Analizando…" : "Analizar contactos", systemImage: "person.crop.rectangle.stack")
                    }
                    .disabled(m.running)
                    if m.total > 0 {
                        ProgressView(value: Double(m.done), total: Double(max(m.total, 1)))
                        Text("\(m.done) / \(m.total)").font(.caption).monospacedDigit()
                    }
                    Text(m.status).font(.callout)
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
