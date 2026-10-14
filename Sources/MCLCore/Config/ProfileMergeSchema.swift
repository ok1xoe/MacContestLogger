/// The Java data-binding model of `AppConfig` v1.1.1 as Jackson 2.22 sees it in `ConfigProfiles.loadInto`
/// (`setDefaultMergeable(true)`, `List`/`Map` not mergeable): every class reachable from `AppConfig`, its known
/// property names in Jackson's order, every settable property with its declared type and what a JSON `null`
/// leaves behind. The tables (`ProfileMergeSchemaTable.swift`) are generated from the JVM probe
/// a maintainer-only probe and pinned against it by `ProfileMergeJavaParityTests`.
///
/// **A configuration field that exists only in Swift** (Java is frozen at v1.1.1, so the probe can never report
/// it): add its property to `swiftOnlyProperties` below — keyed by the Java name of the owning class, with the
/// Swift `CodingKey` as the name, its kind and what `null` does (normally `.fieldDefault`). Do not edit the
/// generated table. Without the entry, a profile saved by Swift (which writes the new key) is rejected with
/// `UnrecognizedPropertyException`; the tripwires are `ProfileMergeTests.profileSavedBySwiftMergesBack` and
/// `ProfileMergeJavaParityTests.swiftWritesJacksonsKeys`. Swift-only names are appended to the end of the known
/// properties of the "Unrecognized field" message (Java has no such message to match).
enum ProfileMergeSchema {

    static let root: String = "cz.ok1xoe.maccontestlogger.config.AppConfig"

