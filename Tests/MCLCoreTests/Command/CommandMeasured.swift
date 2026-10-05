// Table measured on Java v1.1.1 (JDK 21.0.2, en_US) by the maintainer-only probe.
// Do not edit by hand — run the probe again and regenerate the file with
// a maintainer-only probe.

enum CommandMeasured {

    /// Rows `CMD`, `WORD`, `EDGE`, `FUZZ` (input, frequency, second VFO, Ctrl+Enter, result) and `OP`
    /// (input, result); TSV, probe escaping `esc`.
    static let rows: String = #"""
CMD	9999999999999999	14074000	0	false	THROW ArithmeticException: Overflow
CMD	9999999999999999	0	7010000	true	THROW ArithmeticException: Overflow
CMD	9999999999999999	144174000	14030000	true	THROW ArithmeticException: Overflow
CMD	9999999999999999	14074000	0	true	THROW ArithmeticException: Overflow
CMD	/9999999999999999	14074000	0	false	THROW ArithmeticException: Overflow
CMD	/9999999999999999	0	7010000	true	THROW ArithmeticException: Overflow
CMD	/9999999999999999	144174000	14030000	true	THROW ArithmeticException: Overflow
CMD	/9999999999999999	14074000	0	true	THROW ArithmeticException: Overflow
CMD	+9999999999999999	14074000	0	false	THROW ArithmeticException: Overflow
CMD	+9999999999999999	0	7010000	true	THROW ArithmeticException: Overflow
CMD	+9999999999999999	144174000	14030000	true	THROW ArithmeticException: Overflow
CMD	+9999999999999999	14074000	0	true	THROW ArithmeticException: Overflow
CMD	-9999999999999999	14074000	0	false	THROW ArithmeticException: Overflow
CMD	-9999999999999999	0	7010000	true	THROW ArithmeticException: Overflow
CMD	-9999999999999999	144174000	14030000	true	THROW ArithmeticException: Overflow
CMD	-9999999999999999	14074000	0	true	THROW ArithmeticException: Overflow
CMD	9223372036854775	14074000	0	false	Optional[Qsy[freqHz=-9223372036840776616]]
CMD	9223372036854775	0	7010000	true	Optional[Invalid[message=9223372036854775 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
CMD	9223372036854775	144174000	14030000	true	Optional[Split[txFreqHz=-9223372036710776616]]
CMD	9223372036854775	14074000	0	true	Optional[Split[txFreqHz=-9223372036840776616]]
CMD	9223372036854775.807	14074000	0	false	Optional[Qsy[freqHz=-9223372036840775809]]
CMD	9223372036854775.807	0	7010000	true	Optional[Invalid[message=9223372036854775.807 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
CMD	9223372036854775.807	144174000	14030000	true	Optional[Split[txFreqHz=-9223372036710775809]]
CMD	9223372036854775.807	14074000	0	true	Optional[Split[txFreqHz=-9223372036840775809]]
CMD	9223372036854775.8074	14074000	0	false	Optional[Qsy[freqHz=-9223372036840775809]]
CMD	9223372036854775.8074	0	7010000	true	Optional[Invalid[message=9223372036854775.8074 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
CMD	9223372036854775.8074	144174000	14030000	true	Optional[Split[txFreqHz=-9223372036710775809]]
CMD	9223372036854775.8074	14074000	0	true	Optional[Split[txFreqHz=-9223372036840775809]]
CMD	9223372036854775.8075	14074000	0	false	THROW ArithmeticException: Overflow
CMD	9223372036854775.8075	0	7010000	true	THROW ArithmeticException: Overflow
CMD	9223372036854775.8075	144174000	14030000	true	THROW ArithmeticException: Overflow
CMD	9223372036854775.8075	14074000	0	true	THROW ArithmeticException: Overflow
CMD	-9223372036854775.808	14074000	0	false	Optional[Invalid[message=Posun -9223372036854775.808 kHz vede mimo p\u00E1smo]]
CMD	-9223372036854775.808	0	7010000	true	Optional[Invalid[message=Posun -9223372036854775.808 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
CMD	-9223372036854775.808	144174000	14030000	true	Optional[Invalid[message=Posun -9223372036854775.808 kHz vede mimo p\u00E1smo]]
CMD	-9223372036854775.808	14074000	0	true	Optional[Invalid[message=Posun -9223372036854775.808 kHz vede mimo p\u00E1smo]]
CMD	-9223372036854775.8084	14074000	0	false	Optional[Invalid[message=Posun -9223372036854775.8084 kHz vede mimo p\u00E1smo]]
CMD	-9223372036854775.8084	0	7010000	true	Optional[Invalid[message=Posun -9223372036854775.8084 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
CMD	-9223372036854775.8084	144174000	14030000	true	Optional[Invalid[message=Posun -9223372036854775.8084 kHz vede mimo p\u00E1smo]]
CMD	-9223372036854775.8084	14074000	0	true	Optional[Invalid[message=Posun -9223372036854775.8084 kHz vede mimo p\u00E1smo]]
CMD	-9223372036854775.8085	14074000	0	false	THROW ArithmeticException: Overflow
CMD	-9223372036854775.8085	0	7010000	true	THROW ArithmeticException: Overflow
CMD	-9223372036854775.8085	144174000	14030000	true	THROW ArithmeticException: Overflow
CMD	-9223372036854775.8085	14074000	0	true	THROW ArithmeticException: Overflow
CMD	9223372036854776	14074000	0	false	THROW ArithmeticException: Overflow
CMD	9223372036854776	0	7010000	true	THROW ArithmeticException: Overflow
CMD	9223372036854776	144174000	14030000	true	THROW ArithmeticException: Overflow
CMD	9223372036854776	14074000	0	true	THROW ArithmeticException: Overflow
CMD	+9223372036854775	14074000	0	false	Optional[Invalid[message=Posun +9223372036854775 kHz vede mimo p\u00E1smo]]
CMD	+9223372036854775	0	7010000	true	Optional[Invalid[message=Posun +9223372036854775 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
CMD	+9223372036854775	144174000	14030000	true	Optional[Invalid[message=Posun +9223372036854775 kHz vede mimo p\u00E1smo]]
CMD	+9223372036854775	14074000	0	true	Optional[Invalid[message=Posun +9223372036854775 kHz vede mimo p\u00E1smo]]
CMD	-9223372036854775	14074000	0	false	Optional[Invalid[message=Posun -9223372036854775 kHz vede mimo p\u00E1smo]]
CMD	-9223372036854775	0	7010000	true	Optional[Invalid[message=Posun -9223372036854775 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
CMD	-9223372036854775	144174000	14030000	true	Optional[Invalid[message=Posun -9223372036854775 kHz vede mimo p\u00E1smo]]
CMD	-9223372036854775	14074000	0	true	Optional[Invalid[message=Posun -9223372036854775 kHz vede mimo p\u00E1smo]]
CMD	+9223372036854775.807	14074000	0	false	Optional[Invalid[message=Posun +9223372036854775.807 kHz vede mimo p\u00E1smo]]
CMD	+9223372036854775.807	0	7010000	true	Optional[Invalid[message=Posun +9223372036854775.807 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
CMD	+9223372036854775.807	144174000	14030000	true	Optional[Invalid[message=Posun +9223372036854775.807 kHz vede mimo p\u00E1smo]]
CMD	+9223372036854775.807	14074000	0	true	Optional[Invalid[message=Posun +9223372036854775.807 kHz vede mimo p\u00E1smo]]
CMD	+92233720368547	14074000	0	false	Optional[Invalid[message=Posun +92233720368547 kHz vede mimo p\u00E1smo]]
CMD	+92233720368547	0	7010000	true	Optional[Invalid[message=Posun +92233720368547 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
CMD	+92233720368547	144174000	14030000	true	Optional[Invalid[message=Posun +92233720368547 kHz vede mimo p\u00E1smo]]
CMD	+92233720368547	14074000	0	true	Optional[Invalid[message=Posun +92233720368547 kHz vede mimo p\u00E1smo]]
CMD	-92233720368547	14074000	0	false	Optional[Invalid[message=Posun -92233720368547 kHz vede mimo p\u00E1smo]]
CMD	-92233720368547	0	7010000	true	Optional[Invalid[message=Posun -92233720368547 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
CMD	-92233720368547	144174000	14030000	true	Optional[Invalid[message=Posun -92233720368547 kHz vede mimo p\u00E1smo]]
CMD	-92233720368547	14074000	0	true	Optional[Invalid[message=Posun -92233720368547 kHz vede mimo p\u00E1smo]]
CMD	92233720368547	14074000	0	false	Optional[Invalid[message=92233720368547 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
CMD	92233720368547	0	7010000	true	Optional[Invalid[message=92233720368547 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
CMD	92233720368547	144174000	14030000	true	Optional[Invalid[message=92233720368547 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
CMD	92233720368547	14074000	0	true	Optional[Invalid[message=92233720368547 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
CMD	92233720368547758	14074000	0	false	THROW ArithmeticException: Overflow
CMD	92233720368547758	0	7010000	true	THROW ArithmeticException: Overflow
CMD	92233720368547758	144174000	14030000	true	THROW ArithmeticException: Overflow
CMD	92233720368547758	14074000	0	true	THROW ArithmeticException: Overflow
CMD	99999999999	14074000	0	false	Optional[Invalid[message=99999999999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
CMD	99999999999	0	7010000	true	Optional[Invalid[message=99999999999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
CMD	99999999999	144174000	14030000	true	Optional[Invalid[message=99999999999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
CMD	99999999999	14074000	0	true	Optional[Invalid[message=99999999999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
CMD	999999999999999	14074000	0	false	Optional[Invalid[message=999999999999999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
CMD	999999999999999	0	7010000	true	Optional[Invalid[message=999999999999999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
CMD	999999999999999	144174000	14030000	true	Optional[Invalid[message=999999999999999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
CMD	999999999999999	14074000	0	true	Optional[Invalid[message=999999999999999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
CMD	/+9223372036854775	14074000	0	false	Optional[Invalid[message=Posun +9223372036854775 kHz vede mimo p\u00E1smo]]
CMD	/+9223372036854775	0	7010000	true	Optional[Invalid[message=Posun +9223372036854775 kHz vede mimo p\u00E1smo]]
CMD	/+9223372036854775	144174000	14030000	true	Optional[Invalid[message=Posun +9223372036854775 kHz vede mimo p\u00E1smo]]
CMD	/+9223372036854775	14074000	0	true	Optional[Invalid[message=Posun +9223372036854775 kHz vede mimo p\u00E1smo]]
CMD	00000000000000000000000014025	14074000	0	false	Optional[Qsy[freqHz=14025000]]
CMD	00000000000000000000000014025	0	7010000	true	Optional[Split[txFreqHz=14025000]]
CMD	00000000000000000000000014025	144174000	14030000	true	Optional[Split[txFreqHz=14025000]]
CMD	00000000000000000000000014025	14074000	0	true	Optional[Split[txFreqHz=14025000]]
CMD	14025.00000000000000000000001	14074000	0	false	Optional[Qsy[freqHz=14025000]]
CMD	14025.00000000000000000000001	0	7010000	true	Optional[Split[txFreqHz=14025000]]
CMD	14025.00000000000000000000001	144174000	14030000	true	Optional[Split[txFreqHz=14025000]]
CMD	14025.00000000000000000000001	14074000	0	true	Optional[Split[txFreqHz=14025000]]
CMD	10000000000000000000000000000000000000000	14074000	0	false	THROW ArithmeticException: Overflow
CMD	10000000000000000000000000000000000000000	0	7010000	true	THROW ArithmeticException: Overflow
CMD	10000000000000000000000000000000000000000	144174000	14030000	true	THROW ArithmeticException: Overflow
CMD	10000000000000000000000000000000000000000	14074000	0	true	THROW ArithmeticException: Overflow
CMD	0.00000000000000000000000000000000000000005	14074000	0	false	Optional[Qsy[freqHz=14000000]]
CMD	0.00000000000000000000000000000000000000005	0	7010000	true	Optional[Invalid[message=0.00000000000000000000000000000000000000005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
CMD	0.00000000000000000000000000000000000000005	144174000	14030000	true	Optional[Split[txFreqHz=144000000]]
CMD	0.00000000000000000000000000000000000000005	14074000	0	true	Optional[Split[txFreqHz=14000000]]
CMD	14025.0005	14074000	0	false	Optional[Qsy[freqHz=14025001]]
CMD	14025.0005	0	7010000	true	Optional[Split[txFreqHz=14025001]]
CMD	14025.0005	144174000	14030000	true	Optional[Split[txFreqHz=14025001]]
CMD	14025.0005	14074000	0	true	Optional[Split[txFreqHz=14025001]]
CMD	14025.0004999	14074000	0	false	Optional[Qsy[freqHz=14025000]]
CMD	14025.0004999	0	7010000	true	Optional[Split[txFreqHz=14025000]]
CMD	14025.0004999	144174000	14030000	true	Optional[Split[txFreqHz=14025000]]
CMD	14025.0004999	14074000	0	true	Optional[Split[txFreqHz=14025000]]
CMD	14025.0015	14074000	0	false	Optional[Qsy[freqHz=14025002]]
CMD	14025.0015	0	7010000	true	Optional[Split[txFreqHz=14025002]]
CMD	14025.0015	144174000	14030000	true	Optional[Split[txFreqHz=14025002]]
CMD	14025.0015	14074000	0	true	Optional[Split[txFreqHz=14025002]]
CMD	14025.0025	14074000	0	false	Optional[Qsy[freqHz=14025003]]
CMD	14025.0025	0	7010000	true	Optional[Split[txFreqHz=14025003]]
CMD	14025.0025	144174000	14030000	true	Optional[Split[txFreqHz=14025003]]
CMD	14025.0025	14074000	0	true	Optional[Split[txFreqHz=14025003]]
CMD	14025,0005	14074000	0	false	Optional[Qsy[freqHz=14025001]]
CMD	14025,0005	0	7010000	true	Optional[Split[txFreqHz=14025001]]
CMD	14025,0005	144174000	14030000	true	Optional[Split[txFreqHz=14025001]]
CMD	14025,0005	14074000	0	true	Optional[Split[txFreqHz=14025001]]
CMD	14025,5	14074000	0	false	Optional[Qsy[freqHz=14025500]]
CMD	14025,5	0	7010000	true	Optional[Split[txFreqHz=14025500]]
CMD	14025,5	144174000	14030000	true	Optional[Split[txFreqHz=14025500]]
CMD	14025,5	14074000	0	true	Optional[Split[txFreqHz=14025500]]
CMD	-0.0005	14074000	0	false	Optional[Qsy[freqHz=14073999]]
CMD	-0.0005	0	7010000	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
CMD	-0.0005	144174000	14030000	true	Optional[Split[txFreqHz=144173999]]
CMD	-0.0005	14074000	0	true	Optional[Split[txFreqHz=14073999]]
CMD	+0.0005	14074000	0	false	Optional[Qsy[freqHz=14074001]]
CMD	+0.0005	0	7010000	true	Optional[Invalid[message=Posun +0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
CMD	+0.0005	144174000	14030000	true	Optional[Split[txFreqHz=144174001]]
CMD	+0.0005	14074000	0	true	Optional[Split[txFreqHz=14074001]]
CMD	-0.0004	14074000	0	false	Optional[Qsy[freqHz=14074000]]
CMD	-0.0004	0	7010000	true	Optional[Invalid[message=Posun -0.0004 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
CMD	-0.0004	144174000	14030000	true	Optional[Split[txFreqHz=144174000]]
CMD	-0.0004	14074000	0	true	Optional[Split[txFreqHz=14074000]]
CMD	+0.0004	14074000	0	false	Optional[Qsy[freqHz=14074000]]
CMD	+0.0004	0	7010000	true	Optional[Invalid[message=Posun +0.0004 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
CMD	+0.0004	144174000	14030000	true	Optional[Split[txFreqHz=144174000]]
CMD	+0.0004	14074000	0	true	Optional[Split[txFreqHz=14074000]]
CMD	-0.0015	14074000	0	false	Optional[Qsy[freqHz=14073998]]
CMD	-0.0015	0	7010000	true	Optional[Invalid[message=Posun -0.0015 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
CMD	-0.0015	144174000	14030000	true	Optional[Split[txFreqHz=144173998]]
CMD	-0.0015	14074000	0	true	Optional[Split[txFreqHz=14073998]]
CMD	+0.0015	14074000	0	false	Optional[Qsy[freqHz=14074002]]
CMD	+0.0015	0	7010000	true	Optional[Invalid[message=Posun +0.0015 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
CMD	+0.0015	144174000	14030000	true	Optional[Split[txFreqHz=144174002]]
CMD	+0.0015	14074000	0	true	Optional[Split[txFreqHz=14074002]]
CMD	0.0005	14074000	0	false	Optional[Qsy[freqHz=14000001]]
CMD	0.0005	0	7010000	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
CMD	0.0005	144174000	14030000	true	Optional[Split[txFreqHz=144000001]]
CMD	0.0005	14074000	0	true	Optional[Split[txFreqHz=14000001]]
CMD	0.0004	14074000	0	false	Optional[Qsy[freqHz=14000000]]
CMD	0.0004	0	7010000	true	Optional[Invalid[message=0.0004 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
CMD	0.0004	144174000	14030000	true	Optional[Split[txFreqHz=144000000]]
CMD	0.0004	14074000	0	true	Optional[Split[txFreqHz=14000000]]
CMD	025.0005	14074000	0	false	Optional[Qsy[freqHz=14025001]]
CMD	025.0005	0	7010000	true	Optional[Invalid[message=025.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
CMD	025.0005	144174000	14030000	true	Optional[Split[txFreqHz=144025001]]
CMD	025.0005	14074000	0	true	Optional[Split[txFreqHz=14025001]]
CMD	/14030.0005	14074000	0	false	Optional[OtherVfo[freqHz=14030001]]
CMD	/14030.0005	0	7010000	true	Optional[OtherVfo[freqHz=14030001]]
CMD	/14030.0005	144174000	14030000	true	Optional[OtherVfo[freqHz=14030001]]
CMD	/14030.0005	14074000	0	true	Optional[OtherVfo[freqHz=14030001]]
CMD	/-0.0005	14074000	0	false	Optional[OtherVfo[freqHz=14073999]]
CMD	/-0.0005	0	7010000	true	Optional[OtherVfo[freqHz=7009999]]
CMD	/-0.0005	144174000	14030000	true	Optional[OtherVfo[freqHz=14029999]]
CMD	/-0.0005	14074000	0	true	Optional[OtherVfo[freqHz=14073999]]
CMD	0	14074000	0	false	Optional[Qsy[freqHz=14000000]]
CMD	0	0	7010000	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
CMD	0	144174000	14030000	true	Optional[Split[txFreqHz=144000000]]
CMD	0	14074000	0	true	Optional[Split[txFreqHz=14000000]]
CMD	-0	14074000	0	false	Optional[Qsy[freqHz=14074000]]
CMD	-0	0	7010000	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
CMD	-0	144174000	14030000	true	Optional[Split[txFreqHz=144174000]]
CMD	-0	14074000	0	true	Optional[Split[txFreqHz=14074000]]
CMD	+0	14074000	0	false	Optional[Qsy[freqHz=14074000]]
CMD	+0	0	7010000	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
CMD	+0	144174000	14030000	true	Optional[Split[txFreqHz=144174000]]
CMD	+0	14074000	0	true	Optional[Split[txFreqHz=14074000]]
CMD	00	14074000	0	false	Optional[Qsy[freqHz=14000000]]
CMD	00	0	7010000	true	Optional[Invalid[message=00 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
CMD	00	144174000	14030000	true	Optional[Split[txFreqHz=144000000]]
CMD	00	14074000	0	true	Optional[Split[txFreqHz=14000000]]
CMD	000	14074000	0	false	Optional[Qsy[freqHz=14000000]]
CMD	000	0	7010000	true	Optional[Invalid[message=000 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
CMD	000	144174000	14030000	true	Optional[Split[txFreqHz=144000000]]
CMD	000	14074000	0	true	Optional[Split[txFreqHz=14000000]]
CMD	025.1	14074000	0	false	Optional[Qsy[freqHz=14025100]]
CMD	025.1	0	7010000	true	Optional[Invalid[message=025.1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
CMD	025.1	144174000	14030000	true	Optional[Split[txFreqHz=144025100]]
CMD	025.1	14074000	0	true	Optional[Split[txFreqHz=14025100]]
CMD	025	14074000	0	false	Optional[Qsy[freqHz=14025000]]
CMD	025	0	7010000	true	Optional[Invalid[message=025 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
CMD	025	144174000	14030000	true	Optional[Split[txFreqHz=144025000]]
CMD	025	14074000	0	true	Optional[Split[txFreqHz=14025000]]
CMD	/0	14074000	0	false	Optional[OtherVfo[freqHz=14000000]]
CMD	/0	0	7010000	true	Optional[OtherVfo[freqHz=7000000]]
CMD	/0	144174000	14030000	true	Optional[OtherVfo[freqHz=14000000]]
CMD	/0	14074000	0	true	Optional[OtherVfo[freqHz=14000000]]
CMD	/+0	14074000	0	false	Optional[OtherVfo[freqHz=14074000]]
CMD	/+0	0	7010000	true	Optional[OtherVfo[freqHz=7010000]]
CMD	/+0	144174000	14030000	true	Optional[OtherVfo[freqHz=14030000]]
CMD	/+0	14074000	0	true	Optional[OtherVfo[freqHz=14074000]]
CMD	/-0	14074000	0	false	Optional[OtherVfo[freqHz=14074000]]
CMD	/-0	0	7010000	true	Optional[OtherVfo[freqHz=7010000]]
CMD	/-0	144174000	14030000	true	Optional[OtherVfo[freqHz=14030000]]
CMD	/-0	14074000	0	true	Optional[OtherVfo[freqHz=14074000]]
CMD	/+2	14074000	0	false	Optional[OtherVfo[freqHz=14076000]]
CMD	/+2	0	7010000	true	Optional[OtherVfo[freqHz=7012000]]
CMD	/+2	144174000	14030000	true	Optional[OtherVfo[freqHz=14032000]]
CMD	/+2	14074000	0	true	Optional[OtherVfo[freqHz=14076000]]
CMD	/-3	14074000	0	false	Optional[OtherVfo[freqHz=14071000]]
CMD	/-3	0	7010000	true	Optional[OtherVfo[freqHz=7007000]]
CMD	/-3	144174000	14030000	true	Optional[OtherVfo[freqHz=14027000]]
CMD	/-3	14074000	0	true	Optional[OtherVfo[freqHz=14071000]]
CMD	/14030	14074000	0	false	Optional[OtherVfo[freqHz=14030000]]
CMD	/14030	0	7010000	true	Optional[OtherVfo[freqHz=14030000]]
CMD	/14030	144174000	14030000	true	Optional[OtherVfo[freqHz=14030000]]
CMD	/14030	14074000	0	true	Optional[OtherVfo[freqHz=14030000]]
CMD	/025	14074000	0	false	Optional[OtherVfo[freqHz=14025000]]
CMD	/025	0	7010000	true	Optional[OtherVfo[freqHz=7025000]]
CMD	/025	144174000	14030000	true	Optional[OtherVfo[freqHz=14025000]]
CMD	/025	14074000	0	true	Optional[OtherVfo[freqHz=14025000]]
CMD	/	14074000	0	false	Optional.empty
CMD	/	0	7010000	true	Optional.empty
CMD	/	144174000	14030000	true	Optional.empty
CMD	/	14074000	0	true	Optional.empty
CMD	//1	14074000	0	false	Optional.empty
CMD	//1	0	7010000	true	Optional.empty
CMD	//1	144174000	14030000	true	Optional.empty
CMD	//1	14074000	0	true	Optional.empty
CMD	/ 1	14074000	0	false	Optional.empty
CMD	/ 1	0	7010000	true	Optional.empty
CMD	/ 1	144174000	14030000	true	Optional.empty
CMD	/ 1	14074000	0	true	Optional.empty
CMD	/+	14074000	0	false	Optional.empty
CMD	/+	0	7010000	true	Optional.empty
CMD	/+	144174000	14030000	true	Optional.empty
CMD	/+	14074000	0	true	Optional.empty
CMD	+	14074000	0	false	Optional.empty
CMD	+	0	7010000	true	Optional.empty
CMD	+	144174000	14030000	true	Optional.empty
CMD	+	14074000	0	true	Optional.empty
CMD	-	14074000	0	false	Optional.empty
CMD	-	0	7010000	true	Optional.empty
CMD	-	144174000	14030000	true	Optional.empty
CMD	-	14074000	0	true	Optional.empty
CMD	+-1	14074000	0	false	Optional.empty
CMD	+-1	0	7010000	true	Optional.empty
CMD	+-1	144174000	14030000	true	Optional.empty
CMD	+-1	14074000	0	true	Optional.empty
CMD	--1	14074000	0	false	Optional.empty
CMD	--1	0	7010000	true	Optional.empty
CMD	--1	144174000	14030000	true	Optional.empty
CMD	--1	14074000	0	true	Optional.empty
CMD	++1	14074000	0	false	Optional.empty
CMD	++1	0	7010000	true	Optional.empty
CMD	++1	144174000	14030000	true	Optional.empty
CMD	++1	14074000	0	true	Optional.empty
CMD	-1000000	14074000	0	false	Optional[Invalid[message=Posun -1000000 kHz vede mimo p\u00E1smo]]
CMD	-1000000	0	7010000	true	Optional[Invalid[message=Posun -1000000 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
CMD	-1000000	144174000	14030000	true	Optional[Invalid[message=Posun -1000000 kHz vede mimo p\u00E1smo]]
CMD	-1000000	14074000	0	true	Optional[Invalid[message=Posun -1000000 kHz vede mimo p\u00E1smo]]
CMD	+20000	14074000	0	false	Optional[Invalid[message=Posun +20000 kHz vede mimo p\u00E1smo]]
CMD	+20000	0	7010000	true	Optional[Invalid[message=Posun +20000 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
CMD	+20000	144174000	14030000	true	Optional[Invalid[message=Posun +20000 kHz vede mimo p\u00E1smo]]
CMD	+20000	14074000	0	true	Optional[Invalid[message=Posun +20000 kHz vede mimo p\u00E1smo]]
CMD	+500	14074000	0	false	Optional[Invalid[message=Posun +500 kHz vede mimo p\u00E1smo]]
CMD	+500	0	7010000	true	Optional[Invalid[message=Posun +500 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
CMD	+500	144174000	14030000	true	Optional[Split[txFreqHz=144674000]]
CMD	+500	14074000	0	true	Optional[Invalid[message=Posun +500 kHz vede mimo p\u00E1smo]]
CMD	-3	14074000	0	false	Optional[Qsy[freqHz=14071000]]
CMD	-3	0	7010000	true	Optional[Invalid[message=Posun -3 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
CMD	-3	144174000	14030000	true	Optional[Split[txFreqHz=144171000]]
CMD	-3	14074000	0	true	Optional[Split[txFreqHz=14071000]]
CMD	+2	14074000	0	false	Optional[Qsy[freqHz=14076000]]
CMD	+2	0	7010000	true	Optional[Invalid[message=Posun +2 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
CMD	+2	144174000	14030000	true	Optional[Split[txFreqHz=144176000]]
CMD	+2	14074000	0	true	Optional[Split[txFreqHz=14076000]]
CMD	+0.5	14074000	0	false	Optional[Qsy[freqHz=14074500]]
CMD	+0.5	0	7010000	true	Optional[Invalid[message=Posun +0.5 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
CMD	+0.5	144174000	14030000	true	Optional[Split[txFreqHz=144174500]]
CMD	+0.5	14074000	0	true	Optional[Split[txFreqHz=14074500]]
CMD	3500	14074000	0	false	Optional[Qsy[freqHz=3500000]]
CMD	3500	0	7010000	true	Optional[Split[txFreqHz=3500000]]
CMD	3500	144174000	14030000	true	Optional[Split[txFreqHz=3500000]]
CMD	3500	14074000	0	true	Optional[Split[txFreqHz=3500000]]
CMD	50100	14074000	0	false	Optional[Qsy[freqHz=50100000]]
CMD	50100	0	7010000	true	Optional[Split[txFreqHz=50100000]]
CMD	50100	144174000	14030000	true	Optional[Split[txFreqHz=50100000]]
CMD	50100	14074000	0	true	Optional[Split[txFreqHz=50100000]]
CMD	144300	14074000	0	false	Optional[Qsy[freqHz=144300000]]
CMD	144300	0	7010000	true	Optional[Split[txFreqHz=144300000]]
CMD	144300	144174000	14030000	true	Optional[Split[txFreqHz=144300000]]
CMD	144300	14074000	0	true	Optional[Split[txFreqHz=144300000]]
CMD	1830	14074000	0	false	Optional[Qsy[freqHz=1830000]]
CMD	1830	0	7010000	true	Optional[Split[txFreqHz=1830000]]
CMD	1830	144174000	14030000	true	Optional[Split[txFreqHz=1830000]]
CMD	1830	14074000	0	true	Optional[Split[txFreqHz=1830000]]
CMD	12345	14074000	0	false	Optional[Invalid[message=12345 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
CMD	12345	0	7010000	true	Optional[Invalid[message=12345 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
CMD	12345	144174000	14030000	true	Optional[Invalid[message=12345 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
CMD	12345	14074000	0	true	Optional[Invalid[message=12345 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
CMD	250	14074000	0	false	Optional[Qsy[freqHz=14250000]]
CMD	250	0	7010000	true	Optional[Invalid[message=250 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
CMD	250	144174000	14030000	true	Optional[Split[txFreqHz=144250000]]
CMD	250	14074000	0	true	Optional[Split[txFreqHz=14250000]]
CMD	300	14074000	0	false	Optional[Qsy[freqHz=14300000]]
CMD	300	0	7010000	true	Optional[Invalid[message=300 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
CMD	300	144174000	14030000	true	Optional[Split[txFreqHz=144300000]]
CMD	300	14074000	0	true	Optional[Split[txFreqHz=14300000]]
CMD	7012	14074000	0	false	Optional[Qsy[freqHz=7012000]]
CMD	7012	0	7010000	true	Optional[Split[txFreqHz=7012000]]
CMD	7012	144174000	14030000	true	Optional[Split[txFreqHz=7012000]]
CMD	7012	14074000	0	true	Optional[Split[txFreqHz=7012000]]
CMD	14025.1	14074000	0	false	Optional[Qsy[freqHz=14025100]]
CMD	14025.1	0	7010000	true	Optional[Split[txFreqHz=14025100]]
CMD	14025.1	144174000	14030000	true	Optional[Split[txFreqHz=14025100]]
CMD	14025.1	14074000	0	true	Optional[Split[txFreqHz=14025100]]
CMD	14025,1	14074000	0	false	Optional[Qsy[freqHz=14025100]]
CMD	14025,1	0	7010000	true	Optional[Split[txFreqHz=14025100]]
CMD	14025,1	144174000	14030000	true	Optional[Split[txFreqHz=14025100]]
CMD	14025,1	14074000	0	true	Optional[Split[txFreqHz=14025100]]
CMD	14,025.1	14074000	0	false	Optional.empty
CMD	14,025.1	0	7010000	true	Optional.empty
CMD	14,025.1	144174000	14030000	true	Optional.empty
CMD	14,025.1	14074000	0	true	Optional.empty
CMD	14025.1.2	14074000	0	false	Optional.empty
CMD	14025.1.2	0	7010000	true	Optional.empty
CMD	14025.1.2	144174000	14030000	true	Optional.empty
CMD	14025.1.2	14074000	0	true	Optional.empty
CMD	14025,1,2	14074000	0	false	Optional.empty
CMD	14025,1,2	0	7010000	true	Optional.empty
CMD	14025,1,2	144174000	14030000	true	Optional.empty
CMD	14025,1,2	14074000	0	true	Optional.empty
CMD	14025.,1	14074000	0	false	Optional.empty
CMD	14025.,1	0	7010000	true	Optional.empty
CMD	14025.,1	144174000	14030000	true	Optional.empty
CMD	14025.,1	14074000	0	true	Optional.empty
CMD	1.	14074000	0	false	Optional.empty
CMD	1.	0	7010000	true	Optional.empty
CMD	1.	144174000	14030000	true	Optional.empty
CMD	1.	14074000	0	true	Optional.empty
CMD	.5	14074000	0	false	Optional.empty
CMD	.5	0	7010000	true	Optional.empty
CMD	.5	144174000	14030000	true	Optional.empty
CMD	.5	14074000	0	true	Optional.empty
CMD	14025.	14074000	0	false	Optional.empty
CMD	14025.	0	7010000	true	Optional.empty
CMD	14025.	144174000	14030000	true	Optional.empty
CMD	14025.	14074000	0	true	Optional.empty
CMD	,5	14074000	0	false	Optional.empty
CMD	,5	0	7010000	true	Optional.empty
CMD	,5	144174000	14030000	true	Optional.empty
CMD	,5	14074000	0	true	Optional.empty
CMD	1e3	14074000	0	false	Optional.empty
CMD	1e3	0	7010000	true	Optional.empty
CMD	1e3	144174000	14030000	true	Optional.empty
CMD	1e3	14074000	0	true	Optional.empty
CMD	1E3	14074000	0	false	Optional.empty
CMD	1E3	0	7010000	true	Optional.empty
CMD	1E3	144174000	14030000	true	Optional.empty
CMD	1E3	14074000	0	true	Optional.empty
CMD	0x10	14074000	0	false	Optional.empty
CMD	0x10	0	7010000	true	Optional.empty
CMD	0x10	144174000	14030000	true	Optional.empty
CMD	0x10	14074000	0	true	Optional.empty
CMD	14_025	14074000	0	false	Optional.empty
CMD	14_025	0	7010000	true	Optional.empty
CMD	14_025	144174000	14030000	true	Optional.empty
CMD	14_025	14074000	0	true	Optional.empty
CMD	14 025	14074000	0	false	Optional.empty
CMD	14 025	0	7010000	true	Optional.empty
CMD	14 025	144174000	14030000	true	Optional.empty
CMD	14 025	14074000	0	true	Optional.empty
CMD	\uFF11\uFF14\uFF10\uFF12\uFF15	14074000	0	false	Optional.empty
CMD	\uFF11\uFF14\uFF10\uFF12\uFF15	0	7010000	true	Optional.empty
CMD	\uFF11\uFF14\uFF10\uFF12\uFF15	144174000	14030000	true	Optional.empty
CMD	\uFF11\uFF14\uFF10\uFF12\uFF15	14074000	0	true	Optional.empty
CMD	\u0660\u0669	14074000	0	false	Optional.empty
CMD	\u0660\u0669	0	7010000	true	Optional.empty
CMD	\u0660\u0669	144174000	14030000	true	Optional.empty
CMD	\u0660\u0669	14074000	0	true	Optional.empty
CMD	\u0661\u0664\u0660\u0662\u0665	14074000	0	false	Optional.empty
CMD	\u0661\u0664\u0660\u0662\u0665	0	7010000	true	Optional.empty
CMD	\u0661\u0664\u0660\u0662\u0665	144174000	14030000	true	Optional.empty
CMD	\u0661\u0664\u0660\u0662\u0665	14074000	0	true	Optional.empty
CMD	\u06F1\u06F4\u06F0\u06F2\u06F5	14074000	0	false	Optional.empty
CMD	\u06F1\u06F4\u06F0\u06F2\u06F5	0	7010000	true	Optional.empty
CMD	\u06F1\u06F4\u06F0\u06F2\u06F5	144174000	14030000	true	Optional.empty
CMD	\u06F1\u06F4\u06F0\u06F2\u06F5	14074000	0	true	Optional.empty
CMD	\u0967\u096A	14074000	0	false	Optional.empty
CMD	\u0967\u096A	0	7010000	true	Optional.empty
CMD	\u0967\u096A	144174000	14030000	true	Optional.empty
CMD	\u0967\u096A	14074000	0	true	Optional.empty
CMD	/\u0661\u0664	14074000	0	false	Optional.empty
CMD	/\u0661\u0664	0	7010000	true	Optional.empty
CMD	/\u0661\u0664	144174000	14030000	true	Optional.empty
CMD	/\u0661\u0664	14074000	0	true	Optional.empty
CMD	+\u0662	14074000	0	false	Optional.empty
CMD	+\u0662	0	7010000	true	Optional.empty
CMD	+\u0662	144174000	14030000	true	Optional.empty
CMD	+\u0662	14074000	0	true	Optional.empty
CMD	14025\u0660	14074000	0	false	Optional.empty
CMD	14025\u0660	0	7010000	true	Optional.empty
CMD	14025\u0660	144174000	14030000	true	Optional.empty
CMD	14025\u0660	14074000	0	true	Optional.empty
CMD	RIT \u0661\u0662\u0660	14074000	0	false	Optional[Invalid[message=RIT: zadej posun v Hz, nap\u0159. RIT 120 nebo RIT -50]]
CMD	RIT \u0661\u0662\u0660	0	7010000	true	Optional[Invalid[message=RIT: zadej posun v Hz, nap\u0159. RIT 120 nebo RIT -50]]
CMD	RIT \u0661\u0662\u0660	144174000	14030000	true	Optional[Invalid[message=RIT: zadej posun v Hz, nap\u0159. RIT 120 nebo RIT -50]]
CMD	RIT \u0661\u0662\u0660	14074000	0	true	Optional[Invalid[message=RIT: zadej posun v Hz, nap\u0159. RIT 120 nebo RIT -50]]
CMD	RIT +\u0665	14074000	0	false	Optional[Invalid[message=RIT: zadej posun v Hz, nap\u0159. RIT 120 nebo RIT -50]]
CMD	RIT +\u0665	0	7010000	true	Optional[Invalid[message=RIT: zadej posun v Hz, nap\u0159. RIT 120 nebo RIT -50]]
CMD	RIT +\u0665	144174000	14030000	true	Optional[Invalid[message=RIT: zadej posun v Hz, nap\u0159. RIT 120 nebo RIT -50]]
CMD	RIT +\u0665	14074000	0	true	Optional[Invalid[message=RIT: zadej posun v Hz, nap\u0159. RIT 120 nebo RIT -50]]
CMD		14074000	0	false	Optional.empty
CMD		0	7010000	true	Optional.empty
CMD		144174000	14030000	true	Optional.empty
CMD		14074000	0	true	Optional.empty
CMD	 	14074000	0	false	Optional.empty
CMD	 	0	7010000	true	Optional.empty
CMD	 	144174000	14030000	true	Optional.empty
CMD	 	14074000	0	true	Optional.empty
CMD	   	14074000	0	false	Optional.empty
CMD	   	0	7010000	true	Optional.empty
CMD	   	144174000	14030000	true	Optional.empty
CMD	   	14074000	0	true	Optional.empty
CMD	\t	14074000	0	false	Optional.empty
CMD	\t	0	7010000	true	Optional.empty
CMD	\t	144174000	14030000	true	Optional.empty
CMD	\t	14074000	0	true	Optional.empty
CMD	\n	14074000	0	false	Optional.empty
CMD	\n	0	7010000	true	Optional.empty
CMD	\n	144174000	14030000	true	Optional.empty
CMD	\n	14074000	0	true	Optional.empty
CMD	\u00A0	14074000	0	false	Optional.empty
CMD	\u00A0	0	7010000	true	Optional.empty
CMD	\u00A0	144174000	14030000	true	Optional.empty
CMD	\u00A0	14074000	0	true	Optional.empty
CMD	\u2003	14074000	0	false	Optional.empty
CMD	\u2003	0	7010000	true	Optional.empty
CMD	\u2003	144174000	14030000	true	Optional.empty
CMD	\u2003	14074000	0	true	Optional.empty
CMD	\u3000	14074000	0	false	Optional.empty
CMD	\u3000	0	7010000	true	Optional.empty
CMD	\u3000	144174000	14030000	true	Optional.empty
CMD	\u3000	14074000	0	true	Optional.empty
CMD	\u0085	14074000	0	false	Optional.empty
CMD	\u0085	0	7010000	true	Optional.empty
CMD	\u0085	144174000	14030000	true	Optional.empty
CMD	\u0085	14074000	0	true	Optional.empty
CMD	\u2007	14074000	0	false	Optional.empty
CMD	\u2007	0	7010000	true	Optional.empty
CMD	\u2007	144174000	14030000	true	Optional.empty
CMD	\u2007	14074000	0	true	Optional.empty
CMD	\u202F	14074000	0	false	Optional.empty
CMD	\u202F	0	7010000	true	Optional.empty
CMD	\u202F	144174000	14030000	true	Optional.empty
CMD	\u202F	14074000	0	true	Optional.empty
CMD	\u001C	14074000	0	false	Optional.empty
CMD	\u001C	0	7010000	true	Optional.empty
CMD	\u001C	144174000	14030000	true	Optional.empty
CMD	\u001C	14074000	0	true	Optional.empty
CMD	\u0001	14074000	0	false	Optional.empty
CMD	\u0001	0	7010000	true	Optional.empty
CMD	\u0001	144174000	14030000	true	Optional.empty
CMD	\u0001	14074000	0	true	Optional.empty
CMD	\u0000	14074000	0	false	Optional.empty
CMD	\u0000	0	7010000	true	Optional.empty
CMD	\u0000	144174000	14030000	true	Optional.empty
CMD	\u0000	14074000	0	true	Optional.empty
CMD	\u00A0CW	14074000	0	false	Optional.empty
CMD	\u00A0CW	0	7010000	true	Optional.empty
CMD	\u00A0CW	144174000	14030000	true	Optional.empty
CMD	\u00A0CW	14074000	0	true	Optional.empty
CMD	CW\u00A0	14074000	0	false	Optional.empty
CMD	CW\u00A0	0	7010000	true	Optional.empty
CMD	CW\u00A0	144174000	14030000	true	Optional.empty
CMD	CW\u00A0	14074000	0	true	Optional.empty
CMD	cw\u2003	14074000	0	false	Optional.empty
CMD	cw\u2003	0	7010000	true	Optional.empty
CMD	cw\u2003	144174000	14030000	true	Optional.empty
CMD	cw\u2003	14074000	0	true	Optional.empty
CMD	\u2003CW	14074000	0	false	Optional.empty
CMD	\u2003CW	0	7010000	true	Optional.empty
CMD	\u2003CW	144174000	14030000	true	Optional.empty
CMD	\u2003CW	14074000	0	true	Optional.empty
CMD	\u3000CW	14074000	0	false	Optional.empty
CMD	\u3000CW	0	7010000	true	Optional.empty
CMD	\u3000CW	144174000	14030000	true	Optional.empty
CMD	\u3000CW	14074000	0	true	Optional.empty
CMD	 CW 	14074000	0	false	Optional[ChangeMode[mode=CW]]
CMD	 CW 	0	7010000	true	Optional[ChangeMode[mode=CW]]
CMD	 CW 	144174000	14030000	true	Optional[ChangeMode[mode=CW]]
CMD	 CW 	14074000	0	true	Optional[ChangeMode[mode=CW]]
CMD	\tCW\t	14074000	0	false	Optional[ChangeMode[mode=CW]]
CMD	\tCW\t	0	7010000	true	Optional[ChangeMode[mode=CW]]
CMD	\tCW\t	144174000	14030000	true	Optional[ChangeMode[mode=CW]]
CMD	\tCW\t	14074000	0	true	Optional[ChangeMode[mode=CW]]
CMD	CW\n	14074000	0	false	Optional[ChangeMode[mode=CW]]
CMD	CW\n	0	7010000	true	Optional[ChangeMode[mode=CW]]
CMD	CW\n	144174000	14030000	true	Optional[ChangeMode[mode=CW]]
CMD	CW\n	14074000	0	true	Optional[ChangeMode[mode=CW]]
CMD	\nCW	14074000	0	false	Optional[ChangeMode[mode=CW]]
CMD	\nCW	0	7010000	true	Optional[ChangeMode[mode=CW]]
CMD	\nCW	144174000	14030000	true	Optional[ChangeMode[mode=CW]]
CMD	\nCW	14074000	0	true	Optional[ChangeMode[mode=CW]]
CMD	\u0001CW	14074000	0	false	Optional[ChangeMode[mode=CW]]
CMD	\u0001CW	0	7010000	true	Optional[ChangeMode[mode=CW]]
CMD	\u0001CW	144174000	14030000	true	Optional[ChangeMode[mode=CW]]
CMD	\u0001CW	14074000	0	true	Optional[ChangeMode[mode=CW]]
CMD	CW\u0001	14074000	0	false	Optional[ChangeMode[mode=CW]]
CMD	CW\u0001	0	7010000	true	Optional[ChangeMode[mode=CW]]
CMD	CW\u0001	144174000	14030000	true	Optional[ChangeMode[mode=CW]]
CMD	CW\u0001	14074000	0	true	Optional[ChangeMode[mode=CW]]
CMD	\u000BCW\u000C	14074000	0	false	Optional[ChangeMode[mode=CW]]
CMD	\u000BCW\u000C	0	7010000	true	Optional[ChangeMode[mode=CW]]
CMD	\u000BCW\u000C	144174000	14030000	true	Optional[ChangeMode[mode=CW]]
CMD	\u000BCW\u000C	14074000	0	true	Optional[ChangeMode[mode=CW]]
CMD	\u001CCW	14074000	0	false	Optional[ChangeMode[mode=CW]]
CMD	\u001CCW	0	7010000	true	Optional[ChangeMode[mode=CW]]
CMD	\u001CCW	144174000	14030000	true	Optional[ChangeMode[mode=CW]]
CMD	\u001CCW	14074000	0	true	Optional[ChangeMode[mode=CW]]
CMD	 14025 	14074000	0	false	Optional[Qsy[freqHz=14025000]]
CMD	 14025 	0	7010000	true	Optional[Split[txFreqHz=14025000]]
CMD	 14025 	144174000	14030000	true	Optional[Split[txFreqHz=14025000]]
CMD	 14025 	14074000	0	true	Optional[Split[txFreqHz=14025000]]
CMD	\t+2\n	14074000	0	false	Optional[Qsy[freqHz=14076000]]
CMD	\t+2\n	0	7010000	true	Optional[Invalid[message=Posun +2 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
CMD	\t+2\n	144174000	14030000	true	Optional[Split[txFreqHz=144176000]]
CMD	\t+2\n	14074000	0	true	Optional[Split[txFreqHz=14076000]]
CMD	\u00A014025	14074000	0	false	Optional.empty
CMD	\u00A014025	0	7010000	true	Optional.empty
CMD	\u00A014025	144174000	14030000	true	Optional.empty
CMD	\u00A014025	14074000	0	true	Optional.empty
CMD	14025\u00A0	14074000	0	false	Optional.empty
CMD	14025\u00A0	0	7010000	true	Optional.empty
CMD	14025\u00A0	144174000	14030000	true	Optional.empty
CMD	14025\u00A0	14074000	0	true	Optional.empty
CMD	\u0001+2	14074000	0	false	Optional[Qsy[freqHz=14076000]]
CMD	\u0001+2	0	7010000	true	Optional[Invalid[message=Posun +2 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
CMD	\u0001+2	144174000	14030000	true	Optional[Split[txFreqHz=144176000]]
CMD	\u0001+2	14074000	0	true	Optional[Split[txFreqHz=14076000]]
CMD	C W	14074000	0	false	Optional.empty
CMD	C W	0	7010000	true	Optional.empty
CMD	C W	144174000	14030000	true	Optional.empty
CMD	C W	14074000	0	true	Optional.empty
CMD	c w	14074000	0	false	Optional.empty
CMD	c w	0	7010000	true	Optional.empty
CMD	c w	144174000	14030000	true	Optional.empty
CMD	c w	14074000	0	true	Optional.empty
CMD	CW FAST	14074000	0	false	Optional.empty
CMD	CW FAST	0	7010000	true	Optional.empty
CMD	CW FAST	144174000	14030000	true	Optional.empty
CMD	CW FAST	14074000	0	true	Optional.empty
CMD	WIPELOG NOW	14074000	0	false	Optional.empty
CMD	WIPELOG NOW	0	7010000	true	Optional.empty
CMD	WIPELOG NOW	144174000	14030000	true	Optional.empty
CMD	WIPELOG NOW	14074000	0	true	Optional.empty
CMD	WIPELOG\tNOW	14074000	0	false	Optional.empty
CMD	WIPELOG\tNOW	0	7010000	true	Optional.empty
CMD	WIPELOG\tNOW	144174000	14030000	true	Optional.empty
CMD	WIPELOG\tNOW	14074000	0	true	Optional.empty
CMD	cw	14074000	0	false	Optional[ChangeMode[mode=CW]]
CMD	cw	0	7010000	true	Optional[ChangeMode[mode=CW]]
CMD	cw	144174000	14030000	true	Optional[ChangeMode[mode=CW]]
CMD	cw	14074000	0	true	Optional[ChangeMode[mode=CW]]
CMD	Cw	14074000	0	false	Optional[ChangeMode[mode=CW]]
CMD	Cw	0	7010000	true	Optional[ChangeMode[mode=CW]]
CMD	Cw	144174000	14030000	true	Optional[ChangeMode[mode=CW]]
CMD	Cw	14074000	0	true	Optional[ChangeMode[mode=CW]]
CMD	cW	14074000	0	false	Optional[ChangeMode[mode=CW]]
CMD	cW	0	7010000	true	Optional[ChangeMode[mode=CW]]
CMD	cW	144174000	14030000	true	Optional[ChangeMode[mode=CW]]
CMD	cW	14074000	0	true	Optional[ChangeMode[mode=CW]]
CMD	wipelog	14074000	0	false	Optional[WipeLog[]]
CMD	wipelog	0	7010000	true	Optional[WipeLog[]]
CMD	wipelog	144174000	14030000	true	Optional[WipeLog[]]
CMD	wipelog	14074000	0	true	Optional[WipeLog[]]
CMD	WipeLog	14074000	0	false	Optional[WipeLog[]]
CMD	WipeLog	0	7010000	true	Optional[WipeLog[]]
CMD	WipeLog	144174000	14030000	true	Optional[WipeLog[]]
CMD	WipeLog	14074000	0	true	Optional[WipeLog[]]
CMD	w\u0131pelog	14074000	0	false	Optional[WipeLog[]]
CMD	w\u0131pelog	0	7010000	true	Optional[WipeLog[]]
CMD	w\u0131pelog	144174000	14030000	true	Optional[WipeLog[]]
CMD	w\u0131pelog	14074000	0	true	Optional[WipeLog[]]
CMD	R\u0131T 5	14074000	0	false	Optional[Rit[offsetHz=5]]
CMD	R\u0131T 5	0	7010000	true	Optional[Rit[offsetHz=5]]
CMD	R\u0131T 5	144174000	14030000	true	Optional[Rit[offsetHz=5]]
CMD	R\u0131T 5	14074000	0	true	Optional[Rit[offsetHz=5]]
CMD	e\u017Fm	14074000	0	false	Optional[EsmOn[]]
CMD	e\u017Fm	0	7010000	true	Optional[EsmOn[]]
CMD	e\u017Fm	144174000	14030000	true	Optional[EsmOn[]]
CMD	e\u017Fm	14074000	0	true	Optional[EsmOn[]]
CMD	W\u212AEY	14074000	0	false	Optional.empty
CMD	W\u212AEY	0	7010000	true	Optional.empty
CMD	W\u212AEY	144174000	14030000	true	Optional.empty
CMD	W\u212AEY	14074000	0	true	Optional.empty
CMD	wkey	14074000	0	false	Optional[OpenSettingsTab[tabKey=winkey]]
CMD	wkey	0	7010000	true	Optional[OpenSettingsTab[tabKey=winkey]]
CMD	wkey	144174000	14030000	true	Optional[OpenSettingsTab[tabKey=winkey]]
CMD	wkey	14074000	0	true	Optional[OpenSettingsTab[tabKey=winkey]]
CMD	\u212Aey	14074000	0	false	Optional.empty
CMD	\u212Aey	0	7010000	true	Optional.empty
CMD	\u212Aey	144174000	14030000	true	Optional.empty
CMD	\u212Aey	14074000	0	true	Optional.empty
CMD	\u00DF	14074000	0	false	Optional.empty
CMD	\u00DF	0	7010000	true	Optional.empty
CMD	\u00DF	144174000	14030000	true	Optional.empty
CMD	\u00DF	14074000	0	true	Optional.empty
CMD	stra\u00DFe	14074000	0	false	Optional.empty
CMD	stra\u00DFe	0	7010000	true	Optional.empty
CMD	stra\u00DFe	144174000	14030000	true	Optional.empty
CMD	stra\u00DFe	14074000	0	true	Optional.empty
CMD	\uFB00	14074000	0	false	Optional.empty
CMD	\uFB00	0	7010000	true	Optional.empty
CMD	\uFB00	144174000	14030000	true	Optional.empty
CMD	\uFB00	14074000	0	true	Optional.empty
CMD	di\uFB01	14074000	0	false	Optional.empty
CMD	di\uFB01	0	7010000	true	Optional.empty
CMD	di\uFB01	144174000	14030000	true	Optional.empty
CMD	di\uFB01	14074000	0	true	Optional.empty
CMD	\u0130	14074000	0	false	Optional.empty
CMD	\u0130	0	7010000	true	Optional.empty
CMD	\u0130	144174000	14030000	true	Optional.empty
CMD	\u0130	14074000	0	true	Optional.empty
CMD	ft8	14074000	0	false	Optional[ChangeMode[mode=FT8]]
CMD	ft8	0	7010000	true	Optional[ChangeMode[mode=FT8]]
CMD	ft8	144174000	14030000	true	Optional[ChangeMode[mode=FT8]]
CMD	ft8	14074000	0	true	Optional[ChangeMode[mode=FT8]]
CMD	psk31	14074000	0	false	Optional[ChangeMode[mode=PSK]]
CMD	psk31	0	7010000	true	Optional[ChangeMode[mode=PSK]]
CMD	psk31	144174000	14030000	true	Optional[ChangeMode[mode=PSK]]
CMD	psk31	14074000	0	true	Optional[ChangeMode[mode=PSK]]
CMD	RIT 120	14074000	0	false	Optional[Rit[offsetHz=120]]
CMD	RIT 120	0	7010000	true	Optional[Rit[offsetHz=120]]
CMD	RIT 120	144174000	14030000	true	Optional[Rit[offsetHz=120]]
CMD	RIT 120	14074000	0	true	Optional[Rit[offsetHz=120]]
CMD	rit +120	14074000	0	false	Optional[Rit[offsetHz=120]]
CMD	rit +120	0	7010000	true	Optional[Rit[offsetHz=120]]
CMD	rit +120	144174000	14030000	true	Optional[Rit[offsetHz=120]]
CMD	rit +120	14074000	0	true	Optional[Rit[offsetHz=120]]
CMD	RIT -50	14074000	0	false	Optional[Rit[offsetHz=-50]]
CMD	RIT -50	0	7010000	true	Optional[Rit[offsetHz=-50]]
CMD	RIT -50	144174000	14030000	true	Optional[Rit[offsetHz=-50]]
CMD	RIT -50	14074000	0	true	Optional[Rit[offsetHz=-50]]
CMD	rit +00120	14074000	0	false	Optional[Rit[offsetHz=120]]
CMD	rit +00120	0	7010000	true	Optional[Rit[offsetHz=120]]
CMD	rit +00120	144174000	14030000	true	Optional[Rit[offsetHz=120]]
CMD	rit +00120	14074000	0	true	Optional[Rit[offsetHz=120]]
CMD	RIT +5	14074000	0	false	Optional[Rit[offsetHz=5]]
CMD	RIT +5	0	7010000	true	Optional[Rit[offsetHz=5]]
CMD	RIT +5	144174000	14030000	true	Optional[Rit[offsetHz=5]]
CMD	RIT +5	14074000	0	true	Optional[Rit[offsetHz=5]]
CMD	rit 99999	14074000	0	false	Optional[Rit[offsetHz=99999]]
CMD	rit 99999	0	7010000	true	Optional[Rit[offsetHz=99999]]
CMD	rit 99999	144174000	14030000	true	Optional[Rit[offsetHz=99999]]
CMD	rit 99999	14074000	0	true	Optional[Rit[offsetHz=99999]]
CMD	rit 100000	14074000	0	false	Optional[Invalid[message=RIT: zadej posun v Hz, nap\u0159. RIT 120 nebo RIT -50]]
CMD	rit 100000	0	7010000	true	Optional[Invalid[message=RIT: zadej posun v Hz, nap\u0159. RIT 120 nebo RIT -50]]
CMD	rit 100000	144174000	14030000	true	Optional[Invalid[message=RIT: zadej posun v Hz, nap\u0159. RIT 120 nebo RIT -50]]
CMD	rit 100000	14074000	0	true	Optional[Invalid[message=RIT: zadej posun v Hz, nap\u0159. RIT 120 nebo RIT -50]]
CMD	RIT 0	14074000	0	false	Optional[Rit[offsetHz=0]]
CMD	RIT 0	0	7010000	true	Optional[Rit[offsetHz=0]]
CMD	RIT 0	144174000	14030000	true	Optional[Rit[offsetHz=0]]
CMD	RIT 0	14074000	0	true	Optional[Rit[offsetHz=0]]
CMD	RIT -0	14074000	0	false	Optional[Rit[offsetHz=0]]
CMD	RIT -0	0	7010000	true	Optional[Rit[offsetHz=0]]
CMD	RIT -0	144174000	14030000	true	Optional[Rit[offsetHz=0]]
CMD	RIT -0	14074000	0	true	Optional[Rit[offsetHz=0]]
CMD	RIT +-5	14074000	0	false	Optional[Invalid[message=RIT: zadej posun v Hz, nap\u0159. RIT 120 nebo RIT -50]]
CMD	RIT +-5	0	7010000	true	Optional[Invalid[message=RIT: zadej posun v Hz, nap\u0159. RIT 120 nebo RIT -50]]
CMD	RIT +-5	144174000	14030000	true	Optional[Invalid[message=RIT: zadej posun v Hz, nap\u0159. RIT 120 nebo RIT -50]]
CMD	RIT +-5	14074000	0	true	Optional[Invalid[message=RIT: zadej posun v Hz, nap\u0159. RIT 120 nebo RIT -50]]
CMD	RIT 0x10	14074000	0	false	Optional[Invalid[message=RIT: zadej posun v Hz, nap\u0159. RIT 120 nebo RIT -50]]
CMD	RIT 0x10	0	7010000	true	Optional[Invalid[message=RIT: zadej posun v Hz, nap\u0159. RIT 120 nebo RIT -50]]
CMD	RIT 0x10	144174000	14030000	true	Optional[Invalid[message=RIT: zadej posun v Hz, nap\u0159. RIT 120 nebo RIT -50]]
CMD	RIT 0x10	14074000	0	true	Optional[Invalid[message=RIT: zadej posun v Hz, nap\u0159. RIT 120 nebo RIT -50]]
CMD	RIT 12a	14074000	0	false	Optional[Invalid[message=RIT: zadej posun v Hz, nap\u0159. RIT 120 nebo RIT -50]]
CMD	RIT 12a	0	7010000	true	Optional[Invalid[message=RIT: zadej posun v Hz, nap\u0159. RIT 120 nebo RIT -50]]
CMD	RIT 12a	144174000	14030000	true	Optional[Invalid[message=RIT: zadej posun v Hz, nap\u0159. RIT 120 nebo RIT -50]]
CMD	RIT 12a	14074000	0	true	Optional[Invalid[message=RIT: zadej posun v Hz, nap\u0159. RIT 120 nebo RIT -50]]
CMD	RIT	14074000	0	false	Optional[Invalid[message=RIT: zadej posun v Hz, nap\u0159. RIT 120 nebo RIT -50]]
CMD	RIT	0	7010000	true	Optional[Invalid[message=RIT: zadej posun v Hz, nap\u0159. RIT 120 nebo RIT -50]]
CMD	RIT	144174000	14030000	true	Optional[Invalid[message=RIT: zadej posun v Hz, nap\u0159. RIT 120 nebo RIT -50]]
CMD	RIT	14074000	0	true	Optional[Invalid[message=RIT: zadej posun v Hz, nap\u0159. RIT 120 nebo RIT -50]]
CMD	RIT 	14074000	0	false	Optional[Invalid[message=RIT: zadej posun v Hz, nap\u0159. RIT 120 nebo RIT -50]]
CMD	RIT 	0	7010000	true	Optional[Invalid[message=RIT: zadej posun v Hz, nap\u0159. RIT 120 nebo RIT -50]]
CMD	RIT 	144174000	14030000	true	Optional[Invalid[message=RIT: zadej posun v Hz, nap\u0159. RIT 120 nebo RIT -50]]
CMD	RIT 	14074000	0	true	Optional[Invalid[message=RIT: zadej posun v Hz, nap\u0159. RIT 120 nebo RIT -50]]
CMD	RIT\t120	14074000	0	false	Optional[Rit[offsetHz=120]]
CMD	RIT\t120	0	7010000	true	Optional[Rit[offsetHz=120]]
CMD	RIT\t120	144174000	14030000	true	Optional[Rit[offsetHz=120]]
CMD	RIT\t120	14074000	0	true	Optional[Rit[offsetHz=120]]
CMD	RIT  120	14074000	0	false	Optional[Rit[offsetHz=120]]
CMD	RIT  120	0	7010000	true	Optional[Rit[offsetHz=120]]
CMD	RIT  120	144174000	14030000	true	Optional[Rit[offsetHz=120]]
CMD	RIT  120	14074000	0	true	Optional[Rit[offsetHz=120]]
CMD	RIT\u00A0120	14074000	0	false	Optional.empty
CMD	RIT\u00A0120	0	7010000	true	Optional.empty
CMD	RIT\u00A0120	144174000	14030000	true	Optional.empty
CMD	RIT\u00A0120	14074000	0	true	Optional.empty
CMD	RIT 120 5	14074000	0	false	Optional[Invalid[message=RIT: zadej posun v Hz, nap\u0159. RIT 120 nebo RIT -50]]
CMD	RIT 120 5	0	7010000	true	Optional[Invalid[message=RIT: zadej posun v Hz, nap\u0159. RIT 120 nebo RIT -50]]
CMD	RIT 120 5	144174000	14030000	true	Optional[Invalid[message=RIT: zadej posun v Hz, nap\u0159. RIT 120 nebo RIT -50]]
CMD	RIT 120 5	14074000	0	true	Optional[Invalid[message=RIT: zadej posun v Hz, nap\u0159. RIT 120 nebo RIT -50]]
CMD	RIT -00000	14074000	0	false	Optional[Rit[offsetHz=0]]
CMD	RIT -00000	0	7010000	true	Optional[Rit[offsetHz=0]]
CMD	RIT -00000	144174000	14030000	true	Optional[Rit[offsetHz=0]]
CMD	RIT -00000	14074000	0	true	Optional[Rit[offsetHz=0]]
CMD	RIT -99999	14074000	0	false	Optional[Rit[offsetHz=-99999]]
CMD	RIT -99999	0	7010000	true	Optional[Rit[offsetHz=-99999]]
CMD	RIT -99999	144174000	14030000	true	Optional[Rit[offsetHz=-99999]]
CMD	RIT -99999	14074000	0	true	Optional[Rit[offsetHz=-99999]]
CMD	RIT abc	14074000	0	false	Optional[Invalid[message=RIT: zadej posun v Hz, nap\u0159. RIT 120 nebo RIT -50]]
CMD	RIT abc	0	7010000	true	Optional[Invalid[message=RIT: zadej posun v Hz, nap\u0159. RIT 120 nebo RIT -50]]
CMD	RIT abc	144174000	14030000	true	Optional[Invalid[message=RIT: zadej posun v Hz, nap\u0159. RIT 120 nebo RIT -50]]
CMD	RIT abc	14074000	0	true	Optional[Invalid[message=RIT: zadej posun v Hz, nap\u0159. RIT 120 nebo RIT -50]]
CMD	RITX	14074000	0	false	Optional.empty
CMD	RITX	0	7010000	true	Optional.empty
CMD	RITX	144174000	14030000	true	Optional.empty
CMD	RITX	14074000	0	true	Optional.empty
CMD	RIT120	14074000	0	false	Optional.empty
CMD	RIT120	0	7010000	true	Optional.empty
CMD	RIT120	144174000	14030000	true	Optional.empty
CMD	RIT120	14074000	0	true	Optional.empty
CMD	SCRIPT foo bar	14074000	0	false	Optional[RunScript[name=FOO BAR]]
CMD	SCRIPT foo bar	0	7010000	true	Optional[RunScript[name=FOO BAR]]
CMD	SCRIPT foo bar	144174000	14030000	true	Optional[RunScript[name=FOO BAR]]
CMD	SCRIPT foo bar	14074000	0	true	Optional[RunScript[name=FOO BAR]]
CMD	script	14074000	0	false	Optional[Invalid[message=SCRIPT: zadej jm\u00E9no skriptu (soubor scripts/<jm\u00E9no>.txt)]]
CMD	script	0	7010000	true	Optional[Invalid[message=SCRIPT: zadej jm\u00E9no skriptu (soubor scripts/<jm\u00E9no>.txt)]]
CMD	script	144174000	14030000	true	Optional[Invalid[message=SCRIPT: zadej jm\u00E9no skriptu (soubor scripts/<jm\u00E9no>.txt)]]
CMD	script	14074000	0	true	Optional[Invalid[message=SCRIPT: zadej jm\u00E9no skriptu (soubor scripts/<jm\u00E9no>.txt)]]
CMD	SCRIPT  	14074000	0	false	Optional[Invalid[message=SCRIPT: zadej jm\u00E9no skriptu (soubor scripts/<jm\u00E9no>.txt)]]
CMD	SCRIPT  	0	7010000	true	Optional[Invalid[message=SCRIPT: zadej jm\u00E9no skriptu (soubor scripts/<jm\u00E9no>.txt)]]
CMD	SCRIPT  	144174000	14030000	true	Optional[Invalid[message=SCRIPT: zadej jm\u00E9no skriptu (soubor scripts/<jm\u00E9no>.txt)]]
CMD	SCRIPT  	14074000	0	true	Optional[Invalid[message=SCRIPT: zadej jm\u00E9no skriptu (soubor scripts/<jm\u00E9no>.txt)]]
CMD	script run20	14074000	0	false	Optional[RunScript[name=RUN20]]
CMD	script run20	0	7010000	true	Optional[RunScript[name=RUN20]]
CMD	script run20	144174000	14030000	true	Optional[RunScript[name=RUN20]]
CMD	script run20	14074000	0	true	Optional[RunScript[name=RUN20]]
CMD	SCRIPT\tx	14074000	0	false	Optional[RunScript[name=X]]
CMD	SCRIPT\tx	0	7010000	true	Optional[RunScript[name=X]]
CMD	SCRIPT\tx	144174000	14030000	true	Optional[RunScript[name=X]]
CMD	SCRIPT\tx	14074000	0	true	Optional[RunScript[name=X]]
CMD	SCRIPT \u0001x\u0001	14074000	0	false	Optional[RunScript[name=X]]
CMD	SCRIPT \u0001x\u0001	0	7010000	true	Optional[RunScript[name=X]]
CMD	SCRIPT \u0001x\u0001	144174000	14030000	true	Optional[RunScript[name=X]]
CMD	SCRIPT \u0001x\u0001	14074000	0	true	Optional[RunScript[name=X]]
CMD	OPON	14074000	0	false	Optional[Login[operator=]]
CMD	OPON	0	7010000	true	Optional[Login[operator=]]
CMD	OPON	144174000	14030000	true	Optional[Login[operator=]]
CMD	OPON	14074000	0	true	Optional[Login[operator=]]
CMD	opon	14074000	0	false	Optional[Login[operator=]]
CMD	opon	0	7010000	true	Optional[Login[operator=]]
CMD	opon	144174000	14030000	true	Optional[Login[operator=]]
CMD	opon	14074000	0	true	Optional[Login[operator=]]
CMD	OPON K1A	14074000	0	false	Optional[Login[operator=K1A]]
CMD	OPON K1A	0	7010000	true	Optional[Login[operator=K1A]]
CMD	OPON K1A	144174000	14030000	true	Optional[Login[operator=K1A]]
CMD	OPON K1A	14074000	0	true	Optional[Login[operator=K1A]]
CMD	opon k1abc extra	14074000	0	false	Optional[Login[operator=K1ABC]]
CMD	opon k1abc extra	0	7010000	true	Optional[Login[operator=K1ABC]]
CMD	opon k1abc extra	144174000	14030000	true	Optional[Login[operator=K1ABC]]
CMD	opon k1abc extra	14074000	0	true	Optional[Login[operator=K1ABC]]
CMD	LOGIN	14074000	0	false	Optional[Login[operator=]]
CMD	LOGIN	0	7010000	true	Optional[Login[operator=]]
CMD	LOGIN	144174000	14030000	true	Optional[Login[operator=]]
CMD	LOGIN	14074000	0	true	Optional[Login[operator=]]
CMD	LOGIN  ok1xoe	14074000	0	false	Optional[Login[operator=OK1XOE]]
CMD	LOGIN  ok1xoe	0	7010000	true	Optional[Login[operator=OK1XOE]]
CMD	LOGIN  ok1xoe	144174000	14030000	true	Optional[Login[operator=OK1XOE]]
CMD	LOGIN  ok1xoe	14074000	0	true	Optional[Login[operator=OK1XOE]]
CMD	OPON\u00A0K1A	14074000	0	false	Optional.empty
CMD	OPON\u00A0K1A	0	7010000	true	Optional.empty
CMD	OPON\u00A0K1A	144174000	14030000	true	Optional.empty
CMD	OPON\u00A0K1A	14074000	0	true	Optional.empty
CMD	OPON\tK1A	14074000	0	false	Optional[Login[operator=K1A]]
CMD	OPON\tK1A	0	7010000	true	Optional[Login[operator=K1A]]
CMD	OPON\tK1A	144174000	14030000	true	Optional[Login[operator=K1A]]
CMD	OPON\tK1A	14074000	0	true	Optional[Login[operator=K1A]]
CMD	  opon   ok1k  	14074000	0	false	Optional[Login[operator=OK1K]]
CMD	  opon   ok1k  	0	7010000	true	Optional[Login[operator=OK1K]]
CMD	  opon   ok1k  	144174000	14030000	true	Optional[Login[operator=OK1K]]
CMD	  opon   ok1k  	14074000	0	true	Optional[Login[operator=OK1K]]
CMD	OPONX	14074000	0	false	Optional.empty
CMD	OPONX	0	7010000	true	Optional.empty
CMD	OPONX	144174000	14030000	true	Optional.empty
CMD	OPONX	14074000	0	true	Optional.empty
CMD	OPON/P	14074000	0	false	Optional.empty
CMD	OPON/P	0	7010000	true	Optional.empty
CMD	OPON/P	144174000	14030000	true	Optional.empty
CMD	OPON/P	14074000	0	true	Optional.empty
CMD	LOGINX	14074000	0	false	Optional.empty
CMD	LOGINX	0	7010000	true	Optional.empty
CMD	LOGINX	144174000	14030000	true	Optional.empty
CMD	LOGINX	14074000	0	true	Optional.empty
CMD	opon \u00DF	14074000	0	false	Optional[Login[operator=SS]]
CMD	opon \u00DF	0	7010000	true	Optional[Login[operator=SS]]
CMD	opon \u00DF	144174000	14030000	true	Optional[Login[operator=SS]]
CMD	opon \u00DF	14074000	0	true	Optional[Login[operator=SS]]
CMD	TOUR	14074000	0	false	Optional[SetTour[params=]]
CMD	TOUR	0	7010000	true	Optional[SetTour[params=]]
CMD	TOUR	144174000	14030000	true	Optional[SetTour[params=]]
CMD	TOUR	14074000	0	true	Optional[SetTour[params=]]
CMD	tour	14074000	0	false	Optional[SetTour[params=]]
CMD	tour	0	7010000	true	Optional[SetTour[params=]]
CMD	tour	144174000	14030000	true	Optional[SetTour[params=]]
CMD	tour	14074000	0	true	Optional[SetTour[params=]]
CMD	tour 1200/30	14074000	0	false	Optional[SetTour[params=1200/30]]
CMD	tour 1200/30	0	7010000	true	Optional[SetTour[params=1200/30]]
CMD	tour 1200/30	144174000	14030000	true	Optional[SetTour[params=1200/30]]
CMD	tour 1200/30	14074000	0	true	Optional[SetTour[params=1200/30]]
CMD	TOUR\t1200/30	14074000	0	false	Optional[SetTour[params=1200/30]]
CMD	TOUR\t1200/30	0	7010000	true	Optional[SetTour[params=1200/30]]
CMD	TOUR\t1200/30	144174000	14030000	true	Optional[SetTour[params=1200/30]]
CMD	TOUR\t1200/30	14074000	0	true	Optional[SetTour[params=1200/30]]
CMD	TOUR a\u00A0b	14074000	0	false	Optional[SetTour[params=A\u00A0B]]
CMD	TOUR a\u00A0b	0	7010000	true	Optional[SetTour[params=A\u00A0B]]
CMD	TOUR a\u00A0b	144174000	14030000	true	Optional[SetTour[params=A\u00A0B]]
CMD	TOUR a\u00A0b	14074000	0	true	Optional[SetTour[params=A\u00A0B]]
CMD	TOUR1	14074000	0	false	Optional.empty
CMD	TOUR1	0	7010000	true	Optional.empty
CMD	TOUR1	144174000	14030000	true	Optional.empty
CMD	TOUR1	14074000	0	true	Optional.empty
CMD	BONUS	14074000	0	false	Optional[BonusStations[calls=]]
CMD	BONUS	0	7010000	true	Optional[BonusStations[calls=]]
CMD	BONUS	144174000	14030000	true	Optional[BonusStations[calls=]]
CMD	BONUS	14074000	0	true	Optional[BonusStations[calls=]]
CMD	BONUS K1A, K1B	14074000	0	false	Optional[BonusStations[calls=K1A, K1B]]
CMD	BONUS K1A, K1B	0	7010000	true	Optional[BonusStations[calls=K1A, K1B]]
CMD	BONUS K1A, K1B	144174000	14030000	true	Optional[BonusStations[calls=K1A, K1B]]
CMD	BONUS K1A, K1B	14074000	0	true	Optional[BonusStations[calls=K1A, K1B]]
CMD	BONUS  K1A,  K1B 	14074000	0	false	Optional[BonusStations[calls=K1A,  K1B]]
CMD	BONUS  K1A,  K1B 	0	7010000	true	Optional[BonusStations[calls=K1A,  K1B]]
CMD	BONUS  K1A,  K1B 	144174000	14030000	true	Optional[BonusStations[calls=K1A,  K1B]]
CMD	BONUS  K1A,  K1B 	14074000	0	true	Optional[BonusStations[calls=K1A,  K1B]]
CMD	BONUSX	14074000	0	false	Optional.empty
CMD	BONUSX	0	7010000	true	Optional.empty
CMD	BONUSX	144174000	14030000	true	Optional.empty
CMD	BONUSX	14074000	0	true	Optional.empty
CMD	roverqth ham	14074000	0	false	Optional[RoverQth[county=HAM]]
CMD	roverqth ham	0	7010000	true	Optional[RoverQth[county=HAM]]
CMD	roverqth ham	144174000	14030000	true	Optional[RoverQth[county=HAM]]
CMD	roverqth ham	14074000	0	true	Optional[RoverQth[county=HAM]]
CMD	ROVERQTH	14074000	0	false	Optional[RoverQth[county=]]
CMD	ROVERQTH	0	7010000	true	Optional[RoverQth[county=]]
CMD	ROVERQTH	144174000	14030000	true	Optional[RoverQth[county=]]
CMD	ROVERQTH	14074000	0	true	Optional[RoverQth[county=]]
CMD	COUNTYLINE DAD,JEF	14074000	0	false	Optional[CountyLine[counties=DAD,JEF]]
CMD	COUNTYLINE DAD,JEF	0	7010000	true	Optional[CountyLine[counties=DAD,JEF]]
CMD	COUNTYLINE DAD,JEF	144174000	14030000	true	Optional[CountyLine[counties=DAD,JEF]]
CMD	COUNTYLINE DAD,JEF	14074000	0	true	Optional[CountyLine[counties=DAD,JEF]]
CMD	COUNTYLINE	14074000	0	false	Optional[CountyLine[counties=]]
CMD	COUNTYLINE	0	7010000	true	Optional[CountyLine[counties=]]
CMD	COUNTYLINE	144174000	14030000	true	Optional[CountyLine[counties=]]
CMD	COUNTYLINE	14074000	0	true	Optional[CountyLine[counties=]]
CMD	SPOTME	14074000	0	false	Optional[SpotMe[comment=]]
CMD	SPOTME	0	7010000	true	Optional[SpotMe[comment=]]
CMD	SPOTME	144174000	14030000	true	Optional[SpotMe[comment=]]
CMD	SPOTME	14074000	0	true	Optional[SpotMe[comment=]]
CMD	SPOTME CQ TEST	14074000	0	false	Optional[SpotMe[comment=CQ TEST]]
CMD	SPOTME CQ TEST	0	7010000	true	Optional[SpotMe[comment=CQ TEST]]
CMD	SPOTME CQ TEST	144174000	14030000	true	Optional[SpotMe[comment=CQ TEST]]
CMD	SPOTME CQ TEST	14074000	0	true	Optional[SpotMe[comment=CQ TEST]]
CMD	spotme cq  test	14074000	0	false	Optional[SpotMe[comment=CQ  TEST]]
CMD	spotme cq  test	0	7010000	true	Optional[SpotMe[comment=CQ  TEST]]
CMD	spotme cq  test	144174000	14030000	true	Optional[SpotMe[comment=CQ  TEST]]
CMD	spotme cq  test	14074000	0	true	Optional[SpotMe[comment=CQ  TEST]]
CMD	SPOTME\u00A0X	14074000	0	false	Optional.empty
CMD	SPOTME\u00A0X	0	7010000	true	Optional.empty
CMD	SPOTME\u00A0X	144174000	14030000	true	Optional.empty
CMD	SPOTME\u00A0X	14074000	0	true	Optional.empty
CMD	NOCOUNTYLINE	14074000	0	false	Optional[CountyLineOff[]]
CMD	NOCOUNTYLINE	0	7010000	true	Optional[CountyLineOff[]]
CMD	NOCOUNTYLINE	144174000	14030000	true	Optional[CountyLineOff[]]
CMD	NOCOUNTYLINE	14074000	0	true	Optional[CountyLineOff[]]
CMD	NOTOUR	14074000	0	false	Optional[TourOff[]]
CMD	NOTOUR	0	7010000	true	Optional[TourOff[]]
CMD	NOTOUR	144174000	14030000	true	Optional[TourOff[]]
CMD	NOTOUR	14074000	0	true	Optional[TourOff[]]
CMD	OK1XOE	14074000	0	false	Optional.empty
CMD	OK1XOE	0	7010000	true	Optional.empty
CMD	OK1XOE	144174000	14030000	true	Optional.empty
CMD	OK1XOE	14074000	0	true	Optional.empty
CMD	CW1A	14074000	0	false	Optional.empty
CMD	CW1A	0	7010000	true	Optional.empty
CMD	CW1A	144174000	14030000	true	Optional.empty
CMD	CW1A	14074000	0	true	Optional.empty
CMD	NET1X	14074000	0	false	Optional.empty
CMD	NET1X	0	7010000	true	Optional.empty
CMD	NET1X	144174000	14030000	true	Optional.empty
CMD	NET1X	14074000	0	true	Optional.empty
CMD	4X4AA	14074000	0	false	Optional.empty
CMD	4X4AA	0	7010000	true	Optional.empty
CMD	4X4AA	144174000	14030000	true	Optional.empty
CMD	4X4AA	14074000	0	true	Optional.empty
CMD	OK1XOE/P	14074000	0	false	Optional.empty
CMD	OK1XOE/P	0	7010000	true	Optional.empty
CMD	OK1XOE/P	144174000	14030000	true	Optional.empty
CMD	OK1XOE/P	14074000	0	true	Optional.empty
CMD	/P	14074000	0	false	Optional.empty
CMD	/P	0	7010000	true	Optional.empty
CMD	/P	144174000	14030000	true	Optional.empty
CMD	/P	14074000	0	true	Optional.empty
CMD	/-x	14074000	0	false	Optional.empty
CMD	/-x	0	7010000	true	Optional.empty
CMD	/-x	144174000	14030000	true	Optional.empty
CMD	/-x	14074000	0	true	Optional.empty
CMD	OK1ABC	14074000	0	false	Optional.empty
CMD	OK1ABC	0	7010000	true	Optional.empty
CMD	OK1ABC	144174000	14030000	true	Optional.empty
CMD	OK1ABC	14074000	0	true	Optional.empty
CMD	W1AW	14074000	0	false	Optional.empty
CMD	W1AW	0	7010000	true	Optional.empty
CMD	W1AW	144174000	14030000	true	Optional.empty
CMD	W1AW	14074000	0	true	Optional.empty
CMD	1A1A	14074000	0	false	Optional.empty
CMD	1A1A	0	7010000	true	Optional.empty
CMD	1A1A	144174000	14030000	true	Optional.empty
CMD	1A1A	14074000	0	true	Optional.empty
CMD	14025A	14074000	0	false	Optional.empty
CMD	14025A	0	7010000	true	Optional.empty
CMD	14025A	144174000	14030000	true	Optional.empty
CMD	14025A	14074000	0	true	Optional.empty
WORD	WIPELOG	14074000	0	false	Optional[WipeLog[]]
WORD	 WIPELOG 	14074000	0	false	Optional[WipeLog[]]
WORD	WIPELOG X	14074000	0	false	Optional.empty
WORD	wipelog  k1abc  extra	14074000	0	false	Optional.empty
WORD	WIPELOGX	14074000	0	false	Optional.empty
WORD	WIPELOG\u00A0	14074000	0	false	Optional.empty
WORD	CLEARLOG	14074000	0	false	Optional[WipeLog[]]
WORD	clearlog	14074000	0	false	Optional[WipeLog[]]
WORD	 CLEARLOG 	14074000	0	false	Optional[WipeLog[]]
WORD	CLEARLOG X	14074000	0	false	Optional.empty
WORD	clearlog  k1abc  extra	14074000	0	false	Optional.empty
WORD	CLEARLOGX	14074000	0	false	Optional.empty
WORD	CLEARLOG\u00A0	14074000	0	false	Optional.empty
WORD	VERSION	14074000	0	false	Optional[Version[]]
WORD	version	14074000	0	false	Optional[Version[]]
WORD	 VERSION 	14074000	0	false	Optional[Version[]]
WORD	VERSION X	14074000	0	false	Optional.empty
WORD	version  k1abc  extra	14074000	0	false	Optional.empty
WORD	VERSIONX	14074000	0	false	Optional.empty
WORD	VERSION\u00A0	14074000	0	false	Optional.empty
WORD	VER	14074000	0	false	Optional[Version[]]
WORD	ver	14074000	0	false	Optional[Version[]]
WORD	 VER 	14074000	0	false	Optional[Version[]]
WORD	VER X	14074000	0	false	Optional.empty
WORD	ver  k1abc  extra	14074000	0	false	Optional.empty
WORD	VERX	14074000	0	false	Optional.empty
WORD	VER\u00A0	14074000	0	false	Optional.empty
WORD	EXPORT	14074000	0	false	Optional[ExportAdif[]]
WORD	export	14074000	0	false	Optional[ExportAdif[]]
WORD	 EXPORT 	14074000	0	false	Optional[ExportAdif[]]
WORD	EXPORT X	14074000	0	false	Optional.empty
WORD	export  k1abc  extra	14074000	0	false	Optional.empty
WORD	EXPORTX	14074000	0	false	Optional.empty
WORD	EXPORT\u00A0	14074000	0	false	Optional.empty
WORD	IMPORT	14074000	0	false	Optional[ImportLog[]]
WORD	import	14074000	0	false	Optional[ImportLog[]]
WORD	 IMPORT 	14074000	0	false	Optional[ImportLog[]]
WORD	IMPORT X	14074000	0	false	Optional.empty
WORD	import  k1abc  extra	14074000	0	false	Optional.empty
WORD	IMPORTX	14074000	0	false	Optional.empty
WORD	IMPORT\u00A0	14074000	0	false	Optional.empty
WORD	WRITELOG	14074000	0	false	Optional[ExportCabrillo[]]
WORD	writelog	14074000	0	false	Optional[ExportCabrillo[]]
WORD	 WRITELOG 	14074000	0	false	Optional[ExportCabrillo[]]
WORD	WRITELOG X	14074000	0	false	Optional.empty
WORD	writelog  k1abc  extra	14074000	0	false	Optional.empty
WORD	WRITELOGX	14074000	0	false	Optional.empty
WORD	WRITELOG\u00A0	14074000	0	false	Optional.empty
WORD	MAKELOG	14074000	0	false	Optional[ExportCabrillo[]]
WORD	makelog	14074000	0	false	Optional[ExportCabrillo[]]
WORD	 MAKELOG 	14074000	0	false	Optional[ExportCabrillo[]]
WORD	MAKELOG X	14074000	0	false	Optional.empty
WORD	makelog  k1abc  extra	14074000	0	false	Optional.empty
WORD	MAKELOGX	14074000	0	false	Optional.empty
WORD	MAKELOG\u00A0	14074000	0	false	Optional.empty
WORD	RESCORE	14074000	0	false	Optional[Rescore[]]
WORD	rescore	14074000	0	false	Optional[Rescore[]]
WORD	 RESCORE 	14074000	0	false	Optional[Rescore[]]
WORD	RESCORE X	14074000	0	false	Optional.empty
WORD	rescore  k1abc  extra	14074000	0	false	Optional.empty
WORD	RESCOREX	14074000	0	false	Optional.empty
WORD	RESCORE\u00A0	14074000	0	false	Optional.empty
WORD	AUTORSP	14074000	0	false	Optional[AutoRunSp[enabled=true]]
WORD	autorsp	14074000	0	false	Optional[AutoRunSp[enabled=true]]
WORD	 AUTORSP 	14074000	0	false	Optional[AutoRunSp[enabled=true]]
WORD	AUTORSP X	14074000	0	false	Optional.empty
WORD	autorsp  k1abc  extra	14074000	0	false	Optional.empty
WORD	AUTORSPX	14074000	0	false	Optional.empty
WORD	AUTORSP\u00A0	14074000	0	false	Optional.empty
WORD	AUTORSPON	14074000	0	false	Optional[AutoRunSp[enabled=true]]
WORD	autorspon	14074000	0	false	Optional[AutoRunSp[enabled=true]]
WORD	 AUTORSPON 	14074000	0	false	Optional[AutoRunSp[enabled=true]]
WORD	AUTORSPON X	14074000	0	false	Optional.empty
WORD	autorspon  k1abc  extra	14074000	0	false	Optional.empty
WORD	AUTORSPONX	14074000	0	false	Optional.empty
WORD	AUTORSPON\u00A0	14074000	0	false	Optional.empty
WORD	NOAUTRSP	14074000	0	false	Optional[AutoRunSp[enabled=false]]
WORD	noautrsp	14074000	0	false	Optional[AutoRunSp[enabled=false]]
WORD	 NOAUTRSP 	14074000	0	false	Optional[AutoRunSp[enabled=false]]
WORD	NOAUTRSP X	14074000	0	false	Optional.empty
WORD	noautrsp  k1abc  extra	14074000	0	false	Optional.empty
WORD	NOAUTRSPX	14074000	0	false	Optional.empty
WORD	NOAUTRSP\u00A0	14074000	0	false	Optional.empty
WORD	NOAUTORSP	14074000	0	false	Optional[AutoRunSp[enabled=false]]
WORD	noautorsp	14074000	0	false	Optional[AutoRunSp[enabled=false]]
WORD	 NOAUTORSP 	14074000	0	false	Optional[AutoRunSp[enabled=false]]
WORD	NOAUTORSP X	14074000	0	false	Optional.empty
WORD	noautorsp  k1abc  extra	14074000	0	false	Optional.empty
WORD	NOAUTORSPX	14074000	0	false	Optional.empty
WORD	NOAUTORSP\u00A0	14074000	0	false	Optional.empty
WORD	AUTORSPOFF	14074000	0	false	Optional[AutoRunSp[enabled=false]]
WORD	autorspoff	14074000	0	false	Optional[AutoRunSp[enabled=false]]
WORD	 AUTORSPOFF 	14074000	0	false	Optional[AutoRunSp[enabled=false]]
WORD	AUTORSPOFF X	14074000	0	false	Optional.empty
WORD	autorspoff  k1abc  extra	14074000	0	false	Optional.empty
WORD	AUTORSPOFFX	14074000	0	false	Optional.empty
WORD	AUTORSPOFF\u00A0	14074000	0	false	Optional.empty
WORD	ESM	14074000	0	false	Optional[EsmOn[]]
WORD	esm	14074000	0	false	Optional[EsmOn[]]
WORD	 ESM 	14074000	0	false	Optional[EsmOn[]]
WORD	ESM X	14074000	0	false	Optional.empty
WORD	esm  k1abc  extra	14074000	0	false	Optional.empty
WORD	ESMX	14074000	0	false	Optional.empty
WORD	ESM\u00A0	14074000	0	false	Optional.empty
WORD	ESMON	14074000	0	false	Optional[EsmOn[]]
WORD	esmon	14074000	0	false	Optional[EsmOn[]]
WORD	 ESMON 	14074000	0	false	Optional[EsmOn[]]
WORD	ESMON X	14074000	0	false	Optional.empty
WORD	esmon  k1abc  extra	14074000	0	false	Optional.empty
WORD	ESMONX	14074000	0	false	Optional.empty
WORD	ESMON\u00A0	14074000	0	false	Optional.empty
WORD	NOESM	14074000	0	false	Optional[EsmOff[]]
WORD	noesm	14074000	0	false	Optional[EsmOff[]]
WORD	 NOESM 	14074000	0	false	Optional[EsmOff[]]
WORD	NOESM X	14074000	0	false	Optional.empty
WORD	noesm  k1abc  extra	14074000	0	false	Optional.empty
WORD	NOESMX	14074000	0	false	Optional.empty
WORD	NOESM\u00A0	14074000	0	false	Optional.empty
WORD	ESMOFF	14074000	0	false	Optional[EsmOff[]]
WORD	esmoff	14074000	0	false	Optional[EsmOff[]]
WORD	 ESMOFF 	14074000	0	false	Optional[EsmOff[]]
WORD	ESMOFF X	14074000	0	false	Optional.empty
WORD	esmoff  k1abc  extra	14074000	0	false	Optional.empty
WORD	ESMOFFX	14074000	0	false	Optional.empty
WORD	ESMOFF\u00A0	14074000	0	false	Optional.empty
WORD	BCLOG	14074000	0	false	Optional[AppAction[action=BROADCAST_LOG]]
WORD	bclog	14074000	0	false	Optional[AppAction[action=BROADCAST_LOG]]
WORD	 BCLOG 	14074000	0	false	Optional[AppAction[action=BROADCAST_LOG]]
WORD	BCLOG X	14074000	0	false	Optional.empty
WORD	bclog  k1abc  extra	14074000	0	false	Optional.empty
WORD	BCLOGX	14074000	0	false	Optional.empty
WORD	BCLOG\u00A0	14074000	0	false	Optional.empty
WORD	BYE	14074000	0	false	Optional[AppAction[action=EXIT]]
WORD	bye	14074000	0	false	Optional[AppAction[action=EXIT]]
WORD	 BYE 	14074000	0	false	Optional[AppAction[action=EXIT]]
WORD	BYE X	14074000	0	false	Optional.empty
WORD	bye  k1abc  extra	14074000	0	false	Optional.empty
WORD	BYEX	14074000	0	false	Optional.empty
WORD	BYE\u00A0	14074000	0	false	Optional.empty
WORD	EXIT	14074000	0	false	Optional[AppAction[action=EXIT]]
WORD	exit	14074000	0	false	Optional[AppAction[action=EXIT]]
WORD	 EXIT 	14074000	0	false	Optional[AppAction[action=EXIT]]
WORD	EXIT X	14074000	0	false	Optional.empty
WORD	exit  k1abc  extra	14074000	0	false	Optional.empty
WORD	EXITX	14074000	0	false	Optional.empty
WORD	EXIT\u00A0	14074000	0	false	Optional.empty
WORD	QUIT	14074000	0	false	Optional[AppAction[action=EXIT]]
WORD	quit	14074000	0	false	Optional[AppAction[action=EXIT]]
WORD	 QUIT 	14074000	0	false	Optional[AppAction[action=EXIT]]
WORD	QUIT X	14074000	0	false	Optional.empty
WORD	quit  k1abc  extra	14074000	0	false	Optional.empty
WORD	QUITX	14074000	0	false	Optional.empty
WORD	QUIT\u00A0	14074000	0	false	Optional.empty
WORD	EXITNOW	14074000	0	false	Optional[AppAction[action=EXIT_NOW]]
WORD	exitnow	14074000	0	false	Optional[AppAction[action=EXIT_NOW]]
WORD	 EXITNOW 	14074000	0	false	Optional[AppAction[action=EXIT_NOW]]
WORD	EXITNOW X	14074000	0	false	Optional.empty
WORD	exitnow  k1abc  extra	14074000	0	false	Optional.empty
WORD	EXITNOWX	14074000	0	false	Optional.empty
WORD	EXITNOW\u00A0	14074000	0	false	Optional.empty
WORD	QUITNOW	14074000	0	false	Optional[AppAction[action=EXIT_NOW]]
WORD	quitnow	14074000	0	false	Optional[AppAction[action=EXIT_NOW]]
WORD	 QUITNOW 	14074000	0	false	Optional[AppAction[action=EXIT_NOW]]
WORD	QUITNOW X	14074000	0	false	Optional.empty
WORD	quitnow  k1abc  extra	14074000	0	false	Optional.empty
WORD	QUITNOWX	14074000	0	false	Optional.empty
WORD	QUITNOW\u00A0	14074000	0	false	Optional.empty
WORD	CLEARLOGNOW	14074000	0	false	Optional[AppAction[action=WIPE_LOG_NOW]]
WORD	clearlognow	14074000	0	false	Optional[AppAction[action=WIPE_LOG_NOW]]
WORD	 CLEARLOGNOW 	14074000	0	false	Optional[AppAction[action=WIPE_LOG_NOW]]
WORD	CLEARLOGNOW X	14074000	0	false	Optional.empty
WORD	clearlognow  k1abc  extra	14074000	0	false	Optional.empty
WORD	CLEARLOGNOWX	14074000	0	false	Optional.empty
WORD	CLEARLOGNOW\u00A0	14074000	0	false	Optional.empty
WORD	CLOSE	14074000	0	false	Optional[AppAction[action=CLOSE_CONTEST]]
WORD	close	14074000	0	false	Optional[AppAction[action=CLOSE_CONTEST]]
WORD	 CLOSE 	14074000	0	false	Optional[AppAction[action=CLOSE_CONTEST]]
WORD	CLOSE X	14074000	0	false	Optional.empty
WORD	close  k1abc  extra	14074000	0	false	Optional.empty
WORD	CLOSEX	14074000	0	false	Optional.empty
WORD	CLOSE\u00A0	14074000	0	false	Optional.empty
WORD	NEW	14074000	0	false	Optional[AppAction[action=NEW_CONTEST]]
WORD	new	14074000	0	false	Optional[AppAction[action=NEW_CONTEST]]
WORD	 NEW 	14074000	0	false	Optional[AppAction[action=NEW_CONTEST]]
WORD	NEW X	14074000	0	false	Optional.empty
WORD	new  k1abc  extra	14074000	0	false	Optional.empty
WORD	NEWX	14074000	0	false	Optional.empty
WORD	NEW\u00A0	14074000	0	false	Optional.empty
WORD	OPEN	14074000	0	false	Optional[AppAction[action=OPEN_CONTEST]]
WORD	open	14074000	0	false	Optional[AppAction[action=OPEN_CONTEST]]
WORD	 OPEN 	14074000	0	false	Optional[AppAction[action=OPEN_CONTEST]]
WORD	OPEN X	14074000	0	false	Optional.empty
WORD	open  k1abc  extra	14074000	0	false	Optional.empty
WORD	OPENX	14074000	0	false	Optional.empty
WORD	OPEN\u00A0	14074000	0	false	Optional.empty
WORD	COPYLOG	14074000	0	false	Optional[AppAction[action=COPY_LOG]]
WORD	copylog	14074000	0	false	Optional[AppAction[action=COPY_LOG]]
WORD	 COPYLOG 	14074000	0	false	Optional[AppAction[action=COPY_LOG]]
WORD	COPYLOG X	14074000	0	false	Optional.empty
WORD	copylog  k1abc  extra	14074000	0	false	Optional.empty
WORD	COPYLOGX	14074000	0	false	Optional.empty
WORD	COPYLOG\u00A0	14074000	0	false	Optional.empty
WORD	RELOAD	14074000	0	false	Optional[AppAction[action=RELOAD]]
WORD	reload	14074000	0	false	Optional[AppAction[action=RELOAD]]
WORD	 RELOAD 	14074000	0	false	Optional[AppAction[action=RELOAD]]
WORD	RELOAD X	14074000	0	false	Optional.empty
WORD	reload  k1abc  extra	14074000	0	false	Optional.empty
WORD	RELOADX	14074000	0	false	Optional.empty
WORD	RELOAD\u00A0	14074000	0	false	Optional.empty
WORD	RELOADNOW	14074000	0	false	Optional[AppAction[action=RELOAD]]
WORD	reloadnow	14074000	0	false	Optional[AppAction[action=RELOAD]]
WORD	 RELOADNOW 	14074000	0	false	Optional[AppAction[action=RELOAD]]
WORD	RELOADNOW X	14074000	0	false	Optional.empty
WORD	reloadnow  k1abc  extra	14074000	0	false	Optional.empty
WORD	RELOADNOWX	14074000	0	false	Optional.empty
WORD	RELOADNOW\u00A0	14074000	0	false	Optional.empty
WORD	REOPEN	14074000	0	false	Optional[AppAction[action=REOPEN]]
WORD	reopen	14074000	0	false	Optional[AppAction[action=REOPEN]]
WORD	 REOPEN 	14074000	0	false	Optional[AppAction[action=REOPEN]]
WORD	REOPEN X	14074000	0	false	Optional.empty
WORD	reopen  k1abc  extra	14074000	0	false	Optional.empty
WORD	REOPENX	14074000	0	false	Optional.empty
WORD	REOPEN\u00A0	14074000	0	false	Optional.empty
WORD	REOPENNOW	14074000	0	false	Optional[AppAction[action=REOPEN]]
WORD	reopennow	14074000	0	false	Optional[AppAction[action=REOPEN]]
WORD	 REOPENNOW 	14074000	0	false	Optional[AppAction[action=REOPEN]]
WORD	REOPENNOW X	14074000	0	false	Optional.empty
WORD	reopennow  k1abc  extra	14074000	0	false	Optional.empty
WORD	REOPENNOWX	14074000	0	false	Optional.empty
WORD	REOPENNOW\u00A0	14074000	0	false	Optional.empty
WORD	DEBUGCAT	14074000	0	false	Optional[AppAction[action=DEBUG_CAT]]
WORD	debugcat	14074000	0	false	Optional[AppAction[action=DEBUG_CAT]]
WORD	 DEBUGCAT 	14074000	0	false	Optional[AppAction[action=DEBUG_CAT]]
WORD	DEBUGCAT X	14074000	0	false	Optional.empty
WORD	debugcat  k1abc  extra	14074000	0	false	Optional.empty
WORD	DEBUGCATX	14074000	0	false	Optional.empty
WORD	DEBUGCAT\u00A0	14074000	0	false	Optional.empty
WORD	RESET	14074000	0	false	Optional[AppAction[action=RESET_INTERFACES]]
WORD	reset	14074000	0	false	Optional[AppAction[action=RESET_INTERFACES]]
WORD	 RESET 	14074000	0	false	Optional[AppAction[action=RESET_INTERFACES]]
WORD	RESET X	14074000	0	false	Optional.empty
WORD	reset  k1abc  extra	14074000	0	false	Optional.empty
WORD	RESETX	14074000	0	false	Optional.empty
WORD	RESET\u00A0	14074000	0	false	Optional.empty
WORD	BEACONS	14074000	0	false	Optional[AppAction[action=LOAD_BEACONS]]
WORD	beacons	14074000	0	false	Optional[AppAction[action=LOAD_BEACONS]]
WORD	 BEACONS 	14074000	0	false	Optional[AppAction[action=LOAD_BEACONS]]
WORD	BEACONS X	14074000	0	false	Optional.empty
WORD	beacons  k1abc  extra	14074000	0	false	Optional.empty
WORD	BEACONSX	14074000	0	false	Optional.empty
WORD	BEACONS\u00A0	14074000	0	false	Optional.empty
WORD	OPOFF	14074000	0	false	Optional[AppAction[action=LOGOUT]]
WORD	opoff	14074000	0	false	Optional[AppAction[action=LOGOUT]]
WORD	 OPOFF 	14074000	0	false	Optional[AppAction[action=LOGOUT]]
WORD	OPOFF X	14074000	0	false	Optional.empty
WORD	opoff  k1abc  extra	14074000	0	false	Optional.empty
WORD	OPOFFX	14074000	0	false	Optional.empty
WORD	OPOFF\u00A0	14074000	0	false	Optional.empty
WORD	LOGOUT	14074000	0	false	Optional[AppAction[action=LOGOUT]]
WORD	logout	14074000	0	false	Optional[AppAction[action=LOGOUT]]
WORD	 LOGOUT 	14074000	0	false	Optional[AppAction[action=LOGOUT]]
WORD	LOGOUT X	14074000	0	false	Optional.empty
WORD	logout  k1abc  extra	14074000	0	false	Optional.empty
WORD	LOGOUTX	14074000	0	false	Optional.empty
WORD	LOGOUT\u00A0	14074000	0	false	Optional.empty
WORD	RPT	14074000	0	false	Optional[Toggle[setting=CQ_REPEAT, on=true]]
WORD	rpt	14074000	0	false	Optional[Toggle[setting=CQ_REPEAT, on=true]]
WORD	 RPT 	14074000	0	false	Optional[Toggle[setting=CQ_REPEAT, on=true]]
WORD	RPT X	14074000	0	false	Optional.empty
WORD	rpt  k1abc  extra	14074000	0	false	Optional.empty
WORD	RPTX	14074000	0	false	Optional.empty
WORD	RPT\u00A0	14074000	0	false	Optional.empty
WORD	NORPT	14074000	0	false	Optional[Toggle[setting=CQ_REPEAT, on=false]]
WORD	norpt	14074000	0	false	Optional[Toggle[setting=CQ_REPEAT, on=false]]
WORD	 NORPT 	14074000	0	false	Optional[Toggle[setting=CQ_REPEAT, on=false]]
WORD	NORPT X	14074000	0	false	Optional.empty
WORD	norpt  k1abc  extra	14074000	0	false	Optional.empty
WORD	NORPTX	14074000	0	false	Optional.empty
WORD	NORPT\u00A0	14074000	0	false	Optional.empty
WORD	WORKDUPE	14074000	0	false	Optional[Toggle[setting=WORK_DUPES, on=true]]
WORD	workdupe	14074000	0	false	Optional[Toggle[setting=WORK_DUPES, on=true]]
WORD	 WORKDUPE 	14074000	0	false	Optional[Toggle[setting=WORK_DUPES, on=true]]
WORD	WORKDUPE X	14074000	0	false	Optional.empty
WORD	workdupe  k1abc  extra	14074000	0	false	Optional.empty
WORD	WORKDUPEX	14074000	0	false	Optional.empty
WORD	WORKDUPE\u00A0	14074000	0	false	Optional.empty
WORD	WORKDUPEON	14074000	0	false	Optional[Toggle[setting=WORK_DUPES, on=true]]
WORD	workdupeon	14074000	0	false	Optional[Toggle[setting=WORK_DUPES, on=true]]
WORD	 WORKDUPEON 	14074000	0	false	Optional[Toggle[setting=WORK_DUPES, on=true]]
WORD	WORKDUPEON X	14074000	0	false	Optional.empty
WORD	workdupeon  k1abc  extra	14074000	0	false	Optional.empty
WORD	WORKDUPEONX	14074000	0	false	Optional.empty
WORD	WORKDUPEON\u00A0	14074000	0	false	Optional.empty
WORD	NOWORKDUPE	14074000	0	false	Optional[Toggle[setting=WORK_DUPES, on=false]]
WORD	noworkdupe	14074000	0	false	Optional[Toggle[setting=WORK_DUPES, on=false]]
WORD	 NOWORKDUPE 	14074000	0	false	Optional[Toggle[setting=WORK_DUPES, on=false]]
WORD	NOWORKDUPE X	14074000	0	false	Optional.empty
WORD	noworkdupe  k1abc  extra	14074000	0	false	Optional.empty
WORD	NOWORKDUPEX	14074000	0	false	Optional.empty
WORD	NOWORKDUPE\u00A0	14074000	0	false	Optional.empty
WORD	WORKDUPEOFF	14074000	0	false	Optional[Toggle[setting=WORK_DUPES, on=false]]
WORD	workdupeoff	14074000	0	false	Optional[Toggle[setting=WORK_DUPES, on=false]]
WORD	 WORKDUPEOFF 	14074000	0	false	Optional[Toggle[setting=WORK_DUPES, on=false]]
WORD	WORKDUPEOFF X	14074000	0	false	Optional.empty
WORD	workdupeoff  k1abc  extra	14074000	0	false	Optional.empty
WORD	WORKDUPEOFFX	14074000	0	false	Optional.empty
WORD	WORKDUPEOFF\u00A0	14074000	0	false	Optional.empty
WORD	POSTCONTEST	14074000	0	false	Optional[Toggle[setting=POST_CONTEST, on=true]]
WORD	postcontest	14074000	0	false	Optional[Toggle[setting=POST_CONTEST, on=true]]
WORD	 POSTCONTEST 	14074000	0	false	Optional[Toggle[setting=POST_CONTEST, on=true]]
WORD	POSTCONTEST X	14074000	0	false	Optional.empty
WORD	postcontest  k1abc  extra	14074000	0	false	Optional.empty
WORD	POSTCONTESTX	14074000	0	false	Optional.empty
WORD	POSTCONTEST\u00A0	14074000	0	false	Optional.empty
WORD	NOPOSTCONTEST	14074000	0	false	Optional[Toggle[setting=POST_CONTEST, on=false]]
WORD	nopostcontest	14074000	0	false	Optional[Toggle[setting=POST_CONTEST, on=false]]
WORD	 NOPOSTCONTEST 	14074000	0	false	Optional[Toggle[setting=POST_CONTEST, on=false]]
WORD	NOPOSTCONTEST X	14074000	0	false	Optional.empty
WORD	nopostcontest  k1abc  extra	14074000	0	false	Optional.empty
WORD	NOPOSTCONTESTX	14074000	0	false	Optional.empty
WORD	NOPOSTCONTEST\u00A0	14074000	0	false	Optional.empty
WORD	AUTORELOAD	14074000	0	false	Optional[Toggle[setting=AUTO_RELOAD, on=true]]
WORD	autoreload	14074000	0	false	Optional[Toggle[setting=AUTO_RELOAD, on=true]]
WORD	 AUTORELOAD 	14074000	0	false	Optional[Toggle[setting=AUTO_RELOAD, on=true]]
WORD	AUTORELOAD X	14074000	0	false	Optional.empty
WORD	autoreload  k1abc  extra	14074000	0	false	Optional.empty
WORD	AUTORELOADX	14074000	0	false	Optional.empty
WORD	AUTORELOAD\u00A0	14074000	0	false	Optional.empty
WORD	NOAUTORELOAD	14074000	0	false	Optional[Toggle[setting=AUTO_RELOAD, on=false]]
WORD	noautoreload	14074000	0	false	Optional[Toggle[setting=AUTO_RELOAD, on=false]]
WORD	 NOAUTORELOAD 	14074000	0	false	Optional[Toggle[setting=AUTO_RELOAD, on=false]]
WORD	NOAUTORELOAD X	14074000	0	false	Optional.empty
WORD	noautoreload  k1abc  extra	14074000	0	false	Optional.empty
WORD	NOAUTORELOADX	14074000	0	false	Optional.empty
WORD	NOAUTORELOAD\u00A0	14074000	0	false	Optional.empty
WORD	RUNSP	14074000	0	false	Optional[AutoRunSp[enabled=true]]
WORD	runsp	14074000	0	false	Optional[AutoRunSp[enabled=true]]
WORD	 RUNSP 	14074000	0	false	Optional[AutoRunSp[enabled=true]]
WORD	RUNSP X	14074000	0	false	Optional.empty
WORD	runsp  k1abc  extra	14074000	0	false	Optional.empty
WORD	RUNSPX	14074000	0	false	Optional.empty
WORD	RUNSP\u00A0	14074000	0	false	Optional.empty
WORD	RUNSPON	14074000	0	false	Optional[AutoRunSp[enabled=true]]
WORD	runspon	14074000	0	false	Optional[AutoRunSp[enabled=true]]
WORD	 RUNSPON 	14074000	0	false	Optional[AutoRunSp[enabled=true]]
WORD	RUNSPON X	14074000	0	false	Optional.empty
WORD	runspon  k1abc  extra	14074000	0	false	Optional.empty
WORD	RUNSPONX	14074000	0	false	Optional.empty
WORD	RUNSPON\u00A0	14074000	0	false	Optional.empty
WORD	NORUNSP	14074000	0	false	Optional[AutoRunSp[enabled=false]]
WORD	norunsp	14074000	0	false	Optional[AutoRunSp[enabled=false]]
WORD	 NORUNSP 	14074000	0	false	Optional[AutoRunSp[enabled=false]]
WORD	NORUNSP X	14074000	0	false	Optional.empty
WORD	norunsp  k1abc  extra	14074000	0	false	Optional.empty
WORD	NORUNSPX	14074000	0	false	Optional.empty
WORD	NORUNSP\u00A0	14074000	0	false	Optional.empty
WORD	RUNSPOFF	14074000	0	false	Optional[AutoRunSp[enabled=false]]
WORD	runspoff	14074000	0	false	Optional[AutoRunSp[enabled=false]]
WORD	 RUNSPOFF 	14074000	0	false	Optional[AutoRunSp[enabled=false]]
WORD	RUNSPOFF X	14074000	0	false	Optional.empty
WORD	runspoff  k1abc  extra	14074000	0	false	Optional.empty
WORD	RUNSPOFFX	14074000	0	false	Optional.empty
WORD	RUNSPOFF\u00A0	14074000	0	false	Optional.empty
WORD	FULLABBREV	14074000	0	false	Optional[CutNumbers[style=TAUEDN]]
WORD	fullabbrev	14074000	0	false	Optional[CutNumbers[style=TAUEDN]]
WORD	 FULLABBREV 	14074000	0	false	Optional[CutNumbers[style=TAUEDN]]
WORD	FULLABBREV X	14074000	0	false	Optional.empty
WORD	fullabbrev  k1abc  extra	14074000	0	false	Optional.empty
WORD	FULLABBREVX	14074000	0	false	Optional.empty
WORD	FULLABBREV\u00A0	14074000	0	false	Optional.empty
WORD	PROABBREV	14074000	0	false	Optional[CutNumbers[style=TN]]
WORD	proabbrev	14074000	0	false	Optional[CutNumbers[style=TN]]
WORD	 PROABBREV 	14074000	0	false	Optional[CutNumbers[style=TN]]
WORD	PROABBREV X	14074000	0	false	Optional.empty
WORD	proabbrev  k1abc  extra	14074000	0	false	Optional.empty
WORD	PROABBREVX	14074000	0	false	Optional.empty
WORD	PROABBREV\u00A0	14074000	0	false	Optional.empty
WORD	SEMIABBREV	14074000	0	false	Optional[CutNumbers[style=ALL_T]]
WORD	semiabbrev	14074000	0	false	Optional[CutNumbers[style=ALL_T]]
WORD	 SEMIABBREV 	14074000	0	false	Optional[CutNumbers[style=ALL_T]]
WORD	SEMIABBREV X	14074000	0	false	Optional.empty
WORD	semiabbrev  k1abc  extra	14074000	0	false	Optional.empty
WORD	SEMIABBREVX	14074000	0	false	Optional.empty
WORD	SEMIABBREV\u00A0	14074000	0	false	Optional.empty
WORD	NOABBREV	14074000	0	false	Optional[CutNumbers[style=null]]
WORD	noabbrev	14074000	0	false	Optional[CutNumbers[style=null]]
WORD	 NOABBREV 	14074000	0	false	Optional[CutNumbers[style=null]]
WORD	NOABBREV X	14074000	0	false	Optional.empty
WORD	noabbrev  k1abc  extra	14074000	0	false	Optional.empty
WORD	NOABBREVX	14074000	0	false	Optional.empty
WORD	NOABBREV\u00A0	14074000	0	false	Optional.empty
WORD	MSGS	14074000	0	false	Optional[OpenSettingsTab[tabKey=function-keys]]
WORD	msgs	14074000	0	false	Optional[OpenSettingsTab[tabKey=function-keys]]
WORD	 MSGS 	14074000	0	false	Optional[OpenSettingsTab[tabKey=function-keys]]
WORD	MSGS X	14074000	0	false	Optional.empty
WORD	msgs  k1abc  extra	14074000	0	false	Optional.empty
WORD	MSGSX	14074000	0	false	Optional.empty
WORD	MSGS\u00A0	14074000	0	false	Optional.empty
WORD	MESSAGES	14074000	0	false	Optional[OpenSettingsTab[tabKey=function-keys]]
WORD	messages	14074000	0	false	Optional[OpenSettingsTab[tabKey=function-keys]]
WORD	 MESSAGES 	14074000	0	false	Optional[OpenSettingsTab[tabKey=function-keys]]
WORD	MESSAGES X	14074000	0	false	Optional.empty
WORD	messages  k1abc  extra	14074000	0	false	Optional.empty
WORD	MESSAGESX	14074000	0	false	Optional.empty
WORD	MESSAGES\u00A0	14074000	0	false	Optional.empty
WORD	AMSGS	14074000	0	false	Optional[OpenSettingsTab[tabKey=function-keys]]
WORD	amsgs	14074000	0	false	Optional[OpenSettingsTab[tabKey=function-keys]]
WORD	 AMSGS 	14074000	0	false	Optional[OpenSettingsTab[tabKey=function-keys]]
WORD	AMSGS X	14074000	0	false	Optional.empty
WORD	amsgs  k1abc  extra	14074000	0	false	Optional.empty
WORD	AMSGSX	14074000	0	false	Optional.empty
WORD	AMSGS\u00A0	14074000	0	false	Optional.empty
WORD	AMESSAGES	14074000	0	false	Optional[OpenSettingsTab[tabKey=function-keys]]
WORD	amessages	14074000	0	false	Optional[OpenSettingsTab[tabKey=function-keys]]
WORD	 AMESSAGES 	14074000	0	false	Optional[OpenSettingsTab[tabKey=function-keys]]
WORD	AMESSAGES X	14074000	0	false	Optional.empty
WORD	amessages  k1abc  extra	14074000	0	false	Optional.empty
WORD	AMESSAGESX	14074000	0	false	Optional.empty
WORD	AMESSAGES\u00A0	14074000	0	false	Optional.empty
WORD	WKEY	14074000	0	false	Optional[OpenSettingsTab[tabKey=winkey]]
WORD	 WKEY 	14074000	0	false	Optional[OpenSettingsTab[tabKey=winkey]]
WORD	WKEY X	14074000	0	false	Optional.empty
WORD	wkey  k1abc  extra	14074000	0	false	Optional.empty
WORD	WKEYX	14074000	0	false	Optional.empty
WORD	WKEY\u00A0	14074000	0	false	Optional.empty
WORD	WKSETUP	14074000	0	false	Optional[OpenSettingsTab[tabKey=winkey]]
WORD	wksetup	14074000	0	false	Optional[OpenSettingsTab[tabKey=winkey]]
WORD	 WKSETUP 	14074000	0	false	Optional[OpenSettingsTab[tabKey=winkey]]
WORD	WKSETUP X	14074000	0	false	Optional.empty
WORD	wksetup  k1abc  extra	14074000	0	false	Optional.empty
WORD	WKSETUPX	14074000	0	false	Optional.empty
WORD	WKSETUP\u00A0	14074000	0	false	Optional.empty
WORD	NETCONFIG	14074000	0	false	Optional[OpenSettingsTab[tabKey=cluster]]
WORD	netconfig	14074000	0	false	Optional[OpenSettingsTab[tabKey=cluster]]
WORD	 NETCONFIG 	14074000	0	false	Optional[OpenSettingsTab[tabKey=cluster]]
WORD	NETCONFIG X	14074000	0	false	Optional.empty
WORD	netconfig  k1abc  extra	14074000	0	false	Optional.empty
WORD	NETCONFIGX	14074000	0	false	Optional.empty
WORD	NETCONFIG\u00A0	14074000	0	false	Optional.empty
WORD	notour	14074000	0	false	Optional[TourOff[]]
WORD	 NOTOUR 	14074000	0	false	Optional[TourOff[]]
WORD	NOTOUR X	14074000	0	false	Optional.empty
WORD	notour  k1abc  extra	14074000	0	false	Optional.empty
WORD	NOTOURX	14074000	0	false	Optional.empty
WORD	NOTOUR\u00A0	14074000	0	false	Optional.empty
WORD	TOUROFF	14074000	0	false	Optional[TourOff[]]
WORD	touroff	14074000	0	false	Optional[TourOff[]]
WORD	 TOUROFF 	14074000	0	false	Optional[TourOff[]]
WORD	TOUROFF X	14074000	0	false	Optional.empty
WORD	touroff  k1abc  extra	14074000	0	false	Optional.empty
WORD	TOUROFFX	14074000	0	false	Optional.empty
WORD	TOUROFF\u00A0	14074000	0	false	Optional.empty
WORD	nocountyline	14074000	0	false	Optional[CountyLineOff[]]
WORD	 NOCOUNTYLINE 	14074000	0	false	Optional[CountyLineOff[]]
WORD	NOCOUNTYLINE X	14074000	0	false	Optional.empty
WORD	nocountyline  k1abc  extra	14074000	0	false	Optional.empty
WORD	NOCOUNTYLINEX	14074000	0	false	Optional.empty
WORD	NOCOUNTYLINE\u00A0	14074000	0	false	Optional.empty
WORD	SPLIT	14074000	0	false	Optional[Split[txFreqHz=0]]
WORD	split	14074000	0	false	Optional[Split[txFreqHz=0]]
WORD	 SPLIT 	14074000	0	false	Optional[Split[txFreqHz=0]]
WORD	SPLIT X	14074000	0	false	Optional.empty
WORD	split  k1abc  extra	14074000	0	false	Optional.empty
WORD	SPLITX	14074000	0	false	Optional.empty
WORD	SPLIT\u00A0	14074000	0	false	Optional.empty
WORD	NOSPLIT	14074000	0	false	Optional[SplitOff[]]
WORD	nosplit	14074000	0	false	Optional[SplitOff[]]
WORD	 NOSPLIT 	14074000	0	false	Optional[SplitOff[]]
WORD	NOSPLIT X	14074000	0	false	Optional.empty
WORD	nosplit  k1abc  extra	14074000	0	false	Optional.empty
WORD	NOSPLITX	14074000	0	false	Optional.empty
WORD	NOSPLIT\u00A0	14074000	0	false	Optional.empty
WORD	SPLITOFF	14074000	0	false	Optional[SplitOff[]]
WORD	splitoff	14074000	0	false	Optional[SplitOff[]]
WORD	 SPLITOFF 	14074000	0	false	Optional[SplitOff[]]
WORD	SPLITOFF X	14074000	0	false	Optional.empty
WORD	splitoff  k1abc  extra	14074000	0	false	Optional.empty
WORD	SPLITOFFX	14074000	0	false	Optional.empty
WORD	SPLITOFF\u00A0	14074000	0	false	Optional.empty
WORD	SWAP	14074000	0	false	Optional[SwapVfo[]]
WORD	swap	14074000	0	false	Optional[SwapVfo[]]
WORD	 SWAP 	14074000	0	false	Optional[SwapVfo[]]
WORD	SWAP X	14074000	0	false	Optional.empty
WORD	swap  k1abc  extra	14074000	0	false	Optional.empty
WORD	SWAPX	14074000	0	false	Optional.empty
WORD	SWAP\u00A0	14074000	0	false	Optional.empty
WORD	NORIT	14074000	0	false	Optional[Rit[offsetHz=0]]
WORD	norit	14074000	0	false	Optional[Rit[offsetHz=0]]
WORD	 NORIT 	14074000	0	false	Optional[Rit[offsetHz=0]]
WORD	NORIT X	14074000	0	false	Optional.empty
WORD	norit  k1abc  extra	14074000	0	false	Optional.empty
WORD	NORITX	14074000	0	false	Optional.empty
WORD	NORIT\u00A0	14074000	0	false	Optional.empty
WORD	RITOFF	14074000	0	false	Optional[Rit[offsetHz=0]]
WORD	ritoff	14074000	0	false	Optional[Rit[offsetHz=0]]
WORD	 RITOFF 	14074000	0	false	Optional[Rit[offsetHz=0]]
WORD	RITOFF X	14074000	0	false	Optional.empty
WORD	ritoff  k1abc  extra	14074000	0	false	Optional.empty
WORD	RITOFFX	14074000	0	false	Optional.empty
WORD	RITOFF\u00A0	14074000	0	false	Optional.empty
WORD	RITCLEAR	14074000	0	false	Optional[Rit[offsetHz=0]]
WORD	ritclear	14074000	0	false	Optional[Rit[offsetHz=0]]
WORD	 RITCLEAR 	14074000	0	false	Optional[Rit[offsetHz=0]]
WORD	RITCLEAR X	14074000	0	false	Optional.empty
WORD	ritclear  k1abc  extra	14074000	0	false	Optional.empty
WORD	RITCLEARX	14074000	0	false	Optional.empty
WORD	RITCLEAR\u00A0	14074000	0	false	Optional.empty
WORD	CLEARRIT	14074000	0	false	Optional[Rit[offsetHz=0]]
WORD	clearrit	14074000	0	false	Optional[Rit[offsetHz=0]]
WORD	 CLEARRIT 	14074000	0	false	Optional[Rit[offsetHz=0]]
WORD	CLEARRIT X	14074000	0	false	Optional.empty
WORD	clearrit  k1abc  extra	14074000	0	false	Optional.empty
WORD	CLEARRITX	14074000	0	false	Optional.empty
WORD	CLEARRIT\u00A0	14074000	0	false	Optional.empty
WORD	SETUP	14074000	0	false	Optional[OpenSetup[]]
WORD	setup	14074000	0	false	Optional[OpenSetup[]]
WORD	 SETUP 	14074000	0	false	Optional[OpenSetup[]]
WORD	SETUP X	14074000	0	false	Optional.empty
WORD	setup  k1abc  extra	14074000	0	false	Optional.empty
WORD	SETUPX	14074000	0	false	Optional.empty
WORD	SETUP\u00A0	14074000	0	false	Optional.empty
WORD	NETON	14074000	0	false	Optional[NetworkOn[]]
WORD	neton	14074000	0	false	Optional[NetworkOn[]]
WORD	 NETON 	14074000	0	false	Optional[NetworkOn[]]
WORD	NETON X	14074000	0	false	Optional.empty
WORD	neton  k1abc  extra	14074000	0	false	Optional.empty
WORD	NETONX	14074000	0	false	Optional.empty
WORD	NETON\u00A0	14074000	0	false	Optional.empty
WORD	NET	14074000	0	false	Optional[NetworkOn[]]
WORD	net	14074000	0	false	Optional[NetworkOn[]]
WORD	 NET 	14074000	0	false	Optional[NetworkOn[]]
WORD	NET X	14074000	0	false	Optional.empty
WORD	net  k1abc  extra	14074000	0	false	Optional.empty
WORD	NETX	14074000	0	false	Optional.empty
WORD	NET\u00A0	14074000	0	false	Optional.empty
WORD	NETOFF	14074000	0	false	Optional[NetworkOff[]]
WORD	netoff	14074000	0	false	Optional[NetworkOff[]]
WORD	 NETOFF 	14074000	0	false	Optional[NetworkOff[]]
WORD	NETOFF X	14074000	0	false	Optional.empty
WORD	netoff  k1abc  extra	14074000	0	false	Optional.empty
WORD	NETOFFX	14074000	0	false	Optional.empty
WORD	NETOFF\u00A0	14074000	0	false	Optional.empty
WORD	NONET	14074000	0	false	Optional[NetworkOff[]]
WORD	nonet	14074000	0	false	Optional[NetworkOff[]]
WORD	 NONET 	14074000	0	false	Optional[NetworkOff[]]
WORD	NONET X	14074000	0	false	Optional.empty
WORD	nonet  k1abc  extra	14074000	0	false	Optional.empty
WORD	NONETX	14074000	0	false	Optional.empty
WORD	NONET\u00A0	14074000	0	false	Optional.empty
WORD	CW	14074000	0	false	Optional[ChangeMode[mode=CW]]
WORD	CW X	14074000	0	false	Optional.empty
WORD	cw  k1abc  extra	14074000	0	false	Optional.empty
WORD	CWX	14074000	0	false	Optional.empty
WORD	SSB	14074000	0	false	Optional[ChangeMode[mode=SSB]]
WORD	ssb	14074000	0	false	Optional[ChangeMode[mode=SSB]]
WORD	 SSB 	14074000	0	false	Optional[ChangeMode[mode=SSB]]
WORD	SSB X	14074000	0	false	Optional.empty
WORD	ssb  k1abc  extra	14074000	0	false	Optional.empty
WORD	SSBX	14074000	0	false	Optional.empty
WORD	SSB\u00A0	14074000	0	false	Optional.empty
WORD	USB	14074000	0	false	Optional[ChangeMode[mode=SSB]]
WORD	usb	14074000	0	false	Optional[ChangeMode[mode=SSB]]
WORD	 USB 	14074000	0	false	Optional[ChangeMode[mode=SSB]]
WORD	USB X	14074000	0	false	Optional.empty
WORD	usb  k1abc  extra	14074000	0	false	Optional.empty
WORD	USBX	14074000	0	false	Optional.empty
WORD	USB\u00A0	14074000	0	false	Optional.empty
WORD	LSB	14074000	0	false	Optional[ChangeMode[mode=SSB]]
WORD	lsb	14074000	0	false	Optional[ChangeMode[mode=SSB]]
WORD	 LSB 	14074000	0	false	Optional[ChangeMode[mode=SSB]]
WORD	LSB X	14074000	0	false	Optional.empty
WORD	lsb  k1abc  extra	14074000	0	false	Optional.empty
WORD	LSBX	14074000	0	false	Optional.empty
WORD	LSB\u00A0	14074000	0	false	Optional.empty
WORD	AM	14074000	0	false	Optional[ChangeMode[mode=AM]]
WORD	am	14074000	0	false	Optional[ChangeMode[mode=AM]]
WORD	 AM 	14074000	0	false	Optional[ChangeMode[mode=AM]]
WORD	AM X	14074000	0	false	Optional.empty
WORD	am  k1abc  extra	14074000	0	false	Optional.empty
WORD	AMX	14074000	0	false	Optional.empty
WORD	AM\u00A0	14074000	0	false	Optional.empty
WORD	FM	14074000	0	false	Optional[ChangeMode[mode=FM]]
WORD	fm	14074000	0	false	Optional[ChangeMode[mode=FM]]
WORD	 FM 	14074000	0	false	Optional[ChangeMode[mode=FM]]
WORD	FM X	14074000	0	false	Optional.empty
WORD	fm  k1abc  extra	14074000	0	false	Optional.empty
WORD	FMX	14074000	0	false	Optional.empty
WORD	FM\u00A0	14074000	0	false	Optional.empty
WORD	RTTY	14074000	0	false	Optional[ChangeMode[mode=RTTY]]
WORD	rtty	14074000	0	false	Optional[ChangeMode[mode=RTTY]]
WORD	 RTTY 	14074000	0	false	Optional[ChangeMode[mode=RTTY]]
WORD	RTTY X	14074000	0	false	Optional.empty
WORD	rtty  k1abc  extra	14074000	0	false	Optional.empty
WORD	RTTYX	14074000	0	false	Optional.empty
WORD	RTTY\u00A0	14074000	0	false	Optional.empty
WORD	PSK	14074000	0	false	Optional[ChangeMode[mode=PSK]]
WORD	psk	14074000	0	false	Optional[ChangeMode[mode=PSK]]
WORD	 PSK 	14074000	0	false	Optional[ChangeMode[mode=PSK]]
WORD	PSK X	14074000	0	false	Optional.empty
WORD	psk  k1abc  extra	14074000	0	false	Optional.empty
WORD	PSKX	14074000	0	false	Optional.empty
WORD	PSK\u00A0	14074000	0	false	Optional.empty
WORD	PSK31	14074000	0	false	Optional[ChangeMode[mode=PSK]]
WORD	 PSK31 	14074000	0	false	Optional[ChangeMode[mode=PSK]]
WORD	PSK31 X	14074000	0	false	Optional.empty
WORD	psk31  k1abc  extra	14074000	0	false	Optional.empty
WORD	PSK31X	14074000	0	false	Optional.empty
WORD	PSK31\u00A0	14074000	0	false	Optional.empty
WORD	PSK63	14074000	0	false	Optional[ChangeMode[mode=PSK]]
WORD	psk63	14074000	0	false	Optional[ChangeMode[mode=PSK]]
WORD	 PSK63 	14074000	0	false	Optional[ChangeMode[mode=PSK]]
WORD	PSK63 X	14074000	0	false	Optional.empty
WORD	psk63  k1abc  extra	14074000	0	false	Optional.empty
WORD	PSK63X	14074000	0	false	Optional.empty
WORD	PSK63\u00A0	14074000	0	false	Optional.empty
WORD	PSK125	14074000	0	false	Optional[ChangeMode[mode=PSK]]
WORD	psk125	14074000	0	false	Optional[ChangeMode[mode=PSK]]
WORD	 PSK125 	14074000	0	false	Optional[ChangeMode[mode=PSK]]
WORD	PSK125 X	14074000	0	false	Optional.empty
WORD	psk125  k1abc  extra	14074000	0	false	Optional.empty
WORD	PSK125X	14074000	0	false	Optional.empty
WORD	PSK125\u00A0	14074000	0	false	Optional.empty
WORD	PSK250	14074000	0	false	Optional[ChangeMode[mode=PSK]]
WORD	psk250	14074000	0	false	Optional[ChangeMode[mode=PSK]]
WORD	 PSK250 	14074000	0	false	Optional[ChangeMode[mode=PSK]]
WORD	PSK250 X	14074000	0	false	Optional.empty
WORD	psk250  k1abc  extra	14074000	0	false	Optional.empty
WORD	PSK250X	14074000	0	false	Optional.empty
WORD	PSK250\u00A0	14074000	0	false	Optional.empty
WORD	FT8	14074000	0	false	Optional[ChangeMode[mode=FT8]]
WORD	 FT8 	14074000	0	false	Optional[ChangeMode[mode=FT8]]
WORD	FT8 X	14074000	0	false	Optional.empty
WORD	ft8  k1abc  extra	14074000	0	false	Optional.empty
WORD	FT8X	14074000	0	false	Optional.empty
WORD	FT8\u00A0	14074000	0	false	Optional.empty
WORD	FT4	14074000	0	false	Optional[ChangeMode[mode=FT4]]
WORD	ft4	14074000	0	false	Optional[ChangeMode[mode=FT4]]
WORD	 FT4 	14074000	0	false	Optional[ChangeMode[mode=FT4]]
WORD	FT4 X	14074000	0	false	Optional.empty
WORD	ft4  k1abc  extra	14074000	0	false	Optional.empty
WORD	FT4X	14074000	0	false	Optional.empty
WORD	FT4\u00A0	14074000	0	false	Optional.empty
WORD	JT65	14074000	0	false	Optional[ChangeMode[mode=JT65]]
WORD	jt65	14074000	0	false	Optional[ChangeMode[mode=JT65]]
WORD	 JT65 	14074000	0	false	Optional[ChangeMode[mode=JT65]]
WORD	JT65 X	14074000	0	false	Optional.empty
WORD	jt65  k1abc  extra	14074000	0	false	Optional.empty
WORD	JT65X	14074000	0	false	Optional.empty
WORD	JT65\u00A0	14074000	0	false	Optional.empty
WORD	DIGITAL	14074000	0	false	Optional[ChangeMode[mode=DIGITAL]]
WORD	digital	14074000	0	false	Optional[ChangeMode[mode=DIGITAL]]
WORD	 DIGITAL 	14074000	0	false	Optional[ChangeMode[mode=DIGITAL]]
WORD	DIGITAL X	14074000	0	false	Optional.empty
WORD	digital  k1abc  extra	14074000	0	false	Optional.empty
WORD	DIGITALX	14074000	0	false	Optional.empty
WORD	DIGITAL\u00A0	14074000	0	false	Optional.empty
WORD	DIGI	14074000	0	false	Optional[ChangeMode[mode=DIGITAL]]
WORD	digi	14074000	0	false	Optional[ChangeMode[mode=DIGITAL]]
WORD	 DIGI 	14074000	0	false	Optional[ChangeMode[mode=DIGITAL]]
WORD	DIGI X	14074000	0	false	Optional.empty
WORD	digi  k1abc  extra	14074000	0	false	Optional.empty
WORD	DIGIX	14074000	0	false	Optional.empty
WORD	DIGI\u00A0	14074000	0	false	Optional.empty
WORD	 OPON 	14074000	0	false	Optional[Login[operator=]]
WORD	OPON X	14074000	0	false	Optional[Login[operator=X]]
WORD	opon  k1abc  extra	14074000	0	false	Optional[Login[operator=K1ABC]]
WORD	OPON\u00A0	14074000	0	false	Optional.empty
WORD	login	14074000	0	false	Optional[Login[operator=]]
WORD	 LOGIN 	14074000	0	false	Optional[Login[operator=]]
WORD	LOGIN X	14074000	0	false	Optional[Login[operator=X]]
WORD	login  k1abc  extra	14074000	0	false	Optional[Login[operator=K1ABC]]
WORD	LOGIN\u00A0	14074000	0	false	Optional.empty
WORD	 TOUR 	14074000	0	false	Optional[SetTour[params=]]
WORD	TOUR X	14074000	0	false	Optional[SetTour[params=X]]
WORD	tour  k1abc  extra	14074000	0	false	Optional[SetTour[params=K1ABC  EXTRA]]
WORD	TOURX	14074000	0	false	Optional.empty
WORD	TOUR\u00A0	14074000	0	false	Optional.empty
WORD	bonus	14074000	0	false	Optional[BonusStations[calls=]]
WORD	 BONUS 	14074000	0	false	Optional[BonusStations[calls=]]
WORD	BONUS X	14074000	0	false	Optional[BonusStations[calls=X]]
WORD	bonus  k1abc  extra	14074000	0	false	Optional[BonusStations[calls=K1ABC  EXTRA]]
WORD	BONUS\u00A0	14074000	0	false	Optional.empty
WORD	roverqth	14074000	0	false	Optional[RoverQth[county=]]
WORD	 ROVERQTH 	14074000	0	false	Optional[RoverQth[county=]]
WORD	ROVERQTH X	14074000	0	false	Optional[RoverQth[county=X]]
WORD	roverqth  k1abc  extra	14074000	0	false	Optional[RoverQth[county=K1ABC  EXTRA]]
WORD	ROVERQTHX	14074000	0	false	Optional.empty
WORD	ROVERQTH\u00A0	14074000	0	false	Optional.empty
WORD	countyline	14074000	0	false	Optional[CountyLine[counties=]]
WORD	 COUNTYLINE 	14074000	0	false	Optional[CountyLine[counties=]]
WORD	COUNTYLINE X	14074000	0	false	Optional[CountyLine[counties=X]]
WORD	countyline  k1abc  extra	14074000	0	false	Optional[CountyLine[counties=K1ABC  EXTRA]]
WORD	COUNTYLINEX	14074000	0	false	Optional.empty
WORD	COUNTYLINE\u00A0	14074000	0	false	Optional.empty
WORD	spotme	14074000	0	false	Optional[SpotMe[comment=]]
WORD	 SPOTME 	14074000	0	false	Optional[SpotMe[comment=]]
WORD	SPOTME X	14074000	0	false	Optional[SpotMe[comment=X]]
WORD	spotme  k1abc  extra	14074000	0	false	Optional[SpotMe[comment=K1ABC  EXTRA]]
WORD	SPOTMEX	14074000	0	false	Optional.empty
WORD	SPOTME\u00A0	14074000	0	false	Optional.empty
WORD	rit	14074000	0	false	Optional[Invalid[message=RIT: zadej posun v Hz, nap\u0159. RIT 120 nebo RIT -50]]
WORD	 RIT 	14074000	0	false	Optional[Invalid[message=RIT: zadej posun v Hz, nap\u0159. RIT 120 nebo RIT -50]]
WORD	RIT X	14074000	0	false	Optional[Invalid[message=RIT: zadej posun v Hz, nap\u0159. RIT 120 nebo RIT -50]]
WORD	rit  k1abc  extra	14074000	0	false	Optional[Invalid[message=RIT: zadej posun v Hz, nap\u0159. RIT 120 nebo RIT -50]]
WORD	RIT\u00A0	14074000	0	false	Optional.empty
WORD	SCRIPT	14074000	0	false	Optional[Invalid[message=SCRIPT: zadej jm\u00E9no skriptu (soubor scripts/<jm\u00E9no>.txt)]]
WORD	 SCRIPT 	14074000	0	false	Optional[Invalid[message=SCRIPT: zadej jm\u00E9no skriptu (soubor scripts/<jm\u00E9no>.txt)]]
WORD	SCRIPT X	14074000	0	false	Optional[RunScript[name=X]]
WORD	script  k1abc  extra	14074000	0	false	Optional[RunScript[name=K1ABC  EXTRA]]
WORD	SCRIPTX	14074000	0	false	Optional.empty
WORD	SCRIPT\u00A0	14074000	0	false	Optional.empty
EDGE	0	1799999	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0	0	1799999	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	1799999	0	false	Optional[Invalid[message=Posun +0 kHz vede mimo p\u00E1smo]]
EDGE	+0	0	1799999	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	1799999	0	false	Optional[Invalid[message=Posun -0 kHz vede mimo p\u00E1smo]]
EDGE	-0	0	1799999	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	1799999	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	1	0	1799999	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	1799999	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	-1	0	1799999	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	1799999	0	false	Optional[Qsy[freqHz=1800999]]
EDGE	+1	0	1799999	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	1799999	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/0	0	1799999	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	1799999	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	0	1799999	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/+1	1799999	0	false	Optional[OtherVfo[freqHz=1800999]]
EDGE	/+1	0	1799999	true	Optional[OtherVfo[freqHz=1800999]]
EDGE	/-1	1799999	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	0	1799999	true	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	999	1799999	0	false	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	999	0	1799999	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	1799999	0	false	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	0	1799999	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	1799999	0	false	Optional[Invalid[message=Posun -0.0005 kHz vede mimo p\u00E1smo]]
EDGE	-0.0005	0	1799999	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	1800000	0	false	Optional[Qsy[freqHz=1800000]]
EDGE	0	0	1800000	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	1800000	0	false	Optional[Qsy[freqHz=1800000]]
EDGE	+0	0	1800000	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	1800000	0	false	Optional[Qsy[freqHz=1800000]]
EDGE	-0	0	1800000	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	1800000	0	false	Optional[Qsy[freqHz=1801000]]
EDGE	1	0	1800000	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	1800000	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	-1	0	1800000	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	1800000	0	false	Optional[Qsy[freqHz=1801000]]
EDGE	+1	0	1800000	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	1800000	0	false	Optional[OtherVfo[freqHz=1800000]]
EDGE	/0	0	1800000	true	Optional[OtherVfo[freqHz=1800000]]
EDGE	/1	1800000	0	false	Optional[OtherVfo[freqHz=1801000]]
EDGE	/1	0	1800000	true	Optional[OtherVfo[freqHz=1801000]]
EDGE	/+1	1800000	0	false	Optional[OtherVfo[freqHz=1801000]]
EDGE	/+1	0	1800000	true	Optional[OtherVfo[freqHz=1801000]]
EDGE	/-1	1800000	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	0	1800000	true	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	999	1800000	0	false	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	999	0	1800000	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	1800000	0	false	Optional[Qsy[freqHz=1800001]]
EDGE	0.0005	0	1800000	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	1800000	0	false	Optional[Invalid[message=Posun -0.0005 kHz vede mimo p\u00E1smo]]
EDGE	-0.0005	0	1800000	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	2000000	0	false	Optional[Qsy[freqHz=1800000]]
EDGE	0	0	2000000	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	2000000	0	false	Optional[Qsy[freqHz=2000000]]
EDGE	+0	0	2000000	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	2000000	0	false	Optional[Qsy[freqHz=2000000]]
EDGE	-0	0	2000000	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	2000000	0	false	Optional[Qsy[freqHz=1801000]]
EDGE	1	0	2000000	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	2000000	0	false	Optional[Qsy[freqHz=1999000]]
EDGE	-1	0	2000000	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	2000000	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	+1	0	2000000	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	2000000	0	false	Optional[OtherVfo[freqHz=1800000]]
EDGE	/0	0	2000000	true	Optional[OtherVfo[freqHz=1800000]]
EDGE	/1	2000000	0	false	Optional[OtherVfo[freqHz=1801000]]
EDGE	/1	0	2000000	true	Optional[OtherVfo[freqHz=1801000]]
EDGE	/+1	2000000	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/+1	0	2000000	true	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	2000000	0	false	Optional[OtherVfo[freqHz=1999000]]
EDGE	/-1	0	2000000	true	Optional[OtherVfo[freqHz=1999000]]
EDGE	999	2000000	0	false	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	999	0	2000000	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	2000000	0	false	Optional[Qsy[freqHz=1800001]]
EDGE	0.0005	0	2000000	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	2000000	0	false	Optional[Qsy[freqHz=1999999]]
EDGE	-0.0005	0	2000000	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	2000001	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0	0	2000001	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	2000001	0	false	Optional[Invalid[message=Posun +0 kHz vede mimo p\u00E1smo]]
EDGE	+0	0	2000001	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	2000001	0	false	Optional[Invalid[message=Posun -0 kHz vede mimo p\u00E1smo]]
EDGE	-0	0	2000001	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	2000001	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	1	0	2000001	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	2000001	0	false	Optional[Qsy[freqHz=1999001]]
EDGE	-1	0	2000001	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	2000001	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	+1	0	2000001	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	2000001	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/0	0	2000001	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	2000001	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	0	2000001	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/+1	2000001	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/+1	0	2000001	true	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	2000001	0	false	Optional[OtherVfo[freqHz=1999001]]
EDGE	/-1	0	2000001	true	Optional[OtherVfo[freqHz=1999001]]
EDGE	999	2000001	0	false	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	999	0	2000001	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	2000001	0	false	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	0	2000001	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	2000001	0	false	Optional[Qsy[freqHz=2000000]]
EDGE	-0.0005	0	2000001	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	3499999	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0	0	3499999	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	3499999	0	false	Optional[Invalid[message=Posun +0 kHz vede mimo p\u00E1smo]]
EDGE	+0	0	3499999	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	3499999	0	false	Optional[Invalid[message=Posun -0 kHz vede mimo p\u00E1smo]]
EDGE	-0	0	3499999	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	3499999	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	1	0	3499999	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	3499999	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	-1	0	3499999	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	3499999	0	false	Optional[Qsy[freqHz=3500999]]
EDGE	+1	0	3499999	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	3499999	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/0	0	3499999	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	3499999	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	0	3499999	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/+1	3499999	0	false	Optional[OtherVfo[freqHz=3500999]]
EDGE	/+1	0	3499999	true	Optional[OtherVfo[freqHz=3500999]]
EDGE	/-1	3499999	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	0	3499999	true	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	999	3499999	0	false	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	999	0	3499999	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	3499999	0	false	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	0	3499999	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	3499999	0	false	Optional[Invalid[message=Posun -0.0005 kHz vede mimo p\u00E1smo]]
EDGE	-0.0005	0	3499999	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	3500000	0	false	Optional[Qsy[freqHz=3500000]]
EDGE	0	0	3500000	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	3500000	0	false	Optional[Qsy[freqHz=3500000]]
EDGE	+0	0	3500000	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	3500000	0	false	Optional[Qsy[freqHz=3500000]]
EDGE	-0	0	3500000	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	3500000	0	false	Optional[Qsy[freqHz=3501000]]
EDGE	1	0	3500000	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	3500000	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	-1	0	3500000	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	3500000	0	false	Optional[Qsy[freqHz=3501000]]
EDGE	+1	0	3500000	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	3500000	0	false	Optional[OtherVfo[freqHz=3500000]]
EDGE	/0	0	3500000	true	Optional[OtherVfo[freqHz=3500000]]
EDGE	/1	3500000	0	false	Optional[OtherVfo[freqHz=3501000]]
EDGE	/1	0	3500000	true	Optional[OtherVfo[freqHz=3501000]]
EDGE	/+1	3500000	0	false	Optional[OtherVfo[freqHz=3501000]]
EDGE	/+1	0	3500000	true	Optional[OtherVfo[freqHz=3501000]]
EDGE	/-1	3500000	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	0	3500000	true	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	999	3500000	0	false	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	999	0	3500000	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	3500000	0	false	Optional[Qsy[freqHz=3500001]]
EDGE	0.0005	0	3500000	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	3500000	0	false	Optional[Invalid[message=Posun -0.0005 kHz vede mimo p\u00E1smo]]
EDGE	-0.0005	0	3500000	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	4000000	0	false	Optional[Qsy[freqHz=3500000]]
EDGE	0	0	4000000	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	4000000	0	false	Optional[Qsy[freqHz=4000000]]
EDGE	+0	0	4000000	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	4000000	0	false	Optional[Qsy[freqHz=4000000]]
EDGE	-0	0	4000000	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	4000000	0	false	Optional[Qsy[freqHz=3501000]]
EDGE	1	0	4000000	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	4000000	0	false	Optional[Qsy[freqHz=3999000]]
EDGE	-1	0	4000000	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	4000000	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	+1	0	4000000	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	4000000	0	false	Optional[OtherVfo[freqHz=3500000]]
EDGE	/0	0	4000000	true	Optional[OtherVfo[freqHz=3500000]]
EDGE	/1	4000000	0	false	Optional[OtherVfo[freqHz=3501000]]
EDGE	/1	0	4000000	true	Optional[OtherVfo[freqHz=3501000]]
EDGE	/+1	4000000	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/+1	0	4000000	true	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	4000000	0	false	Optional[OtherVfo[freqHz=3999000]]
EDGE	/-1	0	4000000	true	Optional[OtherVfo[freqHz=3999000]]
EDGE	999	4000000	0	false	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	999	0	4000000	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	4000000	0	false	Optional[Qsy[freqHz=3500001]]
EDGE	0.0005	0	4000000	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	4000000	0	false	Optional[Qsy[freqHz=3999999]]
EDGE	-0.0005	0	4000000	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	4000001	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0	0	4000001	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	4000001	0	false	Optional[Invalid[message=Posun +0 kHz vede mimo p\u00E1smo]]
EDGE	+0	0	4000001	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	4000001	0	false	Optional[Invalid[message=Posun -0 kHz vede mimo p\u00E1smo]]
EDGE	-0	0	4000001	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	4000001	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	1	0	4000001	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	4000001	0	false	Optional[Qsy[freqHz=3999001]]
EDGE	-1	0	4000001	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	4000001	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	+1	0	4000001	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	4000001	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/0	0	4000001	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	4000001	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	0	4000001	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/+1	4000001	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/+1	0	4000001	true	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	4000001	0	false	Optional[OtherVfo[freqHz=3999001]]
EDGE	/-1	0	4000001	true	Optional[OtherVfo[freqHz=3999001]]
EDGE	999	4000001	0	false	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	999	0	4000001	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	4000001	0	false	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	0	4000001	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	4000001	0	false	Optional[Qsy[freqHz=4000000]]
EDGE	-0.0005	0	4000001	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	5329999	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0	0	5329999	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	5329999	0	false	Optional[Invalid[message=Posun +0 kHz vede mimo p\u00E1smo]]
EDGE	+0	0	5329999	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	5329999	0	false	Optional[Invalid[message=Posun -0 kHz vede mimo p\u00E1smo]]
EDGE	-0	0	5329999	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	5329999	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	1	0	5329999	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	5329999	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	-1	0	5329999	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	5329999	0	false	Optional[Qsy[freqHz=5330999]]
EDGE	+1	0	5329999	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	5329999	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/0	0	5329999	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	5329999	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	0	5329999	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/+1	5329999	0	false	Optional[OtherVfo[freqHz=5330999]]
EDGE	/+1	0	5329999	true	Optional[OtherVfo[freqHz=5330999]]
EDGE	/-1	5329999	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	0	5329999	true	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	999	5329999	0	false	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	999	0	5329999	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	5329999	0	false	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	0	5329999	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	5329999	0	false	Optional[Invalid[message=Posun -0.0005 kHz vede mimo p\u00E1smo]]
EDGE	-0.0005	0	5329999	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	5330000	0	false	Optional[Qsy[freqHz=5330000]]
EDGE	0	0	5330000	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	5330000	0	false	Optional[Qsy[freqHz=5330000]]
EDGE	+0	0	5330000	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	5330000	0	false	Optional[Qsy[freqHz=5330000]]
EDGE	-0	0	5330000	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	5330000	0	false	Optional[Qsy[freqHz=5331000]]
EDGE	1	0	5330000	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	5330000	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	-1	0	5330000	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	5330000	0	false	Optional[Qsy[freqHz=5331000]]
EDGE	+1	0	5330000	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	5330000	0	false	Optional[OtherVfo[freqHz=5330000]]
EDGE	/0	0	5330000	true	Optional[OtherVfo[freqHz=5330000]]
EDGE	/1	5330000	0	false	Optional[OtherVfo[freqHz=5331000]]
EDGE	/1	0	5330000	true	Optional[OtherVfo[freqHz=5331000]]
EDGE	/+1	5330000	0	false	Optional[OtherVfo[freqHz=5331000]]
EDGE	/+1	0	5330000	true	Optional[OtherVfo[freqHz=5331000]]
EDGE	/-1	5330000	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	0	5330000	true	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	999	5330000	0	false	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	999	0	5330000	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	5330000	0	false	Optional[Qsy[freqHz=5330001]]
EDGE	0.0005	0	5330000	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	5330000	0	false	Optional[Invalid[message=Posun -0.0005 kHz vede mimo p\u00E1smo]]
EDGE	-0.0005	0	5330000	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	5410000	0	false	Optional[Qsy[freqHz=5330000]]
EDGE	0	0	5410000	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	5410000	0	false	Optional[Qsy[freqHz=5410000]]
EDGE	+0	0	5410000	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	5410000	0	false	Optional[Qsy[freqHz=5410000]]
EDGE	-0	0	5410000	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	5410000	0	false	Optional[Qsy[freqHz=5331000]]
EDGE	1	0	5410000	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	5410000	0	false	Optional[Qsy[freqHz=5409000]]
EDGE	-1	0	5410000	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	5410000	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	+1	0	5410000	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	5410000	0	false	Optional[OtherVfo[freqHz=5330000]]
EDGE	/0	0	5410000	true	Optional[OtherVfo[freqHz=5330000]]
EDGE	/1	5410000	0	false	Optional[OtherVfo[freqHz=5331000]]
EDGE	/1	0	5410000	true	Optional[OtherVfo[freqHz=5331000]]
EDGE	/+1	5410000	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/+1	0	5410000	true	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	5410000	0	false	Optional[OtherVfo[freqHz=5409000]]
EDGE	/-1	0	5410000	true	Optional[OtherVfo[freqHz=5409000]]
EDGE	999	5410000	0	false	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	999	0	5410000	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	5410000	0	false	Optional[Qsy[freqHz=5330001]]
EDGE	0.0005	0	5410000	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	5410000	0	false	Optional[Qsy[freqHz=5409999]]
EDGE	-0.0005	0	5410000	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	5410001	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0	0	5410001	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	5410001	0	false	Optional[Invalid[message=Posun +0 kHz vede mimo p\u00E1smo]]
EDGE	+0	0	5410001	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	5410001	0	false	Optional[Invalid[message=Posun -0 kHz vede mimo p\u00E1smo]]
EDGE	-0	0	5410001	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	5410001	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	1	0	5410001	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	5410001	0	false	Optional[Qsy[freqHz=5409001]]
EDGE	-1	0	5410001	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	5410001	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	+1	0	5410001	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	5410001	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/0	0	5410001	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	5410001	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	0	5410001	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/+1	5410001	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/+1	0	5410001	true	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	5410001	0	false	Optional[OtherVfo[freqHz=5409001]]
EDGE	/-1	0	5410001	true	Optional[OtherVfo[freqHz=5409001]]
EDGE	999	5410001	0	false	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	999	0	5410001	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	5410001	0	false	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	0	5410001	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	5410001	0	false	Optional[Qsy[freqHz=5410000]]
EDGE	-0.0005	0	5410001	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	6999999	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0	0	6999999	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	6999999	0	false	Optional[Invalid[message=Posun +0 kHz vede mimo p\u00E1smo]]
EDGE	+0	0	6999999	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	6999999	0	false	Optional[Invalid[message=Posun -0 kHz vede mimo p\u00E1smo]]
EDGE	-0	0	6999999	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	6999999	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	1	0	6999999	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	6999999	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	-1	0	6999999	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	6999999	0	false	Optional[Qsy[freqHz=7000999]]
EDGE	+1	0	6999999	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	6999999	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/0	0	6999999	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	6999999	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	0	6999999	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/+1	6999999	0	false	Optional[OtherVfo[freqHz=7000999]]
EDGE	/+1	0	6999999	true	Optional[OtherVfo[freqHz=7000999]]
EDGE	/-1	6999999	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	0	6999999	true	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	999	6999999	0	false	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	999	0	6999999	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	6999999	0	false	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	0	6999999	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	6999999	0	false	Optional[Invalid[message=Posun -0.0005 kHz vede mimo p\u00E1smo]]
EDGE	-0.0005	0	6999999	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	7000000	0	false	Optional[Qsy[freqHz=7000000]]
EDGE	0	0	7000000	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	7000000	0	false	Optional[Qsy[freqHz=7000000]]
EDGE	+0	0	7000000	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	7000000	0	false	Optional[Qsy[freqHz=7000000]]
EDGE	-0	0	7000000	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	7000000	0	false	Optional[Qsy[freqHz=7001000]]
EDGE	1	0	7000000	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	7000000	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	-1	0	7000000	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	7000000	0	false	Optional[Qsy[freqHz=7001000]]
EDGE	+1	0	7000000	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	7000000	0	false	Optional[OtherVfo[freqHz=7000000]]
EDGE	/0	0	7000000	true	Optional[OtherVfo[freqHz=7000000]]
EDGE	/1	7000000	0	false	Optional[OtherVfo[freqHz=7001000]]
EDGE	/1	0	7000000	true	Optional[OtherVfo[freqHz=7001000]]
EDGE	/+1	7000000	0	false	Optional[OtherVfo[freqHz=7001000]]
EDGE	/+1	0	7000000	true	Optional[OtherVfo[freqHz=7001000]]
EDGE	/-1	7000000	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	0	7000000	true	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	999	7000000	0	false	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	999	0	7000000	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	7000000	0	false	Optional[Qsy[freqHz=7000001]]
EDGE	0.0005	0	7000000	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	7000000	0	false	Optional[Invalid[message=Posun -0.0005 kHz vede mimo p\u00E1smo]]
EDGE	-0.0005	0	7000000	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	7300000	0	false	Optional[Qsy[freqHz=7000000]]
EDGE	0	0	7300000	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	7300000	0	false	Optional[Qsy[freqHz=7300000]]
EDGE	+0	0	7300000	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	7300000	0	false	Optional[Qsy[freqHz=7300000]]
EDGE	-0	0	7300000	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	7300000	0	false	Optional[Qsy[freqHz=7001000]]
EDGE	1	0	7300000	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	7300000	0	false	Optional[Qsy[freqHz=7299000]]
EDGE	-1	0	7300000	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	7300000	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	+1	0	7300000	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	7300000	0	false	Optional[OtherVfo[freqHz=7000000]]
EDGE	/0	0	7300000	true	Optional[OtherVfo[freqHz=7000000]]
EDGE	/1	7300000	0	false	Optional[OtherVfo[freqHz=7001000]]
EDGE	/1	0	7300000	true	Optional[OtherVfo[freqHz=7001000]]
EDGE	/+1	7300000	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/+1	0	7300000	true	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	7300000	0	false	Optional[OtherVfo[freqHz=7299000]]
EDGE	/-1	0	7300000	true	Optional[OtherVfo[freqHz=7299000]]
EDGE	999	7300000	0	false	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	999	0	7300000	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	7300000	0	false	Optional[Qsy[freqHz=7000001]]
EDGE	0.0005	0	7300000	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	7300000	0	false	Optional[Qsy[freqHz=7299999]]
EDGE	-0.0005	0	7300000	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	7300001	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0	0	7300001	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	7300001	0	false	Optional[Invalid[message=Posun +0 kHz vede mimo p\u00E1smo]]
EDGE	+0	0	7300001	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	7300001	0	false	Optional[Invalid[message=Posun -0 kHz vede mimo p\u00E1smo]]
EDGE	-0	0	7300001	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	7300001	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	1	0	7300001	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	7300001	0	false	Optional[Qsy[freqHz=7299001]]
EDGE	-1	0	7300001	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	7300001	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	+1	0	7300001	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	7300001	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/0	0	7300001	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	7300001	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	0	7300001	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/+1	7300001	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/+1	0	7300001	true	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	7300001	0	false	Optional[OtherVfo[freqHz=7299001]]
EDGE	/-1	0	7300001	true	Optional[OtherVfo[freqHz=7299001]]
EDGE	999	7300001	0	false	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	999	0	7300001	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	7300001	0	false	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	0	7300001	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	7300001	0	false	Optional[Qsy[freqHz=7300000]]
EDGE	-0.0005	0	7300001	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	10099999	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0	0	10099999	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	10099999	0	false	Optional[Invalid[message=Posun +0 kHz vede mimo p\u00E1smo]]
EDGE	+0	0	10099999	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	10099999	0	false	Optional[Invalid[message=Posun -0 kHz vede mimo p\u00E1smo]]
EDGE	-0	0	10099999	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	10099999	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	1	0	10099999	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	10099999	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	-1	0	10099999	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	10099999	0	false	Optional[Qsy[freqHz=10100999]]
EDGE	+1	0	10099999	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	10099999	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/0	0	10099999	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	10099999	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	0	10099999	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/+1	10099999	0	false	Optional[OtherVfo[freqHz=10100999]]
EDGE	/+1	0	10099999	true	Optional[OtherVfo[freqHz=10100999]]
EDGE	/-1	10099999	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	0	10099999	true	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	999	10099999	0	false	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	999	0	10099999	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	10099999	0	false	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	0	10099999	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	10099999	0	false	Optional[Invalid[message=Posun -0.0005 kHz vede mimo p\u00E1smo]]
EDGE	-0.0005	0	10099999	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	10100000	0	false	Optional[Qsy[freqHz=10100000]]
EDGE	0	0	10100000	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	10100000	0	false	Optional[Qsy[freqHz=10100000]]
EDGE	+0	0	10100000	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	10100000	0	false	Optional[Qsy[freqHz=10100000]]
EDGE	-0	0	10100000	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	10100000	0	false	Optional[Qsy[freqHz=10101000]]
EDGE	1	0	10100000	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	10100000	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	-1	0	10100000	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	10100000	0	false	Optional[Qsy[freqHz=10101000]]
EDGE	+1	0	10100000	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	10100000	0	false	Optional[OtherVfo[freqHz=10100000]]
EDGE	/0	0	10100000	true	Optional[OtherVfo[freqHz=10100000]]
EDGE	/1	10100000	0	false	Optional[OtherVfo[freqHz=10101000]]
EDGE	/1	0	10100000	true	Optional[OtherVfo[freqHz=10101000]]
EDGE	/+1	10100000	0	false	Optional[OtherVfo[freqHz=10101000]]
EDGE	/+1	0	10100000	true	Optional[OtherVfo[freqHz=10101000]]
EDGE	/-1	10100000	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	0	10100000	true	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	999	10100000	0	false	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	999	0	10100000	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	10100000	0	false	Optional[Qsy[freqHz=10100001]]
EDGE	0.0005	0	10100000	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	10100000	0	false	Optional[Invalid[message=Posun -0.0005 kHz vede mimo p\u00E1smo]]
EDGE	-0.0005	0	10100000	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	10150000	0	false	Optional[Qsy[freqHz=10100000]]
EDGE	0	0	10150000	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	10150000	0	false	Optional[Qsy[freqHz=10150000]]
EDGE	+0	0	10150000	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	10150000	0	false	Optional[Qsy[freqHz=10150000]]
EDGE	-0	0	10150000	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	10150000	0	false	Optional[Qsy[freqHz=10101000]]
EDGE	1	0	10150000	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	10150000	0	false	Optional[Qsy[freqHz=10149000]]
EDGE	-1	0	10150000	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	10150000	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	+1	0	10150000	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	10150000	0	false	Optional[OtherVfo[freqHz=10100000]]
EDGE	/0	0	10150000	true	Optional[OtherVfo[freqHz=10100000]]
EDGE	/1	10150000	0	false	Optional[OtherVfo[freqHz=10101000]]
EDGE	/1	0	10150000	true	Optional[OtherVfo[freqHz=10101000]]
EDGE	/+1	10150000	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/+1	0	10150000	true	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	10150000	0	false	Optional[OtherVfo[freqHz=10149000]]
EDGE	/-1	0	10150000	true	Optional[OtherVfo[freqHz=10149000]]
EDGE	999	10150000	0	false	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	999	0	10150000	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	10150000	0	false	Optional[Qsy[freqHz=10100001]]
EDGE	0.0005	0	10150000	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	10150000	0	false	Optional[Qsy[freqHz=10149999]]
EDGE	-0.0005	0	10150000	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	10150001	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0	0	10150001	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	10150001	0	false	Optional[Invalid[message=Posun +0 kHz vede mimo p\u00E1smo]]
EDGE	+0	0	10150001	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	10150001	0	false	Optional[Invalid[message=Posun -0 kHz vede mimo p\u00E1smo]]
EDGE	-0	0	10150001	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	10150001	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	1	0	10150001	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	10150001	0	false	Optional[Qsy[freqHz=10149001]]
EDGE	-1	0	10150001	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	10150001	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	+1	0	10150001	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	10150001	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/0	0	10150001	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	10150001	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	0	10150001	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/+1	10150001	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/+1	0	10150001	true	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	10150001	0	false	Optional[OtherVfo[freqHz=10149001]]
EDGE	/-1	0	10150001	true	Optional[OtherVfo[freqHz=10149001]]
EDGE	999	10150001	0	false	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	999	0	10150001	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	10150001	0	false	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	0	10150001	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	10150001	0	false	Optional[Qsy[freqHz=10150000]]
EDGE	-0.0005	0	10150001	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	13999999	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0	0	13999999	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	13999999	0	false	Optional[Invalid[message=Posun +0 kHz vede mimo p\u00E1smo]]
EDGE	+0	0	13999999	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	13999999	0	false	Optional[Invalid[message=Posun -0 kHz vede mimo p\u00E1smo]]
EDGE	-0	0	13999999	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	13999999	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	1	0	13999999	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	13999999	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	-1	0	13999999	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	13999999	0	false	Optional[Qsy[freqHz=14000999]]
EDGE	+1	0	13999999	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	13999999	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/0	0	13999999	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	13999999	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	0	13999999	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/+1	13999999	0	false	Optional[OtherVfo[freqHz=14000999]]
EDGE	/+1	0	13999999	true	Optional[OtherVfo[freqHz=14000999]]
EDGE	/-1	13999999	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	0	13999999	true	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	999	13999999	0	false	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	999	0	13999999	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	13999999	0	false	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	0	13999999	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	13999999	0	false	Optional[Invalid[message=Posun -0.0005 kHz vede mimo p\u00E1smo]]
EDGE	-0.0005	0	13999999	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	14000000	0	false	Optional[Qsy[freqHz=14000000]]
EDGE	0	0	14000000	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	14000000	0	false	Optional[Qsy[freqHz=14000000]]
EDGE	+0	0	14000000	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	14000000	0	false	Optional[Qsy[freqHz=14000000]]
EDGE	-0	0	14000000	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	14000000	0	false	Optional[Qsy[freqHz=14001000]]
EDGE	1	0	14000000	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	14000000	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	-1	0	14000000	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	14000000	0	false	Optional[Qsy[freqHz=14001000]]
EDGE	+1	0	14000000	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	14000000	0	false	Optional[OtherVfo[freqHz=14000000]]
EDGE	/0	0	14000000	true	Optional[OtherVfo[freqHz=14000000]]
EDGE	/1	14000000	0	false	Optional[OtherVfo[freqHz=14001000]]
EDGE	/1	0	14000000	true	Optional[OtherVfo[freqHz=14001000]]
EDGE	/+1	14000000	0	false	Optional[OtherVfo[freqHz=14001000]]
EDGE	/+1	0	14000000	true	Optional[OtherVfo[freqHz=14001000]]
EDGE	/-1	14000000	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	0	14000000	true	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	999	14000000	0	false	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	999	0	14000000	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	14000000	0	false	Optional[Qsy[freqHz=14000001]]
EDGE	0.0005	0	14000000	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	14000000	0	false	Optional[Invalid[message=Posun -0.0005 kHz vede mimo p\u00E1smo]]
EDGE	-0.0005	0	14000000	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	14350000	0	false	Optional[Qsy[freqHz=14000000]]
EDGE	0	0	14350000	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	14350000	0	false	Optional[Qsy[freqHz=14350000]]
EDGE	+0	0	14350000	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	14350000	0	false	Optional[Qsy[freqHz=14350000]]
EDGE	-0	0	14350000	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	14350000	0	false	Optional[Qsy[freqHz=14001000]]
EDGE	1	0	14350000	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	14350000	0	false	Optional[Qsy[freqHz=14349000]]
EDGE	-1	0	14350000	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	14350000	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	+1	0	14350000	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	14350000	0	false	Optional[OtherVfo[freqHz=14000000]]
EDGE	/0	0	14350000	true	Optional[OtherVfo[freqHz=14000000]]
EDGE	/1	14350000	0	false	Optional[OtherVfo[freqHz=14001000]]
EDGE	/1	0	14350000	true	Optional[OtherVfo[freqHz=14001000]]
EDGE	/+1	14350000	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/+1	0	14350000	true	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	14350000	0	false	Optional[OtherVfo[freqHz=14349000]]
EDGE	/-1	0	14350000	true	Optional[OtherVfo[freqHz=14349000]]
EDGE	999	14350000	0	false	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	999	0	14350000	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	14350000	0	false	Optional[Qsy[freqHz=14000001]]
EDGE	0.0005	0	14350000	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	14350000	0	false	Optional[Qsy[freqHz=14349999]]
EDGE	-0.0005	0	14350000	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	14350001	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0	0	14350001	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	14350001	0	false	Optional[Invalid[message=Posun +0 kHz vede mimo p\u00E1smo]]
EDGE	+0	0	14350001	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	14350001	0	false	Optional[Invalid[message=Posun -0 kHz vede mimo p\u00E1smo]]
EDGE	-0	0	14350001	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	14350001	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	1	0	14350001	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	14350001	0	false	Optional[Qsy[freqHz=14349001]]
EDGE	-1	0	14350001	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	14350001	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	+1	0	14350001	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	14350001	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/0	0	14350001	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	14350001	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	0	14350001	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/+1	14350001	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/+1	0	14350001	true	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	14350001	0	false	Optional[OtherVfo[freqHz=14349001]]
EDGE	/-1	0	14350001	true	Optional[OtherVfo[freqHz=14349001]]
EDGE	999	14350001	0	false	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	999	0	14350001	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	14350001	0	false	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	0	14350001	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	14350001	0	false	Optional[Qsy[freqHz=14350000]]
EDGE	-0.0005	0	14350001	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	18067999	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0	0	18067999	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	18067999	0	false	Optional[Invalid[message=Posun +0 kHz vede mimo p\u00E1smo]]
EDGE	+0	0	18067999	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	18067999	0	false	Optional[Invalid[message=Posun -0 kHz vede mimo p\u00E1smo]]
EDGE	-0	0	18067999	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	18067999	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	1	0	18067999	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	18067999	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	-1	0	18067999	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	18067999	0	false	Optional[Qsy[freqHz=18068999]]
EDGE	+1	0	18067999	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	18067999	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/0	0	18067999	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	18067999	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	0	18067999	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/+1	18067999	0	false	Optional[OtherVfo[freqHz=18068999]]
EDGE	/+1	0	18067999	true	Optional[OtherVfo[freqHz=18068999]]
EDGE	/-1	18067999	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	0	18067999	true	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	999	18067999	0	false	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	999	0	18067999	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	18067999	0	false	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	0	18067999	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	18067999	0	false	Optional[Invalid[message=Posun -0.0005 kHz vede mimo p\u00E1smo]]
EDGE	-0.0005	0	18067999	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	18068000	0	false	Optional[Qsy[freqHz=18068000]]
EDGE	0	0	18068000	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	18068000	0	false	Optional[Qsy[freqHz=18068000]]
EDGE	+0	0	18068000	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	18068000	0	false	Optional[Qsy[freqHz=18068000]]
EDGE	-0	0	18068000	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	18068000	0	false	Optional[Qsy[freqHz=18069000]]
EDGE	1	0	18068000	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	18068000	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	-1	0	18068000	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	18068000	0	false	Optional[Qsy[freqHz=18069000]]
EDGE	+1	0	18068000	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	18068000	0	false	Optional[OtherVfo[freqHz=18068000]]
EDGE	/0	0	18068000	true	Optional[OtherVfo[freqHz=18068000]]
EDGE	/1	18068000	0	false	Optional[OtherVfo[freqHz=18069000]]
EDGE	/1	0	18068000	true	Optional[OtherVfo[freqHz=18069000]]
EDGE	/+1	18068000	0	false	Optional[OtherVfo[freqHz=18069000]]
EDGE	/+1	0	18068000	true	Optional[OtherVfo[freqHz=18069000]]
EDGE	/-1	18068000	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	0	18068000	true	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	999	18068000	0	false	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	999	0	18068000	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	18068000	0	false	Optional[Qsy[freqHz=18068001]]
EDGE	0.0005	0	18068000	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	18068000	0	false	Optional[Invalid[message=Posun -0.0005 kHz vede mimo p\u00E1smo]]
EDGE	-0.0005	0	18068000	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	18168000	0	false	Optional[Qsy[freqHz=18068000]]
EDGE	0	0	18168000	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	18168000	0	false	Optional[Qsy[freqHz=18168000]]
EDGE	+0	0	18168000	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	18168000	0	false	Optional[Qsy[freqHz=18168000]]
EDGE	-0	0	18168000	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	18168000	0	false	Optional[Qsy[freqHz=18069000]]
EDGE	1	0	18168000	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	18168000	0	false	Optional[Qsy[freqHz=18167000]]
EDGE	-1	0	18168000	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	18168000	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	+1	0	18168000	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	18168000	0	false	Optional[OtherVfo[freqHz=18068000]]
EDGE	/0	0	18168000	true	Optional[OtherVfo[freqHz=18068000]]
EDGE	/1	18168000	0	false	Optional[OtherVfo[freqHz=18069000]]
EDGE	/1	0	18168000	true	Optional[OtherVfo[freqHz=18069000]]
EDGE	/+1	18168000	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/+1	0	18168000	true	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	18168000	0	false	Optional[OtherVfo[freqHz=18167000]]
EDGE	/-1	0	18168000	true	Optional[OtherVfo[freqHz=18167000]]
EDGE	999	18168000	0	false	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	999	0	18168000	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	18168000	0	false	Optional[Qsy[freqHz=18068001]]
EDGE	0.0005	0	18168000	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	18168000	0	false	Optional[Qsy[freqHz=18167999]]
EDGE	-0.0005	0	18168000	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	18168001	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0	0	18168001	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	18168001	0	false	Optional[Invalid[message=Posun +0 kHz vede mimo p\u00E1smo]]
EDGE	+0	0	18168001	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	18168001	0	false	Optional[Invalid[message=Posun -0 kHz vede mimo p\u00E1smo]]
EDGE	-0	0	18168001	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	18168001	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	1	0	18168001	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	18168001	0	false	Optional[Qsy[freqHz=18167001]]
EDGE	-1	0	18168001	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	18168001	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	+1	0	18168001	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	18168001	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/0	0	18168001	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	18168001	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	0	18168001	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/+1	18168001	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/+1	0	18168001	true	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	18168001	0	false	Optional[OtherVfo[freqHz=18167001]]
EDGE	/-1	0	18168001	true	Optional[OtherVfo[freqHz=18167001]]
EDGE	999	18168001	0	false	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	999	0	18168001	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	18168001	0	false	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	0	18168001	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	18168001	0	false	Optional[Qsy[freqHz=18168000]]
EDGE	-0.0005	0	18168001	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	20999999	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0	0	20999999	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	20999999	0	false	Optional[Invalid[message=Posun +0 kHz vede mimo p\u00E1smo]]
EDGE	+0	0	20999999	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	20999999	0	false	Optional[Invalid[message=Posun -0 kHz vede mimo p\u00E1smo]]
EDGE	-0	0	20999999	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	20999999	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	1	0	20999999	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	20999999	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	-1	0	20999999	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	20999999	0	false	Optional[Qsy[freqHz=21000999]]
EDGE	+1	0	20999999	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	20999999	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/0	0	20999999	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	20999999	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	0	20999999	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/+1	20999999	0	false	Optional[OtherVfo[freqHz=21000999]]
EDGE	/+1	0	20999999	true	Optional[OtherVfo[freqHz=21000999]]
EDGE	/-1	20999999	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	0	20999999	true	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	999	20999999	0	false	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	999	0	20999999	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	20999999	0	false	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	0	20999999	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	20999999	0	false	Optional[Invalid[message=Posun -0.0005 kHz vede mimo p\u00E1smo]]
EDGE	-0.0005	0	20999999	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	21000000	0	false	Optional[Qsy[freqHz=21000000]]
EDGE	0	0	21000000	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	21000000	0	false	Optional[Qsy[freqHz=21000000]]
EDGE	+0	0	21000000	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	21000000	0	false	Optional[Qsy[freqHz=21000000]]
EDGE	-0	0	21000000	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	21000000	0	false	Optional[Qsy[freqHz=21001000]]
EDGE	1	0	21000000	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	21000000	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	-1	0	21000000	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	21000000	0	false	Optional[Qsy[freqHz=21001000]]
EDGE	+1	0	21000000	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	21000000	0	false	Optional[OtherVfo[freqHz=21000000]]
EDGE	/0	0	21000000	true	Optional[OtherVfo[freqHz=21000000]]
EDGE	/1	21000000	0	false	Optional[OtherVfo[freqHz=21001000]]
EDGE	/1	0	21000000	true	Optional[OtherVfo[freqHz=21001000]]
EDGE	/+1	21000000	0	false	Optional[OtherVfo[freqHz=21001000]]
EDGE	/+1	0	21000000	true	Optional[OtherVfo[freqHz=21001000]]
EDGE	/-1	21000000	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	0	21000000	true	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	999	21000000	0	false	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	999	0	21000000	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	21000000	0	false	Optional[Qsy[freqHz=21000001]]
EDGE	0.0005	0	21000000	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	21000000	0	false	Optional[Invalid[message=Posun -0.0005 kHz vede mimo p\u00E1smo]]
EDGE	-0.0005	0	21000000	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	21450000	0	false	Optional[Qsy[freqHz=21000000]]
EDGE	0	0	21450000	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	21450000	0	false	Optional[Qsy[freqHz=21450000]]
EDGE	+0	0	21450000	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	21450000	0	false	Optional[Qsy[freqHz=21450000]]
EDGE	-0	0	21450000	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	21450000	0	false	Optional[Qsy[freqHz=21001000]]
EDGE	1	0	21450000	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	21450000	0	false	Optional[Qsy[freqHz=21449000]]
EDGE	-1	0	21450000	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	21450000	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	+1	0	21450000	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	21450000	0	false	Optional[OtherVfo[freqHz=21000000]]
EDGE	/0	0	21450000	true	Optional[OtherVfo[freqHz=21000000]]
EDGE	/1	21450000	0	false	Optional[OtherVfo[freqHz=21001000]]
EDGE	/1	0	21450000	true	Optional[OtherVfo[freqHz=21001000]]
EDGE	/+1	21450000	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/+1	0	21450000	true	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	21450000	0	false	Optional[OtherVfo[freqHz=21449000]]
EDGE	/-1	0	21450000	true	Optional[OtherVfo[freqHz=21449000]]
EDGE	999	21450000	0	false	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	999	0	21450000	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	21450000	0	false	Optional[Qsy[freqHz=21000001]]
EDGE	0.0005	0	21450000	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	21450000	0	false	Optional[Qsy[freqHz=21449999]]
EDGE	-0.0005	0	21450000	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	21450001	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0	0	21450001	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	21450001	0	false	Optional[Invalid[message=Posun +0 kHz vede mimo p\u00E1smo]]
EDGE	+0	0	21450001	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	21450001	0	false	Optional[Invalid[message=Posun -0 kHz vede mimo p\u00E1smo]]
EDGE	-0	0	21450001	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	21450001	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	1	0	21450001	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	21450001	0	false	Optional[Qsy[freqHz=21449001]]
EDGE	-1	0	21450001	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	21450001	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	+1	0	21450001	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	21450001	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/0	0	21450001	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	21450001	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	0	21450001	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/+1	21450001	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/+1	0	21450001	true	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	21450001	0	false	Optional[OtherVfo[freqHz=21449001]]
EDGE	/-1	0	21450001	true	Optional[OtherVfo[freqHz=21449001]]
EDGE	999	21450001	0	false	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	999	0	21450001	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	21450001	0	false	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	0	21450001	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	21450001	0	false	Optional[Qsy[freqHz=21450000]]
EDGE	-0.0005	0	21450001	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	24889999	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0	0	24889999	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	24889999	0	false	Optional[Invalid[message=Posun +0 kHz vede mimo p\u00E1smo]]
EDGE	+0	0	24889999	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	24889999	0	false	Optional[Invalid[message=Posun -0 kHz vede mimo p\u00E1smo]]
EDGE	-0	0	24889999	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	24889999	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	1	0	24889999	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	24889999	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	-1	0	24889999	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	24889999	0	false	Optional[Qsy[freqHz=24890999]]
EDGE	+1	0	24889999	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	24889999	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/0	0	24889999	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	24889999	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	0	24889999	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/+1	24889999	0	false	Optional[OtherVfo[freqHz=24890999]]
EDGE	/+1	0	24889999	true	Optional[OtherVfo[freqHz=24890999]]
EDGE	/-1	24889999	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	0	24889999	true	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	999	24889999	0	false	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	999	0	24889999	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	24889999	0	false	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	0	24889999	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	24889999	0	false	Optional[Invalid[message=Posun -0.0005 kHz vede mimo p\u00E1smo]]
EDGE	-0.0005	0	24889999	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	24890000	0	false	Optional[Qsy[freqHz=24890000]]
EDGE	0	0	24890000	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	24890000	0	false	Optional[Qsy[freqHz=24890000]]
EDGE	+0	0	24890000	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	24890000	0	false	Optional[Qsy[freqHz=24890000]]
EDGE	-0	0	24890000	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	24890000	0	false	Optional[Qsy[freqHz=24891000]]
EDGE	1	0	24890000	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	24890000	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	-1	0	24890000	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	24890000	0	false	Optional[Qsy[freqHz=24891000]]
EDGE	+1	0	24890000	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	24890000	0	false	Optional[OtherVfo[freqHz=24890000]]
EDGE	/0	0	24890000	true	Optional[OtherVfo[freqHz=24890000]]
EDGE	/1	24890000	0	false	Optional[OtherVfo[freqHz=24891000]]
EDGE	/1	0	24890000	true	Optional[OtherVfo[freqHz=24891000]]
EDGE	/+1	24890000	0	false	Optional[OtherVfo[freqHz=24891000]]
EDGE	/+1	0	24890000	true	Optional[OtherVfo[freqHz=24891000]]
EDGE	/-1	24890000	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	0	24890000	true	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	999	24890000	0	false	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	999	0	24890000	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	24890000	0	false	Optional[Qsy[freqHz=24890001]]
EDGE	0.0005	0	24890000	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	24890000	0	false	Optional[Invalid[message=Posun -0.0005 kHz vede mimo p\u00E1smo]]
EDGE	-0.0005	0	24890000	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	24990000	0	false	Optional[Qsy[freqHz=24890000]]
EDGE	0	0	24990000	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	24990000	0	false	Optional[Qsy[freqHz=24990000]]
EDGE	+0	0	24990000	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	24990000	0	false	Optional[Qsy[freqHz=24990000]]
EDGE	-0	0	24990000	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	24990000	0	false	Optional[Qsy[freqHz=24891000]]
EDGE	1	0	24990000	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	24990000	0	false	Optional[Qsy[freqHz=24989000]]
EDGE	-1	0	24990000	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	24990000	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	+1	0	24990000	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	24990000	0	false	Optional[OtherVfo[freqHz=24890000]]
EDGE	/0	0	24990000	true	Optional[OtherVfo[freqHz=24890000]]
EDGE	/1	24990000	0	false	Optional[OtherVfo[freqHz=24891000]]
EDGE	/1	0	24990000	true	Optional[OtherVfo[freqHz=24891000]]
EDGE	/+1	24990000	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/+1	0	24990000	true	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	24990000	0	false	Optional[OtherVfo[freqHz=24989000]]
EDGE	/-1	0	24990000	true	Optional[OtherVfo[freqHz=24989000]]
EDGE	999	24990000	0	false	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	999	0	24990000	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	24990000	0	false	Optional[Qsy[freqHz=24890001]]
EDGE	0.0005	0	24990000	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	24990000	0	false	Optional[Qsy[freqHz=24989999]]
EDGE	-0.0005	0	24990000	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	24990001	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0	0	24990001	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	24990001	0	false	Optional[Invalid[message=Posun +0 kHz vede mimo p\u00E1smo]]
EDGE	+0	0	24990001	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	24990001	0	false	Optional[Invalid[message=Posun -0 kHz vede mimo p\u00E1smo]]
EDGE	-0	0	24990001	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	24990001	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	1	0	24990001	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	24990001	0	false	Optional[Qsy[freqHz=24989001]]
EDGE	-1	0	24990001	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	24990001	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	+1	0	24990001	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	24990001	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/0	0	24990001	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	24990001	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	0	24990001	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/+1	24990001	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/+1	0	24990001	true	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	24990001	0	false	Optional[OtherVfo[freqHz=24989001]]
EDGE	/-1	0	24990001	true	Optional[OtherVfo[freqHz=24989001]]
EDGE	999	24990001	0	false	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	999	0	24990001	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	24990001	0	false	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	0	24990001	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	24990001	0	false	Optional[Qsy[freqHz=24990000]]
EDGE	-0.0005	0	24990001	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	27999999	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0	0	27999999	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	27999999	0	false	Optional[Invalid[message=Posun +0 kHz vede mimo p\u00E1smo]]
EDGE	+0	0	27999999	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	27999999	0	false	Optional[Invalid[message=Posun -0 kHz vede mimo p\u00E1smo]]
EDGE	-0	0	27999999	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	27999999	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	1	0	27999999	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	27999999	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	-1	0	27999999	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	27999999	0	false	Optional[Qsy[freqHz=28000999]]
EDGE	+1	0	27999999	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	27999999	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/0	0	27999999	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	27999999	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	0	27999999	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/+1	27999999	0	false	Optional[OtherVfo[freqHz=28000999]]
EDGE	/+1	0	27999999	true	Optional[OtherVfo[freqHz=28000999]]
EDGE	/-1	27999999	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	0	27999999	true	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	999	27999999	0	false	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	999	0	27999999	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	27999999	0	false	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	0	27999999	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	27999999	0	false	Optional[Invalid[message=Posun -0.0005 kHz vede mimo p\u00E1smo]]
EDGE	-0.0005	0	27999999	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	28000000	0	false	Optional[Qsy[freqHz=28000000]]
EDGE	0	0	28000000	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	28000000	0	false	Optional[Qsy[freqHz=28000000]]
EDGE	+0	0	28000000	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	28000000	0	false	Optional[Qsy[freqHz=28000000]]
EDGE	-0	0	28000000	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	28000000	0	false	Optional[Qsy[freqHz=28001000]]
EDGE	1	0	28000000	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	28000000	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	-1	0	28000000	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	28000000	0	false	Optional[Qsy[freqHz=28001000]]
EDGE	+1	0	28000000	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	28000000	0	false	Optional[OtherVfo[freqHz=28000000]]
EDGE	/0	0	28000000	true	Optional[OtherVfo[freqHz=28000000]]
EDGE	/1	28000000	0	false	Optional[OtherVfo[freqHz=28001000]]
EDGE	/1	0	28000000	true	Optional[OtherVfo[freqHz=28001000]]
EDGE	/+1	28000000	0	false	Optional[OtherVfo[freqHz=28001000]]
EDGE	/+1	0	28000000	true	Optional[OtherVfo[freqHz=28001000]]
EDGE	/-1	28000000	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	0	28000000	true	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	999	28000000	0	false	Optional[Qsy[freqHz=28999000]]
EDGE	999	0	28000000	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	28000000	0	false	Optional[Qsy[freqHz=28000001]]
EDGE	0.0005	0	28000000	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	28000000	0	false	Optional[Invalid[message=Posun -0.0005 kHz vede mimo p\u00E1smo]]
EDGE	-0.0005	0	28000000	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	29700000	0	false	Optional[Qsy[freqHz=28000000]]
EDGE	0	0	29700000	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	29700000	0	false	Optional[Qsy[freqHz=29700000]]
EDGE	+0	0	29700000	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	29700000	0	false	Optional[Qsy[freqHz=29700000]]
EDGE	-0	0	29700000	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	29700000	0	false	Optional[Qsy[freqHz=28001000]]
EDGE	1	0	29700000	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	29700000	0	false	Optional[Qsy[freqHz=29699000]]
EDGE	-1	0	29700000	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	29700000	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	+1	0	29700000	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	29700000	0	false	Optional[OtherVfo[freqHz=28000000]]
EDGE	/0	0	29700000	true	Optional[OtherVfo[freqHz=28000000]]
EDGE	/1	29700000	0	false	Optional[OtherVfo[freqHz=28001000]]
EDGE	/1	0	29700000	true	Optional[OtherVfo[freqHz=28001000]]
EDGE	/+1	29700000	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/+1	0	29700000	true	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	29700000	0	false	Optional[OtherVfo[freqHz=29699000]]
EDGE	/-1	0	29700000	true	Optional[OtherVfo[freqHz=29699000]]
EDGE	999	29700000	0	false	Optional[Qsy[freqHz=28999000]]
EDGE	999	0	29700000	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	29700000	0	false	Optional[Qsy[freqHz=28000001]]
EDGE	0.0005	0	29700000	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	29700000	0	false	Optional[Qsy[freqHz=29699999]]
EDGE	-0.0005	0	29700000	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	29700001	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0	0	29700001	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	29700001	0	false	Optional[Invalid[message=Posun +0 kHz vede mimo p\u00E1smo]]
EDGE	+0	0	29700001	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	29700001	0	false	Optional[Invalid[message=Posun -0 kHz vede mimo p\u00E1smo]]
EDGE	-0	0	29700001	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	29700001	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	1	0	29700001	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	29700001	0	false	Optional[Qsy[freqHz=29699001]]
EDGE	-1	0	29700001	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	29700001	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	+1	0	29700001	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	29700001	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/0	0	29700001	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	29700001	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	0	29700001	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/+1	29700001	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/+1	0	29700001	true	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	29700001	0	false	Optional[OtherVfo[freqHz=29699001]]
EDGE	/-1	0	29700001	true	Optional[OtherVfo[freqHz=29699001]]
EDGE	999	29700001	0	false	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	999	0	29700001	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	29700001	0	false	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	0	29700001	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	29700001	0	false	Optional[Qsy[freqHz=29700000]]
EDGE	-0.0005	0	29700001	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	49999999	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0	0	49999999	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	49999999	0	false	Optional[Invalid[message=Posun +0 kHz vede mimo p\u00E1smo]]
EDGE	+0	0	49999999	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	49999999	0	false	Optional[Invalid[message=Posun -0 kHz vede mimo p\u00E1smo]]
EDGE	-0	0	49999999	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	49999999	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	1	0	49999999	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	49999999	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	-1	0	49999999	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	49999999	0	false	Optional[Qsy[freqHz=50000999]]
EDGE	+1	0	49999999	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	49999999	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/0	0	49999999	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	49999999	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	0	49999999	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/+1	49999999	0	false	Optional[OtherVfo[freqHz=50000999]]
EDGE	/+1	0	49999999	true	Optional[OtherVfo[freqHz=50000999]]
EDGE	/-1	49999999	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	0	49999999	true	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	999	49999999	0	false	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	999	0	49999999	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	49999999	0	false	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	0	49999999	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	49999999	0	false	Optional[Invalid[message=Posun -0.0005 kHz vede mimo p\u00E1smo]]
EDGE	-0.0005	0	49999999	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	50000000	0	false	Optional[Qsy[freqHz=50000000]]
EDGE	0	0	50000000	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	50000000	0	false	Optional[Qsy[freqHz=50000000]]
EDGE	+0	0	50000000	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	50000000	0	false	Optional[Qsy[freqHz=50000000]]
EDGE	-0	0	50000000	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	50000000	0	false	Optional[Qsy[freqHz=50001000]]
EDGE	1	0	50000000	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	50000000	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	-1	0	50000000	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	50000000	0	false	Optional[Qsy[freqHz=50001000]]
EDGE	+1	0	50000000	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	50000000	0	false	Optional[OtherVfo[freqHz=50000000]]
EDGE	/0	0	50000000	true	Optional[OtherVfo[freqHz=50000000]]
EDGE	/1	50000000	0	false	Optional[OtherVfo[freqHz=50001000]]
EDGE	/1	0	50000000	true	Optional[OtherVfo[freqHz=50001000]]
EDGE	/+1	50000000	0	false	Optional[OtherVfo[freqHz=50001000]]
EDGE	/+1	0	50000000	true	Optional[OtherVfo[freqHz=50001000]]
EDGE	/-1	50000000	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	0	50000000	true	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	999	50000000	0	false	Optional[Qsy[freqHz=50999000]]
EDGE	999	0	50000000	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	50000000	0	false	Optional[Qsy[freqHz=50000001]]
EDGE	0.0005	0	50000000	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	50000000	0	false	Optional[Invalid[message=Posun -0.0005 kHz vede mimo p\u00E1smo]]
EDGE	-0.0005	0	50000000	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	54000000	0	false	Optional[Qsy[freqHz=50000000]]
EDGE	0	0	54000000	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	54000000	0	false	Optional[Qsy[freqHz=54000000]]
EDGE	+0	0	54000000	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	54000000	0	false	Optional[Qsy[freqHz=54000000]]
EDGE	-0	0	54000000	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	54000000	0	false	Optional[Qsy[freqHz=50001000]]
EDGE	1	0	54000000	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	54000000	0	false	Optional[Qsy[freqHz=53999000]]
EDGE	-1	0	54000000	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	54000000	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	+1	0	54000000	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	54000000	0	false	Optional[OtherVfo[freqHz=50000000]]
EDGE	/0	0	54000000	true	Optional[OtherVfo[freqHz=50000000]]
EDGE	/1	54000000	0	false	Optional[OtherVfo[freqHz=50001000]]
EDGE	/1	0	54000000	true	Optional[OtherVfo[freqHz=50001000]]
EDGE	/+1	54000000	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/+1	0	54000000	true	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	54000000	0	false	Optional[OtherVfo[freqHz=53999000]]
EDGE	/-1	0	54000000	true	Optional[OtherVfo[freqHz=53999000]]
EDGE	999	54000000	0	false	Optional[Qsy[freqHz=50999000]]
EDGE	999	0	54000000	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	54000000	0	false	Optional[Qsy[freqHz=50000001]]
EDGE	0.0005	0	54000000	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	54000000	0	false	Optional[Qsy[freqHz=53999999]]
EDGE	-0.0005	0	54000000	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	54000001	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0	0	54000001	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	54000001	0	false	Optional[Invalid[message=Posun +0 kHz vede mimo p\u00E1smo]]
EDGE	+0	0	54000001	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	54000001	0	false	Optional[Invalid[message=Posun -0 kHz vede mimo p\u00E1smo]]
EDGE	-0	0	54000001	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	54000001	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	1	0	54000001	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	54000001	0	false	Optional[Qsy[freqHz=53999001]]
EDGE	-1	0	54000001	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	54000001	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	+1	0	54000001	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	54000001	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/0	0	54000001	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	54000001	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	0	54000001	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/+1	54000001	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/+1	0	54000001	true	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	54000001	0	false	Optional[OtherVfo[freqHz=53999001]]
EDGE	/-1	0	54000001	true	Optional[OtherVfo[freqHz=53999001]]
EDGE	999	54000001	0	false	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	999	0	54000001	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	54000001	0	false	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	0	54000001	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	54000001	0	false	Optional[Qsy[freqHz=54000000]]
EDGE	-0.0005	0	54000001	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	143999999	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0	0	143999999	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	143999999	0	false	Optional[Invalid[message=Posun +0 kHz vede mimo p\u00E1smo]]
EDGE	+0	0	143999999	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	143999999	0	false	Optional[Invalid[message=Posun -0 kHz vede mimo p\u00E1smo]]
EDGE	-0	0	143999999	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	143999999	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	1	0	143999999	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	143999999	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	-1	0	143999999	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	143999999	0	false	Optional[Qsy[freqHz=144000999]]
EDGE	+1	0	143999999	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	143999999	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/0	0	143999999	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	143999999	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	0	143999999	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/+1	143999999	0	false	Optional[OtherVfo[freqHz=144000999]]
EDGE	/+1	0	143999999	true	Optional[OtherVfo[freqHz=144000999]]
EDGE	/-1	143999999	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	0	143999999	true	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	999	143999999	0	false	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	999	0	143999999	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	143999999	0	false	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	0	143999999	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	143999999	0	false	Optional[Invalid[message=Posun -0.0005 kHz vede mimo p\u00E1smo]]
EDGE	-0.0005	0	143999999	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	144000000	0	false	Optional[Qsy[freqHz=144000000]]
EDGE	0	0	144000000	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	144000000	0	false	Optional[Qsy[freqHz=144000000]]
EDGE	+0	0	144000000	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	144000000	0	false	Optional[Qsy[freqHz=144000000]]
EDGE	-0	0	144000000	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	144000000	0	false	Optional[Qsy[freqHz=144001000]]
EDGE	1	0	144000000	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	144000000	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	-1	0	144000000	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	144000000	0	false	Optional[Qsy[freqHz=144001000]]
EDGE	+1	0	144000000	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	144000000	0	false	Optional[OtherVfo[freqHz=144000000]]
EDGE	/0	0	144000000	true	Optional[OtherVfo[freqHz=144000000]]
EDGE	/1	144000000	0	false	Optional[OtherVfo[freqHz=144001000]]
EDGE	/1	0	144000000	true	Optional[OtherVfo[freqHz=144001000]]
EDGE	/+1	144000000	0	false	Optional[OtherVfo[freqHz=144001000]]
EDGE	/+1	0	144000000	true	Optional[OtherVfo[freqHz=144001000]]
EDGE	/-1	144000000	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	0	144000000	true	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	999	144000000	0	false	Optional[Qsy[freqHz=144999000]]
EDGE	999	0	144000000	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	144000000	0	false	Optional[Qsy[freqHz=144000001]]
EDGE	0.0005	0	144000000	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	144000000	0	false	Optional[Invalid[message=Posun -0.0005 kHz vede mimo p\u00E1smo]]
EDGE	-0.0005	0	144000000	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	148000000	0	false	Optional[Qsy[freqHz=144000000]]
EDGE	0	0	148000000	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	148000000	0	false	Optional[Qsy[freqHz=148000000]]
EDGE	+0	0	148000000	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	148000000	0	false	Optional[Qsy[freqHz=148000000]]
EDGE	-0	0	148000000	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	148000000	0	false	Optional[Qsy[freqHz=144001000]]
EDGE	1	0	148000000	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	148000000	0	false	Optional[Qsy[freqHz=147999000]]
EDGE	-1	0	148000000	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	148000000	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	+1	0	148000000	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	148000000	0	false	Optional[OtherVfo[freqHz=144000000]]
EDGE	/0	0	148000000	true	Optional[OtherVfo[freqHz=144000000]]
EDGE	/1	148000000	0	false	Optional[OtherVfo[freqHz=144001000]]
EDGE	/1	0	148000000	true	Optional[OtherVfo[freqHz=144001000]]
EDGE	/+1	148000000	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/+1	0	148000000	true	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	148000000	0	false	Optional[OtherVfo[freqHz=147999000]]
EDGE	/-1	0	148000000	true	Optional[OtherVfo[freqHz=147999000]]
EDGE	999	148000000	0	false	Optional[Qsy[freqHz=144999000]]
EDGE	999	0	148000000	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	148000000	0	false	Optional[Qsy[freqHz=144000001]]
EDGE	0.0005	0	148000000	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	148000000	0	false	Optional[Qsy[freqHz=147999999]]
EDGE	-0.0005	0	148000000	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	148000001	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0	0	148000001	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	148000001	0	false	Optional[Invalid[message=Posun +0 kHz vede mimo p\u00E1smo]]
EDGE	+0	0	148000001	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	148000001	0	false	Optional[Invalid[message=Posun -0 kHz vede mimo p\u00E1smo]]
EDGE	-0	0	148000001	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	148000001	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	1	0	148000001	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	148000001	0	false	Optional[Qsy[freqHz=147999001]]
EDGE	-1	0	148000001	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	148000001	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	+1	0	148000001	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	148000001	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/0	0	148000001	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	148000001	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	0	148000001	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/+1	148000001	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/+1	0	148000001	true	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	148000001	0	false	Optional[OtherVfo[freqHz=147999001]]
EDGE	/-1	0	148000001	true	Optional[OtherVfo[freqHz=147999001]]
EDGE	999	148000001	0	false	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	999	0	148000001	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	148000001	0	false	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	0	148000001	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	148000001	0	false	Optional[Qsy[freqHz=148000000]]
EDGE	-0.0005	0	148000001	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	429999999	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0	0	429999999	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	429999999	0	false	Optional[Invalid[message=Posun +0 kHz vede mimo p\u00E1smo]]
EDGE	+0	0	429999999	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	429999999	0	false	Optional[Invalid[message=Posun -0 kHz vede mimo p\u00E1smo]]
EDGE	-0	0	429999999	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	429999999	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	1	0	429999999	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	429999999	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	-1	0	429999999	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	429999999	0	false	Optional[Qsy[freqHz=430000999]]
EDGE	+1	0	429999999	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	429999999	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/0	0	429999999	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	429999999	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	0	429999999	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/+1	429999999	0	false	Optional[OtherVfo[freqHz=430000999]]
EDGE	/+1	0	429999999	true	Optional[OtherVfo[freqHz=430000999]]
EDGE	/-1	429999999	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	0	429999999	true	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	999	429999999	0	false	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	999	0	429999999	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	429999999	0	false	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	0	429999999	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	429999999	0	false	Optional[Invalid[message=Posun -0.0005 kHz vede mimo p\u00E1smo]]
EDGE	-0.0005	0	429999999	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	430000000	0	false	Optional[Qsy[freqHz=430000000]]
EDGE	0	0	430000000	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	430000000	0	false	Optional[Qsy[freqHz=430000000]]
EDGE	+0	0	430000000	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	430000000	0	false	Optional[Qsy[freqHz=430000000]]
EDGE	-0	0	430000000	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	430000000	0	false	Optional[Qsy[freqHz=430001000]]
EDGE	1	0	430000000	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	430000000	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	-1	0	430000000	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	430000000	0	false	Optional[Qsy[freqHz=430001000]]
EDGE	+1	0	430000000	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	430000000	0	false	Optional[OtherVfo[freqHz=430000000]]
EDGE	/0	0	430000000	true	Optional[OtherVfo[freqHz=430000000]]
EDGE	/1	430000000	0	false	Optional[OtherVfo[freqHz=430001000]]
EDGE	/1	0	430000000	true	Optional[OtherVfo[freqHz=430001000]]
EDGE	/+1	430000000	0	false	Optional[OtherVfo[freqHz=430001000]]
EDGE	/+1	0	430000000	true	Optional[OtherVfo[freqHz=430001000]]
EDGE	/-1	430000000	0	false	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	0	430000000	true	Optional[Invalid[message=Posun -1 kHz vede mimo p\u00E1smo]]
EDGE	999	430000000	0	false	Optional[Qsy[freqHz=430999000]]
EDGE	999	0	430000000	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	430000000	0	false	Optional[Qsy[freqHz=430000001]]
EDGE	0.0005	0	430000000	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	430000000	0	false	Optional[Invalid[message=Posun -0.0005 kHz vede mimo p\u00E1smo]]
EDGE	-0.0005	0	430000000	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	440000000	0	false	Optional[Qsy[freqHz=430000000]]
EDGE	0	0	440000000	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	440000000	0	false	Optional[Qsy[freqHz=440000000]]
EDGE	+0	0	440000000	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	440000000	0	false	Optional[Qsy[freqHz=440000000]]
EDGE	-0	0	440000000	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	440000000	0	false	Optional[Qsy[freqHz=430001000]]
EDGE	1	0	440000000	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	440000000	0	false	Optional[Qsy[freqHz=439999000]]
EDGE	-1	0	440000000	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	440000000	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	+1	0	440000000	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	440000000	0	false	Optional[OtherVfo[freqHz=430000000]]
EDGE	/0	0	440000000	true	Optional[OtherVfo[freqHz=430000000]]
EDGE	/1	440000000	0	false	Optional[OtherVfo[freqHz=430001000]]
EDGE	/1	0	440000000	true	Optional[OtherVfo[freqHz=430001000]]
EDGE	/+1	440000000	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/+1	0	440000000	true	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	440000000	0	false	Optional[OtherVfo[freqHz=439999000]]
EDGE	/-1	0	440000000	true	Optional[OtherVfo[freqHz=439999000]]
EDGE	999	440000000	0	false	Optional[Qsy[freqHz=430999000]]
EDGE	999	0	440000000	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	440000000	0	false	Optional[Qsy[freqHz=430000001]]
EDGE	0.0005	0	440000000	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	440000000	0	false	Optional[Qsy[freqHz=439999999]]
EDGE	-0.0005	0	440000000	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	0	440000001	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0	0	440000001	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	+0	440000001	0	false	Optional[Invalid[message=Posun +0 kHz vede mimo p\u00E1smo]]
EDGE	+0	0	440000001	true	Optional[Invalid[message=Posun +0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	-0	440000001	0	false	Optional[Invalid[message=Posun -0 kHz vede mimo p\u00E1smo]]
EDGE	-0	0	440000001	true	Optional[Invalid[message=Posun -0 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	1	440000001	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	1	0	440000001	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-1	440000001	0	false	Optional[Qsy[freqHz=439999001]]
EDGE	-1	0	440000001	true	Optional[Invalid[message=Posun -1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	+1	440000001	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	+1	0	440000001	true	Optional[Invalid[message=Posun +1 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
EDGE	/0	440000001	0	false	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/0	0	440000001	true	Optional[Invalid[message=0 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	440000001	0	false	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/1	0	440000001	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	/+1	440000001	0	false	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/+1	0	440000001	true	Optional[Invalid[message=Posun +1 kHz vede mimo p\u00E1smo]]
EDGE	/-1	440000001	0	false	Optional[OtherVfo[freqHz=439999001]]
EDGE	/-1	0	440000001	true	Optional[OtherVfo[freqHz=439999001]]
EDGE	999	440000001	0	false	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	999	0	440000001	true	Optional[Invalid[message=999 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	440000001	0	false	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	0.0005	0	440000001	true	Optional[Invalid[message=0.0005 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
EDGE	-0.0005	440000001	0	false	Optional[Qsy[freqHz=440000000]]
EDGE	-0.0005	0	440000001	true	Optional[Invalid[message=Posun -0.0005 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
FUZZ	87,-01-2- 0 8.--,8	14074000	0	true	Optional.empty
FUZZ	.4 ,9156 5/	14074000	0	true	Optional.empty
FUZZ	QX39\u00A0XHWI8Y8 	144174000	14030000	true	Optional.empty
FUZZ	32	14074000	0	true	Optional[Split[txFreqHz=14032000]]
FUZZ	\u0663+ 06/-/	14074000	0	true	Optional.empty
FUZZ	EEY\u0663Y9OZ,3SW	14074000	0	false	Optional.empty
FUZZ	D\u00A0/H5IW\u2003-	14074000	0	false	Optional.empty
FUZZ	-/.42/12-02+75/	14074000	0	true	Optional.empty
FUZZ	\u00DF58	144174000	14030000	true	Optional.empty
FUZZ	71B1RG0\u00DFQ4+F\u0663FD	144174000	14030000	true	Optional.empty
FUZZ	 ,P3PQTUHC6++OJ.C	144174000	14030000	true	Optional.empty
FUZZ	51 \u00A0747	144174000	14030000	true	Optional.empty
FUZZ	,/38\u00A00,55-5-,+3177 	144174000	14030000	true	Optional.empty
FUZZ	,..\u00A088 -5+9-60\u00A05	144174000	14030000	true	Optional.empty
FUZZ		14074000	0	false	Optional.empty
FUZZ	JKZT5Y\u00A0222OZ	14074000	0	false	Optional.empty
FUZZ	387	144174000	14030000	true	Optional[Split[txFreqHz=144387000]]
FUZZ	EPR \u00DFWKIESQ-	0	7010000	true	Optional.empty
FUZZ	+\u00A08367\u0663\u00A0+31	14074000	0	true	Optional.empty
FUZZ	758\u00A0.7769,87+,8,248	0	7010000	true	Optional.empty
FUZZ	B05MV	14074000	0	false	Optional.empty
FUZZ	55,060 -++.+ 6/	0	7010000	true	Optional.empty
FUZZ	P73W4.U2V\u2003EGTJH2	0	7010000	true	Optional.empty
FUZZ	60 9164 3\u00A01\u0663\u066321+6	144174000	14030000	true	Optional.empty
FUZZ	.061795	144174000	14030000	true	Optional.empty
FUZZ	8/\u0663.\u00A0\u0663,5/\u0663/\u06631 94	14074000	0	false	Optional.empty
FUZZ	1/,8\u00A00+076883 0 8 +	14074000	0	false	Optional.empty
FUZZ	N5KM\u00A02+CCKI9CS	14074000	0	true	Optional.empty
FUZZ	/969+\u06636643,\u0663+\u06630,/0	14074000	0	false	Optional.empty
FUZZ	606\u00A0\u0663 2 .0\u0663 97+0-20	144174000	14030000	true	Optional.empty
FUZZ	5-/	14074000	0	true	Optional.empty
FUZZ	916	144174000	14030000	true	Optional[Split[txFreqHz=144916000]]
FUZZ	1 6/04-	0	7010000	true	Optional.empty
FUZZ		14074000	0	false	Optional.empty
FUZZ		14074000	0	false	Optional.empty
FUZZ	0\u00A0,+765	14074000	0	true	Optional.empty
FUZZ	\u0663110874/ +9097\u00A025	14074000	0	false	Optional.empty
FUZZ	\u066357.81	144174000	14030000	true	Optional.empty
FUZZ	9\u00DFJWL\u00DF	144174000	14030000	true	Optional.empty
FUZZ	47,,\u0663- - 	144174000	14030000	true	Optional.empty
FUZZ	9	0	7010000	true	Optional[Invalid[message=9 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
FUZZ	8\u00A0 197	14074000	0	true	Optional.empty
FUZZ	48\u066329,	144174000	14030000	true	Optional.empty
FUZZ	-X40-KWNJ\u00DFKT	144174000	14030000	true	Optional.empty
FUZZ	S9	144174000	14030000	true	Optional.empty
FUZZ	2\u0663/	144174000	14030000	true	Optional.empty
FUZZ	B6U7DW47/BSWSB.\u00A0A/	144174000	14030000	true	Optional.empty
FUZZ	67 /\u00A059\u0663/\u0663-2\u0663--0.	0	7010000	true	Optional.empty
FUZZ	.64\u06632.\u0663\u06637\u0663-4 02949	144174000	14030000	true	Optional.empty
FUZZ	/73/7\u00A09,2//,2	14074000	0	false	Optional.empty
FUZZ	3 24,\u0663	144174000	14030000	true	Optional.empty
FUZZ	N\u00DFM86EZF	14074000	0	true	Optional.empty
FUZZ	.530\u00A0\u066346 6780 68.+	14074000	0	true	Optional.empty
FUZZ	Q+UUO4NAD\u0663 IR/SMXL5	14074000	0	false	Optional.empty
FUZZ		14074000	0	false	Optional.empty
FUZZ	49- .08 066	144174000	14030000	true	Optional.empty
FUZZ	 5	0	7010000	true	Optional[Invalid[message=5 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
FUZZ	 \u0663	14074000	0	true	Optional.empty
FUZZ	6-9+6--0+50	14074000	0	true	Optional.empty
FUZZ	+WL	14074000	0	false	Optional.empty
FUZZ	PBWPF39 +DX3QVX6L	144174000	14030000	true	Optional.empty
FUZZ	 2+\u06638.5599,+/ 5\u066384	144174000	14030000	true	Optional.empty
FUZZ	9/+./5,+6\u00A0467622	0	7010000	true	Optional.empty
FUZZ	1	0	7010000	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
FUZZ	+4292203-	144174000	14030000	true	Optional.empty
FUZZ	K\u0663CS7G3	14074000	0	true	Optional.empty
FUZZ	N4Y2I	144174000	14030000	true	Optional.empty
FUZZ		14074000	0	false	Optional.empty
FUZZ	S, Y G	0	7010000	true	Optional.empty
FUZZ	\u066311\u00A091,90/	0	7010000	true	Optional.empty
FUZZ	947\u0663 \u00A022230949.89.6\u00A0	14074000	0	true	Optional.empty
FUZZ	6FHB,H\u00DF+9NPJA07TN4FB	14074000	0	true	Optional.empty
FUZZ	 75+ +.2260,4	14074000	0	false	Optional.empty
FUZZ	5+ \u00A0\u06635991.0\u0663+\u00A0025,	144174000	14030000	true	Optional.empty
FUZZ	\u0663 4\u00A05931\u0663791 \u0663,	144174000	14030000	true	Optional.empty
FUZZ	+5 +	0	7010000	true	Optional.empty
FUZZ	8+,2/566+31 -\u00A0	0	7010000	true	Optional.empty
FUZZ	-,5BUU\u00DF	14074000	0	true	Optional.empty
FUZZ	 91-/3	0	7010000	true	Optional.empty
FUZZ	UO8L/2\u20033	0	7010000	true	Optional.empty
FUZZ	7,5285 4\u00A0-5 .815\u00A0439	14074000	0	true	Optional.empty
FUZZ	2G76H-C,N4-X\u2003VWNMMK	144174000	14030000	true	Optional.empty
FUZZ	1	0	7010000	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
FUZZ	888359,\u00A0711	14074000	0	false	Optional.empty
FUZZ	57.\u00A02-0+\u0663\u066332127	0	7010000	true	Optional.empty
FUZZ	167673	14074000	0	false	Optional[Invalid[message=167673 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
FUZZ		14074000	0	false	Optional.empty
FUZZ	.81654\u00A0	144174000	14030000	true	Optional.empty
FUZZ	9+90/4-	14074000	0	true	Optional.empty
FUZZ	4\u0663,5 1\u00A05/2 3\u0663	14074000	0	true	Optional.empty
FUZZ	\u06632102\u00A0/,28,,,8 +	144174000	14030000	true	Optional.empty
FUZZ	2 -.5,65-.2302.60	14074000	0	true	Optional.empty
FUZZ	3+5	0	7010000	true	Optional.empty
FUZZ	 7	14074000	0	true	Optional[Split[txFreqHz=14007000]]
FUZZ	./YH,J+-	14074000	0	false	Optional.empty
FUZZ	2,\u06635	14074000	0	false	Optional.empty
FUZZ	\u00DFTJ6SG-8E UL	144174000	14030000	true	Optional.empty
FUZZ	03+1\u00A0\u06631+.\u0663416	144174000	14030000	true	Optional.empty
FUZZ	.+,17+	144174000	14030000	true	Optional.empty
FUZZ	5 64AHM.DJ.J\u2003VHE	14074000	0	true	Optional.empty
FUZZ	 ,6\u00A0.6/5\u0663.5\u00A048.	14074000	0	false	Optional.empty
FUZZ	/09.5T -H9ZGFM\u0663	14074000	0	false	Optional.empty
FUZZ	549+\u00A030+324. ,/	14074000	0	true	Optional.empty
FUZZ	-3-16-4,84-7 78,\u00A0	144174000	14030000	true	Optional.empty
FUZZ	 .4.	14074000	0	false	Optional.empty
FUZZ	8,\u2003081G+79, I+VHFJJ\u0663	0	7010000	true	Optional.empty
FUZZ		14074000	0	false	Optional.empty
FUZZ	\u00A0F,9+Q8Y80OPR1	144174000	14030000	true	Optional.empty
FUZZ	0,733886,6120\u00A0\u00A03	0	7010000	true	Optional.empty
FUZZ	621,04/+1\u06636	0	7010000	true	Optional.empty
FUZZ	\u0663403	14074000	0	false	Optional.empty
FUZZ	21169/+	0	7010000	true	Optional.empty
FUZZ	900.99+\u00A04\u00A080,/	0	7010000	true	Optional.empty
FUZZ	\u0663RZFOTQ6Y725	144174000	14030000	true	Optional.empty
FUZZ	 9,9+9,64+	0	7010000	true	Optional.empty
FUZZ	+989/509-\u06633	14074000	0	true	Optional.empty
FUZZ	35.\u06632 81\u00A0\u00A0.54,8 20\u00A0	0	7010000	true	Optional.empty
FUZZ	,3	14074000	0	true	Optional.empty
FUZZ	CUX7\u00DFZOY \u00A0R	14074000	0	false	Optional.empty
FUZZ	1,-\u00A05-\u0663-	14074000	0	false	Optional.empty
FUZZ	2	144174000	14030000	true	Optional[Split[txFreqHz=144002000]]
FUZZ	C4IY.D7NZDXK3	14074000	0	false	Optional.empty
FUZZ	2+5 4738046	144174000	14030000	true	Optional.empty
FUZZ	9-	14074000	0	false	Optional.empty
FUZZ	+ 9	14074000	0	false	Optional.empty
FUZZ	8,4+	14074000	0	true	Optional.empty
FUZZ	67,70-3346/	14074000	0	false	Optional.empty
FUZZ	536\u06638	0	7010000	true	Optional.empty
FUZZ	12\u00A045/98	144174000	14030000	true	Optional.empty
FUZZ	J-BP4R	14074000	0	true	Optional.empty
FUZZ		14074000	0	false	Optional.empty
FUZZ	0+\u00A0.30 ,754624.	144174000	14030000	true	Optional.empty
FUZZ	6	144174000	14030000	true	Optional[Split[txFreqHz=144006000]]
FUZZ	\u00A0E53/MMZ EUHD3C\u2003	0	7010000	true	Optional.empty
FUZZ	8.602/656	144174000	14030000	true	Optional.empty
FUZZ	DG4FITQO9.U5LQ	14074000	0	false	Optional.empty
FUZZ	48/9+078\u00A0. 	144174000	14030000	true	Optional.empty
FUZZ	5/-\u00A0379/670 \u00A0581	144174000	14030000	true	Optional.empty
FUZZ	\u00DF66-X4	144174000	14030000	true	Optional.empty
FUZZ	.2++3 ,\u00A0/.75-46, 	0	7010000	true	Optional.empty
FUZZ	7\u0663+841,.6-.3,\u066353	0	7010000	true	Optional.empty
FUZZ	\u0663-05/4\u066349+	14074000	0	true	Optional.empty
FUZZ	32 698-6/0\u0663\u00A06	14074000	0	true	Optional.empty
FUZZ	33	14074000	0	false	Optional[Qsy[freqHz=14033000]]
FUZZ	5UM4\u2003C	14074000	0	true	Optional.empty
FUZZ	86\u0663/.-1+,835-,\u00A09\u00A0	14074000	0	true	Optional.empty
FUZZ	+1148	14074000	0	true	Optional[Invalid[message=Posun +1148 kHz vede mimo p\u00E1smo]]
FUZZ		14074000	0	false	Optional.empty
FUZZ	98+3	14074000	0	true	Optional.empty
FUZZ	/+ 2285 .47315,8+-	14074000	0	true	Optional.empty
FUZZ	4\u00A08\u06635\u00A0\u06637	144174000	14030000	true	Optional.empty
FUZZ	5	0	7010000	true	Optional[Invalid[message=5 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
FUZZ	784402..923	14074000	0	true	Optional.empty
FUZZ	0\u00A0	14074000	0	false	Optional.empty
FUZZ	76/2\u00A09.0\u00A04	0	7010000	true	Optional.empty
FUZZ	1.76-5,027+\u0663+68	14074000	0	false	Optional.empty
FUZZ	4958	14074000	0	false	Optional[Invalid[message=4958 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
FUZZ	8-033,\u00A0\u00A09\u00A0.05//-.1/1	14074000	0	true	Optional.empty
FUZZ	M4QIM-FO9LP/\u00A0\u00DFOG0Q	144174000	14030000	true	Optional.empty
FUZZ	/0465	144174000	14030000	true	Optional[Invalid[message=0465 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
FUZZ	.  3,/-\u0663.5 ,6	0	7010000	true	Optional.empty
FUZZ		14074000	0	false	Optional.empty
FUZZ	NDRM70USPQ/EDI4H\u00A03	14074000	0	true	Optional.empty
FUZZ	-+45.+\u0663/54 	0	7010000	true	Optional.empty
FUZZ	06/41	144174000	14030000	true	Optional.empty
FUZZ	0\u06638 	14074000	0	true	Optional.empty
FUZZ	5QDSYWA	14074000	0	false	Optional.empty
FUZZ	5,0+1/49	0	7010000	true	Optional.empty
FUZZ	41\u00A075767+01/0//6	14074000	0	false	Optional.empty
FUZZ	,X2G-\u2003P\u00DFBIE\u2003H-A	0	7010000	true	Optional.empty
FUZZ	\u00A0/12 3. 5	14074000	0	false	Optional.empty
FUZZ	\u2003BDQ\u2003I9E7GN/	14074000	0	true	Optional.empty
FUZZ	O49	14074000	0	false	Optional.empty
FUZZ	-I\u0663	14074000	0	true	Optional.empty
FUZZ	X/LNK18 ,	0	7010000	true	Optional.empty
FUZZ	96/48\u066374,8	144174000	14030000	true	Optional.empty
FUZZ	680+	0	7010000	true	Optional.empty
FUZZ	996-4	0	7010000	true	Optional.empty
FUZZ	/7P8X	14074000	0	false	Optional.empty
FUZZ	RI	14074000	0	true	Optional.empty
FUZZ	6 6	14074000	0	false	Optional.empty
FUZZ	PQ2U,B+CXM+VTI-SOU6	14074000	0	true	Optional.empty
FUZZ	140759.\u00A06	144174000	14030000	true	Optional.empty
FUZZ	- 3 	14074000	0	false	Optional.empty
FUZZ	0LZ BG,08\u2003VH/Q\u00DFSZVY2	14074000	0	true	Optional.empty
FUZZ	679\u0663.115\u06634\u066372	14074000	0	true	Optional.empty
FUZZ	5,	14074000	0	true	Optional.empty
FUZZ	 17 +2+739 .-51	14074000	0	false	Optional.empty
FUZZ	D38AHZZ8M8NO\u00DFP	0	7010000	true	Optional.empty
FUZZ	7\u00DFTJGJZ 4EBQ+.S+W	0	7010000	true	Optional.empty
FUZZ	\u00A0	14074000	0	false	Optional.empty
FUZZ	3\u0663\u0663,+./686.	0	7010000	true	Optional.empty
FUZZ	0\u0663215\u00A0/7,1	144174000	14030000	true	Optional.empty
FUZZ	36738274	144174000	14030000	true	Optional[Invalid[message=36738274 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
FUZZ	71-9+/4130 -4.10019+	0	7010000	true	Optional.empty
FUZZ		14074000	0	false	Optional.empty
FUZZ		14074000	0	false	Optional.empty
FUZZ	\u0663+2.2 -9 1	14074000	0	true	Optional.empty
FUZZ	3249+7\u0663\u06632.13./744/2	14074000	0	true	Optional.empty
FUZZ	2344328.+,--	14074000	0	true	Optional.empty
FUZZ	EJBP9NLJ9GV6C8	0	7010000	true	Optional.empty
FUZZ		14074000	0	false	Optional.empty
FUZZ	48+3	14074000	0	false	Optional.empty
FUZZ	CYEY/KMZTAD2-	14074000	0	true	Optional.empty
FUZZ	X1IZY1 Y-C4F1YS	14074000	0	false	Optional.empty
FUZZ	0 \u00DF\u2003ZU0\u0663I-OUE\u00A0+NP	144174000	14030000	true	Optional.empty
FUZZ	8FZ\u0663VR0-A-N	144174000	14030000	true	Optional.empty
FUZZ	3..\u00A05+7\u0663-	144174000	14030000	true	Optional.empty
FUZZ	\u0663	14074000	0	true	Optional.empty
FUZZ	MN4D	0	7010000	true	Optional.empty
FUZZ	\u06632\u0663 5,	14074000	0	true	Optional.empty
FUZZ	+2,41,+88	0	7010000	true	Optional.empty
FUZZ	9	0	7010000	true	Optional[Invalid[message=9 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
FUZZ	0 4/+8.05\u06635,\u00A04 ,7. 	144174000	14030000	true	Optional.empty
FUZZ	-36/12 59+8075	0	7010000	true	Optional.empty
FUZZ	\u00A04,8-,\u00A0\u00A07\u066308	14074000	0	true	Optional.empty
FUZZ		14074000	0	false	Optional.empty
FUZZ	N-OS+K2US,BO4	14074000	0	false	Optional.empty
FUZZ	3,ZM8H 0\u2003XQRHO	0	7010000	true	Optional.empty
FUZZ	7/53.7	14074000	0	true	Optional.empty
FUZZ		14074000	0	false	Optional.empty
FUZZ	-042-/22.91 0/\u00A092	0	7010000	true	Optional.empty
FUZZ	.U	14074000	0	true	Optional.empty
FUZZ	-4ZMNV5+-Y	14074000	0	false	Optional.empty
FUZZ	2PZM	0	7010000	true	Optional.empty
FUZZ	 +2+.2948	0	7010000	true	Optional.empty
FUZZ	\u06639142-	14074000	0	false	Optional.empty
FUZZ	85	0	7010000	true	Optional[Invalid[message=85 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
FUZZ	6\u066317/-6	0	7010000	true	Optional.empty
FUZZ	,3-3/-00260\u06636-	0	7010000	true	Optional.empty
FUZZ	63 \u066338	0	7010000	true	Optional.empty
FUZZ	JI3C.\u0663T43\u0663QBHU	144174000	14030000	true	Optional.empty
FUZZ	-5\u0663+29,72	14074000	0	false	Optional.empty
FUZZ	 -	0	7010000	true	Optional.empty
FUZZ	+,J7\u2003N\u00DF	144174000	14030000	true	Optional.empty
FUZZ	1,\u0663//+1	144174000	14030000	true	Optional.empty
FUZZ	,	14074000	0	false	Optional.empty
FUZZ	\u00A05	0	7010000	true	Optional.empty
FUZZ	5\u00A07,0-\u0663+\u066351/ 	14074000	0	true	Optional.empty
FUZZ	T	14074000	0	false	Optional.empty
FUZZ	0	14074000	0	false	Optional[Qsy[freqHz=14000000]]
FUZZ	\u0663/-.907,408	14074000	0	true	Optional.empty
FUZZ	64,	144174000	14030000	true	Optional.empty
FUZZ	8\u0663,--\u00A0  \u00A0\u00A0+\u066349	14074000	0	false	Optional.empty
FUZZ	0	14074000	0	false	Optional[Qsy[freqHz=14000000]]
FUZZ	995\u066305+7 \u0663/882-4	14074000	0	false	Optional.empty
FUZZ	4V.,3\u0663M8	14074000	0	true	Optional.empty
FUZZ	2\u00A03.30 \u00A07\u00A094\u066354	14074000	0	false	Optional.empty
FUZZ		14074000	0	false	Optional.empty
FUZZ	2180\u00A033	0	7010000	true	Optional.empty
FUZZ	PORG 4ZH0J.	144174000	14030000	true	Optional.empty
FUZZ	, 15	14074000	0	false	Optional.empty
FUZZ	GW,P9LV9FBE	14074000	0	true	Optional.empty
FUZZ	K\u00DFC.MI/	14074000	0	false	Optional.empty
FUZZ	08	14074000	0	false	Optional[Qsy[freqHz=14008000]]
FUZZ	81-5	0	7010000	true	Optional.empty
FUZZ	164 3,57344985	14074000	0	true	Optional.empty
FUZZ	/6722-\u00A0-0/	0	7010000	true	Optional.empty
FUZZ	-9\u06630982\u00A03\u0663.-+	144174000	14030000	true	Optional.empty
FUZZ	3\u00A0,	14074000	0	true	Optional.empty
FUZZ	\u00A06/9	14074000	0	false	Optional.empty
FUZZ	OI\u2003J+P9\u00DFL	14074000	0	false	Optional.empty
FUZZ	75 775	14074000	0	true	Optional.empty
FUZZ	011-314-511-0028.2+	0	7010000	true	Optional.empty
FUZZ	+1,\u06637,731\u00A07-59,702 	14074000	0	false	Optional.empty
FUZZ	\u0663828\u0663-0 9542 19.,2 9	14074000	0	false	Optional.empty
FUZZ	,-5+/+.	14074000	0	true	Optional.empty
FUZZ	/4S	144174000	14030000	true	Optional.empty
FUZZ	8XF3\u0663UG8ITJ	14074000	0	true	Optional.empty
FUZZ	4,626+38-25	144174000	14030000	true	Optional.empty
FUZZ	5781 793,6,	144174000	14030000	true	Optional.empty
FUZZ	3C9WUO,-4	14074000	0	true	Optional.empty
FUZZ	EKV0	14074000	0	false	Optional.empty
FUZZ	+38\u06635-1,\u066355029	144174000	14030000	true	Optional.empty
FUZZ	+\u0663 506	14074000	0	true	Optional.empty
FUZZ	92+.46/-35	144174000	14030000	true	Optional.empty
FUZZ		14074000	0	false	Optional.empty
FUZZ	541.504818.795\u00A03663\u0663	144174000	14030000	true	Optional.empty
FUZZ	37	14074000	0	false	Optional[Qsy[freqHz=14037000]]
FUZZ	SAJ-3 Z.JL8OMVE	0	7010000	true	Optional.empty
FUZZ		14074000	0	false	Optional.empty
FUZZ	//.2+37-9	14074000	0	true	Optional.empty
FUZZ	90,.+./18610\u066320+	0	7010000	true	Optional.empty
FUZZ	4\u06631950.6.\u066327	14074000	0	false	Optional.empty
FUZZ	+ 15	0	7010000	true	Optional.empty
FUZZ	\u00A08/ 662	0	7010000	true	Optional.empty
FUZZ	 59	14074000	0	false	Optional[Qsy[freqHz=14059000]]
FUZZ	\u06635,5 4 \u0663 6\u00A09\u00A0/1\u00A0 	0	7010000	true	Optional.empty
FUZZ	2.4-4425	14074000	0	false	Optional.empty
FUZZ	/\u00A088719, +\u00A041/  /	14074000	0	false	Optional.empty
FUZZ	-3/1.\u00A0	144174000	14030000	true	Optional.empty
FUZZ	-	0	7010000	true	Optional.empty
FUZZ	146690481	14074000	0	true	Optional[Invalid[message=146690481 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
FUZZ	\u06635,.31-2\u0663./4440/27.	14074000	0	true	Optional.empty
FUZZ	+\u00A060\u00A0 8+34\u0663 1\u0663	144174000	14030000	true	Optional.empty
FUZZ	76721---9	14074000	0	true	Optional.empty
FUZZ	,0	14074000	0	false	Optional.empty
FUZZ	QKP\u00A0IYO5HN\u00A06P	14074000	0	false	Optional.empty
FUZZ	BIE+GF1\u2003Y1CYBY	14074000	0	true	Optional.empty
FUZZ	2 	144174000	14030000	true	Optional[Split[txFreqHz=144002000]]
FUZZ	F1N7QFV	0	7010000	true	Optional.empty
FUZZ	I23-H7R\u00A0OLT5,6+VE/\u00DF	144174000	14030000	true	Optional.empty
FUZZ	7/+/	14074000	0	false	Optional.empty
FUZZ	\u00A0,\u06633\u00A02\u0663/	144174000	14030000	true	Optional.empty
FUZZ	++676668	14074000	0	true	Optional.empty
FUZZ	CJI\u0663N7-A/-.KO-P/O-6	144174000	14030000	true	Optional.empty
FUZZ	/FL\u00A0X+\u2003Z6DC	14074000	0	false	Optional.empty
FUZZ	+	14074000	0	true	Optional.empty
FUZZ	32882+6	144174000	14030000	true	Optional.empty
FUZZ	PXZSL3P.4ZRPMTNNOM	14074000	0	true	Optional.empty
FUZZ	7ZFZ\u00DFK.MOIJFS,-JT2UW	144174000	14030000	true	Optional.empty
FUZZ	2\u00A0-9839\u00A0/0	0	7010000	true	Optional.empty
FUZZ	.UCF9CR6-	0	7010000	true	Optional.empty
FUZZ	6ODEKYKDX7.3J	0	7010000	true	Optional.empty
FUZZ	,V\u00DF,	14074000	0	true	Optional.empty
FUZZ		14074000	0	false	Optional.empty
FUZZ	5\u06634244	14074000	0	false	Optional.empty
FUZZ	5-PX	14074000	0	false	Optional.empty
FUZZ	,YC4D7HSZ9XVZA+7,I	0	7010000	true	Optional.empty
FUZZ		14074000	0	false	Optional.empty
FUZZ	39/EF \u0663\u2003\u00DFJBLS\u00A0K.I4, 	144174000	14030000	true	Optional.empty
FUZZ	\u00A09\u00A02+\u0663\u0663\u06636.,+ 864,/+	14074000	0	false	Optional.empty
FUZZ	 \u00A0\u00A08\u00A0+2	14074000	0	true	Optional.empty
FUZZ	6,51--9\u00A09\u00A0  	14074000	0	false	Optional.empty
FUZZ	3-\u066377\u00A010,2+0	0	7010000	true	Optional.empty
FUZZ	M.,9Z8WB/\u00A07UAZW6JS	14074000	0	true	Optional.empty
FUZZ	1\u00A07\u00A05012+47\u06631	14074000	0	false	Optional.empty
FUZZ	9+U/,VMFQKQ	14074000	0	false	Optional.empty
FUZZ	.6\u0663	14074000	0	true	Optional.empty
FUZZ	777	14074000	0	true	Optional[Invalid[message=777 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
FUZZ	,33+989-781	144174000	14030000	true	Optional.empty
FUZZ	90\u0663480	14074000	0	false	Optional.empty
FUZZ	\u00A03\u0663-475,\u066357 , 7	0	7010000	true	Optional.empty
FUZZ	-0\u00A08,5	14074000	0	false	Optional.empty
FUZZ	24..,+7..96-50,04,8	14074000	0	true	Optional.empty
FUZZ	\u00A08R\u06637NFF\u00DFX	0	7010000	true	Optional.empty
FUZZ	2	144174000	14030000	true	Optional[Split[txFreqHz=144002000]]
FUZZ	Z3V	0	7010000	true	Optional.empty
FUZZ	 	14074000	0	false	Optional.empty
FUZZ	U,E,N\u00DFEB,K-WUZ\u2003	0	7010000	true	Optional.empty
FUZZ	.5  /.\u066339852	144174000	14030000	true	Optional.empty
FUZZ	\u06638+,52.934	14074000	0	true	Optional.empty
FUZZ		14074000	0	false	Optional.empty
FUZZ	94PN+6KMZ+QUZV/X/0B	0	7010000	true	Optional.empty
FUZZ	ISK	0	7010000	true	Optional.empty
FUZZ	. /	0	7010000	true	Optional.empty
FUZZ	RAO	14074000	0	false	Optional.empty
FUZZ	3+ 02.3	14074000	0	true	Optional.empty
FUZZ	-4	14074000	0	true	Optional[Split[txFreqHz=14070000]]
FUZZ	-Q68F74CSWDZMJ81R6PL	144174000	14030000	true	Optional.empty
FUZZ	P	14074000	0	false	Optional.empty
FUZZ	5.039-6/68- 082	14074000	0	false	Optional.empty
FUZZ	8/AA67PYHQFZ3HTMB	144174000	14030000	true	Optional.empty
FUZZ	R/K\u200350W4/F783	144174000	14030000	true	Optional.empty
FUZZ	UW MUC	0	7010000	true	Optional.empty
FUZZ	 8+\u0663-6.471\u00A09706292/-	144174000	14030000	true	Optional.empty
FUZZ	Q\u2003DH\u2003ALY83Z	144174000	14030000	true	Optional.empty
FUZZ		14074000	0	false	Optional.empty
FUZZ	\u00A06	144174000	14030000	true	Optional.empty
FUZZ	868\u0663	0	7010000	true	Optional.empty
FUZZ	D56RP.ASK5A168\u2003	144174000	14030000	true	Optional.empty
FUZZ	.0BJD6\u2003T	0	7010000	true	Optional.empty
FUZZ	 .,588	14074000	0	true	Optional.empty
FUZZ	-+,.\u00A0920.\u00A032425	14074000	0	true	Optional.empty
FUZZ	- 	14074000	0	true	Optional.empty
FUZZ	64\u00A036	0	7010000	true	Optional.empty
FUZZ	3  ,5,4	14074000	0	false	Optional.empty
FUZZ	+,	0	7010000	true	Optional.empty
FUZZ	L5 	14074000	0	true	Optional.empty
FUZZ	TB0AWV--SZB-G-	144174000	14030000	true	Optional.empty
FUZZ	B.3,4Q	144174000	14030000	true	Optional.empty
FUZZ	6539 44.8+	144174000	14030000	true	Optional.empty
FUZZ	 41 710\u00A0,\u00A0	0	7010000	true	Optional.empty
FUZZ	3 8	14074000	0	true	Optional.empty
FUZZ	\u0663 5ES03D0P BO,AG\u2003Z\u0663	14074000	0	false	Optional.empty
FUZZ		14074000	0	false	Optional.empty
FUZZ	\u00A0\u00A061/53\u00A09,2-+\u00A0036\u0663	0	7010000	true	Optional.empty
FUZZ	.36ZVVJ2,5.\u00A02MUONZ	0	7010000	true	Optional.empty
FUZZ	609.4-684	144174000	14030000	true	Optional.empty
FUZZ	01258+0.	0	7010000	true	Optional.empty
FUZZ	\u00DF	14074000	0	true	Optional.empty
FUZZ	1+ 2\u0663\u0663/04 887\u00A031-\u06638	144174000	14030000	true	Optional.empty
FUZZ	TGV	14074000	0	true	Optional.empty
FUZZ	\u06639,/182\u00A0/3+58\u00A003	14074000	0	true	Optional.empty
FUZZ	4-+,2/7\u00A075+0-8-6/19	14074000	0	false	Optional.empty
FUZZ	5 592738/-343.3,\u00A08\u0663	14074000	0	true	Optional.empty
FUZZ	G.\u00DFS\u0663K00O,T-GU	14074000	0	true	Optional.empty
FUZZ	 4+.40\u00A07 41744	14074000	0	false	Optional.empty
FUZZ	N0SL1P\u0663	0	7010000	true	Optional.empty
FUZZ	M\u2003UI6YDH\u0663\u00A0.K	14074000	0	true	Optional.empty
FUZZ	5/-\u066347-	144174000	14030000	true	Optional.empty
FUZZ	3DMTJGU6	144174000	14030000	true	Optional.empty
FUZZ	\u066313118/5+/824	0	7010000	true	Optional.empty
FUZZ	5/192924\u00A0+	144174000	14030000	true	Optional.empty
FUZZ	300-+9\u0663792\u00A0	14074000	0	true	Optional.empty
FUZZ	11	14074000	0	false	Optional[Qsy[freqHz=14011000]]
FUZZ	HAB-HK\u0663H	14074000	0	false	Optional.empty
FUZZ	8\u0663 \u0663\u00A0-7	14074000	0	false	Optional.empty
FUZZ		14074000	0	false	Optional.empty
FUZZ	.8/3/6438/91 /62	144174000	14030000	true	Optional.empty
FUZZ	04	14074000	0	false	Optional[Qsy[freqHz=14004000]]
FUZZ	4\u0663,+8 9\u00A082\u00A08.24-	14074000	0	false	Optional.empty
FUZZ	07-1-61482...8/7	14074000	0	true	Optional.empty
FUZZ	4	14074000	0	false	Optional[Qsy[freqHz=14004000]]
FUZZ	-\u2003518CRX\u0663ZAKXLB2,0D0	14074000	0	false	Optional.empty
FUZZ	4-3/.8\u00A04\u0663-,032  3\u00A0,4	0	7010000	true	Optional.empty
FUZZ	8 2Q/CXQ4APO	14074000	0	false	Optional.empty
FUZZ	M0YW+R,2	144174000	14030000	true	Optional.empty
FUZZ	7-434/8\u06633\u00A0	14074000	0	false	Optional.empty
FUZZ	QF+1TD\u00A0IFV\u0663ISKR	14074000	0	false	Optional.empty
FUZZ	KI1E	144174000	14030000	true	Optional.empty
FUZZ	\u2003SU CTDVDV8JTJEWZ	14074000	0	false	Optional.empty
FUZZ	,3\u0663+635- -2 5\u00A0/5	14074000	0	false	Optional.empty
FUZZ	9W	144174000	14030000	true	Optional.empty
FUZZ	/D4N.\u0663-7\u0663K	144174000	14030000	true	Optional.empty
FUZZ	53+1 2+5503,	14074000	0	false	Optional.empty
FUZZ	 ,8/	14074000	0	true	Optional.empty
FUZZ	.DC9N1.FWZO	0	7010000	true	Optional.empty
FUZZ	\u00A0+2/4906\u00A083	14074000	0	false	Optional.empty
FUZZ	0,-.7813/,1/.278	14074000	0	false	Optional.empty
FUZZ	11-+\u0663\u00A06.268	0	7010000	true	Optional.empty
FUZZ	.\u0663+ /-+0	0	7010000	true	Optional.empty
FUZZ	Y\u20034+K	144174000	14030000	true	Optional.empty
FUZZ	94 6/4-+4,440+7	14074000	0	false	Optional.empty
FUZZ	--4.\u06632+83 1 61,	14074000	0	true	Optional.empty
FUZZ	+,2763/36618\u06631.\u00A03 \u06638	14074000	0	false	Optional.empty
FUZZ	5\u00A0\u00A0,\u066357-18,2	14074000	0	false	Optional.empty
FUZZ	\u00A03+7+	14074000	0	false	Optional.empty
FUZZ	1\u06635	14074000	0	true	Optional.empty
FUZZ	3.942\u00A01 5	144174000	14030000	true	Optional.empty
FUZZ	-7/65366,.15/\u00A08\u00A050	0	7010000	true	Optional.empty
FUZZ	DHJMTMYI	14074000	0	false	Optional.empty
FUZZ	+6.---4-65,+9	14074000	0	false	Optional.empty
FUZZ	5.69,254-2+8/3	14074000	0	true	Optional.empty
FUZZ	09390 -.502\u00A02	0	7010000	true	Optional.empty
FUZZ	-.	0	7010000	true	Optional.empty
FUZZ	72	14074000	0	true	Optional[Split[txFreqHz=14072000]]
FUZZ	48,,19-96\u00A0-35\u0663 69	0	7010000	true	Optional.empty
FUZZ	VP0ORCOAB	144174000	14030000	true	Optional.empty
FUZZ	GS4UT0PDHG2LK4I2N 	144174000	14030000	true	Optional.empty
FUZZ	43257+3,+	14074000	0	false	Optional.empty
FUZZ	/	14074000	0	true	Optional.empty
FUZZ	XP	14074000	0	false	Optional.empty
FUZZ	46\u00A0,7	0	7010000	true	Optional.empty
FUZZ	776-3.+96\u00A04\u00A034701	0	7010000	true	Optional.empty
FUZZ	\u00A0\u0663/+,,7 76160\u06632.83	144174000	14030000	true	Optional.empty
FUZZ	38-.3404 46	14074000	0	true	Optional.empty
FUZZ	7/,\u00A01370100\u00A0-	14074000	0	true	Optional.empty
FUZZ	0	14074000	0	false	Optional[Qsy[freqHz=14000000]]
FUZZ	1UH	14074000	0	false	Optional.empty
FUZZ	4,4/32 	144174000	14030000	true	Optional.empty
FUZZ	J1-6,.X/+7A1MCV+.	144174000	14030000	true	Optional.empty
FUZZ	090\u00A072/4	0	7010000	true	Optional.empty
FUZZ	1\u0663-	14074000	0	true	Optional.empty
FUZZ	41-	14074000	0	false	Optional.empty
FUZZ	9/9319	14074000	0	false	Optional.empty
FUZZ	0639- \u00A084	0	7010000	true	Optional.empty
FUZZ	F96HN82G/PY	14074000	0	false	Optional.empty
FUZZ	/\u0663,+,9.	144174000	14030000	true	Optional.empty
FUZZ	.,\u00A0\u066317//\u06637.8	0	7010000	true	Optional.empty
FUZZ		14074000	0	false	Optional.empty
FUZZ	O6\u0663. 9 RBUTX\u00A0L	14074000	0	false	Optional.empty
FUZZ	.- 640+9/27+\u0663570-24	144174000	14030000	true	Optional.empty
FUZZ	3+5073	14074000	0	true	Optional.empty
FUZZ	43-8+5+	14074000	0	true	Optional.empty
FUZZ	4,456\u00A0.4\u00A076+49+\u066381/	14074000	0	false	Optional.empty
FUZZ	6 ,	144174000	14030000	true	Optional.empty
FUZZ	7\u0663,5-.4-92177-5 	14074000	0	true	Optional.empty
FUZZ	.12	14074000	0	true	Optional.empty
FUZZ	\u00A099\u0663+6	144174000	14030000	true	Optional.empty
FUZZ	158+-7.	0	7010000	true	Optional.empty
FUZZ	\u00A0271.,,-+9\u00A02-0-3,\u00A0	14074000	0	false	Optional.empty
FUZZ	 IU3KL\u00A0GH.1R1H,6 	0	7010000	true	Optional.empty
FUZZ	-,638077951-.4\u0663758.	0	7010000	true	Optional.empty
FUZZ	+4/8876.0/1.\u00A01+-	14074000	0	false	Optional.empty
FUZZ	   2	144174000	14030000	true	Optional[Split[txFreqHz=144002000]]
FUZZ	15\u0663+\u0663+\u0663-9\u0663	14074000	0	false	Optional.empty
FUZZ	1\u00DFCNO	144174000	14030000	true	Optional.empty
FUZZ	2B\u00A0MP.M/IL72KCU370M	14074000	0	true	Optional.empty
FUZZ	-+,/46 ,758	14074000	0	true	Optional.empty
FUZZ	4-520+ +,	14074000	0	false	Optional.empty
FUZZ	JP+\u2003F02A1A23OW W.Y	144174000	14030000	true	Optional.empty
FUZZ	QPX-HEY	14074000	0	false	Optional.empty
FUZZ		14074000	0	false	Optional.empty
FUZZ	9-.8\u066314\u0663374910353\u00A017	14074000	0	false	Optional.empty
FUZZ	X\u00A0O/EN	0	7010000	true	Optional.empty
FUZZ	S+,I9S	14074000	0	true	Optional.empty
FUZZ		14074000	0	false	Optional.empty
FUZZ	2+69..53 4 ,,,3	0	7010000	true	Optional.empty
FUZZ	DV\u2003T2AYP	0	7010000	true	Optional.empty
FUZZ	78\u00A0,1408	14074000	0	false	Optional.empty
FUZZ	5-5+5,-	14074000	0	false	Optional.empty
FUZZ	+	14074000	0	true	Optional.empty
FUZZ	,SDY1HRNT794,C	14074000	0	false	Optional.empty
FUZZ	 40128255\u0663-/+6-/	14074000	0	true	Optional.empty
FUZZ	64+5,-\u06630	144174000	14030000	true	Optional.empty
FUZZ	K\u0663	14074000	0	false	Optional.empty
FUZZ	33\u00A0, \u00A0/,90+8/,768+46	144174000	14030000	true	Optional.empty
FUZZ	42//4165,3.+	144174000	14030000	true	Optional.empty
FUZZ	971./22+.030++	144174000	14030000	true	Optional.empty
FUZZ	L\u00A068YGNLXV8.R.Q\u00DFFIK	14074000	0	false	Optional.empty
FUZZ	69/+3 	14074000	0	false	Optional.empty
FUZZ		14074000	0	false	Optional.empty
FUZZ	\u066370/.6\u00A04,5+23+ \u00A09	144174000	14030000	true	Optional.empty
FUZZ	BQ3N3HIDC	0	7010000	true	Optional.empty
FUZZ	0 2 5+ 9//2/+0+0182,	0	7010000	true	Optional.empty
FUZZ	VS3R	14074000	0	false	Optional.empty
FUZZ	1K\u2003\u00A0TFS\u00DF-4\u2003.MSD8	0	7010000	true	Optional.empty
FUZZ	7.93.31+83\u00A0/6-6	0	7010000	true	Optional.empty
FUZZ	CE\u00A0ZQ8-\u00DFO+0 + F+.Y\u2003	0	7010000	true	Optional.empty
FUZZ		14074000	0	false	Optional.empty
FUZZ	3971\u0663	14074000	0	true	Optional.empty
FUZZ	Y	0	7010000	true	Optional.empty
FUZZ	1CH \u2003FEF\u00A0 F+/	14074000	0	false	Optional.empty
FUZZ	1\u066390/174 3+60\u0663	0	7010000	true	Optional.empty
FUZZ		14074000	0	false	Optional.empty
FUZZ	2	144174000	14030000	true	Optional[Split[txFreqHz=144002000]]
FUZZ	..4/ \u06638+7+\u00A0+6/ 4\u0663	144174000	14030000	true	Optional.empty
FUZZ	6/0- 54.-/348997.\u00A017	14074000	0	true	Optional.empty
FUZZ	-2.-/	14074000	0	true	Optional.empty
FUZZ	EW82V	144174000	14030000	true	Optional.empty
FUZZ	JM//AO6A6GC9I	144174000	14030000	true	Optional.empty
FUZZ	 3LOKSB2X7Q	14074000	0	false	Optional.empty
FUZZ	KII+Q5HUC\u00A0P-/B7\u00A0 I0	14074000	0	false	Optional.empty
FUZZ	39.-3\u0663512 6-	144174000	14030000	true	Optional.empty
FUZZ	 16  2,18	144174000	14030000	true	Optional.empty
FUZZ	BJW	14074000	0	true	Optional.empty
FUZZ	863430 78,4 30.	144174000	14030000	true	Optional.empty
FUZZ	\u00A0297\u0663492,601+6/90	144174000	14030000	true	Optional.empty
FUZZ	\u06635 7906..20-\u06637 \u0663	14074000	0	false	Optional.empty
FUZZ	512\u06633\u00A0.	14074000	0	false	Optional.empty
FUZZ	\u20039PVXRHY8	0	7010000	true	Optional.empty
FUZZ	68	144174000	14030000	true	Optional[Split[txFreqHz=144068000]]
FUZZ	1 +439388+\u00A0+1 	14074000	0	false	Optional.empty
FUZZ	\u06634+9.9 --85-+/\u06639\u06637	14074000	0	false	Optional.empty
FUZZ	39.50,536.56/	14074000	0	true	Optional.empty
FUZZ	AI9.QB	144174000	14030000	true	Optional.empty
FUZZ	,86/12	144174000	14030000	true	Optional.empty
FUZZ	90	14074000	0	true	Optional[Split[txFreqHz=14090000]]
FUZZ	42+ \u00A05 \u00A07 4	14074000	0	true	Optional.empty
FUZZ	RH+QG-Z\u00DFQQ	14074000	0	true	Optional.empty
FUZZ	745/409\u00A02\u00A0\u0663\u00A0 61	144174000	14030000	true	Optional.empty
FUZZ	Q 0+3N	0	7010000	true	Optional.empty
FUZZ	\u06637861.2 \u0663/05\u0663 \u00A05.,14	0	7010000	true	Optional.empty
FUZZ	/47\u06631851+\u00A071+63	0	7010000	true	Optional.empty
FUZZ	1 ,.4./2-.415 1	144174000	14030000	true	Optional.empty
FUZZ	AGHZ864NI	0	7010000	true	Optional.empty
FUZZ	+\u00A0 .,.,5--6741366 2	0	7010000	true	Optional.empty
FUZZ	5SM3UMQHGN3M\u00A0X\u20035Z	14074000	0	false	Optional.empty
FUZZ		14074000	0	false	Optional.empty
FUZZ	 6\u00A0/9+55,04 /, 177	0	7010000	true	Optional.empty
FUZZ	E3DQ.4WNZ\u2003	0	7010000	true	Optional.empty
FUZZ	-\u00A0\u06634547,	14074000	0	false	Optional.empty
FUZZ	437,5\u00A0-5872\u0663\u0663892 	14074000	0	true	Optional.empty
FUZZ	5\u00A0	14074000	0	true	Optional.empty
FUZZ	\u00A09\u2003EOM5\u0663V6YOY\u00A0BYB\u2003F	144174000	14030000	true	Optional.empty
FUZZ	489259+30	14074000	0	true	Optional.empty
FUZZ	1+29\u00A0,\u00A0460340/ 419	14074000	0	true	Optional.empty
FUZZ	BRN3V+	144174000	14030000	true	Optional.empty
FUZZ	0\u00A09,/4.5404\u0663.,/	14074000	0	true	Optional.empty
FUZZ	 00794\u0663\u06639303	14074000	0	true	Optional.empty
FUZZ	0/57+9 -9.57/749	14074000	0	false	Optional.empty
FUZZ	EA+ZU9DZC	144174000	14030000	true	Optional.empty
FUZZ	9621/   3	144174000	14030000	true	Optional.empty
FUZZ	.7\u00A0+5.	0	7010000	true	Optional.empty
FUZZ	F6LSN+W\u00DF J/X9	144174000	14030000	true	Optional.empty
FUZZ	9\u00A05/11-3\u0663 3774-3	14074000	0	true	Optional.empty
FUZZ	/5	144174000	14030000	true	Optional[OtherVfo[freqHz=14005000]]
FUZZ	85\u00A04.\u066319938.3582,7-	14074000	0	false	Optional.empty
FUZZ	5+-\u00A040-69	14074000	0	true	Optional.empty
FUZZ	+\u06636 8	144174000	14030000	true	Optional.empty
FUZZ	- 0,26,57\u00A03-44	14074000	0	true	Optional.empty
FUZZ	.\u00A07968 4\u0663\u06632	14074000	0	false	Optional.empty
FUZZ	9	0	7010000	true	Optional[Invalid[message=9 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
FUZZ	EK	144174000	14030000	true	Optional.empty
FUZZ	,LI\u00DFIGB31VW	0	7010000	true	Optional.empty
FUZZ	05660,020.57\u00A0 /	14074000	0	false	Optional.empty
FUZZ	58..880 9,/70356/	0	7010000	true	Optional.empty
FUZZ	35- 588.5	14074000	0	true	Optional.empty
FUZZ	.16,.-0042\u00A0	144174000	14030000	true	Optional.empty
FUZZ	5/I\u06638W3C,MP\u00A0	14074000	0	false	Optional.empty
FUZZ	2,J\u2003U0\u2003P	14074000	0	true	Optional.empty
FUZZ	\u00A04 	14074000	0	false	Optional.empty
FUZZ	329314,2\u00A0\u00A0-2\u0663+-	144174000	14030000	true	Optional.empty
FUZZ	7-5/\u00A0\u00A0+360-3\u00A0\u00A0,1,75	0	7010000	true	Optional.empty
FUZZ	13 417\u00A052+0,	144174000	14030000	true	Optional.empty
FUZZ	+886.\u06634490.-.+8,	14074000	0	true	Optional.empty
FUZZ	223	14074000	0	true	Optional[Split[txFreqHz=14223000]]
FUZZ	172315\u06633	14074000	0	true	Optional.empty
FUZZ	 	14074000	0	false	Optional.empty
FUZZ	27-+\u00A08202\u00A0--.	14074000	0	true	Optional.empty
FUZZ	\u0663\u06637.634.	144174000	14030000	true	Optional.empty
FUZZ	7\u00A0\u00A0-5-	144174000	14030000	true	Optional.empty
FUZZ	\u06636 -80183783	144174000	14030000	true	Optional.empty
FUZZ	A\u06636ZJ.H5\u2003L-4S70NUX	14074000	0	false	Optional.empty
FUZZ	5F4ON\u2003+J\u0663\u00A0Q\u2003WUCREA,	14074000	0	false	Optional.empty
FUZZ	-TW7U+,KZ+H+/OL	14074000	0	false	Optional.empty
FUZZ	287	0	7010000	true	Optional[Invalid[message=287 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
FUZZ	.,,2\u0663\u00A0\u00A01 2	14074000	0	false	Optional.empty
FUZZ	/1827513082.+04/	14074000	0	false	Optional.empty
FUZZ	94\u00A0,\u00A05\u00A017,	144174000	14030000	true	Optional.empty
FUZZ	I 1/XCF/F+GSI	14074000	0	true	Optional.empty
FUZZ	1\u00A0.-4645-46\u06638, 4	0	7010000	true	Optional.empty
FUZZ	9+008+86/2	144174000	14030000	true	Optional.empty
FUZZ	\u06631. 	14074000	0	false	Optional.empty
FUZZ		14074000	0	false	Optional.empty
FUZZ	/\u20037TJV\u00A0\u00A0358SCU+M7	0	7010000	true	Optional.empty
FUZZ	3K,G \u00A0I/Z.CY	14074000	0	true	Optional.empty
FUZZ	7C	14074000	0	false	Optional.empty
FUZZ	8,7\u06636,1,72  +5	144174000	14030000	true	Optional.empty
FUZZ	6C\u2003LT3X\u2003 IESGY3	144174000	14030000	true	Optional.empty
FUZZ	1.+2173\u06630,6/-25944	14074000	0	false	Optional.empty
FUZZ	9 -8+442\u00A032.-851+36	14074000	0	true	Optional.empty
FUZZ	490\u0663 +++3/45888,.	144174000	14030000	true	Optional.empty
FUZZ	938	144174000	14030000	true	Optional[Split[txFreqHz=144938000]]
FUZZ	8/349\u06636/,/	144174000	14030000	true	Optional.empty
FUZZ	,027\u00A0 5\u0663393\u00A0./1	144174000	14030000	true	Optional.empty
FUZZ	,98	14074000	0	true	Optional.empty
FUZZ	.OOV5DF	14074000	0	true	Optional.empty
FUZZ	-590\u0663+3342-6-30-,8,	14074000	0	true	Optional.empty
FUZZ	/6 Q\u2003KT3.T3 25KIC	14074000	0	false	Optional.empty
FUZZ	10	14074000	0	true	Optional[Split[txFreqHz=14010000]]
FUZZ	P R73	144174000	14030000	true	Optional.empty
FUZZ	+\u00A083.\u0663\u00A0,.4	14074000	0	true	Optional.empty
FUZZ	9-\u0663//6698662	14074000	0	false	Optional.empty
FUZZ	Q,\u00DFR	144174000	14030000	true	Optional.empty
FUZZ	\u00A05\u00A030	14074000	0	false	Optional.empty
FUZZ	\u0663+\u00A0	14074000	0	false	Optional.empty
FUZZ	6	144174000	14030000	true	Optional[Split[txFreqHz=144006000]]
FUZZ	,9787\u06630229\u00A0	0	7010000	true	Optional.empty
FUZZ	\u066398\u06632\u0663-\u00A03+\u066394\u0663+	0	7010000	true	Optional.empty
FUZZ	/9.4/+5-./	0	7010000	true	Optional.empty
FUZZ	0P NL\u0663YCX.6	0	7010000	true	Optional.empty
FUZZ	-\u0663498	0	7010000	true	Optional.empty
FUZZ	E1ZSJN96,RB9IG6HCHX	14074000	0	false	Optional.empty
FUZZ		14074000	0	false	Optional.empty
FUZZ	9/-35,-/ 	14074000	0	true	Optional.empty
FUZZ	XLA	0	7010000	true	Optional.empty
FUZZ	GGQ17,\u00A0RVQMIAQ3W	144174000	14030000	true	Optional.empty
FUZZ	.-\u06631+/606 0,\u0663,	144174000	14030000	true	Optional.empty
FUZZ	P1\u2003+1F	144174000	14030000	true	Optional.empty
FUZZ	\u00A0+6D\u00DFBI0X	0	7010000	true	Optional.empty
FUZZ	  0624.	144174000	14030000	true	Optional.empty
FUZZ	/VZ.6PQYMAV1,Q	0	7010000	true	Optional.empty
FUZZ	838+	144174000	14030000	true	Optional.empty
FUZZ	\u20034Y1- 140D-0NI.Q\u2003GI	0	7010000	true	Optional.empty
FUZZ	A\u00A0J\u00A0DB0XYZB0D\u06634\u2003Q	0	7010000	true	Optional.empty
FUZZ	.,507343901132\u066322+,7	0	7010000	true	Optional.empty
FUZZ	 0SK\u00DFV\u0663C	14074000	0	true	Optional.empty
FUZZ		14074000	0	false	Optional.empty
FUZZ	--+0,2	14074000	0	true	Optional.empty
FUZZ	-49,+,	14074000	0	true	Optional.empty
FUZZ	9\u0663 956 	14074000	0	false	Optional.empty
FUZZ		14074000	0	false	Optional.empty
FUZZ	,\u06639 /9// 11  1,	14074000	0	true	Optional.empty
FUZZ	97\u00A0/\u00A05\u0663-90415  .	0	7010000	true	Optional.empty
FUZZ	-442	0	7010000	true	Optional[Invalid[message=Posun -442 kHz: aktu\u00E1ln\u00ED frekvence nen\u00ED zn\u00E1m\u00E1]]
FUZZ	8G.S0ERUK6M3V	0	7010000	true	Optional.empty
FUZZ	+8SOP/Y.B	0	7010000	true	Optional.empty
FUZZ	/\u0663+/.+3520	0	7010000	true	Optional.empty
FUZZ	45-3,469-.	14074000	0	true	Optional.empty
FUZZ	.72.19+	144174000	14030000	true	Optional.empty
FUZZ	ZBI-\u2003VM+W1ZW0P\u00DF.	14074000	0	true	Optional.empty
FUZZ	-\u00A05.29	14074000	0	true	Optional.empty
FUZZ	++4	14074000	0	false	Optional.empty
FUZZ	 	14074000	0	false	Optional.empty
FUZZ	0\u00A04+,	0	7010000	true	Optional.empty
FUZZ	5/	144174000	14030000	true	Optional.empty
FUZZ		14074000	0	false	Optional.empty
FUZZ	09,0\u0663.95\u0663.60408-0	144174000	14030000	true	Optional.empty
FUZZ	/ 90/,7,-\u06639\u06631/7	14074000	0	true	Optional.empty
FUZZ	4,57690\u00A0 6,926\u0663	14074000	0	true	Optional.empty
FUZZ	7ZLEWISN	0	7010000	true	Optional.empty
FUZZ		14074000	0	false	Optional.empty
FUZZ	 1	0	7010000	true	Optional[Invalid[message=1 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
FUZZ	7\u066335\u00A0 ++87460\u00A0\u06637	14074000	0	true	Optional.empty
FUZZ	3UCY51Z3ZYU	0	7010000	true	Optional.empty
FUZZ	83\u0663. ,,\u00A05	14074000	0	true	Optional.empty
FUZZ	OK8E\u0663CW4\u0663201WQ\u2003R	14074000	0	true	Optional.empty
FUZZ	\u00A0\u00A0 772\u00A0195,+\u06635	14074000	0	false	Optional.empty
FUZZ	5S	144174000	14030000	true	Optional.empty
FUZZ	0 4\u066342.\u00A0\u00A0 6\u0663+	14074000	0	true	Optional.empty
FUZZ	+GKMNA3TP03B1ZJK4\u2003\u00DF	0	7010000	true	Optional.empty
FUZZ	34+  67	14074000	0	true	Optional.empty
FUZZ	6GPJDW+0\u2003	14074000	0	false	Optional.empty
FUZZ	+/072 56	144174000	14030000	true	Optional.empty
FUZZ	 657\u00A09 56	14074000	0	false	Optional.empty
FUZZ	BLJ	14074000	0	false	Optional.empty
FUZZ	 UB.T3K5Q3	14074000	0	false	Optional.empty
FUZZ	90\u00A0.,\u00A0	0	7010000	true	Optional.empty
FUZZ	0. 08,16+1-\u00A08\u00A0-.\u0663.8	14074000	0	false	Optional.empty
FUZZ		14074000	0	false	Optional.empty
FUZZ	3/.351,+62..,	14074000	0	false	Optional.empty
FUZZ	 	14074000	0	false	Optional.empty
FUZZ	V42P06/B\u20031UX3SOIZ2VU	14074000	0	true	Optional.empty
FUZZ	\u066365.067\u00A01	144174000	14030000	true	Optional.empty
FUZZ	\u06638+17130.002,9671\u00A0	14074000	0	true	Optional.empty
FUZZ	+-102-760+160 38\u00A05	0	7010000	true	Optional.empty
FUZZ		14074000	0	false	Optional.empty
FUZZ	.\u06634 /\u0663,3\u0663..2305	0	7010000	true	Optional.empty
FUZZ	/\u0663\u00A054802	14074000	0	true	Optional.empty
FUZZ	W5,H	144174000	14030000	true	Optional.empty
FUZZ	TXZ2\u00DFW5/4+	0	7010000	true	Optional.empty
FUZZ	-SS	0	7010000	true	Optional.empty
FUZZ	O21\u00A02,-EK6	14074000	0	true	Optional.empty
FUZZ	4-5\u0663536	0	7010000	true	Optional.empty
FUZZ	8	14074000	0	false	Optional[Qsy[freqHz=14008000]]
FUZZ	+2 \u00A065,	144174000	14030000	true	Optional.empty
FUZZ	77,	14074000	0	false	Optional.empty
FUZZ	61,CTN\u0663\u066348C13EI6SXH	144174000	14030000	true	Optional.empty
FUZZ	5/8 9 /99+47\u00A05,.	14074000	0	true	Optional.empty
FUZZ	 8\u06634/3181,43\u00A06-	0	7010000	true	Optional.empty
FUZZ	9709	14074000	0	true	Optional[Invalid[message=9709 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
FUZZ	9006.75\u00A033+9,	0	7010000	true	Optional.empty
FUZZ	 +-/\u0663/9,+51/234\u0663	14074000	0	false	Optional.empty
FUZZ	C U	14074000	0	false	Optional.empty
FUZZ	R\u2003	0	7010000	true	Optional.empty
FUZZ	9790,\u00A08620+8 9	14074000	0	true	Optional.empty
FUZZ		14074000	0	false	Optional.empty
FUZZ	58/1 2\u0663+124 	14074000	0	false	Optional.empty
FUZZ	 ,- .897,\u0663,-98\u00A00 	144174000	14030000	true	Optional.empty
FUZZ		14074000	0	false	Optional.empty
FUZZ	789\u066399\u00A0 +551 \u00A0	0	7010000	true	Optional.empty
FUZZ	10/0- /8-45-	14074000	0	true	Optional.empty
FUZZ	QV0R0	0	7010000	true	Optional.empty
FUZZ	A1C54\u06633+/4H\u2003\u066348	144174000	14030000	true	Optional.empty
FUZZ	6\u0663/.,3/9.86.-\u00A0,1,-9/	144174000	14030000	true	Optional.empty
FUZZ	40\u00A00\u00A02. 8,2 57\u0663-5+/	14074000	0	true	Optional.empty
FUZZ	+,+1437\u00A093	0	7010000	true	Optional.empty
FUZZ	72/4\u06634\u0663,/8346501	14074000	0	false	Optional.empty
FUZZ	19054	14074000	0	true	Optional[Invalid[message=19054 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
FUZZ	\u0663	14074000	0	true	Optional.empty
FUZZ	8\u00A0,8\u0663	14074000	0	true	Optional.empty
FUZZ	 0517 4 1	14074000	0	false	Optional.empty
FUZZ	-72/2,-7,	0	7010000	true	Optional.empty
FUZZ	 8-9.\u0663, 4	14074000	0	true	Optional.empty
FUZZ		14074000	0	false	Optional.empty
FUZZ	-- \u0663\u0663/833/+-.10\u06634	144174000	14030000	true	Optional.empty
FUZZ	839\u00A0491\u06637+3-6-9 1	14074000	0	false	Optional.empty
FUZZ	54+7+82+787	0	7010000	true	Optional.empty
FUZZ	WPL	14074000	0	true	Optional.empty
FUZZ	\u00DFB28\u00A0H \u0663X	14074000	0	false	Optional.empty
FUZZ	.989295+/1+37-5.\u00A0	144174000	14030000	true	Optional.empty
FUZZ	/PIG	14074000	0	true	Optional.empty
FUZZ	18 \u06631\u00A0	0	7010000	true	Optional.empty
FUZZ	T3B,\u00DFUK-C\u0663	0	7010000	true	Optional.empty
FUZZ	\u06636/84+.635	0	7010000	true	Optional.empty
FUZZ	M,O F/\u0663YFZA64NI	14074000	0	true	Optional.empty
FUZZ	\u00A02.XCVQI\u0663	14074000	0	false	Optional.empty
FUZZ	9 2O/	14074000	0	true	Optional.empty
FUZZ	\u0663,54	14074000	0	false	Optional.empty
FUZZ	45+380	0	7010000	true	Optional.empty
FUZZ	\u0663--62319\u00A08\u0663, ,27\u00A00.3	14074000	0	true	Optional.empty
FUZZ	609\u0663 ,6\u0663838\u00A0+\u0663- 	14074000	0	true	Optional.empty
FUZZ	11	14074000	0	false	Optional[Qsy[freqHz=14011000]]
FUZZ	8+\u00A0\u0663/4-51 	144174000	14030000	true	Optional.empty
FUZZ	9/5597177640	0	7010000	true	Optional.empty
FUZZ	1+ .7.1582\u00A0221 +	0	7010000	true	Optional.empty
FUZZ	8 ZBO0F\u00A00/5+\u00DF\u2003YDRD\u2003X	144174000	14030000	true	Optional.empty
FUZZ	. \u00A039\u06633\u06630-  6+.,	14074000	0	true	Optional.empty
FUZZ	 348/56/-	14074000	0	true	Optional.empty
FUZZ	\u00A0+- -+ 5-\u00A0690 ,2	0	7010000	true	Optional.empty
FUZZ	\u00A0004.,/+93,718\u06635	14074000	0	false	Optional.empty
FUZZ	702061	144174000	14030000	true	Optional[Invalid[message=702061 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
FUZZ	\u00A086\u00A0/ 2 	0	7010000	true	Optional.empty
FUZZ		14074000	0	false	Optional.empty
FUZZ	77689 3.-0654	144174000	14030000	true	Optional.empty
FUZZ		14074000	0	false	Optional.empty
FUZZ	,1393.\u0663963	0	7010000	true	Optional.empty
FUZZ	+4..1/3+9 1\u00A06661475	144174000	14030000	true	Optional.empty
FUZZ	. 	144174000	14030000	true	Optional.empty
FUZZ	4P M0L	0	7010000	true	Optional.empty
FUZZ	4IQ	14074000	0	false	Optional.empty
FUZZ	2 1 3.5\u0663/ ,4.\u00A005,	144174000	14030000	true	Optional.empty
FUZZ	500GGFZKPK\u00DFT\u20032\u066311	144174000	14030000	true	Optional.empty
FUZZ	\u00A0325+\u00A0399\u00A071	144174000	14030000	true	Optional.empty
FUZZ	70-3,58	14074000	0	false	Optional.empty
FUZZ	00.6,	14074000	0	false	Optional.empty
FUZZ	  , 88 02/39	14074000	0	true	Optional.empty
FUZZ	/2-3/62,856016.1	0	7010000	true	Optional.empty
FUZZ	4493681446\u066319\u00A07\u00A0/1/	144174000	14030000	true	Optional.empty
FUZZ	5/ \u066353	14074000	0	true	Optional.empty
FUZZ	\u2003DIF8+TKP3CD0+9\u00DFM	14074000	0	false	Optional.empty
FUZZ	 A	0	7010000	true	Optional.empty
FUZZ	O,B+1WTO3C1	144174000	14030000	true	Optional.empty
FUZZ		14074000	0	false	Optional.empty
FUZZ	FX+R,C R-J9 XI89D\u20036	14074000	0	true	Optional.empty
FUZZ	6/219,79.5,-	0	7010000	true	Optional.empty
FUZZ	25\u00A0 + , .6.--\u0663\u0663,/	0	7010000	true	Optional.empty
FUZZ	XVIEXC71/L55R8P\u00DFQ0,	14074000	0	false	Optional.empty
FUZZ	W EC-PAW4NT	144174000	14030000	true	Optional.empty
FUZZ	I TE0JI8	0	7010000	true	Optional.empty
FUZZ	GPX0,M711	0	7010000	true	Optional.empty
FUZZ	2B3E0DW	0	7010000	true	Optional.empty
FUZZ	\u00A0	14074000	0	false	Optional.empty
FUZZ	L1	0	7010000	true	Optional.empty
FUZZ	V\u0663J\u00A0M/T	14074000	0	true	Optional.empty
FUZZ	3,00	0	7010000	true	Optional[Invalid[message=3,00 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
FUZZ	47+\u06636	14074000	0	true	Optional.empty
FUZZ	6-0 /983 30.3 \u0663/49+	14074000	0	false	Optional.empty
FUZZ	WQUN15K4\u20039XDIB4PU	144174000	14030000	true	Optional.empty
FUZZ	ZP-CS3RV	14074000	0	false	Optional.empty
FUZZ	4.3-	14074000	0	false	Optional.empty
FUZZ	 .4\u00A08-5\u06637-7	14074000	0	false	Optional.empty
FUZZ		14074000	0	false	Optional.empty
FUZZ	\u0663798996/470/65-+/,	14074000	0	false	Optional.empty
FUZZ	09R/4\u00A0T B9J06CC1	144174000	14030000	true	Optional.empty
FUZZ	5665+1204/\u00A09,93\u00A0\u0663 +	14074000	0	false	Optional.empty
FUZZ	DCZDEU0IX,/2	0	7010000	true	Optional.empty
FUZZ	4330- 9854.+\u00A0.\u00A0/	14074000	0	true	Optional.empty
FUZZ	9Q/\u00DF9A,H-ZB 11YW6	0	7010000	true	Optional.empty
FUZZ	8\u0663+1- +	14074000	0	true	Optional.empty
FUZZ	8+06\u00A0.2,01	144174000	14030000	true	Optional.empty
FUZZ	69.461	14074000	0	false	Optional[Qsy[freqHz=14069461]]
FUZZ	HC	14074000	0	true	Optional.empty
FUZZ	905\u00A09. ,1 57\u00A028, 54	0	7010000	true	Optional.empty
FUZZ	8736	144174000	14030000	true	Optional[Invalid[message=8736 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
FUZZ	+53.	0	7010000	true	Optional.empty
FUZZ	-58.MO+T7PTN	14074000	0	false	Optional.empty
FUZZ	-I22/R,Z B9WALK	14074000	0	true	Optional.empty
FUZZ	 ,507229\u06630/ ,831+/	0	7010000	true	Optional.empty
FUZZ	YKSUR,ZZ1	14074000	0	true	Optional.empty
FUZZ	 	14074000	0	false	Optional.empty
FUZZ	-/\u00A01-++02\u00A0972/-8,, 	144174000	14030000	true	Optional.empty
FUZZ	/ .003+62-,+4	0	7010000	true	Optional.empty
FUZZ	498	14074000	0	true	Optional[Invalid[message=498 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
FUZZ	\u00A0,	14074000	0	false	Optional.empty
FUZZ	\u00A0+K.L9-,RNJU	0	7010000	true	Optional.empty
FUZZ	U IE	14074000	0	true	Optional.empty
FUZZ	8.4\u066363\u00A0\u00A061681+2,2779	144174000	14030000	true	Optional.empty
FUZZ	\u2003M3LEODBQMIVC -II	14074000	0	false	Optional.empty
FUZZ	ZZJ\u2003U\u20034SBOG969+.+H	14074000	0	false	Optional.empty
FUZZ	XOSQI/YL XG\u00DF2 /	14074000	0	true	Optional.empty
FUZZ	74	0	7010000	true	Optional[Invalid[message=74 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
FUZZ	VNFJL7FNCVO8DC,/\u00A0	14074000	0	true	Optional.empty
FUZZ	27343 2	14074000	0	true	Optional.empty
FUZZ	8H\u00DFKU1EI\u00DF+K,BWPJ9BL	14074000	0	true	Optional.empty
FUZZ	\u00A0/2+\u00A05 /	14074000	0	false	Optional.empty
FUZZ	46028+,57	14074000	0	true	Optional.empty
FUZZ	91\u00A0,.0375+\u0663.	14074000	0	true	Optional.empty
FUZZ	GNW4A	0	7010000	true	Optional.empty
FUZZ	.6-01+45\u00A0663	0	7010000	true	Optional.empty
FUZZ		14074000	0	false	Optional.empty
FUZZ	N7 2IWJ,M.CWO4SC,ZKX	14074000	0	false	Optional.empty
FUZZ	.90/\u066326260 1\u00A0 48	14074000	0	false	Optional.empty
FUZZ	06-/57/ 9.,/4	0	7010000	true	Optional.empty
FUZZ	9\u0663D6D\u00DFR\u00A0B,6.P\u00A0K055	14074000	0	false	Optional.empty
FUZZ	291/ -7\u06630	144174000	14030000	true	Optional.empty
FUZZ	26..\u0663	14074000	0	true	Optional.empty
FUZZ	0\u0663594-5+-.77-7-84	14074000	0	false	Optional.empty
FUZZ	96.+9,72	14074000	0	false	Optional.empty
FUZZ	\u0663PZCYYDPJ	14074000	0	false	Optional.empty
FUZZ	+7\u0663++\u00A0-- 75	0	7010000	true	Optional.empty
FUZZ	97+.659	0	7010000	true	Optional.empty
FUZZ	 	14074000	0	false	Optional.empty
FUZZ	4/44\u00A0.	0	7010000	true	Optional.empty
FUZZ	25,39\u00A0	0	7010000	true	Optional.empty
FUZZ	++03/2363\u00A0\u00A08+/3\u066365	0	7010000	true	Optional.empty
FUZZ	271 8752.0	144174000	14030000	true	Optional.empty
FUZZ	CPTN\u0663,2P3I994VPZ	14074000	0	false	Optional.empty
FUZZ	EQ E.\u2003A34\u20036H	0	7010000	true	Optional.empty
FUZZ	 202\u06631.9+ 4\u0663-+2..+24	144174000	14030000	true	Optional.empty
FUZZ	3, 0\u00A0+,///4\u00A0	14074000	0	true	Optional.empty
FUZZ	/	14074000	0	true	Optional.empty
FUZZ	4/6\u0663\u06634-3  \u0663. 694+	14074000	0	false	Optional.empty
FUZZ	+9674/9497,1+08-	144174000	14030000	true	Optional.empty
FUZZ	184\u00A0	14074000	0	true	Optional.empty
FUZZ	333/1795\u0663- 11 1489	14074000	0	false	Optional.empty
FUZZ	\u06630	0	7010000	true	Optional.empty
FUZZ	9\u00DFFET/\u00A07,/\u00DFV	0	7010000	true	Optional.empty
FUZZ	R6 T,H4D5EK056XQ\u0663IT	14074000	0	true	Optional.empty
FUZZ	7-6 155\u00A0,	0	7010000	true	Optional.empty
FUZZ	.983/+4\u06632\u06632	14074000	0	false	Optional.empty
FUZZ	Q6/SN-C	14074000	0	true	Optional.empty
FUZZ	X	14074000	0	false	Optional.empty
FUZZ	\u066386563	0	7010000	true	Optional.empty
FUZZ	0554592-473	0	7010000	true	Optional.empty
FUZZ	9	0	7010000	true	Optional[Invalid[message=9 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
FUZZ	X.2-I-9SH.X	14074000	0	true	Optional.empty
FUZZ	\u0663369053\u00A0\u0663,	144174000	14030000	true	Optional.empty
FUZZ	9/ 95.34.71080	0	7010000	true	Optional.empty
FUZZ	1,936 	14074000	0	true	Optional[Split[txFreqHz=14001936]]
FUZZ	,9,8 	14074000	0	true	Optional.empty
FUZZ	F6K7	14074000	0	false	Optional.empty
FUZZ	\u0663-/ 40\u00A04.8+	144174000	14030000	true	Optional.empty
FUZZ		14074000	0	false	Optional.empty
FUZZ	N7C3ZQ\u0663U+BDUNLY 19+G	14074000	0	true	Optional.empty
FUZZ	631LXJN.C\u06635Q1.	14074000	0	true	Optional.empty
FUZZ	6\u0663686\u06634-7119 4//,	0	7010000	true	Optional.empty
FUZZ	5NS	144174000	14030000	true	Optional.empty
FUZZ	55040+2-\u0663+\u06631\u00A0	14074000	0	false	Optional.empty
FUZZ	FF\u00DFKC6KZC96H\u00DF3H	144174000	14030000	true	Optional.empty
FUZZ	/\u2003.+G73\u00A0ZFTV6	144174000	14030000	true	Optional.empty
FUZZ	B253W\u00DFO,	14074000	0	true	Optional.empty
FUZZ	+.94752\u0663/+6851321/1	0	7010000	true	Optional.empty
FUZZ	J7MP OH\u00A0\u20039IFD	144174000	14030000	true	Optional.empty
FUZZ	13FIXGHP6G\u00DF.-OJR	144174000	14030000	true	Optional.empty
FUZZ	05+2 4\u00A04\u06633+7\u066338\u066355	14074000	0	true	Optional.empty
FUZZ	6++58	0	7010000	true	Optional.empty
FUZZ	/. 6 6\u06636	144174000	14030000	true	Optional.empty
FUZZ	1.+-5\u06636\u00A0 7226/62	14074000	0	true	Optional.empty
FUZZ	.\u00A0699.2 07/8/37	14074000	0	true	Optional.empty
FUZZ	913,,56\u00A0\u00A0.356+41598	144174000	14030000	true	Optional.empty
FUZZ	77.0\u00A0 06916\u0663 ,	0	7010000	true	Optional.empty
FUZZ	6.,\u00A07054884-96+1462,	14074000	0	false	Optional.empty
FUZZ	TWS\u00A0VAU+	0	7010000	true	Optional.empty
FUZZ	832 \u00A04+\u00A00+4186.\u00A016-8	144174000	14030000	true	Optional.empty
FUZZ	68586\u0663\u00A0..5	14074000	0	true	Optional.empty
FUZZ	84\u0663,1,3.\u00A0\u00A0	14074000	0	true	Optional.empty
FUZZ		14074000	0	false	Optional.empty
FUZZ	7H W3,NHPH4	0	7010000	true	Optional.empty
FUZZ	.+-\u00A0+-1\u00A09\u066397\u0663\u00A0	144174000	14030000	true	Optional.empty
FUZZ	8ZBTP4,	14074000	0	false	Optional.empty
FUZZ	TR SW2MAU6V B	14074000	0	true	Optional.empty
FUZZ	NSYL-X  9BRW	0	7010000	true	Optional.empty
FUZZ	--\u00A0.	144174000	14030000	true	Optional.empty
FUZZ	5	0	7010000	true	Optional[Invalid[message=5 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
FUZZ	4\u00A07-7+/,1	144174000	14030000	true	Optional.empty
FUZZ	\u0663KS\u00DFXW3DHR5AVPUB+5C	14074000	0	false	Optional.empty
FUZZ	\u00A02K5ZC7FC80C-A4AMWQ0	144174000	14030000	true	Optional.empty
FUZZ	.\u0663.1\u0663, 7244 +--437\u00A0	0	7010000	true	Optional.empty
FUZZ	L.T7TYO	0	7010000	true	Optional.empty
FUZZ	6\u06630,/3\u00A0.\u066371267-	14074000	0	false	Optional.empty
FUZZ	1SG9,LC2A,G	0	7010000	true	Optional.empty
FUZZ	8\u0663--528-.	0	7010000	true	Optional.empty
FUZZ	MQG4,N,9GE\u00A0	144174000	14030000	true	Optional.empty
FUZZ	-,1\u06630\u00A0/ 42\u00A0\u06638+\u00A08	144174000	14030000	true	Optional.empty
FUZZ	/,\u0663-2	14074000	0	true	Optional.empty
FUZZ	-	0	7010000	true	Optional.empty
FUZZ	\u00A0\u06632 +-	14074000	0	true	Optional.empty
FUZZ	/BRN0JD\u00DFC	14074000	0	true	Optional.empty
FUZZ	RVG01K5CV+	144174000	14030000	true	Optional.empty
FUZZ		14074000	0	false	Optional.empty
FUZZ	,- 09/72,+	0	7010000	true	Optional.empty
FUZZ	NBA8JO BZ/\u0663/M\u0663U	14074000	0	false	Optional.empty
FUZZ	66	14074000	0	false	Optional[Qsy[freqHz=14066000]]
FUZZ	1\u00A0VZZGK	14074000	0	true	Optional.empty
FUZZ	2+6\u00A0/+3\u00A0	14074000	0	false	Optional.empty
FUZZ	2HE\u00DF	14074000	0	false	Optional.empty
FUZZ	0\u0663,5\u00A06,2,0+ 5297\u0663-1 	0	7010000	true	Optional.empty
FUZZ	54 	0	7010000	true	Optional[Invalid[message=54 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
FUZZ	-	0	7010000	true	Optional.empty
FUZZ	T I G	14074000	0	false	Optional.empty
FUZZ	86\u00A0\u0663\u00A015051148\u06632/+1	144174000	14030000	true	Optional.empty
FUZZ	STNOIRLE40HS+TC	14074000	0	true	Optional.empty
FUZZ	EV.8J74JU6JGI	0	7010000	true	Optional.empty
FUZZ		14074000	0	false	Optional.empty
FUZZ	.02.\u0663,001539550\u00A0	0	7010000	true	Optional.empty
FUZZ	 ,0967\u00A08\u066305/49 \u00A0	144174000	14030000	true	Optional.empty
FUZZ	722.4+7\u066393,+896+	0	7010000	true	Optional.empty
FUZZ	M	0	7010000	true	Optional.empty
FUZZ	9	0	7010000	true	Optional[Invalid[message=9 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
FUZZ	9748\u0663/642 /36-\u00A0	14074000	0	true	Optional.empty
FUZZ	HP4\u00A07DRHX2Q6EV.\u2003ZJ	14074000	0	false	Optional.empty
FUZZ	\u20031A8 	14074000	0	true	Optional.empty
FUZZ	MI\u00A0+AS	0	7010000	true	Optional.empty
FUZZ	.1722\u00A0.56	14074000	0	true	Optional.empty
FUZZ	3	14074000	0	true	Optional[Split[txFreqHz=14003000]]
FUZZ	18.\u0663. \u066350	14074000	0	false	Optional.empty
FUZZ	A2\u00DF	144174000	14030000	true	Optional.empty
FUZZ	302131163,/2346	144174000	14030000	true	Optional.empty
FUZZ	0\u0663	14074000	0	true	Optional.empty
FUZZ	 ,0,95 	14074000	0	false	Optional.empty
FUZZ	KIC53RT8NDISJ	14074000	0	true	Optional.empty
FUZZ	0\u00A01.2-	14074000	0	false	Optional.empty
FUZZ	.29,\u0663\u0663754\u00A040\u0663 ,\u0663-	14074000	0	false	Optional.empty
FUZZ	 9	0	7010000	true	Optional[Invalid[message=9 kHz nele\u017E\u00ED v \u017E\u00E1dn\u00E9m p\u00E1smu]]
FUZZ	+7	14074000	0	false	Optional[Qsy[freqHz=14081000]]
FUZZ	\u06632 5 .+63.9	0	7010000	true	Optional.empty
FUZZ	+80,553+-	14074000	0	false	Optional.empty
FUZZ	0\u06630 \u00A03  0 8135145	0	7010000	true	Optional.empty
FUZZ	69\u0663\u00A034+.,	14074000	0	false	Optional.empty
FUZZ	92266/,.19	14074000	0	false	Optional.empty
FUZZ	\u00A006-,,9-+737480\u00A0,2.\u00A0	14074000	0	true	Optional.empty
FUZZ	0 Y\u00DF03RDNW89\u00A0Z\u00A0Z8MLF	14074000	0	false	Optional.empty
FUZZ	 5-4\u0663+1/4-.5	144174000	14030000	true	Optional.empty
FUZZ	++2\u00A0\u06636\u00A0	14074000	0	true	Optional.empty
FUZZ		14074000	0	false	Optional.empty
FUZZ	6-8\u0663722--	0	7010000	true	Optional.empty
FUZZ	354893,+ 983+,44	14074000	0	false	Optional.empty
FUZZ	6.3\u00A0	0	7010000	true	Optional.empty
FUZZ	334. \u066369. 478,21-	0	7010000	true	Optional.empty
FUZZ	 -9.0\u06631,,\u0663/-\u0663	144174000	14030000	true	Optional.empty
FUZZ	19/\u00A0\u0663312078/\u0663\u0663 ,	14074000	0	false	Optional.empty
FUZZ	+4 \u0663 .98/67\u066332+94	14074000	0	true	Optional.empty
FUZZ	2FXU+9WSVYBAZ2H	14074000	0	true	Optional.empty
FUZZ	C	14074000	0	true	Optional.empty
FUZZ	WNR\u00DFZE1.M4L G1OQI9	14074000	0	true	Optional.empty
FUZZ	EFUE4VN-U1,BTWGE	0	7010000	true	Optional.empty
FUZZ	.41	14074000	0	true	Optional.empty
FUZZ	+0\u00A0\u0663,, \u00A02	144174000	14030000	true	Optional.empty
FUZZ	FSD X3+	14074000	0	true	Optional.empty
FUZZ	,/++0292208-53\u00A08.	14074000	0	true	Optional.empty
FUZZ	 031.+20.34,25	0	7010000	true	Optional.empty
FUZZ	IZQ\u00A0-Q\u00DFCH4	14074000	0	false	Optional.empty
FUZZ	\u0663\u0663/0898\u00A0\u0663\u06635-	144174000	14030000	true	Optional.empty
FUZZ	\u00A03\u00A000/+6-	14074000	0	false	Optional.empty
FUZZ	.	144174000	14030000	true	Optional.empty
FUZZ	,HZ.J\u00A0P-2I\u00A0,	144174000	14030000	true	Optional.empty
FUZZ	-4/21\u0663+88376 	0	7010000	true	Optional.empty
OP	OPON	Optional[OperatorCommand[operator=]]
OP	OPON OK1XOE	Optional[OperatorCommand[operator=OK1XOE]]
OP	  opon   ok1k  	Optional[OperatorCommand[operator=OK1K]]
OP	OK1XOE	Optional.empty
OP		Optional.empty
OP	 	Optional.empty
OP	OPONX	Optional.empty
OP	 opon\tk1x 	Optional[OperatorCommand[operator=K1X]]
OP	LOGIN	Optional[OperatorCommand[operator=]]
OP	login a b c	Optional[OperatorCommand[operator=A]]
OP	OPON\u00A0K1A	Optional.empty
OP	\u00A0OPON	Optional.empty
OP	opon \u00DF	Optional[OperatorCommand[operator=SS]]
OP	OPON\u000BX	Optional[OperatorCommand[operator=X]]
OP	OPON\u0001X	Optional.empty
OP	\u0001OPON X	Optional[OperatorCommand[operator=X]]
OP	OPON  	Optional[OperatorCommand[operator=]]
OP	LOGIN\nOK1A	Optional[OperatorCommand[operator=OK1A]]
OP	op on	Optional.empty
OP	O\u0131ON	Optional.empty
OP.null	Optional.empty	Optional.empty
"""#
}
