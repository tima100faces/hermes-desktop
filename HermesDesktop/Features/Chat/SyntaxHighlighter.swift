import SwiftUI

// MARK: - SyntaxHighlighter
//
// Minimal, dependency-free syntax highlighter for CodeBlockView
// (docs/UI-SPEC.md §4): keywords → hkAccent2, strings → hkSuccess,
// comments → hkNeutral, everything else → hkMuted.
//
// A single hand-written scanner, not a real per-language parser: it
// recognizes line/block comments and quoted strings, then colors
// keywords from one merged list spanning the languages this app's code
// blocks actually see (Swift, Python, JS/TS, Go, Rust, C-family, shell,
// SQL). Good enough to make code readable at a glance; not 100%
// language-accurate (e.g. a Go-only keyword lights up in a Python
// block) — an acceptable trade-off for staying dependency-free.

enum SyntaxHighlighter {

    static func highlight(code: String, language: String?) -> AttributedString {
        let lang = (language ?? "").lowercased()
        let lineComment = lineCommentPrefix(for: lang)
        let allowBlockComment = blockCommentSupported(for: lang)

        var result = AttributedString()
        var buffer = ""

        func appendSpan(_ text: String, color: Color) {
            guard !text.isEmpty else { return }
            var piece = AttributedString(text)
            piece.foregroundColor = color
            result += piece
        }

        func flushBuffer() {
            guard !buffer.isEmpty else { return }
            highlightPlainRun(buffer, appendSpan: appendSpan)
            buffer = ""
        }

        let chars = Array(code)
        let n = chars.count
        var i = 0

        while i < n {
            let c = chars[i]

            if let lineComment, matches(chars, at: i, prefix: lineComment) {
                flushBuffer()
                var j = i
                while j < n, chars[j] != "\n" { j += 1 }
                appendSpan(String(chars[i..<j]), color: .hkNeutral)
                i = j
                continue
            }

            if allowBlockComment, c == "/", i + 1 < n, chars[i + 1] == "*" {
                flushBuffer()
                var j = i + 2
                while j + 1 < n, !(chars[j] == "*" && chars[j + 1] == "/") { j += 1 }
                j = min(j + 2, n)
                appendSpan(String(chars[i..<j]), color: .hkNeutral)
                i = j
                continue
            }

            if c == "\"" || c == "'" || c == "`" {
                flushBuffer()
                let quote = c
                var j = i + 1
                while j < n, chars[j] != quote {
                    j += (chars[j] == "\\" && j + 1 < n) ? 2 : 1
                }
                j = min(j + 1, n)
                appendSpan(String(chars[i..<j]), color: .hkSuccess)
                i = j
                continue
            }

            buffer.append(c)
            i += 1
        }
        flushBuffer()

        return result
    }

    // MARK: - Plain-run word/keyword split

    private static func highlightPlainRun(_ text: String, appendSpan: (String, Color) -> Void) {
        var word = ""
        var punctuation = ""

        func flushWord() {
            guard !word.isEmpty else { return }
            appendSpan(word, keywords.contains(word) ? .hkAccent2 : .hkMuted)
            word = ""
        }

        func flushPunctuation() {
            guard !punctuation.isEmpty else { return }
            appendSpan(punctuation, .hkMuted)
            punctuation = ""
        }

        for c in text {
            if c.isLetter || c.isNumber || c == "_" {
                flushPunctuation()
                word.append(c)
            } else {
                flushWord()
                punctuation.append(c)
            }
        }
        flushWord()
        flushPunctuation()
    }

    // MARK: - Matching Helper

    private static func matches(_ chars: [Character], at index: Int, prefix: String) -> Bool {
        let p = Array(prefix)
        guard index + p.count <= chars.count else { return false }
        for k in 0..<p.count where chars[index + k] != p[k] { return false }
        return true
    }

    // MARK: - Per-Language Comment Style

    private static func lineCommentPrefix(for language: String) -> String? {
        switch language {
        case "python", "py", "bash", "sh", "shell", "zsh", "ruby", "rb",
             "yaml", "yml", "toml", "r", "perl", "makefile", "make":
            return "#"
        case "sql":
            return "--"
        case "html", "xml", "markdown", "md":
            return nil
        default:
            return "//"
        }
    }

    private static func blockCommentSupported(for language: String) -> Bool {
        switch language {
        case "python", "py", "bash", "sh", "shell", "zsh", "ruby", "rb",
             "yaml", "yml", "toml", "sql", "html", "xml", "json",
             "markdown", "md", "makefile", "make":
            return false
        default:
            return true
        }
    }

    // MARK: - Merged Keyword Set

    /// One keyword list spanning the languages this app's code blocks
    /// typically use, rather than a per-language dictionary — keeps the
    /// highlighter to a single pass with no language-specific parser.
    private static let keywords: Set<String> = [
        // Swift
        "func", "var", "let", "if", "else", "guard", "for", "while", "repeat",
        "switch", "case", "default", "break", "continue", "return", "struct",
        "class", "enum", "protocol", "extension", "import", "init", "deinit",
        "self", "Self", "super", "nil", "true", "false", "throws", "throw",
        "try", "catch", "do", "async", "await", "static", "private", "public",
        "internal", "fileprivate", "open", "final", "override", "mutating",
        "inout", "where", "in", "as", "is", "typealias", "associatedtype",
        "some", "any", "weak", "unowned", "lazy", "defer", "subscript",

        // Python
        "def", "elif", "except", "finally", "with", "from", "yield", "lambda",
        "pass", "global", "nonlocal", "del", "raise", "assert", "not", "and",
        "or", "None", "True", "False",

        // JavaScript / TypeScript
        "function", "const", "extends", "new", "delete", "typeof",
        "instanceof", "of", "undefined", "void", "get", "set", "interface",
        "type", "enum", "implements", "protected", "readonly", "export",

        // Go
        "package", "range", "chan", "go", "select", "fallthrough",

        // Rust
        "fn", "mut", "loop", "match", "trait", "impl", "pub", "use", "mod",
        "crate", "move", "ref", "dyn", "unsafe", "Some", "Ok", "Err",

        // C / C++
        "int", "float", "double", "char", "void", "virtual", "template",
        "namespace", "typedef", "union", "nullptr", "include", "define",
        "const", "public", "private", "protected",

        // Shell
        "then", "fi", "elif", "esac", "done", "local", "export", "echo",

        // SQL
        "SELECT", "FROM", "WHERE", "INSERT", "INTO", "VALUES", "UPDATE",
        "SET", "DELETE", "JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "ON",
        "AND", "OR", "NOT", "NULL", "AS", "GROUP", "BY", "ORDER", "HAVING",
        "LIMIT", "CREATE", "TABLE", "ALTER", "DROP", "PRIMARY", "KEY",
        "FOREIGN", "REFERENCES", "DISTINCT", "UNION", "ALL",
    ]
}
