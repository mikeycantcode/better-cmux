import Foundation

/// Where better cmux's own releases live. Every update URL (appcast feed,
/// release notes, manual download) derives from here, so updates track this
/// fork rather than upstream cmux.
public enum BetterCmuxRelease {
    public static let repositoryURLString = "https://github.com/mikeycantcode/better-cmux"

    public static let appcastURLString = "\(repositoryURLString)/releases/latest/download/appcast.xml"

    public static let manualDownloadURLString = "\(repositoryURLString)/releases/latest/download/bettercmux-macos.dmg"

    public static func releaseTagURLString(_ tag: String) -> String {
        "\(repositoryURLString)/releases/tag/\(tag)"
    }

    public static func commitURLString(_ hash: String) -> String {
        "\(repositoryURLString)/commit/\(hash)"
    }
}
