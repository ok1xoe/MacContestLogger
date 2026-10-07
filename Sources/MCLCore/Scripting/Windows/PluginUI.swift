import Foundation

/// The declarative content of a plugin window (protocol 1, `{"type":"set","window":…,"content":{"elements":[…]}}`):
/// a vertical stack of elements the app renders with its own styles — a plugin chooses a meaning (`dupe`, `mult`,
/// `warn`), never a colour or a font. Parsing is lenient: an element that cannot be read is left out with a warning,
/// so a newer plugin still shows what this version understands.
public struct PluginUIContent: Equatable, Sendable {

    /// At most this many rows per table and items per list (the rest is cut with a warning).
    public static let maxRows = 2_000
    /// At most this many elements in the whole content (all tabs).
    public static let maxElements = 2_000
    /// Tabs inside tabs at most this deep.
    public static let maxDepth = 3
    /// At most this many canvas shapes in the whole content (all canvases).
    public static let maxShapesTotal = 10_000

    public var elements: [PluginUIElement]
    /// What was left out or cut (shown in the messages window once per kind).
    public var warnings: [String]

    public init(elements: [PluginUIElement] = [], warnings: [String] = []) {
        self.elements = elements
        self.warnings = warnings
    }

    /// Reads `content`; a content that is not an object with an `elements` list is an error.
    public static func parse(_ content: PluginJSON) throws(PluginJSON.ParseError) -> PluginUIContent {
        guard let list = content["elements"]?.arrayValue else {
            throw PluginJSON.ParseError(message: "content must be an object with an \"elements\" list")
        }
        var parser = Parser()
        let elements: [PluginUIElement] = parser.elements(list, depth: 0)
        return PluginUIContent(elements: elements, warnings: parser.warnings)
    }

    private struct Parser {
        var warnings: [String] = []
        var count = 0
        var shapeCount = 0

        mutating func warn(_ text: String) {
            if !warnings.contains(text) {
                warnings.append(text)
            }
        }

        mutating func elements(_ list: [PluginJSON], depth: Int) -> [PluginUIElement] {
            var out: [PluginUIElement] = []
            for item in list {
                guard count < PluginUIContent.maxElements else {
                    warn("more than \(PluginUIContent.maxElements) elements: the rest is not shown")
                    break
                }
                if let element = element(item, depth: depth) {
                    count += 1
                    out.append(element)
                }
            }
            return out
        }

        mutating func element(_ item: PluginJSON, depth: Int) -> PluginUIElement? {
            guard let type = item["type"]?.stringValue else {
                warn("an element without a type was left out")
                return nil
            }
            switch type {
            case "text":
                return .text(item["text"]?.stringValue ?? "", style: style(item["style"]))
            case "table":
                return .table(table(item))
            case "list":
                return .list(list(item))
            case "button":
                guard let id = item["id"]?.stringValue else {
                    warn("a button without an id was left out")
                    return nil
                }
                return .button(id: id, label: item["label"]?.stringValue ?? id,
                               enabled: item["enabled"]?.boolValue ?? true)
            case "toggle":
                guard let id = item["id"]?.stringValue else {
                    warn("a toggle without an id was left out")
                    return nil
                }
                return .toggle(id: id, label: item["label"]?.stringValue ?? id, value: item["value"]?.boolValue ?? false)
            case "progress":
                let max: Double = item["max"]?.doubleValue ?? 1
                let value: Double = item["value"]?.doubleValue ?? 0
                return .progress(value: Swift.max(0, Swift.min(value, max)), max: Swift.max(max, 0),
                                 label: item["label"]?.stringValue)
            case "tabs":
                guard depth < PluginUIContent.maxDepth else {
                    warn("tabs nested deeper than \(PluginUIContent.maxDepth) were left out")
                    return nil
                }
                var tabs: [PluginUITab] = []
                for (index, tab) in (item["tabs"]?.arrayValue ?? []).enumerated() {
                    let id: String = tab["id"]?.stringValue ?? String(index)
                    let children: [PluginJSON] = tab["elements"]?.arrayValue ?? []
                    tabs.append(PluginUITab(id: id, title: tab["title"]?.stringValue ?? id,
                                            elements: elements(children, depth: depth + 1)))
                }
                return .tabs(id: item["id"]?.stringValue, tabs: tabs)
            case "canvas":
                return .canvas(canvas(item))
            default:
                warn("unknown element type \"\(type)\" was left out")
                return nil
            }
        }

