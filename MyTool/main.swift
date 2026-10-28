import Foundation
import CoreServices
import Darwin
import Security

// MARK: - Models

struct DownloadSourceInfo: Codable {
    let sourceName: String
    let downloadURL: String?
    let webURL: String?
    let version: String?
    let extraDetails: String?
    let homebrewPackage: String?
}

struct AppDetails: Codable {
    let targetPath: String
    let targetType: String
    let fileSizeBytes: Int64
    let formattedFileSize: String
    let lastModified: String?
    
    // Bundle Info
    let bundleName: String?
    let bundleIdentifier: String?
    let bundleVersion: String?
    let bundleShortVersion: String?
    let minOSVersion: String?
    let copyright: String?
    
    // Code Signing
    let signingTeamId: String?
    let signingAuthority: String?
    let hasHardenedRuntime: Bool?
    let codeSigningRequirement: String?
    
    // Download URLs & Sources
    let primaryDownloadURL: String?
    let primaryWebURL: String?
    let downloadSources: [DownloadSourceInfo]
    let homebrewPackage: String?
    
    // Sparkle Info
    let sparkleFrameworkDetected: Bool
    let sparkleFrameworkVersion: String?
    let sparkleFeedURL: String?
    let sparkleEdKey: String?
    let sparkleDSAKeyFile: String?
    let sparkleCheckIntervalHours: Double?
    let sparkleAutoChecksEnabled: Bool?
    let sparkleAutoUpdatesAllowed: Bool?
    
    // Live Sparkle Feed Details
    let sparkleLatestVersion: String?
    let sparkleLatestDownloadURL: String?
    let sparkleLatestReleaseDate: String?
    let sparkleLatestMinOS: String?
    let sparkleLatestPackageSize: String?
    let sparkleLatestReleaseNotesURL: String?
    let sparkleFeedFetchStatus: String?
}

// MARK: - Sparkle Feed XML Parser

final class SparkleFeedParser: NSObject, XMLParserDelegate {
    struct FeedItem {
        var title: String?
        var version: String?
        var shortVersion: String?
        var downloadURL: String?
        var fileSize: Int64?
        var mimeType: String?
        var edSignature: String?
        var dsaSignature: String?
        var minOSVersion: String?
        var pubDate: String?
        var releaseNotesURL: String?
    }
    
    var items: [FeedItem] = []
    var feedTitle: String?
    
    private var currentItem: FeedItem?
    private var currentElement: String = ""
    private var currentText: String = ""
    private var inItem: Bool = false
    
    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String : String] = [:]
    ) {
        currentElement = elementName
        currentText = ""
        
        let lowerName = elementName.lowercased()
        if lowerName == "item" {
            inItem = true
            currentItem = FeedItem()
        } else if inItem && lowerName == "enclosure" {
            if let url = attributeDict["url"] {
                currentItem?.downloadURL = url
            }
            if let lenStr = attributeDict["length"], let len = Int64(lenStr) {
                currentItem?.fileSize = len
            }
            if let type = attributeDict["type"] {
                currentItem?.mimeType = type
            }
            for (key, val) in attributeDict {
                let kLower = key.lowercased()
                if kLower.hasSuffix("edsignature") {
                    currentItem?.edSignature = val
                } else if kLower.hasSuffix("dsasignature") {
                    currentItem?.dsaSignature = val
                } else if kLower.hasSuffix("shortversionstring") && (currentItem?.shortVersion == nil) {
                    currentItem?.shortVersion = val
                } else if kLower.hasSuffix("version") && (currentItem?.version == nil) {
                    currentItem?.version = val
                }
            }
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText.append(string)
    }
    
    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerName = elementName.lowercased()
        
        if inItem {
            if lowerName == "item" {
                if let item = currentItem {
                    items.append(item)
                }
                currentItem = nil
                inItem = false
            } else if lowerName == "title" {
                currentItem?.title = text
            } else if lowerName == "pubdate" {
                currentItem?.pubDate = text
            } else if lowerName.hasSuffix("shortversionstring") {
                currentItem?.shortVersion = text
            } else if lowerName.hasSuffix("version") {
                currentItem?.version = text
            } else if lowerName.hasSuffix("minimumsystemversion") {
                currentItem?.minOSVersion = text
            } else if lowerName.hasSuffix("releasenoteslink") {
                currentItem?.releaseNotesURL = text
            }
        } else {
            if lowerName == "title" && feedTitle == nil {
                feedTitle = text
            }
        }
    }
}

// MARK: - Inspection Helpers

struct QuarantineInfo {
    let rawString: String
    let flags: String?
    let date: Date?
    let agent: String?
    let uuid: String?
}

func readExtendedAttribute(path: String, name: String) -> Data? {
    let size = getxattr(path, name, nil, 0, 0, 0)
    guard size > 0 else { return nil }
    var data = Data(count: size)
    let readSize = data.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) -> ssize_t in
        guard let baseAddress = buffer.baseAddress else { return -1 }
        return getxattr(path, name, baseAddress, size, 0, 0)
    }
    guard readSize == size else { return nil }
    return data
}

