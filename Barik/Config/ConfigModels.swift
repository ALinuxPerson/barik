import Foundation

struct RootToml: Decodable {
    var theme: String?
    var widgets: WidgetsSection
    var showBackground: Bool // Pd618

    init() {
        self.theme = nil
        self.widgets = WidgetsSection(displayed: [], others: [:])
        self.showBackground = true // P2519
    }

    private enum CodingKeys: String, CodingKey {
        case theme
        case widgets
        case showBackground // Pd618
    }
}

struct Config {
    let rootToml: RootToml

    init(rootToml: RootToml = RootToml()) {
        self.rootToml = rootToml
    }

    var theme: String {
        rootToml.theme ?? "light"
    }
}

typealias ConfigData = [String: TOMLValue]

class ConfigProvider: ObservableObject {
    @Published var config: ConfigData

    init(config: ConfigData) {
        self.config = config
    }
}

struct WidgetsSection: Decodable {
    let displayed: [TomlWidgetItem]
    let others: [String: ConfigData]

    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int? = nil

        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(
        displayed: [TomlWidgetItem],
        others: [String: ConfigData]
    ) {
        self.displayed = displayed
        self.others = others
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)

        let displayedKey = DynamicKey(stringValue: "displayed")!
        let displayedArray = try container.decode(
            [TomlWidgetItem].self, forKey: displayedKey)
        self.displayed = displayedArray

        var tempDict = [String: ConfigData]()

        for key in container.allKeys {
            guard key.stringValue != "displayed" else { continue }

            let nested = try container.nestedContainer(
                keyedBy: DynamicKey.self, forKey: key)

            var widgetDict = ConfigData()
            for nestedKey in nested.allKeys {
                let value = try nested.decode(TOMLValue.self, forKey: nestedKey)
                widgetDict[nestedKey.stringValue] = value
            }
            tempDict[key.stringValue] = widgetDict
        }

        self.others = tempDict
    }

    func config(for widgetId: String) -> ConfigData? {
        let keys = widgetId.split(separator: ".").map { String($0) }

        var current: Any? = others

        for key in keys {
            guard let dict = current as? [String: Any] else {
                return nil
            }
            current = dict[key]
        }

        return (current as? TOMLValue)?.dictionaryValue as? ConfigData
    }
}

struct TomlWidgetItem: Decodable {
    let id: String
    let inlineParams: ConfigData

    init(id: String, inlineParams: ConfigData) {
        self.id = id
        self.inlineParams = inlineParams
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let strValue = try? container.decode(String.self) {
            self.id = strValue
            self.inlineParams = [:]
            return
        }

        let dictValue = try container.decode([String: ConfigData].self)

        guard dictValue.count == 1,
            let (widgetId, params) = dictValue.first
        else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription:
                        "Uncorrect inline-table in [widgets.displayed]"
                )
            )
        }

        self.id = widgetId
        self.inlineParams = params
    }
}

enum TOMLValue: Decodable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case double(Double)
    case array([TOMLValue])
    case dictionary(ConfigData)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let str = try? container.decode(String.self) {
            self = .string(str)
            return
        }
        if let b = try? container.decode(Bool.self) {
            self = .bool(b)
            return
        }
        if let i = try? container.decode(Int.self) {
            self = .int(i)
            return
        }
        if let d = try? container.decode(Double.self) {
            self = .double(d)
            return
        }
        if let arr = try? container.decode([TOMLValue].self) {
            self = .array(arr)
            return
        }
        if let dict = try? container.decode(ConfigData.self) {
            self = .dictionary(dict)
            return
        }

        self = .null
    }
}

extension TOMLValue {
    var stringValue: String? {
        if case let .string(s) = self { return s }
        return nil
    }

    var intValue: Int? {
        if case let .int(i) = self { return i }
        return nil
    }

    var boolValue: Bool? {
        if case let .bool(b) = self { return b }
        return nil
    }

    var arrayValue: [TOMLValue]? {
        if case let .array(arr) = self { return arr }
        return nil
    }

    var dictionaryValue: ConfigData? {
        if case let .dictionary(dict) = self { return dict }
        return nil
    }
}
