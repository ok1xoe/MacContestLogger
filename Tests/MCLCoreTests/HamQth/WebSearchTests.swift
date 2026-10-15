import Testing
@testable import MCLCore

@Suite struct WebSearchTests {

    @Test func theGoogleSearchOfACall() {
        #expect(WebSearch.googleURL(call: " ok1xoe ") == "https://www.google.com/search?q=OK1XOE")
        #expect(WebSearch.googleURL(call: "OK/DL1ABC/P") == "https://www.google.com/search?q=OK%2FDL1ABC%2FP")
        #expect(WebSearch.googleURL(call: "  ") == nil)
    }
}
