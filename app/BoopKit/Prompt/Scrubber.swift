import Foundation

/// Takes secrets out of a prompt before anything reads it: each one becomes
/// `[secret]`, keeping the name it was given (`API_KEY=[secret]`,
/// `?token=[secret]`) so the words around it still read. Plain rules, in
/// order, so a key inside a URL goes with the URL's rule. It errs toward
/// scrubbing: a long code-like word is gone too, which a reading never
/// needs.
public enum Scrubber {
    public static let secret = "[secret]"

    /// Each rule's pattern, and what replaces a match (`$1` keeps its first group).
    static let rules: [(pattern: String, template: String)] = [
        // A private key block, whole.
        (#"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----"#, secret),
        // A URL's user and password: https://me:pa55@host.
        (#"(://)[^/\s:@]+:[^/\s@]+@"#, "$1\(secret)@"),
        // A URL's secret parameters: ?token=…, &api_key=….
        (#"(?i)([?&](?:access_token|api_key|apikey|key|password|secret|sig|signature|token)=)[^&\s]+"#, "$1\(secret)"),
        // A name that says it holds a secret, then = or :, then a value of
        // six or more with a letter in it: API_KEY=…, password: hunter2,
        // "token": "…", aws_secret_access_key = …; not max_tokens: 4096.
        (#"(?i)(\b[\w.-]*(?:api[_-]?key|access[_-]?key|secret|token|password|passwd|pwd)[\w-]*["']?\s*[=:]\s*)["']?(?=[^\s"',;&]*[A-Za-z])[^\s"',;&]{6,}["']?"#, "$1\(secret)"),
        // A bearer token: Authorization: Bearer ….
        (#"(?i)(\bbearer\s+)[A-Za-z0-9._~+/=-]{12,}"#, "$1\(secret)"),
        // Keys and tokens by their shape: OpenAI and Anthropic, GitHub,
        // AWS, Slack, Google, Stripe, and a JWT.
        (#"\b(?:sk|pk|rk)-[A-Za-z0-9_-]{16,}"#, secret),
        (#"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})"#, secret),
        (#"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"#, secret),
        (#"\bxox[abprs]-[A-Za-z0-9-]{10,}"#, secret),
        (#"\bAIza[0-9A-Za-z_-]{35}"#, secret),
        (#"\b(?:sk|rk|pk)_(?:live|test)_[A-Za-z0-9]{16,}"#, secret),
        (#"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+"#, secret),
        // An email address.
        (#"[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+"#, secret),
        // Any other long run of letters and digits with both in it: a hash,
        // a token, base64. Paths keep their slashes and UUIDs their
        // hyphens, so neither matches.
        (#"\b(?=[A-Za-z0-9+_=]*[0-9])(?=[A-Za-z0-9+_=]*[A-Za-z])[A-Za-z0-9+_=]{32,}"#, secret),
    ]

    static let compiled = rules.map { (try! NSRegularExpression(pattern: $0.pattern), $0.template) }

    /// `text` with every secret replaced.
    public static func scrub(_ text: String) -> String {
        compiled.reduce(text) { text, rule in
            rule.0.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: rule.1)
        }
    }
}