    /// Hand-maintained Swift-only properties by owning Java class (see the type's documentation): the two switches
    /// of the SCP and N+1 rows (`scpSuggestionsEnabled`, `nPlusOneEnabled`), the preferred online callbook
    /// (`preferredCallbook`), the Dupesheet's suffix order (`dupesheetSortBySuffix`), the Check window (`check*`) and
    /// the unmatched call mark (`showUnmatchedCallMark`), Club Log's DXCC data switch (`clubLog.ctyEnabled`), the DX
    /// cluster Bands/Modes spot filter (`dxCluster.spotFilter*`), the band map options (`dxCluster.bandmap*`), the band map US licence
    /// lines (`dxCluster.showUsLicenseLines`), the band map's call-frame, tuning tolerances and packet spot mode
    /// (`dxCluster.callFrame`, `dxCluster.tuningTolerance*Hz`, `dxCluster.spotModeOnTune`), the Telnet window options
    /// (`dxCluster.clusterSoftware`, `autoLogon`, `showButtons`, `showDxCount`, `saveSpots`,
    /// `randomizeSpotFrequencies`), the blacklist switch (`dxCluster.blacklistEnabled`), the spot comment, S&P spotting
    /// and special calls (`dxCluster.spotComment`, `spotAllSpQsos`, `specialCalls*`), the call stack
    /// (`esm.nextCallKey`, `esm.callStack*`), digital call stacking (`digital.digitalCallStacking`), the call history
    /// switches and extra
    /// files (`callHistory*`) and a contest's own call history and function key files (`contestSetups.*.callHistoryFile`,
    /// `contestSetups.*.functionKeyFiles`) its first serial and master.scp (`contestSetups.*.firstSerial`, `contestSetups.*.scpFile`).
    static let swiftOnlyProperties: [String: [Property]] = [
        root: [
            Property("scpSuggestionsEnabled", .boolean, .fieldDefault),
            Property("nPlusOneEnabled", .boolean, .fieldDefault),
            Property("preferredCallbook", .string, .fieldDefault),
            Property("checkHiddenPanes", .list(.string), .fieldDefault),
            Property("checkPaneWeights", .map(.integer), .fieldDefault),
            Property("checkYankOrder", .list(.string), .fieldDefault),
            Property("checkYankAllowDupes", .boolean, .fieldDefault),
            Property("checkFavorEndDifferences", .boolean, .fieldDefault),
            Property("checkTelnetMinSpots", .int, .fieldDefault),
            Property("checkReverseEnabled", .boolean, .fieldDefault),
            Property("checkReverseThreshold", .int, .fieldDefault),
            Property("checkReverseFromStart", .boolean, .fieldDefault),
            Property("showUnmatchedCallMark", .boolean, .fieldDefault),
            Property("dupesheetSortBySuffix", .boolean, .fieldDefault),
            Property("showSentCw", .boolean, .fieldDefault),
            Property("cwSpeedStepSecondary", .int, .fieldDefault),
            Property("clearPrefilledExchange", .boolean, .fieldDefault),
            Property("entryHiddenBands", .list(.string), .fieldDefault),
            Property("entryBandButtonsClick", .boolean, .fieldDefault),
            Property("entryShowUtcClock", .boolean, .fieldDefault),
            Property("logShowModeColumn", .boolean, .fieldDefault),
            Property("multGridBands", .map(.string), .fieldDefault),
            Property("multExpected", .map(.string), .fieldDefault),
            Property("multGridShowAll", .list(.string), .fieldDefault),
            Property("moveMultsDisplay", .string, .fieldDefault),
            Property("moveMultsRange", .string, .fieldDefault),
            Property("moveMultsBands", .string, .fieldDefault),
            Property("moveMultsModes", .string, .fieldDefault),
            Property("graylineLayers", .list(.string), .fieldDefault),
            Property("graylineSpots", .int, .fieldDefault),
            Property("entryHiddenSections", .list(.string), .fieldDefault),
            Property("resetRxAfterRunQso", .boolean, .fieldDefault),
            Property("macroQsyStepKHz", .int, .fieldDefault),
            Property("functionKeysPerOperator", .boolean, .fieldDefault),
            Property("callHistoryLookupEnabled", .boolean, .fieldDefault),
            Property("callHistoryExtraFiles", .list(.string), .fieldDefault),
            Property("callHistoryShowUserInfo", .boolean, .fieldDefault),
        ],
        "cz.ok1xoe.maccontestlogger.config.ContestSetup": [
            Property("callHistoryFile", .string, .fieldDefault),
            Property("functionKeyFiles", .map(.string), .fieldDefault),
            Property("firstSerial", .int, .fieldDefault),
            Property("scpFile", .string, .fieldDefault),
            Property("goalFile", .string, .fieldDefault),
        ],
        "cz.ok1xoe.maccontestlogger.config.DxClusterConfig": [
            Property("spotFilterHiddenBands", .list(.string), .fieldDefault),
            Property("spotFilterHiddenModes", .list(.string), .fieldDefault),
            Property("spotFilterContest", .boolean, .fieldDefault),
            Property("spotFilterSpotterContinents", .list(.string), .fieldDefault),
            Property("spotFilterSpotterOwnCountry", .boolean, .fieldDefault),
            Property("spotFilterHideNonWorkable", .boolean, .fieldDefault),
            Property("showUsLicenseLines", .boolean, .fieldDefault),
            Property("bandmapLowestAtBottom", .boolean, .fieldDefault),
            Property("bandmapWheelDisabled", .boolean, .fieldDefault),
            Property("callFrame", .boolean, .fieldDefault),
            Property("tuningToleranceCwHz", .int, .fieldDefault),
            Property("tuningToleranceSsbHz", .int, .fieldDefault),
            Property("tuningToleranceDigiHz", .int, .fieldDefault),
            Property("spotModeOnTune", .boolean, .fieldDefault),
            Property("bandmapButtons", .list(.bean("cz.ok1xoe.maccontestlogger.config.DxClusterCommand")),
                     .fieldDefault),
            Property("filterCwWideHz", .int, .fieldDefault),
            Property("filterCwNarrowHz", .int, .fieldDefault),
            Property("filterSsbWideHz", .int, .fieldDefault),
            Property("filterSsbNarrowHz", .int, .fieldDefault),
            Property("filterDigiWideHz", .int, .fieldDefault),
            Property("filterDigiNarrowHz", .int, .fieldDefault),
            Property("clusterSoftware", .string, .fieldDefault),
            Property("autoLogon", .boolean, .fieldDefault),
            Property("showButtons", .boolean, .fieldDefault),
            Property("showDxCount", .int, .fieldDefault),
            Property("saveSpots", .boolean, .fieldDefault),
            Property("randomizeSpotFrequencies", .boolean, .fieldDefault),
            Property("spotFilterSpotterPrefixes", .list(.string), .fieldDefault),
            Property("spotFilterSpotterCallAreas", .list(.string), .fieldDefault),
            Property("spotFilterOnlyCallHistory", .boolean, .fieldDefault),
            Property("spotFilterOnlyWorked", .boolean, .fieldDefault),
            Property("spotFilterHideBeacons", .boolean, .fieldDefault),
            Property("spotFilterRemoveBusted", .boolean, .fieldDefault),
            Property("spotFilterBustedTwoChars", .boolean, .fieldDefault),
            Property("spotFilterPreferredSpotters", .list(.string), .fieldDefault),
            Property("blacklistEnabled", .boolean, .fieldDefault),
            Property("spotComment", .string, .fieldDefault),
            Property("spotAllSpQsos", .boolean, .fieldDefault),
            Property("specialCalls", .list(.string), .fieldDefault),
            Property("specialCallsIncludeBonus", .boolean, .fieldDefault),
        ],
        "cz.ok1xoe.maccontestlogger.config.RunModeConfig": [
            Property("repeatMaxMinutes", .int, .fieldDefault),
        ],
        "cz.ok1xoe.maccontestlogger.config.VoiceKeyerConfig": [
            Property("outputDevice2", .string, .fieldDefault),
            Property("outputLevel", .int, .fieldDefault),
        ],
        "cz.ok1xoe.maccontestlogger.config.CwKeyerConfig": [
            Property("stackMessages", .boolean, .fieldDefault),
        ],
        "cz.ok1xoe.maccontestlogger.config.ClubLogConfig": [
            Property("ctyEnabled", .boolean, .fieldDefault),
        ],
        "cz.ok1xoe.maccontestlogger.config.EsmConfig": [
            Property("nextCallKey", .int, .fieldDefault),
            Property("callStackOrder", .string, .fieldDefault),
            Property("callStackClearOnBandChange", .boolean, .fieldDefault),
            Property("keyMap", .list(.int), .fieldDefault),
            Property("sendPartialCalls", .boolean, .fieldDefault),
            Property("callExchangeSeparator", .string, .fieldDefault),
        ],
        "cz.ok1xoe.maccontestlogger.config.DigitalConfig": [
            Property("digitalCallStacking", .boolean, .fieldDefault),
            Property("autoTrxUpdate", .boolean, .fieldDefault),
            Property("rttyModem", .string, .fieldDefault),
            Property("pskModem", .string, .fieldDefault),
            Property("callValidity", .string, .fieldDefault),
            Property("validateScp", .boolean, .fieldDefault),
            Property("validateCallHistory", .boolean, .fieldDefault),
            Property("validateSpotted", .boolean, .fieldDefault),
            Property("validateLogged", .boolean, .fieldDefault),
            Property("scpGarbageSearch", .boolean, .fieldDefault),
            Property("highlightBackground", .boolean, .fieldDefault),
            Property("nonScrollingRx", .boolean, .fieldDefault),
            Property("pauseOnCallHover", .boolean, .fieldDefault),
            Property("hoverMode", .boolean, .fieldDefault),
            Property("rightClickReturn", .boolean, .fieldDefault),
            Property("sendSpaceOnClick", .boolean, .fieldDefault),
            Property("captionRadioFrequency", .boolean, .fieldDefault),
            Property("grabOrder", .string, .fieldDefault),
            Property("grabNoDupes", .boolean, .fieldDefault),
            Property("grabOnlyScp", .boolean, .fieldDefault),
            Property("grabClearOnQsy", .boolean, .fieldDefault),
            Property("grabClearOnCq", .boolean, .fieldDefault),
            Property("grabSendSpace", .boolean, .fieldDefault),
            Property("grabAddToBandmap", .boolean, .fieldDefault),
            Property("cwIdEnabled", .boolean, .fieldDefault),
            Property("cwIdText", .string, .fieldDefault),
            Property("diButtonCount", .int, .fieldDefault),
            Property("rxOutputToFile", .boolean, .fieldDefault),
            Property("diMessages", .list(.bean("cz.ok1xoe.maccontestlogger.config.FunctionKeyMessage")), .fieldDefault),
            Property("alignRttyHz", .int, .fieldDefault),
            Property("alignOtherHz", .int, .fieldDefault),
            Property("afcOnCq", .boolean, .fieldDefault),
            Property("netWithRunChange", .boolean, .fieldDefault),
            Property("shiftCompEnabled", .boolean, .fieldDefault),
            Property("shiftCompHz", .int, .fieldDefault),
            Property("fldigi2Host", .string, .fieldDefault),
            Property("fldigi2Port", .int, .fieldDefault),
            Property("extraRx", .string, .fieldDefault),
            Property("extraRxToGrab", .boolean, .fieldDefault),
            Property("rttyInterface", .string, .fieldDefault),
            Property("tncType", .string, .fieldDefault),
            Property("tncPort", .string, .fieldDefault),
            Property("tncBaud", .int, .fieldDefault),
            Property("tncTx", .string, .fieldDefault),
            Property("tncRx", .string, .fieldDefault),
            Property("tncEsc", .string, .fieldDefault),
            Property("tinyFskPort", .string, .fieldDefault),
            Property("wkRttyBaud", .int, .fieldDefault),
            Property("wkRttyReverse", .boolean, .fieldDefault),
            Property("wkRttyFskOnKey", .boolean, .fieldDefault),
            Property("diFontName", .string, .fieldDefault),
            Property("diTextColor", .string, .fieldDefault),
            Property("diBackgroundColor", .string, .fieldDefault),
        ],
        "cz.ok1xoe.maccontestlogger.config.WsjtxConfig": [
            Property("highlightCalls", .boolean, .fieldDefault),
            Property("mirrorDxCall", .boolean, .fieldDefault),
            Property("clearDecodesOnBandChange", .boolean, .fieldDefault),
            Property("jtdxTcpEnabled", .boolean, .fieldDefault),
            Property("jtdxTcpBind", .string, .fieldDefault),
            Property("programPath", .string, .fieldDefault),
            Property("programArgs", .string, .fieldDefault),
            Property("radio2Id", .string, .fieldDefault),
            Property("openDecodesOnLaunch", .boolean, .fieldDefault),
        ],
    ]