func parseQuarantine(raw: String) -> QuarantineInfo {
    let parts = raw.components(separatedBy: ";")
    var flags: String? = nil
    var date: Date? = nil
    var agent: String? = nil
    var uuid: String? = nil
    
    if parts.indices.contains(0) { flags = parts[0] }
    if parts.indices.contains(1) {
        if let timestampHex = UInt64(parts[1], radix: 16) {
            date = Date(timeIntervalSince1970: TimeInterval(timestampHex))
        }
    }
    if parts.indices.contains(2) {
        agent = parts[2].replacingOccurrences(of: "\\x20", with: " ")
    }
    if parts.indices.contains(3) { uuid = parts[3] }
    
    return QuarantineInfo(rawString: raw, flags: flags, date: date, agent: agent, uuid: uuid)
}

func getWhereFroms(atPath path: String) -> [String] {
    let attrName = "com.apple.metadata:kMDItemWhereFroms"
    if let data = readExtendedAttribute(path: path, name: attrName) {
        if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String] {
            return plist
        }
    }
    
    let url = URL(fileURLWithPath: path)
    if let mdItem = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL),
       let list = MDItemCopyAttribute(mdItem, kMDItemWhereFroms) as? [String] {
        return list
    }
    return []
}

func findWhereFromsForTarget(path: String) -> [String] {
    // Finder and archive tools do not consistently preserve provenance on the
    // bundle root. Check the files most likely to retain it as well.
    let infoPlist = (path as NSString).appendingPathComponent("Contents/Info.plist")
    let macosDir = (path as NSString).appendingPathComponent("Contents/MacOS")
    var candidates = [path, infoPlist]

    if let contents = try? FileManager.default.contentsOfDirectory(atPath: macosDir) {
        candidates.append(contentsOf: contents.map {
            (macosDir as NSString).appendingPathComponent($0)
        })
    }

    var urls: [String] = []
    for candidate in candidates {
        for url in getWhereFroms(atPath: candidate) where !urls.contains(url) {
            urls.append(url)
        }
    }
    return urls
}

func findURLsInBundleMetadata(_ infoPlist: [String: Any]?) -> [(label: String, url: String)] {
    guard let infoPlist else { return [] }

    var results: [(label: String, url: String)] = []
    for (key, value) in infoPlist {
        guard let value = value as? String,
              let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            continue
        }

        let lowercasedKey = key.lowercased()
        guard lowercasedKey.contains("url") || lowercasedKey.contains("website") || lowercasedKey.contains("homepage") else {
            continue
        }
        results.append((key, value))
    }
    return results
}

func findQuarantineForTarget(path: String) -> QuarantineInfo? {
    if let data = readExtendedAttribute(path: path, name: "com.apple.quarantine"),
       let raw = String(data: data, encoding: .utf8) {
        return parseQuarantine(raw: raw)
    }
    
    let infoPlist = (path as NSString).appendingPathComponent("Contents/Info.plist")
    if let data = readExtendedAttribute(path: infoPlist, name: "com.apple.quarantine"),
       let raw = String(data: data, encoding: .utf8) {
        return parseQuarantine(raw: raw)
    }
    return nil
}

func getCodeSigningInfo(path: String) -> (teamId: String?, signer: String?, isHardened: Bool, requirement: String?)? {
    let url = URL(fileURLWithPath: path)
    var staticCode: SecStaticCode?
    guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
          let code = staticCode else {
        return nil
    }
    var infoCF: CFDictionary?
    guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &infoCF) == errSecSuccess,
          let info = infoCF as? [String: Any] else {
        return nil
    }
    
    let teamId = info[kSecCodeInfoTeamIdentifier as String] as? String
    let certs = info[kSecCodeInfoCertificates as String] as? [SecCertificate]
    var signerName: String? = nil
    if let firstCert = certs?.first {
        var commonNameCF: CFString?
        if SecCertificateCopyCommonName(firstCert, &commonNameCF) == errSecSuccess,
           let cn = commonNameCF as? String {
            signerName = cn
        }
    }
    let flags = info[kSecCodeInfoFlags as String] as? UInt32 ?? 0
    let isHardened = (flags & 0x00010000) != 0
    
    // Designated Code Signing Requirement
    var requirementStr: String? = nil
    var reqCF: SecRequirement?
    if SecCodeCopyDesignatedRequirement(code, [], &reqCF) == errSecSuccess, let req = reqCF {
        var strCF: CFString?
        if SecRequirementCopyString(req, [], &strCF) == errSecSuccess, let s = strCF as String? {
            requirementStr = s
        }
    }
    
    return (teamId, signerName, isHardened, requirementStr)
}

func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useAll]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}

func cleanInputPath(_ input: String) -> String {
    var str = input.trimmingCharacters(in: .whitespacesAndNewlines)
    
    // Remove enclosing single or double quotes
    if (str.hasPrefix("\"") && str.hasSuffix("\"")) || (str.hasPrefix("'") && str.hasSuffix("'")) {
        if str.count >= 2 {
            str = String(str.dropFirst().dropLast())
        }
    }
    
    // Convert 'file://' URL if dragged as URL
    if str.hasPrefix("file://") {
        if let url = URL(string: str) {
            str = url.path
        }
    }
    
    // Unescape Terminal backslash escapes (e.g. "\ ")
    var unescaped = ""
    var isEscaping = false
    for char in str {
        if isEscaping {
            unescaped.append(char)
            isEscaping = false
        } else if char == "\\" {
            isEscaping = true
        } else {
            unescaped.append(char)
        }
    }
    str = unescaped
    
    str = (str as NSString).expandingTildeInPath
    str = (str as NSString).standardizingPath
    return str
}

