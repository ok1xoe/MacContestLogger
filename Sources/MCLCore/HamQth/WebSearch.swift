import Foundation

/// N1MM View → „Show Google (Internet)": a web search for a call, opened in the browser (no credentials, nothing is
/// sent anywhere but the browser's own request).
public enum WebSearch {

    public static let displayName = "Google"

    /// `https://www.google.com/search?q=<CALL>` (the call trimmed and upper-cased as for the callbooks, the query
    /// percent-encoded); `nil` for a blank call.
    public static func googleURL(call: String) -> String? {
        let key: String = CallbookPolicy.key(call)
        guard !key.isEmpty else { return nil }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let query: String = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
        return "https://www.google.com/search?q=" + query
    }
}
