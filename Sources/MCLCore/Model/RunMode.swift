/// How a QSO was made in a contest: RUN (we call CQ) or S&P (search & pounce).
public enum RunMode: String, Codable, Sendable {
    case run = "RUN"
    case searchAndPounce = "SEARCH_AND_POUNCE"
}
