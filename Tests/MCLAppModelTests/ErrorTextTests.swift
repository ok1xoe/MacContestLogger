import Foundation
import MCLCore
import Testing
@testable import MCLAppModel

/// `ErrorText.message` goes through `JavaThrowable`: Java `getMessage()`, `null` printed as "null".
@Suite struct ErrorTextTests {

    @Test func javaThrowablesUseTheirJavaMessage() {
        #expect(ErrorText.message(CabrilloReaderError.unreadable(message: "Nelze načíst Cabrillo: /x",
                                                                 causeClass: "java.io.IOException"))
            == "Nelze načíst Cabrillo: /x")
        #expect(ErrorText.message(CabrilloReaderError.numberFormat(message: "For input string: \"1\""))
            == "For input string: \"1\"")
        #expect(ErrorText.message(LogbookError("Nelze otevřít deník: jdbc:sqlite:/x")) == "Nelze otevřít deník: jdbc:sqlite:/x")
        #expect(ErrorText.message(JavaIOError(nil, javaClass: "java.net.ConnectException")) == "null")
    }

    @Test func foundationErrorsKeepTheirLocalizedDescription() {
        let error = NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteOutOfSpace.rawValue)
        #expect(ErrorText.message(error) == error.localizedDescription)
    }
}