// MARK: - Online Scrapers (Homebrew, GitHub & Mac App Store)

func fetchJSON(from urlString: String, timeout: TimeInterval = 4.0) async -> [String: Any]? {
    guard let url = URL(string: urlString) else { return nil }
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
    request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
    do {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
    } catch {
        return nil
    }
}

func fetchJSONArray(from urlString: String, timeout: TimeInterval = 12.0) async -> [[String: Any]]? {
    guard let url = URL(string: urlString) else { return nil }
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
    request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
    do {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]]
    } catch {
        return nil
    }
}

func normalizedDiscoveryName(_ value: String) -> String {
    String(value.lowercased().filter { $0.isLetter || $0.isNumber })
}

func fetchGitHubJSON(from url: URL) async -> [String: Any]? {
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 6.0)
    request.setValue("Appinfo", forHTTPHeaderField: "User-Agent")
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")

    do {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
    } catch {
        return nil
    }
}

func scrapeGitHubRelease(name: String, bundleId: String?, filename: String) async -> DownloadSourceInfo? {
    let appName = (filename as NSString).deletingPathExtension
    var searchTerms = [appName]
    if let bundleId, let finalComponent = bundleId.split(separator: ".").last {
        let bundleTerm = String(finalComponent)
        if !searchTerms.contains(bundleTerm) {
            searchTerms.append(bundleTerm)
        }
    }

    let expectedNames = Set([normalizedDiscoveryName(name), normalizedDiscoveryName(appName)])
    var repositoryFallback: DownloadSourceInfo?
    for term in searchTerms {
        var components = URLComponents(string: "https://api.github.com/search/repositories")
        components?.queryItems = [
            URLQueryItem(name: "q", value: "\(term) in:name,description,readme"),
            URLQueryItem(name: "per_page", value: "5")
        ]
        guard let searchURL = components?.url,
              let searchResponse = await fetchGitHubJSON(from: searchURL),
              let items = searchResponse["items"] as? [[String: Any]] else {
            continue
        }

        let matchingRepositories = items.filter { repository in
            guard let repositoryName = repository["name"] as? String else { return false }
            let normalizedRepositoryName = normalizedDiscoveryName(repositoryName)
            if expectedNames.contains(normalizedRepositoryName) {
                return true
            }
            return bundleId.map { bundleIdentifier in
                let description = repository["description"] as? String ?? ""
                return description.localizedCaseInsensitiveContains(bundleIdentifier)
            } ?? false
        }

        for repository in matchingRepositories.prefix(3) {
            guard let fullName = repository["full_name"] as? String else {
                continue
            }

            let repositoryPage = repository["html_url"] as? String
            if repositoryFallback == nil {
                repositoryFallback = DownloadSourceInfo(
                    sourceName: "GitHub Repository (\(fullName))",
                    downloadURL: nil,
                    webURL: repositoryPage,
                    version: nil,
                    extraDetails: "No published GitHub release asset was found.",
                    homebrewPackage: nil
                )
            }

            guard let releaseURL = URL(string: "https://api.github.com/repos/\(fullName)/releases/latest"),
                  let release = await fetchGitHubJSON(from: releaseURL) else {
                continue
            }

            let assets = release["assets"] as? [[String: Any]] ?? []
            let preferredAsset = assets.first { asset in
                guard let assetName = asset["name"] as? String else { return false }
                let lowercasedName = assetName.lowercased()
                return lowercasedName.contains(normalizedDiscoveryName(appName)) ||
                    [".dmg", ".pkg", ".zip"].contains { lowercasedName.hasSuffix($0) }
            }
            guard let asset = preferredAsset,
                  let downloadURL = asset["browser_download_url"] as? String else {
                continue
            }

            let releasePage = release["html_url"] as? String
            let repositoryWebsite = repository["homepage"] as? String
            let website = repositoryWebsite?.isEmpty == false ? repositoryWebsite : releasePage
            let version = (release["name"] as? String) ?? (release["tag_name"] as? String)
            let assetName = asset["name"] as? String
            return DownloadSourceInfo(
                sourceName: "GitHub Release (\(fullName))",
                downloadURL: downloadURL,
                webURL: website,
                version: version,
                extraDetails: [
                    assetName.map { "Release asset: \($0)" },
                    releasePage.map { "GitHub release: \($0)" }
                ].compactMap { $0 }.joined(separator: " • "),
                homebrewPackage: nil
            )
        }
    }

    if let repositoryFallback {
        return repositoryFallback
    }

    var searchComponents = URLComponents(string: "https://github.com/search")
    searchComponents?.queryItems = [
        URLQueryItem(name: "q", value: appName),
        URLQueryItem(name: "type", value: "repositories")
    ]
    return DownloadSourceInfo(
        sourceName: "GitHub Repository Search",
        downloadURL: nil,
        webURL: searchComponents?.url?.absoluteString,
        version: nil,
        extraDetails: "No matching GitHub repository or release asset was found.",
        homebrewPackage: nil
    )
}

