import Contacts
import Foundation

/// Motor de extracción. Lee claves internas (no públicas) de CNContact relacionadas
/// con el Póster de Contacto y vuelca todo lo que consiga a Documents/ (visible en Archivos).
final class Probe {
    typealias Log = (String) -> Void
    typealias Progress = (Int, Int) -> Void

    let store = CNContactStore()
    private let fm = FileManager.default

    /// Claves candidatas conocidas (iOS 17/18). Se completan con lo que aparezca en el runtime.
    static let knownCandidates = [
        "wallpaper", "watchWallpaperImageData", "sensitiveContentConfiguration",
        "fullscreenImageData", "wallpaperMetadata", "wallpaperURI", "posterData",
        "memojiMetadata", "imageType", "imageHash", "cropRect",
    ]
    /// Patrón para considerar que un contacto "tiene póster".
    static let posterPattern = try! NSRegularExpression(
        pattern: "wallpaper|poster|fullscreen|memoji", options: [.caseInsensitive])
    static let candidatePattern = try! NSRegularExpression(
        pattern: "wallpaper|poster|fullscreen|sensitive|memoji|watch.*image|imageType|imageHash|cropRect",
        options: [.caseInsensitive])

    static func matches(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    // MARK: - Permiso

    func requestAccess() async -> CNAuthorizationStatus {
        _ = try? await store.requestAccess(for: .contacts)
        return CNContactStore.authorizationStatus(for: .contacts)
    }

    // MARK: - Ejecución completa

    func run(log: @escaping Log, progress: @escaping Progress) throws -> URL {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd_HHmmss"
        let outDir = docs.appendingPathComponent("PosterProbe_\(df.string(from: Date()))")
        let contactsDir = outDir.appendingPathComponent("contactos")
        try fm.createDirectory(at: contactsDir, withIntermediateDirectories: true)

        var informe: [String] = []
        let device = ProcessInfo.processInfo.operatingSystemVersionString
        informe.append("PosterProbe — \(Date())")
        informe.append("iOS: \(device)")
        informe.append("Permiso Contactos: \(CNContactStore.authorizationStatus(for: .contacts).rawValue) (3=completo, 4=limitado)")
        informe.append("")

        // 1) Descubrimiento en runtime
        let contactProps = ObjCCatch.propertyNames(of: CNContact.self)
        informe.append("== Propiedades de CNContact (\(contactProps.count)) ==")
        informe.append(contactProps.joined(separator: ", "))
        informe.append("")
        for clsName in ["CNWallpaper", "CNWallpaperMetadata", "CNSensitiveContentConfiguration",
                        "CNMemojiMetadata", "PRPosterConfiguration", "PRSPosterArchiver"] {
            if let cls = NSClassFromString(clsName) {
                informe.append("== Clase \(clsName) ==")
                informe.append("Propiedades: " + ObjCCatch.propertyNames(of: cls).joined(separator: ", "))
                informe.append("Getters: " + ObjCCatch.getterNames(of: cls).prefix(200).joined(separator: ", "))
                informe.append("")
            } else {
                informe.append("== Clase \(clsName): no existe en este iOS ==")
            }
        }

        var candidates = Probe.knownCandidates
        for p in contactProps where Probe.matches(Probe.candidatePattern, p) && !candidates.contains(p) {
            candidates.append(p)
        }
        log("Claves candidatas: \(candidates.count)")

        // 2) Probar cada clave por separado
        informe.append("")
        informe.append("== Prueba de claves (fetch de 1 contacto) ==")
        var usable: [String] = []
        for key in candidates {
            let r = testKey(key)
            informe.append("  \(key): \(r ?? "OK")")
            log("\(key): \(r == nil ? "OK" : "✗")")
            if r == nil { usable.append(key) }
        }
        informe.append("")

        if usable.isEmpty {
            informe.append("Ninguna clave interna es accesible desde una app de terceros en este iOS.")
            try informe.joined(separator: "\n").write(
                to: outDir.appendingPathComponent("informe.txt"), atomically: true, encoding: .utf8)
            return outDir
        }

        // 3) Recorrido completo
        let base: [String] = [CNContactIdentifierKey, CNContactGivenNameKey, CNContactFamilyNameKey,
                              CNContactOrganizationNameKey, CNContactImageDataAvailableKey]
        let keys = (base + usable).map { ($0 as NSString) as CNKeyDescriptor }
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.unifyResults = true

        var total = 0
        _ = ObjCCatch.run {
            _ = try? self.store.enumerateContacts(with: CNContactFetchRequest(
                keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor])) { _, _ in total += 1 }
        }
        log("Contactos: \(total)")

        var csv = ["nombre;identificador;claves_con_datos;ficheros"]
        var withPoster = 0
        var keyCounts: [String: Int] = [:]
        var done = 0
        var enumError: String?
        let exc = ObjCCatch.run {
            do {
                try self.store.enumerateContacts(with: request) { contact, _ in
                    done += 1
                    if done % 50 == 0 { progress(done, total) }
                    autoreleasepool {
                        var values: [(String, Any)] = []
                        var hasPoster = false
                        for key in usable {
                            var err: NSString?
                            guard let v = ObjCCatch.value(of: contact, forKey: key, error: &err),
                                  !(v is NSNull) else { continue }
                            if let d = v as? Data, d.isEmpty { continue }
                            if let s = v as? String, s.isEmpty { continue }
                            values.append((key, v))
                            keyCounts[key, default: 0] += 1
                            if Probe.matches(Probe.posterPattern, key) { hasPoster = true }
                        }
                        guard hasPoster else { return }
                        withPoster += 1
                        let name = [contact.givenName, contact.familyName]
                            .filter { !$0.isEmpty }.joined(separator: " ")
                        let display = name.isEmpty ? (contact.organizationName.isEmpty ? "sin_nombre"
                                                     : contact.organizationName) : name
                        let dir = contactsDir.appendingPathComponent(
                            "\(Probe.safe(display))__\(Probe.safe(String(contact.identifier.prefix(8))))")
                        try? self.fm.createDirectory(at: dir, withIntermediateDirectories: true)
                        var meta: [String: Any] = ["nombre": display, "identificador": contact.identifier]
                        var files = 0
                        for (key, v) in values {
                            meta[key] = self.dump(v, dir: dir, name: key, depth: 0, files: &files)
                        }
                        if let json = try? JSONSerialization.data(
                            withJSONObject: Probe.jsonSafe(meta), options: [.prettyPrinted, .sortedKeys]) {
                            try? json.write(to: dir.appendingPathComponent("meta.json"))
                        }
                        csv.append("\(display);\(contact.identifier);"
                                   + values.map { $0.0 }.joined(separator: ",") + ";\(files)")
                    }
                }
            } catch {
                enumError = error.localizedDescription
            }
        }
        progress(done, total)

        informe.append("== Resultado ==")
        informe.append("Contactos recorridos: \(done) de \(total)")
        informe.append("Contactos con póster: \(withPoster)")
        for (k, c) in keyCounts.sorted(by: { $0.value > $1.value }) {
            informe.append("  \(k): \(c) contactos con valor")
        }
        if let e = enumError { informe.append("Error de enumeración: \(e)") }
        if let e = exc { informe.append("Excepción de enumeración: \(e)") }

        try informe.joined(separator: "\n").write(
            to: outDir.appendingPathComponent("informe.txt"), atomically: true, encoding: .utf8)
        try ("\u{FEFF}" + csv.joined(separator: "\n")).write(
            to: outDir.appendingPathComponent("resumen.csv"), atomically: true, encoding: .utf8)
        log("Contactos con póster: \(withPoster)")
        return outDir
    }

