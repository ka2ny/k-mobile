import Foundation

/// What the app and its extensions share, through the App Group: the computer's address, Home's last readings
/// (the widgets draw them; nothing in an extension asks the computer itself), and what the Share Sheet left for k-beam.
enum Shared {
    static let group = "group.os.khole"
    static var defaults: UserDefaults { UserDefaults(suiteName: group) ?? .standard }

    /// The phone app's address on the computer (https://<name>:<port>/), set when the app pairs.
    static var computer: URL? {
        get { defaults.string(forKey: "computer").flatMap(URL.init(string:)) }
        set { defaults.set(newValue?.absoluteString, forKey: "computer") }
    }

    /// The folder the Share Sheet puts files in for the app to hand k-beam.
    static var inbox: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appendingPathComponent("share-inbox", isDirectory: true)
    }
}

/// Home's readings as the phone app last had them (remote/app/hub.js posts them to the app; /app/widgets).
struct Readings: Codable, Equatable {
    struct Battery: Codable, Equatable { var level: Int; var charging: Bool }
    var at: Date
    var needs: Int = 0            // agents that need your yes
    var working: Int = 0
    var first: String = ""        // the first one's name
    var assistant: String = ""    // the Assistant's state, in the phone app's words
    var battery: Battery?
    var storageFree: Double?      // bytes
    var memoryPercent: Int?

    static let key = "readings"
    static func load() -> Readings? {
        guard let data = Shared.defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Readings.self, from: data)
    }
    func save() {
        if let data = try? JSONEncoder().encode(self) { Shared.defaults.set(data, forKey: Readings.key) }
    }
}