func scrapeHomebrewCask(name: String, bundleId: String?, filename: String) async -> DownloadSourceInfo? {
    // Generate potential cask candidate tokens
    var tokensToTry: [String] = []
    
    // 1. Filename based (e.g. "Cyberduck.app" -> "cyberduck", "Visual Studio Code.app" -> "visual-studio-code")
    let baseFile = ((filename as NSString).deletingPathExtension)
        .lowercased()
        .replacingOccurrences(of: " ", with: "-")
    tokensToTry.append(baseFile)
    
    // 2. Name based
    let cleanName = name.lowercased().replacingOccurrences(of: " ", with: "-")
    if !tokensToTry.contains(cleanName) {
        tokensToTry.append(cleanName)
    }
    
    // 3. Bundle Id based (e.g. "ch.sudo.cyberduck" -> "cyberduck", "com.google.Chrome" -> "google-chrome")
    if let bId = bundleId {
        let parts = bId.lowercased().components(separatedBy: ".")
        if let last = parts.last, !tokensToTry.contains(last) {
            tokensToTry.append(last)
        }
        if parts.count >= 2 {
            let combined = "\(parts[parts.count - 2])-\(parts[parts.count - 1])"
            if !tokensToTry.contains(combined) {
                tokensToTry.append(combined)
            }
        }
    }
    
    for token in tokensToTry {
        let cleanToken = token.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? token
        let apiURL = "https://formulae.brew.sh/api/cask/\(cleanToken).json"
        if let json = await fetchJSON(from: apiURL) {
            let dlURL = json["url"] as? String
            let homepage = json["homepage"] as? String
            let version = json["version"] as? String
            let desc = json["desc"] as? String
            
            if dlURL != nil || homepage != nil {
                return DownloadSourceInfo(
                    sourceName: "Web-Discovered Link",
                    downloadURL: dlURL,
                    webURL: homepage,
                    version: version,
                    extraDetails: desc,
                    homebrewPackage: "homebrew/cask/\(token)"
                )
            }
        }
    }

    // An app's display name and Homebrew cask token frequently differ (for
    // example, a vendor prefix may be present). Fall back to the catalog and
    // match its declared app artifact or name instead of guessing the token.
    let expectedNames = Set([
        normalizedDiscoveryName(name),
        normalizedDiscoveryName((filename as NSString).deletingPathExtension)
    ])
    if let casks = await fetchJSONArray(from: "https://formulae.brew.sh/api/cask.json") {
        for cask in casks {
            let caskNames = cask["name"] as? [String] ?? []
            let artifacts = cask["artifacts"] as? [Any] ?? []
            let matchesName = caskNames.contains { expectedNames.contains(normalizedDiscoveryName($0)) }
            let matchesArtifact = artifacts.contains {
                String(describing: $0).localizedCaseInsensitiveContains(filename)
            }
            guard matchesName || matchesArtifact else { continue }

            let token = cask["token"] as? String ?? "matching cask"
            let downloadURL = cask["url"] as? String
            let homepage = cask["homepage"] as? String
            let version = cask["version"] as? String
            let description = cask["desc"] as? String
            if downloadURL != nil || homepage != nil {
                return DownloadSourceInfo(
                    sourceName: "Web-Discovered Link",
                    downloadURL: downloadURL,
                    webURL: homepage,
                    version: version,
                    extraDetails: description,
                    homebrewPackage: "homebrew/cask/\(token)"
                )
            }
        }
    }
    
    return nil
}

func scrapeMacAppStore(bundleId: String) async -> DownloadSourceInfo? {
    guard !bundleId.isEmpty else { return nil }
    let lookupURL = "https://itunes.apple.com/lookup?bundleId=\(bundleId)&entity=macSoftware"
    guard let json = await fetchJSON(from: lookupURL),
          let results = json["results"] as? [[String: Any]],
          let first = results.first else {
        return nil
    }
    
    let storeURL = first["trackViewUrl"] as? String
    let devURL = first["sellerUrl"] as? String
    let version = first["version"] as? String
    let price = first["formattedPrice"] as? String
    let seller = first["sellerName"] as? String
    
    var extras: [String] = []
    if let s = seller { extras.append("Developer: \(s)") }
    if let p = price { extras.append("Price: \(p)") }
    
    return DownloadSourceInfo(
        sourceName: "Apple Mac App Store",
        downloadURL: storeURL,
        webURL: devURL,
        version: version,
        extraDetails: extras.isEmpty ? nil : extras.joined(separator: " • "),
        homebrewPackage: nil
    )
}

// MARK: - Inspection Engine