    /// nil si la clave se puede pedir y leer; si no, el error.
    private func testKey(_ key: String) -> String? {
        let req = CNContactFetchRequest(keysToFetch: [
            CNContactIdentifierKey as CNKeyDescriptor, (key as NSString) as CNKeyDescriptor])
        var result: String?
        let exc = ObjCCatch.run {
            do {
                try self.store.enumerateContacts(with: req) { contact, stop in
                    var err: NSString?
                    _ = ObjCCatch.value(of: contact, forKey: key, error: &err)
                    if let err = err { result = "lectura: \(err)" }
                    stop.pointee = true
                }
            } catch {
                result = "fetch: \(error.localizedDescription)"
            }
        }
        if let exc = exc { return "excepción: \(exc)" }
        return result
    }

    // MARK: - Volcado recursivo

    /// Escribe datos binarios a disco y devuelve una representación JSON del valor.
    private func dump(_ v: Any, dir: URL, name: String, depth: Int, files: inout Int) -> Any {
        if let d = v as? Data {
            let ext = Probe.sniff(d)
            let url = dir.appendingPathComponent("\(Probe.safe(name)).\(ext)")
            try? d.write(to: url)
            files += 1
            if ext == "plist", let obj = try? PropertyListSerialization.propertyList(from: d, format: nil) {
                return ["fichero": url.lastPathComponent, "bytes": d.count,
                        "plist": Probe.jsonSafe(obj)]
            }
            return ["fichero": url.lastPathComponent, "bytes": d.count]
        }
        if v is String || v is NSNumber || v is Date { return v }
        if let url = v as? URL { return url.absoluteString }
        if let arr = v as? [Any] {
            return arr.enumerated().map { i, x in
                dump(x, dir: dir, name: "\(name)_\(i)", depth: depth + 1, files: &files)
            }
        }
        guard let obj = v as? NSObject else { return String(describing: v) }

        var out: [String: Any] = ["$clase": NSStringFromClass(type(of: obj))]
        // Copia archivada completa del objeto (se puede analizar luego en el NAS)
        var archived: Data?
        _ = ObjCCatch.run {
            archived = try? NSKeyedArchiver.archivedData(withRootObject: obj, requiringSecureCoding: false)
        }
        if let a = archived {
            let url = dir.appendingPathComponent("\(Probe.safe(name)).archive.plist")
            try? a.write(to: url)
            files += 1
            out["$archivo"] = url.lastPathComponent
        }
        if depth >= 3 {
            out["$descripcion"] = String(obj.description.prefix(2000))
            return out
        }
        for p in ObjCCatch.propertyNames(of: type(of: obj)) {
            if ["hash", "superclass", "description", "debugDescription"].contains(p) { continue }
            var err: NSString?
            guard let pv = ObjCCatch.value(of: obj, forKey: p, error: &err), !(pv is NSNull) else {
                if let err = err { out[p] = "⚠︎ \(err)" }
                continue
            }
            out[p] = dump(pv, dir: dir, name: "\(name).\(p)", depth: depth + 1, files: &files)
        }
        return out
    }

