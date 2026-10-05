import Testing
@testable import MCLCore

/// Port of the Java `cat/SerialParamsTest` + `SP.toSetConf` measurements (maintainer-only probe).
@Suite struct SerialParamsTests {

    @Test func omitsRtsDtrWhenUnset() {
        let p = SerialParams(dataBits: 8, stopBits: 1, parity: "None", handshake: "None", rts: "Unset", dtr: "Unset")
        #expect(p.toSetConf() == "data_bits=8,stop_bits=1,serial_parity=None,serial_handshake=None")
    }

    @Test func omitsHandshakeWhenBlank() {
        // empty handshake = do not force (Default rig) — serial_handshake must not appear
        let p = SerialParams(dataBits: 8, stopBits: 1, parity: "None", handshake: "", rts: "Unset", dtr: "Unset")
        #expect(p.toSetConf() == "data_bits=8,stop_bits=1,serial_parity=None")
    }

    @Test func includesRtsDtrWhenSet() {
        let p = SerialParams(dataBits: 7, stopBits: 2, parity: "Even", handshake: "Hardware", rts: "ON", dtr: "OFF")
        let expected = "data_bits=7,stop_bits=2,serial_parity=Even,serial_handshake=Hardware,rts_state=ON,dtr_state=OFF"
        #expect(p.toSetConf() == expected)
    }

    /// `SP.toSetConf`: handshake omitted even for only spaces (`isBlank`), `Unset` regardless of letter
    /// case, `null` parity as the literal `null`, `null` rts/dtr/handshake omitted.
    @Test func measuredEdgeCases() {
        let cases: [(String?, String?, String?, String?, String)] = [
            ("None", "None", "Unset", "Unset",
             "data_bits=8,stop_bits=1,serial_parity=None,serial_handshake=None"),
            ("None", "", "unset", "UNSET", "data_bits=8,stop_bits=1,serial_parity=None"),
            ("Even", " ", "ON", "OFF", "data_bits=8,stop_bits=1,serial_parity=Even,rts_state=ON,dtr_state=OFF"),
            ("None", nil, nil, nil, "data_bits=8,stop_bits=1,serial_parity=None"),
            (nil, "Hardware", "On", "Off",
             "data_bits=8,stop_bits=1,serial_parity=null,serial_handshake=Hardware,rts_state=On,dtr_state=Off"),
        ]
        for (parity, handshake, rts, dtr, expected) in cases {
            let p = SerialParams(dataBits: 8, stopBits: 1, parity: parity, handshake: handshake, rts: rts, dtr: dtr)
            #expect(p.toSetConf() == expected)
        }
    }
}