    /// The Swift-only keys as paths in a written configuration (`name` on the root, `owner/name` in a bean property
    /// of the root), for the parity gates that compare against what v1.1.1 writes.
    static let swiftOnlyPaths: [[String]] = {
        var paths: [[String]] = []
        let rootProperties: [Property] = generatedClasses[root]?.properties ?? []
        for (owner, properties) in swiftOnlyProperties.sorted(by: { $0.key < $1.key }) {
            let prefixes: [[String]] = owner == root
                ? [[]]
                : rootProperties.filter { $0.kind == .bean(owner) }.map { [$0.name] }
            for prefix in prefixes {
                for property in properties {
                    paths.append(prefix + [property.name])
                }
            }
        }
        return paths
    }()

    /// The schema in use: the generated table extended by `swiftOnlyProperties`.
    static let classes: [String: BeanClass] = extending(generatedClasses, with: swiftOnlyProperties)

    /// `classes` with `extra` properties appended to their owners (also to the known property names).
    static func extending(_ classes: [String: BeanClass],
                          with extra: [String: [Property]]) -> [String: BeanClass] {
        var result: [String: BeanClass] = classes
        for (owner, properties) in extra {
            guard let bean = result[owner] else { continue }
            let names: [String] = properties.map(\.name)
            result[owner] = BeanClass(name: bean.name, known: bean.known + names,
                                      properties: bean.properties + properties)
        }
        return result
    }