func inspectTarget(path: String, fetchNetwork: Bool) async -> AppDetails? {
    let fm = FileManager.default
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: path, isDirectory: &isDir) else {
        return nil
    }
    
    let filename = (path as NSString).lastPathComponent
    let pathExtension = (path as NSString).pathExtension.lowercased()
    var targetType = "File"
    if isDir.boolValue {
        if pathExtension == "app" {
            targetType = "macOS Application Bundle (.app)"
        } else if pathExtension == "pkg" || pathExtension == "mpkg" {
            targetType = "Installer Package Bundle (.pkg)"
        } else {
            targetType = "Directory"
        }
    } else {
        if pathExtension == "pkg" {
            targetType = "Flat Installer Package (.pkg)"
        } else if pathExtension == "dmg" {
            targetType = "Apple Disk Image (.dmg)"
        } else if ["zip", "tgz", "tar", "gz", "bz2"].contains(pathExtension) {
            targetType = "Archive (\(pathExtension.uppercased()))"
        } else {
            targetType = "File (\(pathExtension.isEmpty ? "Binary" : pathExtension))"
        }
    }
    
    // File attributes
    var fileSizeBytes: Int64 = 0
    var lastModified: String? = nil
    let dateFormatter = DateFormatter()
    dateFormatter.dateStyle = .medium
    dateFormatter.timeStyle = .medium
    
    if let attrs = try? fm.attributesOfItem(atPath: path) {
        if let size = attrs[.size] as? NSNumber {
            fileSizeBytes = size.int64Value
        }
        if let modDate = attrs[.modificationDate] as? Date {
            lastModified = dateFormatter.string(from: modDate)
        }
    }
    
    // Read Info.plist if available
    var infoPlistDict: [String: Any]? = nil
    var infoPlistPath = (path as NSString).appendingPathComponent("Contents/Info.plist")
    if !fm.fileExists(atPath: infoPlistPath) {
        infoPlistPath = (path as NSString).appendingPathComponent("Info.plist")
    }
    if fm.fileExists(atPath: infoPlistPath) {
        if let data = try? Data(contentsOf: URL(fileURLWithPath: infoPlistPath)),
           let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
            infoPlistDict = plist
        }
    }
    
    let bundleName = (infoPlistDict?["CFBundleDisplayName"] as? String) ?? (infoPlistDict?["CFBundleName"] as? String) ?? ((filename as NSString).deletingPathExtension)
    let bundleIdentifier = infoPlistDict?["CFBundleIdentifier"] as? String
    let bundleVersion = infoPlistDict?["CFBundleVersion"] as? String
    let bundleShortVersion = infoPlistDict?["CFBundleShortVersionString"] as? String
    let minOSVersion = infoPlistDict?["LSMinimumSystemVersion"] as? String
    let copyright = infoPlistDict?["NSHumanReadableCopyright"] as? String
    
    // Code Signing & Designated Requirement
    let signingInfo = getCodeSigningInfo(path: path)
    
    // Download Sources List
    var downloadSources: [DownloadSourceInfo] = []
    
    // 1. Download Metadata (WhereFroms & Quarantine)
    let whereFroms = findWhereFromsForTarget(path: path)
    let quarantine = findQuarantineForTarget(path: path)
    if !whereFroms.isEmpty || quarantine != nil {
        let dlURL = whereFroms.indices.contains(0) ? whereFroms[0] : nil
        let refURL = whereFroms.indices.contains(1) ? whereFroms[1] : nil
        var extra: [String] = []
        if let agent = quarantine?.agent { extra.append("Downloaded via: \(agent)") }
        if let qDate = quarantine?.date { extra.append("Downloaded on: \(dateFormatter.string(from: qDate))") }
        
        downloadSources.append(
            DownloadSourceInfo(
                sourceName: "Quarantine Metadata (macOS kMDItemWhereFroms)",
                downloadURL: dlURL,
                webURL: refURL,
                version: nil,
                extraDetails: extra.isEmpty ? nil : extra.joined(separator: " • "),
                homebrewPackage: nil
            )
        )
    }

    // Some apps publish their update feed, release notes, or product page in
    // Info.plist even when Finder download provenance has been removed.
    for metadataURL in findURLsInBundleMetadata(infoPlistDict) {
        downloadSources.append(
            DownloadSourceInfo(
                sourceName: "Application Metadata (\(metadataURL.label))",
                downloadURL: metadataURL.url,
                webURL: metadataURL.url,
                version: nil,
                extraDetails: "URL declared in the app's Info.plist",
                homebrewPackage: nil
            )
        )
    }
    
    // Sparkle Framework Detection
    let sparkleFrameworkPath = (path as NSString).appendingPathComponent("Contents/Frameworks/Sparkle.framework")
    let sparkleFrameworkDetected = fm.fileExists(atPath: sparkleFrameworkPath)
    var sparkleFrameworkVersion: String? = nil
    if sparkleFrameworkDetected {
        let sparklePlistPath = (sparkleFrameworkPath as NSString).appendingPathComponent("Resources/Info.plist")
        if let sData = try? Data(contentsOf: URL(fileURLWithPath: sparklePlistPath)),
           let sPlist = try? PropertyListSerialization.propertyList(from: sData, options: [], format: nil) as? [String: Any],
           let sVer = sPlist["CFBundleShortVersionString"] as? String {
            sparkleFrameworkVersion = sVer
        } else {
            sparkleFrameworkVersion = "Detected (Version unknown)"
        }
    }
    
    // Sparkle Keys in App Info.plist
    let sparkleFeedURL = (infoPlistDict?["SUFeedURL"] as? String) ?? (infoPlistDict?["SUFeedURLString"] as? String)
    let sparkleEdKey = infoPlistDict?["SUPublicEDKey"] as? String
    let sparkleDSAKeyFile = infoPlistDict?["SUPublicDSAKeyFile"] as? String
    let checkIntervalSecs = (infoPlistDict?["SUScheduledCheckInterval"] as? NSNumber)?.doubleValue
    let sparkleCheckIntervalHours = checkIntervalSecs != nil ? (checkIntervalSecs! / 3600.0) : nil
    let sparkleAutoChecksEnabled = infoPlistDict?["SUEnableAutomaticChecks"] as? Bool
    let sparkleAutoUpdatesAllowed = infoPlistDict?["SUAllowsAutomaticUpdates"] as? Bool
    
    // Live Sparkle Feed Inspection
    var latestVersion: String? = nil
    var latestDownloadURL: String? = nil
    var latestReleaseDate: String? = nil
    var latestMinOS: String? = nil
    var latestPackageSize: String? = nil
    var latestReleaseNotesURL: String? = nil
    var feedFetchStatus: String? = nil
    
    if let feedURLString = sparkleFeedURL, let feedURL = URL(string: feedURLString) {
        if fetchNetwork {
            do {
                var request = URLRequest(url: feedURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8.0)
                request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)", forHTTPHeaderField: "User-Agent")
                
                let (data, response) = try await URLSession.shared.data(for: request)
                if let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) {
                    let parser = SparkleFeedParser()
                    let xmlParser = XMLParser(data: data)
                    xmlParser.delegate = parser
                    xmlParser.shouldProcessNamespaces = false
                    
                    if xmlParser.parse(), let firstItem = parser.items.first {
                        feedFetchStatus = "Live feed retrieved successfully (\(parser.items.count) item\(parser.items.count == 1 ? "" : "s") found)"
                        latestVersion = firstItem.shortVersion ?? firstItem.version ?? firstItem.title
                        latestDownloadURL = firstItem.downloadURL
                        latestReleaseDate = firstItem.pubDate
                        latestMinOS = firstItem.minOSVersion
                        latestReleaseNotesURL = firstItem.releaseNotesURL
                        if let size = firstItem.fileSize {
                            latestPackageSize = formatBytes(size)
                        }
                        
                        // Add Sparkle Feed Enclosure as a Download Source!
                        if let dl = latestDownloadURL {
                            downloadSources.append(
                                DownloadSourceInfo(
                                    sourceName: "Sparkle Appcast Feed",
                                    downloadURL: dl,
                                    webURL: latestReleaseNotesURL ?? feedURLString,
                                    version: latestVersion,
                                    extraDetails: latestPackageSize != nil ? "Package Size: \(latestPackageSize!)" : nil,
                                    homebrewPackage: nil
                                )
                            )
                        }
                    } else {
                        feedFetchStatus = "Feed was reachable but no valid release items were found"
                    }
                } else if let httpResp = response as? HTTPURLResponse {
                    feedFetchStatus = "HTTP Error \(httpResp.statusCode)"
                }
            } catch {
                feedFetchStatus = "Network lookup failed: \(error.localizedDescription)"
            }
        } else {
            feedFetchStatus = "Network lookup skipped (--no-network enabled)"
        }
    }
    
    // Scraper Fallback 1: Homebrew Cask Catalog
    if fetchNetwork {
        if let brewInfo = await scrapeHomebrewCask(name: bundleName, bundleId: bundleIdentifier, filename: filename) {
            downloadSources.append(brewInfo)
        }
    }
    
    // Scraper Fallback 2: GitHub release assets
    if fetchNetwork, let gitHubInfo = await scrapeGitHubRelease(name: bundleName, bundleId: bundleIdentifier, filename: filename) {
        downloadSources.append(gitHubInfo)
    }

    // Scraper Fallback 3: Apple Mac App Store
    if fetchNetwork, let bId = bundleIdentifier {
        if let appStoreInfo = await scrapeMacAppStore(bundleId: bId) {
            downloadSources.append(appStoreInfo)
        }
    }

    // Several sources can legitimately identify the same URL. Keep the report
    // concise while retaining distinct origins that point to different URLs.
    let homebrewPackage = downloadSources.compactMap(\.homebrewPackage).first
    var seenSourceURLs = Set<String>()
    downloadSources = downloadSources.filter { source in
        let key = "\(source.downloadURL ?? "")|\(source.webURL ?? "")"
        return seenSourceURLs.insert(key).inserted
    }
    
    // Determine Primary Download URL & Web URL
    var primaryDownloadURL: String? = nil
    var primaryWebURL: String? = nil
    for src in downloadSources where src.sourceName != "GitHub Repository Search" {
        if primaryDownloadURL == nil && src.downloadURL != nil {
            primaryDownloadURL = src.downloadURL
        }
        if primaryWebURL == nil && src.webURL != nil {
            primaryWebURL = src.webURL
        }
    }
    
    return AppDetails(
        targetPath: path,
        targetType: targetType,
        fileSizeBytes: fileSizeBytes,
        formattedFileSize: formatBytes(fileSizeBytes),
        lastModified: lastModified,
        bundleName: bundleName,
        bundleIdentifier: bundleIdentifier,
        bundleVersion: bundleVersion,
        bundleShortVersion: bundleShortVersion,
        minOSVersion: minOSVersion,
        copyright: copyright,
        signingTeamId: signingInfo?.teamId,
        signingAuthority: signingInfo?.signer,
        hasHardenedRuntime: signingInfo?.isHardened,
        codeSigningRequirement: signingInfo?.requirement,
        primaryDownloadURL: primaryDownloadURL,
        primaryWebURL: primaryWebURL,
        downloadSources: downloadSources,
        homebrewPackage: homebrewPackage,
        sparkleFrameworkDetected: sparkleFrameworkDetected,
        sparkleFrameworkVersion: sparkleFrameworkVersion,
        sparkleFeedURL: sparkleFeedURL,
        sparkleEdKey: sparkleEdKey,
        sparkleDSAKeyFile: sparkleDSAKeyFile,
        sparkleCheckIntervalHours: sparkleCheckIntervalHours,
        sparkleAutoChecksEnabled: sparkleAutoChecksEnabled,
        sparkleAutoUpdatesAllowed: sparkleAutoUpdatesAllowed,
        sparkleLatestVersion: latestVersion,
        sparkleLatestDownloadURL: latestDownloadURL,
        sparkleLatestReleaseDate: latestReleaseDate,
        sparkleLatestMinOS: latestMinOS,
        sparkleLatestPackageSize: latestPackageSize,
        sparkleLatestReleaseNotesURL: latestReleaseNotesURL,
        sparkleFeedFetchStatus: feedFetchStatus
    )
}

