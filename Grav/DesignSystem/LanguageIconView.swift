import AppKit
import SwiftUI

/// Renders the official vector SVG language/tool icon (from the bundled 79-icon Devicon catalog)
/// corresponding to any file path or filename, with clean macOS fallbacks for `.app` bundles and
/// unknown extensions.
public struct LanguageIconView: View {
    public var path: String
    public var changeKind: FileChangeKind?
    public var size: CGFloat

    public init(path: String, changeKind: FileChangeKind? = nil, size: CGFloat = 15) {
        self.path = path
        self.changeKind = changeKind
        self.size = size
    }

    public var body: some View {
        let isDeleted = changeKind == .delete

        Group {
            if let assetName = Self.assetName(for: path),
               let nsImage = Self.cachedAsset(named: assetName)
            {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .opacity(isDeleted ? 0.55 : 1.0)
                    .saturation(isDeleted ? 0.35 : 1.0)
            } else if path.lowercased().hasSuffix(".app") {
                Image(systemName: isDeleted ? "trash" : "app.fill")
                    .font(.system(size: size * 0.78, weight: .medium))
                    .foregroundStyle(isDeleted ? GravPalette.coral : Color.white.opacity(0.68))
            } else {
                fallbackSymbol(isDeleted: isDeleted)
            }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if isDeleted && Self.assetName(for: path) != nil {
                Circle()
                    .fill(GravPalette.coral)
                    .frame(width: max(4.5, size * 0.32), height: max(4.5, size * 0.32))
                    .overlay(
                        Circle()
                            .strokeBorder(Color.black, lineWidth: 1)
                    )
                    .offset(x: 1.5, y: 1.5)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func fallbackSymbol(isDeleted: Bool) -> some View {
        let (symbol, color): (String, Color) = {
            if isDeleted { return ("trash", GravPalette.coral) }
            switch changeKind {
            case .create: return ("doc.badge.plus", GravPalette.emerald)
            case .edit, .overwrite: return ("doc.text", GravPalette.fileEdit)
            case .delete: return ("trash", GravPalette.coral)
            case .none: return ("doc.text", Color.white.opacity(0.58))
            }
        }()
        Image(systemName: symbol)
            .font(.system(size: size * 0.78, weight: .medium))
            .foregroundStyle(color)
    }

    // MARK: - Asset Cache & Comprehensive Extension / Filename Mapping (150+ Languages & Configs)

    @MainActor
    private static var imageCache: [String: NSImage] = [:]

    @MainActor
    private static func cachedAsset(named name: String) -> NSImage? {
        if let cached = imageCache[name] {
            return cached
        }
        if let loaded = NSImage(named: name) {
            imageCache[name] = loaded
            return loaded
        }
        return nil
    }

    /// Maps file basenames and extensions to the corresponding bundled Devicon SVG `lang_<key>` asset.
    public static func assetName(for path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        let filename = url.lastPathComponent.lowercased()
        let ext = url.pathExtension.lowercased()

        // 1. Exact special filenames & dotfiles
        if let exact = exactFilenameMap[filename] {
            return "lang_\(exact)"
        }
        if filename.hasPrefix("dockerfile") || filename.hasPrefix("docker-compose") || filename == "compose.yml" || filename == "compose.yaml" {
            return "lang_docker"
        }
        if filename.hasPrefix("next.config.") {
            return "lang_nextjs"
        }
        if filename.hasPrefix("vite.config.") {
            return "lang_vitejs"
        }
        if filename.hasPrefix("tailwind.config.") {
            return "lang_tailwindcss"
        }
        if filename.hasPrefix("webpack.config.") {
            return "lang_webpack"
        }
        if filename.hasPrefix(".eslint") || filename.hasPrefix("eslint.config.") {
            return "lang_eslint"
        }
        if filename.hasPrefix("astro.config.") {
            return "lang_astro"
        }
        if filename.hasPrefix("svelte.config.") {
            return "lang_svelte"
        }
        if filename.hasPrefix("nuxt.config.") || filename.hasPrefix("vue.config.") {
            return "lang_vuejs"
        }
        if filename.hasPrefix("bun.") || filename == "bunfig.toml" {
            return "lang_bun"
        }
        if filename.hasPrefix("deno.") {
            return "lang_deno"
        }
        if filename.hasPrefix("firebase.") || filename == ".firebaserc" {
            return "lang_firebase"
        }
        if filename.hasPrefix("nginx") {
            return "lang_nginx"
        }
        if filename.hasPrefix("cmakelists") {
            return "lang_cmake"
        }
        if filename.hasPrefix(".git") {
            return "lang_git"
        }
        if path.lowercased().contains("/.github/") {
            return "lang_github"
        }

        // 2. File extension map (covering 100+ programming, markup, schema & DevOps extensions)
        if let key = extensionMap[ext] {
            return "lang_\(key)"
        }
        return nil
    }

    private static let exactFilenameMap: [String: String] = [
        "package.swift": "swift",
        "package.json": "npm",
        "package-lock.json": "npm",
        ".npmrc": "npm",
        "tsconfig.json": "typescript",
        "jsconfig.json": "javascript",
        "cargo.toml": "rust",
        "cargo.lock": "rust",
        "go.mod": "go",
        "go.sum": "go",
        "requirements.txt": "python",
        "pyproject.toml": "python",
        "pipfile": "python",
        "gemfile": "ruby",
        "gemfile.lock": "ruby",
        "rakefile": "ruby",
        "podfile": "apple",
        "composer.json": "php",
        "pubspec.yaml": "flutter",
        "build.gradle": "gradle",
        "build.gradle.kts": "gradle",
        "settings.gradle": "gradle",
        "settings.gradle.kts": "gradle",
        "gradlew": "gradle",
        "project.pbxproj": "xcode",
        "contents.xcworkspacedata": "xcode",
        "info.plist": "apple",
        "entitlements": "apple",
        "schema.prisma": "prisma",
        "ansible.cfg": "ansible",
        "redis.conf": "redis",
        "readme.md": "markdown",
        "changelog.md": "markdown",
    ]

    private static let extensionMap: [String: String] = [
        // Apple / Native / Systems
        "swift": "swift",
        "m": "objectivec",
        "mm": "objectivec",
        "c": "c",
        "h": "c",
        "cpp": "cplusplus",
        "cc": "cplusplus",
        "cxx": "cplusplus",
        "hpp": "cplusplus",
        "hh": "cplusplus",
        "hxx": "cplusplus",
        "rs": "rust",
        "go": "go",
        "zig": "zig",
        "nim": "nim",
        "cmake": "cmake",
        "xcodeproj": "xcode",
        "xcworkspace": "xcode",
        "pbxproj": "xcode",
        "storyboard": "xcode",
        "xib": "xcode",
        "xcassets": "xcode",
        "entitlements": "apple",
        "plist": "apple",
        "wasm": "wasm",
        "wat": "wasm",

        // Web / JS / TS / Frontend Frameworks
        "ts": "typescript",
        "mts": "typescript",
        "cts": "typescript",
        "d.ts": "typescript",
        "tsx": "react",
        "jsx": "react",
        "js": "javascript",
        "mjs": "javascript",
        "cjs": "javascript",
        "html": "html5",
        "htm": "html5",
        "css": "css3",
        "scss": "sass",
        "sass": "sass",
        "vue": "vuejs",
        "svelte": "svelte",
        "astro": "astro",
        "graphql": "graphql",
        "gql": "graphql",

        // Backend / Scripting / Functional / JVM / .NET
        "py": "python",
        "pyi": "python",
        "pyw": "python",
        "rb": "ruby",
        "erb": "ruby",
        "php": "php",
        "java": "java",
        "kt": "kotlin",
        "kts": "kotlin",
        "scala": "scala",
        "sc": "scala",
        "cs": "csharp",
        "csx": "csharp",
        "fs": "fsharp",
        "fsx": "fsharp",
        "fsi": "fsharp",
        "dart": "dart",
        "ex": "elixir",
        "exs": "elixir",
        "erl": "erlang",
        "hrl": "erlang",
        "hs": "haskell",
        "lhs": "haskell",
        "clj": "clojure",
        "cljs": "clojure",
        "cljc": "clojure",
        "edn": "clojure",
        "lua": "lua",
        "pl": "perl",
        "pm": "perl",
        "r": "r",
        "rmd": "r",
        "jl": "julia",
        "ml": "ocaml",
        "mli": "ocaml",
        "groovy": "groovy",
        "gradle": "gradle",
        "sol": "solidity",

        // Shell / Infrastructure / Data / Docs
        "sh": "bash",
        "bash": "bash",
        "zsh": "bash",
        "fish": "bash",
        "ps1": "powershell",
        "psm1": "powershell",
        "dockerfile": "docker",
        "tf": "terraform",
        "tfvars": "terraform",
        "hcl": "terraform",
        "json": "json",
        "jsonc": "json",
        "jsonl": "json",
        "yml": "yaml",
        "yaml": "yaml",
        "toml": "toml",
        "xml": "xml",
        "svg": "xml",
        "md": "markdown",
        "mdx": "markdown",
        "markdown": "markdown",
        "sql": "postgresql",
        "psql": "postgresql",
        "sqlite": "sqlite",
        "db": "sqlite",
        "prisma": "prisma",
        "proto": "protobuf",
        "tex": "latex",
        "bib": "latex",
        "ipynb": "jupyter",
        "conf": "nginx",
        "nginx": "nginx",
    ]
}
