/// MQTT client error like the Java Paho 1.2.5 `MqttException`: `code` = `getReasonCode()`, `cause` = the Java
/// `getCause().toString()` (or `nil`). `description` = Paho `toString()`: "<text> (<code>)" and with a cause
/// "<text> (<code>) - <cause>". Texts come from the English `messages.properties` bundle (Paho localizes them by JVM locale —
/// probes run with `-Duser.language=en`).
public struct MqttClientError: Error, Equatable, Sendable, CustomStringConvertible {
    public let code: Int
    public let cause: String?
    /// DISCONNECT reason code from the broker (Paho `MqttException(int, MqttDisconnect)`; 0 = none).
    public let disconnectReasonCode: UInt8
    /// Reason String (0x1F) from a DISCONNECT by the broker.
    public let disconnectReasonString: String?

    public init(code: Int, cause: String? = nil, disconnectReasonCode: UInt8 = 0, disconnectReasonString: String? = nil) {
        self.code = code
        self.cause = cause
        self.disconnectReasonCode = disconnectReasonCode
        self.disconnectReasonString = disconnectReasonString
    }

    /// `REASON_CODE_CLIENT_TIMEOUT` — CONNACK did not arrive in time, or the broker did not answer PINGREQ.
    public static let clientTimeout = 32_000
    /// `REASON_CODE_NO_MESSAGE_IDS_AVAILABLE`.
    public static let noMessageIds = 32_001
    /// `REASON_CODE_WRITE_TIMEOUT` — two keep-alive intervals without a successful write.
    public static let writeTimeout = 32_002
    /// `REASON_CODE_CLIENT_CONNECTED`.
    public static let clientConnected = 32_100
    /// `REASON_CODE_CLIENT_DISCONNECTING` — pending operations ended by disconnecting (`resolveOldTokens(null)`).
    public static let clientDisconnecting = 32_102
    /// `REASON_CODE_SERVER_CONNECT_ERROR` — the TCP/TLS connection failed.
    public static let serverConnectError = 32_103
    /// `REASON_CODE_CLIENT_NOT_CONNECTED`.
    public static let clientNotConnected = 32_104
    /// `REASON_CODE_CONNECTION_LOST`.
    public static let connectionLost = 32_109
    /// `REASON_CODE_CLIENT_CLOSED`.
    public static let clientClosed = 32_111
    /// `REASON_CODE_MAX_INFLIGHT` — more unacknowledged QoS 1 than the broker's Receive Maximum.
    public static let maxInflight = 32_202
    /// `REASON_CODE_SERVER_DISCONNECTED` — broker poslal DISCONNECT.
    public static let serverDisconnected = 32_204
    /// `REASON_CODE_INVALID_RETURN_CODE`.
    public static let invalidReturnCode = 50_001
    /// `REASON_CODE_MALFORMED_PACKET`.
    public static let malformedPacket = 50_002
    /// `REASON_CODE_DUPLICATE_PROPERTY`.
    public static let duplicateProperty = 50_005
    /// MQTT 5 reason code 0x82 Protocol Error (a second CONNACK, a packet the broker must not send).
    public static let protocolError = 0x82

    /// Texty `org/eclipse/paho/mqttv5/common/nls/messages.properties` (anglicky).
    static let texts: [Int: String] = [
        1: "Invalid protocol version", 2: "Invalid client ID", 3: "Broker unavailable",
        4: "Bad user name or password", 5: "Not authorized to connect", 6: "Unexpected error",
        16: "No matching subscribers.", 17: "No subscription existed.", 24: "Continue authentication.",
        25: "Re-authenticate.", 128: "Unspecified error.", 129: "Malformed packet.", 130: "Protocol error.",
        131: "Implementation specific error.", 132: "Unsupported protocol version.",
        133: "Client identifier not valid.", 134: "Bad User Name or Password.", 135: "Not authorized.",
        136: "Server unavailable.", 137: "Server busy.", 138: "Banned.", 139: "Server shutting down.",
        140: "Bad authentication method.", 141: "Keep Alive timeout.", 142: "Session taken over.",
        143: "Topic Filter invalid.", 144: "Topic Name invalid.", 145: "Packet identifier in use.",
        146: "Packet identifier not found.", 147: "Receive Maximum exceeded.", 148: "Topic Alias invalid.",
        149: "Packet too large.", 150: "Message rate too high.", 151: "Quota exceeded.",
        152: "Administrative action.", 153: "Payload format invalid.", 154: "Retain not supported.",
        155: "QoS not supported", 156: "Use another server.", 157: "Server moved.",
        158: "Shared Subscriptions not supported.", 159: "Connection rate exceeded.", 160: "Maximum connect time.",
        161: "Subscription Identifiers not supported.",
        32_000: "Timed out waiting for a response from the server",
        32_001: "Internal error, caused by no new message IDs being available",
        32_002: "Timed out while waiting to write messages to the server", 32_100: "Client is connected",
        32_101: "Client is disconnected", 32_102: "Client is currently disconnecting",
        32_103: "Unable to connect to server", 32_104: "Client is not connected", 32_108: "Unrecognized packet",
        32_109: "Connection lost", 32_110: "Connect already in progress", 32_111: "Client is closed",
        32_202: "Too many publishes in progress", 32_204: "The Server Disconnected the client.",
        50_000: "Invalid Message Property Identifier", 50_001: "Invalid Return code", 50_002: "Malformed Packet",
        50_005: "Duplicate property in Packet",
    ]

    /// Java `getMessage()` (without the cause): the bundle text, otherwise `Untranslated MqttException - RC: <code>`;
    /// for a broker DISCONNECT additionally ` Disconnect RC: <n>` (≠ 0) and ` Disconnect Reason: <text>`.
    public var message: String {
        var text: String = Self.texts[code] ?? "Untranslated MqttException - RC: \(code)"
        if disconnectReasonCode != 0 {
            text += " Disconnect RC: \(disconnectReasonCode)"
        }
        if let disconnectReasonString {
            text += " Disconnect Reason: \(disconnectReasonString)"
        }
        return text
    }

    public var description: String {
        let head = "\(message) (\(code))"
        guard let cause else { return head }
        return "\(head) - \(cause)"
    }

    static let notConnected = MqttClientError(code: clientNotConnected)
    static let closed = MqttClientError(code: clientClosed)
    static let disconnecting = MqttClientError(code: clientDisconnecting)

    /// Decoding error of incoming bytes (Paho throws its own codes from `MqttInputStream`, mostly 50002).
    static func decoding(_ error: MqttCodecError) -> MqttClientError {
        switch error {
        case .invalidReasonCode:
            return MqttClientError(code: invalidReturnCode)
        case .duplicateProperty:
            return MqttClientError(code: duplicateProperty)
        default:
            return MqttClientError(code: malformedPacket)
        }
    }
}