    /// The declared Java type of a property.
    indirect enum Kind: Equatable, Sendable {
        case string, int, long, double, boolean
        /// `java.lang.Integer` (a map value).
        case integer
        /// An enum, by Java class name.
        case enumeration(String)
        /// A bean, by Java class name (a property of this type is merged into the current instance).
        case bean(String)
        /// `List<…>` (deserialized as a new `ArrayList`, replaces the current one).
        case list(Kind)
        /// `Map<String, …>` (deserialized as a new `LinkedHashMap`, replaces the current one).
        case map(Kind)

        /// `ClassUtil.getTypeDescription` / `ClassUtil.nameOf` (without the backticks).
        var javaType: String {
            switch self {
            case .string: return "java.lang.String"
            case .int: return "int"
            case .long: return "long"
            case .double: return "double"
            case .boolean: return "boolean"
            case .integer: return "java.lang.Integer"
            case .enumeration(let name), .bean(let name): return name
            case .list(let element): return "java.util.ArrayList<" + element.javaType + ">"
            case .map(let value): return "java.util.LinkedHashMap<java.lang.String," + value.javaType + ">"
            }
        }
    }

    /// What `{"property": null}` leaves in the configuration, measured through the getter.
    enum NullOutcome: Equatable, Sendable {
        /// The getter returns `null` (Swift: the field default when decoding).
        case null
        /// The getter returns the value of a new instance (the setter or the getter substitutes it).
        case fieldDefault
        /// The getter returns this value.
        case value(ProfileJson)
        /// The setter throws `NullPointerException` (`InfoWindowConfig.setOffTimeMode`).
        case throwsNullPointer
    }

    struct Property: Sendable {
        let name: String
        let kind: Kind
        let onNull: NullOutcome

        init(_ name: String, _ kind: Kind, _ onNull: NullOutcome) {
            self.name = name
            self.kind = kind
            self.onNull = onNull
        }
    }

    struct BeanClass: Sendable {
        let name: String
        /// `getKnownPropertyNames()` in Jackson's iteration order (the "Unrecognized field" message).
        let known: [String]
        let properties: [Property]

        func property(_ name: String) -> Property? {
            properties.first { $0.name == name }
        }
    }

    struct EnumType: Sendable {
        /// The constants by ordinal (index coercion).
        let constants: [String]
        /// The constants in Jackson's lookup order (the "not one of the values accepted" message).
        let keys: [String]
    }
}