        mutating func canvas(_ item: PluginJSON) -> PluginUICanvas {
            let width: Double = clamp(item["width"]?.doubleValue ?? 300, 1, PluginUICanvas.maxSide)
            let height: Double = clamp(item["height"]?.doubleValue ?? 200, 1, PluginUICanvas.maxSide)
            var shapes: [PluginUIShape] = []
            let source: [PluginJSON] = item["shapes"]?.arrayValue ?? []
            for (index, shape) in source.enumerated() {
                guard index < PluginUICanvas.maxShapes else {
                    warn("a canvas has more than \(PluginUICanvas.maxShapes) shapes: the rest is not drawn")
                    break
                }
                guard shapeCount < PluginUIContent.maxShapesTotal else {
                    warn("more than \(PluginUIContent.maxShapesTotal) canvas shapes in all: the rest is not drawn")
                    break
                }
                shapeCount += 1
                if let parsed = self.shape(shape) {
                    shapes.append(parsed)
                }
            }
            return PluginUICanvas(id: item["id"]?.stringValue, width: width, height: height, shapes: shapes,
                                  label: item["label"]?.stringValue)
        }

        private func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
            guard value.isFinite else { return low }
            return Swift.min(Swift.max(value, low), high)
        }

        private func number(_ value: PluginJSON?) -> Double? {
            guard let number = value?.doubleValue, number.isFinite else { return nil }
            return clamp(number, -PluginUICanvas.maxSide, 2 * PluginUICanvas.maxSide)
        }

        mutating func shape(_ item: PluginJSON) -> PluginUIShape? {
            let style: PluginUIStyle = self.style(item["style"])
            let fill: Bool = item["fill"]?.boolValue ?? false
            let lineWidth: Double = clamp(item["lineWidth"]?.doubleValue ?? 1, 0.5, 20)
            switch item["shape"]?.stringValue {
            case "line":
                guard let x1 = number(item["x1"]), let y1 = number(item["y1"]), let x2 = number(item["x2"]),
                      let y2 = number(item["y2"]) else { break }
                return .line(from: PluginUIPoint(x: x1, y: y1), to: PluginUIPoint(x: x2, y: y2), style: style,
                             lineWidth: lineWidth)
            case "rect":
                guard let x = number(item["x"]), let y = number(item["y"]), let w = number(item["w"]),
                      let h = number(item["h"]) else { break }
                return .rect(x: x, y: y, width: w, height: h, style: style, fill: fill, lineWidth: lineWidth)
            case "circle":
                guard let x = number(item["cx"]), let y = number(item["cy"]), let r = number(item["r"]) else { break }
                return .circle(center: PluginUIPoint(x: x, y: y), radius: abs(r), style: style, fill: fill,
                               lineWidth: lineWidth)
            case "path":
                let points: [PluginUIPoint] = (item["points"]?.arrayValue ?? []).prefix(PluginUICanvas.maxPathPoints)
                    .compactMap { point in
                        guard let pair = point.arrayValue, pair.count == 2, let x = number(pair[0]),
                              let y = number(pair[1]) else { return nil }
                        return PluginUIPoint(x: x, y: y)
                    }
                guard points.count >= 2 else { break }
                return .path(points: points, closed: item["closed"]?.boolValue ?? false, style: style, fill: fill,
                             lineWidth: lineWidth)
            case "text":
                guard let x = number(item["x"]), let y = number(item["y"]), let text = item["text"]?.stringValue else {
                    break
                }
                return .text(text, at: PluginUIPoint(x: x, y: y), style: style,
                             size: clamp(item["size"]?.doubleValue ?? 12, 6, 72))
            default:
                break
            }
            warn("a canvas shape that cannot be read was left out")
            return nil
        }

