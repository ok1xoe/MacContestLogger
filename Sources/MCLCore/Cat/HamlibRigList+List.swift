import os

extension HamlibRigList {

    /// Java fallback list when `rigctl` is missing or prints nothing.
    static let fallback: [RigModel] = [
        RigModel(number: 1, mfg: "Hamlib", model: "Dummy"),
        RigModel(number: 2, mfg: "Hamlib", model: "NET rigctl"),
    ]

    /// Loads the model list by running `rigctl -l` (listing only, controls nothing); never returns an empty list.
    /// Blocks until the process ends — call off Swift's shared pool.
    public static func list() -> [RigModel] {
        list(binary: HamlibBinary.resolve("rigctl"))
    }

    /// `list()` with the given binary: every output line (stdout and stderr, Java `redirectErrorStream`) through
    /// `parseLine`, waiting for the end of output and of the process; an unrunnable binary or no model → `fallback`.
    static func list(binary: String) -> [RigModel] {
        let models = OSAllocatedUnfairLock(initialState: [RigModel]())
        let runner = ProcessRunner(executable: binary, arguments: ["-l"]) { line in
            if let model = parseLine(line) {
                models.withLock { $0.append(model) }
            }
        }
        do {
            try runner.start()
        } catch {
            return fallback
        }
        // Java waits without a limit (read to EOF, then `waitFor()`).
        runner.waitForOutput(timeoutMs: Int(Int32.max))
        runner.waitForExit(timeoutMs: Int(Int32.max))
        let result = models.withLock { $0 }
        return result.isEmpty ? fallback : result
    }
}