// MARK: - Output Formatting

func printFormattedReport(_ details: AppDetails) {
    let line = String(repeating: "─", count: 70)
    let doubleLine = String(repeating: "═", count: 70)
    
    print("\n" + doubleLine)
    print(" 📦 TARGET OVERVIEW")
    print(doubleLine)
    print("  • Path:               \(details.targetPath)")
    print("  • Type:               \(details.targetType)")
    if let name = details.bundleName {
        print("  • Name:               \(name)")
    }
    if let bundleId = details.bundleIdentifier {
        print("  • Bundle ID:          \(bundleId)")
    }
    if let version = details.bundleShortVersion, let build = details.bundleVersion {
        print("  • Version:            \(version) (Build \(build))")
    } else if let version = details.bundleShortVersion ?? details.bundleVersion {
        print("  • Version:            \(version)")
    }
    if let minOS = details.minOSVersion {
        print("  • Minimum macOS:      \(minOS)")
    }
    if details.fileSizeBytes > 0 {
        print("  • Size:               \(details.formattedFileSize)")
    }
    if let modified = details.lastModified {
        print("  • Last Modified:      \(modified)")
    }
    
    // Code Signing & Designated Requirement Section
    print("\n" + line)
    print(" 🛡️ CODE SIGNING & DESIGNATED REQUIREMENT")
    print(line)
    if let signer = details.signingAuthority {
        print("  • Code Signer:        \(signer)")
        if let team = details.signingTeamId {
            print("  • Team ID:            \(team)")
        }
        if let hardened = details.hasHardenedRuntime {
            print("  • Hardened Runtime:   \(hardened ? "Enabled" : "Disabled")")
        }
        if let req = details.codeSigningRequirement {
            print("  • Designated Req:     \(req)")
        } else {
            print("  • Designated Req:     None found")
        }
    } else {
        print("  ⚠️  Not code-signed or ad-hoc signed without certificates.")
    }
    
    // Download URLs & Scrapers Section
    print("\n" + line)
    print(" 🌐 DOWNLOAD URL DETAILS")
    print(line)
    
    if details.downloadSources.isEmpty {
        print("  ⚠️  No download URL found across all sources:")
        print("     • Quarantine metadata: Not recorded locally")
        print("     • Sparkle feed: Not present or unconfigured")
        print("     • Homebrew Cask Catalog: Not matched")
        print("     • GitHub releases: Not matched")
        print("     • Mac App Store: Not matched")
    } else {
        if let primaryDL = details.primaryDownloadURL {
            print("  🔥 Primary Download:   \(primaryDL)")
        }
        if let primaryWeb = details.primaryWebURL {
            print("  🔗 Primary Web / Site: \(primaryWeb)")
        }
        
        print("\n  [Discovered Sources (\(details.downloadSources.count))]:")
        for (index, src) in details.downloadSources.enumerated() {
            print("   \(index + 1). \(src.sourceName)")
            if let dl = src.downloadURL {
                print("      • Download URL:   \(dl)")
            }
            if let web = src.webURL {
                print("      • Web / Origin:   \(web)")
            }
            if let ver = src.version {
                print("      • Version:        \(ver)")
            }
            if let extra = src.extraDetails {
                print("      • Info:           \(extra)")
            }
        }
    }

    print("\n" + line)
    print(" 🍺 HOMEBREW")
    print(line)
    if let package = details.homebrewPackage {
        print("  • Available as:       \(package)")
    } else {
        print("  ℹ️  No matching Homebrew cask was found.")
    }
    
    // Sparkle Feed Section
    print("\n" + line)
    print(" ✨ SPARKLE UPDATE FEED")
    print(line)
    
    if details.sparkleFeedURL == nil && !details.sparkleFrameworkDetected {
        print("  ℹ️  No Sparkle feed or framework detected.")
        print("     (App may use Mac App Store, another update mechanism, or has no auto-updater)")
    } else {
        if let feedURL = details.sparkleFeedURL {
            print("  • Appcast Feed URL:   \(feedURL)")
        } else {
            print("  • Appcast Feed URL:   Not specified in Info.plist (SUFeedURL missing)")
        }
        
        if details.sparkleFrameworkDetected {
            print("  • Framework Status:   Installed in Contents/Frameworks/Sparkle.framework")
            if let ver = details.sparkleFrameworkVersion {
                print("  • Framework Version:  \(ver)")
            }
        }
        
        if let edKey = details.sparkleEdKey {
            print("  • Public EdDSA Key:   \(edKey) (Sparkle 2 security)")
        }
        if let dsaKey = details.sparkleDSAKeyFile {
            print("  • Public DSA Key:     \(dsaKey) (Legacy Sparkle 1)")
        }
        if let interval = details.sparkleCheckIntervalHours {
            print("  • Check Interval:     Every \(String(format: "%.1f", interval)) hours")
        }
        if let autoChecks = details.sparkleAutoChecksEnabled {
            print("  • Automatic Checks:   \(autoChecks ? "Enabled" : "Disabled")")
        }
        if let autoUpdates = details.sparkleAutoUpdatesAllowed {
            print("  • Auto Updates:       \(autoUpdates ? "Allowed" : "Prompt user")")
        }
        
        // Feed inspection details
        if let status = details.sparkleFeedFetchStatus {
            print("\n  [Live Feed Status]")
            print("  • Status:             \(status)")
            
            if let latestVer = details.sparkleLatestVersion {
                print("  • Latest Version:     \(latestVer)")
            }
            if let feedDL = details.sparkleLatestDownloadURL {
                print("  • Latest Download:    \(feedDL)")
            }
            if let date = details.sparkleLatestReleaseDate {
                print("  • Released:           \(date)")
            }
            if let minOS = details.sparkleLatestMinOS {
                print("  • Min macOS Required: \(minOS)")
            }
            if let pkgSize = details.sparkleLatestPackageSize {
                print("  • Package Size:       \(pkgSize)")
            }
            if let notes = details.sparkleLatestReleaseNotesURL {
                print("  • Release Notes:      \(notes)")
            }
        }
    }
    print(doubleLine + "\n")
}

