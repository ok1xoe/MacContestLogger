/// Determines the other station's class (`stationClasses`) by DXCC entity — drives the conditional
/// exchange and scoring (e.g. W/VE vs DX, OK/OM vs DX). Port of Java
/// `engine/StationClassifier.java`.
///
/// The `when` conditions are evaluated over a **probe context** (only entities, `received`
/// empty, callsign/band/mode/class `nil`), so `mode:` never matches, `bandIn: [~]`
/// always does and a missing `when` means "always". It returns the `id` of the **first** matching class —
/// even if it is `nil` (Java does not keep searching); none → `nil`.
///
/// Leniency versus Java (a deliberate divergence from Java v1.1.1): a `nil` element of `stationClasses`
/// (Java NPE on `sc.when()`) is skipped; `fieldEquals.field: ~` (Java NPE over `Map.of()`)
/// does not match.
public enum StationClassifier {

    public static func classify(_ definition: ContestDefinition, worked: DxccEntity?,
                                own: DxccEntity?) throws(ExpressionError) -> String? {
        guard let classes = definition.stationClasses, !classes.isEmpty else {
            return nil
        }
        let probe = QsoContext(call: nil, band: nil, mode: nil, received: JavaLinkedMap(),
                               workedEntity: worked, ownEntity: own, workedClass: nil)
        for stationClass in classes {
            guard let stationClass else { continue }
            if try ConditionEvaluator.eval(stationClass.when, probe) {
                return stationClass.id
            }
        }
        return nil
    }
}