        mutating func style(_ value: PluginJSON?) -> PluginUIStyle {
            guard let name = value?.stringValue else { return .normal }
            guard let style = PluginUIStyle(rawValue: name) else {
                warn("unknown style \"\(name)\" shown as normal")
                return .normal
            }
            return style
        }

        mutating func cell(_ value: PluginJSON) -> PluginUICell {
            switch value {
            case .string(let text):
                return PluginUICell(text: text, style: .normal)
            case .int(let number):
                return PluginUICell(text: String(number), style: .normal)
            case .double(let number):
                return PluginUICell(text: String(number), style: .normal)
            case .bool(let flag):
                return PluginUICell(text: flag ? "true" : "false", style: .normal)
            case .object:
                let text: String = value["text"].map(Self.plain) ?? ""
                return PluginUICell(text: text, style: style(value["style"]))
            default:
                return PluginUICell(text: "", style: .normal)
            }
        }

        static func plain(_ value: PluginJSON) -> String {
            switch value {
            case .string(let text): return text
            case .int(let number): return String(number)
            case .double(let number): return String(number)
            case .bool(let flag): return flag ? "true" : "false"
            default: return ""
            }
        }

        mutating func table(_ item: PluginJSON) -> PluginUITable {
            var columns: [PluginUIColumn] = []
            for column in item["columns"]?.arrayValue ?? [] {
                if let title = column.stringValue {
                    columns.append(PluginUIColumn(title: title, alignRight: false))
                } else {
                    columns.append(PluginUIColumn(title: column["title"]?.stringValue ?? "",
                                                  alignRight: column["align"]?.stringValue == "right"))
                }
            }
            var rows: [PluginUIRow] = []
            let source: [PluginJSON] = item["rows"]?.arrayValue ?? []
            for (index, row) in source.enumerated() {
                guard index < PluginUIContent.maxRows else {
                    warn("a table has more than \(PluginUIContent.maxRows) rows: the rest is not shown")
                    break
                }
                let cells: [PluginJSON]
                var rowId: String?
                var rowStyle: PluginUIStyle = .normal
                if let list = row.arrayValue {
                    cells = list
                } else {
                    cells = row["cells"]?.arrayValue ?? []
                    rowId = row["id"]?.stringValue ?? row["id"]?.intValue.map { String($0) }
                    rowStyle = style(row["style"])
                }
                rows.append(PluginUIRow(id: rowId, cells: cells.map { cell($0) }, style: rowStyle))
            }
            return PluginUITable(id: item["id"]?.stringValue, columns: columns, rows: rows,
                                 truncated: source.count > PluginUIContent.maxRows)
        }

        mutating func list(_ item: PluginJSON) -> PluginUIList {
            var items: [PluginUIListItem] = []
            let source: [PluginJSON] = item["items"]?.arrayValue ?? []
            for (index, entry) in source.enumerated() {
                guard index < PluginUIContent.maxRows else {
                    warn("a list has more than \(PluginUIContent.maxRows) items: the rest is not shown")
                    break
                }
                let cell: PluginUICell = cell(entry)
                items.append(PluginUIListItem(id: entry["id"]?.stringValue, text: cell.text, style: cell.style))
            }
            return PluginUIList(id: item["id"]?.stringValue, items: items)
        }
    }
}

/// The meanings a plugin may give a text, a cell or a row; the app maps them to its own colours.
public enum PluginUIStyle: String, Equatable, Sendable, CaseIterable {
    case normal, title, muted, warn, new, dupe, mult
}

public struct PluginUICell: Equatable, Sendable {
    public let text: String
    public let style: PluginUIStyle