    // MARK: - Utilidades

    static func sniff(_ d: Data) -> String {
        let b = [UInt8](d.prefix(16))
        func starts(_ s: [UInt8]) -> Bool { b.count >= s.count && Array(b.prefix(s.count)) == s }
        if starts([0x50, 0x4B, 0x03, 0x04]) { return "zip" }
        if starts(Array("bplist00".utf8)) { return "plist" }
        if starts(Array("<?xml".utf8)) { return "plist" }
        if starts([0xFF, 0xD8, 0xFF]) { return "jpg" }
        if starts([0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if starts([0x49, 0x49, 0x2A, 0x00]) || starts([0x4D, 0x4D, 0x00, 0x2A]) { return "tiff" }
        if b.count >= 12, Array(b[4..<8]) == Array("ftyp".utf8) {
            let brand = String(bytes: b[8..<12], encoding: .ascii) ?? ""
            return ["heic", "heix", "mif1", "msf1", "hevc"].contains(brand) ? "heic" : "mp4"
        }
        return "bin"
    }

    static func safe(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters)
        let r = s.components(separatedBy: bad).joined(separator: "_")
            .trimmingCharacters(in: .whitespaces)
        return r.isEmpty ? "sin_nombre" : String(r.prefix(80))
    }

    /// Convierte a algo serializable por JSONSerialization.
    static func jsonSafe(_ v: Any) -> Any {
        switch v {
        case let d as [String: Any]: return d.mapValues { jsonSafe($0) }
        case let d as NSDictionary:
            var r: [String: Any] = [:]
            for (k, x) in d { r["\(k)"] = jsonSafe(x) }
            return r
        case let a as [Any]: return a.map { jsonSafe($0) }
        case let s as String: return s
        case let n as NSNumber: return n
        case let d as Date: return ISO8601DateFormatter().string(from: d)
        case let d as Data: return "<\(d.count) bytes>"
        default: return String(describing: v)
        }
    }

    /// Empaqueta la carpeta en un .zip junto a ella (para compartir o copiar al NAS).
    static func zip(_ folder: URL) -> URL? {
        var result: URL?
        var err: NSError?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &err) { tmp in
            let dest = folder.deletingLastPathComponent()
                .appendingPathComponent(folder.lastPathComponent + ".zip")
            try? FileManager.default.removeItem(at: dest)
            if (try? FileManager.default.copyItem(at: tmp, to: dest)) != nil { result = dest }
        }
        return result
    }
}