// MARK: - Banner & Interactive Mode

func printBanner() {
    print("""
    ╔══════════════════════════════════════════════════════════════════════╗
    ║                  Appinfo - App & Package Inspector                   ║
    ║                                  🍍                                  ║
    ║              You awake to find yourself in a dark room               ║
    ╚══════════════════════════════════════════════════════════════════════╝
    """)
}

func printHelp() {
    print("""
    Usage:
      appinfo [options] [<path-to-app-or-package> ...]
      
    Interactive Mode:
      Run 'appinfo' without file arguments, then drag and drop any app (.app),
      installer package (.pkg), disk image (.dmg), or archive into the terminal!

    Options:
      --json         Output detailed results in structured JSON format
      --no-network   Skip live network lookup (Sparkle, Homebrew, GitHub, App Store)
      -h, --help     Show this help message and exit

    Examples:
      appinfo /Applications/Cyberduck.app
      appinfo /Applications/Keynote.app
      appinfo ~/Downloads/Install.pkg
      appinfo --json /Applications/Slack.app
    """)
}

// MARK: - Main Execution

let arguments = CommandLine.arguments.dropFirst()

var showJson = false
var fetchNetwork = true
var targetPaths: [String] = []

for arg in arguments {
    switch arg {
    case "-h", "--help":
        printHelp()
        exit(0)
    case "--json":
        showJson = true
    case "--no-network":
        fetchNetwork = false
    default:
        if !arg.hasPrefix("-") {
            targetPaths.append(cleanInputPath(arg))
        }
    }
}