    public init(text: String, style: PluginUIStyle) {
        self.text = text
        self.style = style
    }
}

public struct PluginUIColumn: Equatable, Sendable {
    public let title: String
    public let alignRight: Bool

    public init(title: String, alignRight: Bool) {
        self.title = title
        self.alignRight = alignRight
    }
}

public struct PluginUIRow: Equatable, Sendable {
    /// The row id the click events carry (`rowId`), `nil` = the index only.
    public let id: String?
    public let cells: [PluginUICell]
    /// The style of the cells that have none of their own.
    public let style: PluginUIStyle

    public init(id: String?, cells: [PluginUICell], style: PluginUIStyle) {
        self.id = id
        self.cells = cells
        self.style = style
    }
}

public struct PluginUITable: Equatable, Sendable {
    /// The id the click events carry as `target`; a table without an id sends no events.
    public let id: String?
    public let columns: [PluginUIColumn]
    public let rows: [PluginUIRow]
    /// More rows were sent than shown.
    public let truncated: Bool

    public init(id: String?, columns: [PluginUIColumn], rows: [PluginUIRow], truncated: Bool) {
        self.id = id
        self.columns = columns
        self.rows = rows
        self.truncated = truncated
    }
}

public struct PluginUIListItem: Equatable, Sendable {
    public let id: String?
    public let text: String
    public let style: PluginUIStyle

    public init(id: String?, text: String, style: PluginUIStyle) {
        self.id = id
        self.text = text
        self.style = style
    }
}

public struct PluginUIList: Equatable, Sendable {
    public let id: String?
    public let items: [PluginUIListItem]

    public init(id: String?, items: [PluginUIListItem]) {
        self.id = id
        self.items = items
    }
}

public struct PluginUITab: Equatable, Sendable {
    public let id: String
    public let title: String
    public let elements: [PluginUIElement]

    public init(id: String, title: String, elements: [PluginUIElement]) {
        self.id = id
        self.title = title
        self.elements = elements
    }
}

public struct PluginUIPoint: Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// A shape of a canvas, in the canvas's own coordinates (origin top left, y down, points).
public enum PluginUIShape: Equatable, Sendable {
    case line(from: PluginUIPoint, to: PluginUIPoint, style: PluginUIStyle, lineWidth: Double)
    case rect(x: Double, y: Double, width: Double, height: Double, style: PluginUIStyle, fill: Bool, lineWidth: Double)
    case circle(center: PluginUIPoint, radius: Double, style: PluginUIStyle, fill: Bool, lineWidth: Double)
    case path(points: [PluginUIPoint], closed: Bool, style: PluginUIStyle, fill: Bool, lineWidth: Double)
    case text(String, at: PluginUIPoint, style: PluginUIStyle, size: Double)
}

/// A drawing area: shapes in its coordinates; with an `id` a click sends `click` with `value` `{x, y}`.
public struct PluginUICanvas: Equatable, Sendable {
    /// The largest side (points).
    public static let maxSide: Double = 4_000
    /// At most this many shapes per canvas.
    public static let maxShapes = 5_000
    /// At most this many points per path.
    public static let maxPathPoints = 2_000

    public let id: String?
    public let width: Double
    public let height: Double
    public let shapes: [PluginUIShape]
    /// What VoiceOver says for the drawing.
    public let label: String?

    public init(id: String?, width: Double, height: Double, shapes: [PluginUIShape], label: String?) {
        self.id = id
        self.width = width
        self.height = height
        self.shapes = shapes
        self.label = label
    }
}

/// One element of a plugin window.
public indirect enum PluginUIElement: Equatable, Sendable {
    case text(String, style: PluginUIStyle)
    case table(PluginUITable)
    case list(PluginUIList)
    case button(id: String, label: String, enabled: Bool)
    case toggle(id: String, label: String, value: Bool)
    case progress(value: Double, max: Double, label: String?)
    case tabs(id: String?, tabs: [PluginUITab])
    case canvas(PluginUICanvas)
}
