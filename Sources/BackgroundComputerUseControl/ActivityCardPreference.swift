import Foundation

enum ActivityCardPreference {
    static let key = "BCUActivityCardEnabled"

    static func isEnabled(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }
}
