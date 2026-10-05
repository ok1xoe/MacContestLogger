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
    /// of the SCP and N+1 rows (`scpSuggestionsEnabled`, `nPlusOneEnabled`) and the preferred online callbook
    /// (`preferredCallbook`).
    static let swiftOnlyProperties: [String: [Property]] = [
        root: [
            Property("scpSuggestionsEnabled", .boolean, .fieldDefault),
            Property("nPlusOneEnabled", .boolean, .fieldDefault),
            Property("preferredCallbook", .string, .fieldDefault),
        ],
    ]

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
