import Foundation
import MCLCore

/// N1MM „Import country list from downloaded file" (Tools): a chosen `cty.dat` becomes the DXCC source
/// (`UserCountryFile`), and „Remove imported country list" returns to Club Log / the local data. Either way the
/// contest data are reloaded and the log's country stamp is checked (an older log is flagged as with Club Log).
extension DataToolsModel {

    /// An imported country list is in use.
    public var hasImportedCountryFile: Bool {
        FileManager.default.fileExists(atPath: UserCountryFile.url(dataDir: dataDir).path)
    }

    /// Imports `file` (checked first: a file without countries is refused and the previous source stays).
    public func importCountryFile(_ file: URL) {
        let dir: URL = dataDir
        track { [weak self] in
            let result: Result<Int, UserCountryFile.Failure>
            do {
                result = try await BlockingQueue.run {
                    do throws(UserCountryFile.Failure) {
                        return .success(try UserCountryFile.install(from: file, dataDir: dir))
                    } catch {
                        return .failure(error)
                    }
                }
            } catch {
                result = .failure(.io(ErrorText.message(error)))
            }
            guard let self else { return }
            switch result {
            case .success(let count):
                await self.contest.reloadContestData()
                _ = await self.checkDxccStamp(warn: false)
                self.reportCountryFile(ContestMessage("Seznam zemí importován ze souboru %s: %s zemí",
                                                      .string(file.lastPathComponent), .int(count)))
            case .failure(let failure):
                self.reportCountryFile(Self.countryFileText(failure))
            }
        }
    }

    /// Removes the imported list (nothing to do when there is none).
    public func removeCountryFile() {
        let dir: URL = dataDir
        track { [weak self] in
            let removed: Result<Bool, UserCountryFile.Failure>
            do {
                removed = try await BlockingQueue.run {
                    do throws(UserCountryFile.Failure) {
                        return .success(try UserCountryFile.remove(dataDir: dir))
                    } catch {
                        return .failure(error)
                    }
                }
            } catch {
                removed = .failure(.io(ErrorText.message(error)))
            }
            guard let self else { return }
            switch removed {
            case .success(true):
                await self.contest.reloadContestData()
                _ = await self.checkDxccStamp(warn: false)
                self.reportCountryFile(ContestMessage("Importovaný seznam zemí odstraněn, platí původní data DXCC"))
            case .success(false):
                self.status.show("Žádný importovaný seznam zemí")
            case .failure(let failure):
                self.reportCountryFile(Self.countryFileText(failure))
            }
        }
    }

    private func reportCountryFile(_ text: ContestMessage) {
        status.show(text)
        messages.add(language.text(text), at: now())
    }

    nonisolated static func countryFileText(_ failure: UserCountryFile.Failure) -> ContestMessage {
        switch failure {
        case .noEntities:
            return ContestMessage("Soubor neobsahuje žádnou zemi ve formátu cty.dat — seznam zemí se nezměnil")
        case .io(let text):
            return ContestMessage("Seznam zemí nejde importovat: %s", .string(text))
        }
    }
}