if !targetPaths.isEmpty {
    // CLI Arguments Mode
    var allDetails: [AppDetails] = []
    for path in targetPaths {
        if let details = await inspectTarget(path: path, fetchNetwork: fetchNetwork) {
            allDetails.append(details)
            if !showJson {
                printFormattedReport(details)
            }
        } else {
            fputs("❌ Error: Target path not found or inaccessible: \(path)\n", stderr)
        }
    }
    
    if showJson {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let jsonData = try? encoder.encode(allDetails), let jsonString = String(data: jsonData, encoding: .utf8) {
            print(jsonString)
        }
    }
} else {
    // Interactive Mode: Drag & drop support
    printBanner()
    print("Drag and drop an application (.app), package (.pkg), or file here.")
    print("Press Enter to inspect. Type 'q' or 'exit' to quit.\n")
    
    while true {
        print("👉 Drop file here: ", terminator: "")
        fflush(stdout)
        
        guard let line = readLine() else {
            break
        }
        
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            continue
        }
        if trimmed.lowercased() == "q" || trimmed.lowercased() == "exit" {
            print("Goodbye!")
            break
        }
        
        let cleaned = cleanInputPath(trimmed)
        if let details = await inspectTarget(path: cleaned, fetchNetwork: fetchNetwork) {
            printFormattedReport(details)
        } else {
            print("\n❌ File not found: '\(cleaned)'")
            print("Make sure you dragged a valid .app, .pkg, or file path.\n")
        }
    }
}
