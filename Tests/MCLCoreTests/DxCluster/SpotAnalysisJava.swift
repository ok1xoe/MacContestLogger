/// The output of a maintainer-only probe over the Kotlin `ContestController`
/// (v1.1.1, JDK 21) — byte for byte `spot-analysis-probe.tsv`. Replayed by `SpotAnalyzerParityTests`.
enum SpotAnalysisJava {
    static let tsv: String = #"""
parseSnr		null
parseSnr	CW 25 dB 28 WPM CQ	25
parseSnr	25dB	25
parseSnr	25   dB	25
parseSnr	-12 dB	12
parseSnr	dB 7	null
parseSnr	7 db	null
parseSnr	007 dB	7
parseSnr	99999999999 dB	null
parseSnr	2147483647 dB	2147483647
parseSnr	2147483648 dB	null
parseSnr	1 dB 2 dB	1
parseSnr	\u0661\u0662 dB	null
parseSnr	12\u00A0dB	null
parseSnr	12\u0009dB	12
parseSnr	x5 dBm	5
parseSnr	null	null
needs	none	false	false
status	none	0	false	0	false
mode	none	0	CW	CW
predict	none	0	{}
tooltip	none	0	DL1ABC   14025.0 kHz\u000AM\u00F3d: CW (CW, vyhodnocuje se)\u000ASpotter: OK1RR
status	none	1	false	0	false
mode	none	1	SSB	PHONE
predict	none	1	{}
tooltip	none	1	LU1ABC   14250.0 kHz\u000AM\u00F3d: SSB (PHONE, vyhodnocuje se)\u000ASpotter: OK1RR\u000AKoment\u00E1\u0159: SSB
status	none	2	false	0	false
mode	none	2	CW	null
predict	none	2	{}
tooltip	none	2	OK1ABC   3000.0 kHz\u000AM\u00F3d: CW (neur\u010Diteln\u00FD, vyhodnocuje se)\u000ASpotter: OK1RR
grid	none	dxcc	false 0 0 rows=0 spotAt=[]
grid	none	grid	false 0 0 rows=0 spotAt=[]
grid	none	itu	false 0 0 rows=0 spotAt=[]
grid	none	cq	false 0 0 rows=0 spotAt=[]
grid	none	districts	false 0 0 rows=0 spotAt=[]
grid	none	sections	false 0 0 rows=0 spotAt=[]
grid	none	other	false 0 0 rows=0 spotAt=[]
grid	none	bogus	false 0 0 rows=0 spotAt=[]
bandPlanCategory	1810000	CW
bandPlanCategory	3550000	CW
bandPlanCategory	3700000	PHONE
bandPlanCategory	7074000	PHONE
bandPlanCategory	14000000	CW
bandPlanCategory	14100000	null
bandPlanCategory	14200000	PHONE
bandPlanCategory	50100000	null
bandPlanCategory	144300000	null
bandPlanCategory	5000000	null
bandPlanCategory	0	null
bandPlanSegments	14000000-14350000	CW:14000000-14070000 DIGI:14070001-14099000 PHONE:14101000-14350000
bandPlanSegments	7000000-7200000	CW:7000000-7040000 DIGI:7040001-7050000 PHONE:7050001-7200000
bandPlanSegments	3500000-3800000	CW:3500000-3570000 DIGI:3570001-3600000 PHONE:3600001-3800000
bandPlanSegments	14060000-14070000	CW:14060000-14070000
bandPlanSegments	5000000-5100000	
bandPlanSegments	14350000-14000000	
needs	cqww	true	false
status	cqww	0	true	0	false
mode	cqww	0	CW	CW
predict	cqww	0	{zone=14}
tooltip	cqww	0	DL1ABC   14025.0 kHz\u000AM\u00F3d: CW (CW, vyhodnocuje se)\u000ASpotter: OK1RR
status	cqww	1	false	0	false
mode	cqww	1	CW	CW
predict	cqww	1	{zone=14}
tooltip	cqww	1	DL2XYZ   14030.0 kHz\u000AM\u00F3d: CW (CW, vyhodnocuje se)\u000ASpotter: DK0SK-#\u000AKoment\u00E1\u0159: CW 18 dB 25 WPM CQ
status	cqww	2	false	2	true
mode	cqww	2	CW	CW
predict	cqww	2	{zone=4}
tooltip	cqww	2	W1AW   14010.0 kHz\u000AM\u00F3d: CW (CW, vyhodnocuje se)\u000AGrid: FN31 \u2192 pole FN\u000ASpotter: OK1RR
status	cqww	3	true	1	true
mode	cqww	3	CW	CW
predict	cqww	3	{zone=4}
tooltip	cqww	3	W1AW   7010.0 kHz\u000AM\u00F3d: CW (CW, vyhodnocuje se)\u000AGrid: FN31 \u2192 pole FN\u000ASpotter: OK1RR
status	cqww	4	false	0	false
mode	cqww	4	CW	CW
predict	cqww	4	{zone=25}
tooltip	cqww	4	JA1ABC   21020.0 kHz\u000AM\u00F3d: CW (CW, vyhodnocuje se)\u000AGrid: PM95 \u2192 pole PM\u000ASpotter: OK1RR
status	cqww	5	false	2	true
mode	cqww	5	CW	CW
predict	cqww	5	{zone=25}
tooltip	cqww	5	JA1ABC   28020.0 kHz\u000AM\u00F3d: CW (CW, vyhodnocuje se)\u000AGrid: PM95 \u2192 pole PM\u000ASpotter: OK1RR\u000AKoment\u00E1\u0159: 5 dB
status	cqww	6	false	0	false
mode	cqww	6	SSB	PHONE
predict	cqww	6	{zone=13}
tooltip	cqww	6	LU1ABC   14250.0 kHz\u000AM\u00F3d: SSB (PHONE, ignorov\u00E1no)\u000ASpotter: OK1RR\u000AKoment\u00E1\u0159: SSB
status	cqww	7	false	0	false
mode	cqww	7	FT8	DIGI
predict	cqww	7	{zone=5}
tooltip	cqww	7	VE3ABC   14074.0 kHz\u000AM\u00F3d: FT8 (DIGI, ignorov\u00E1no)\u000ASpotter: OK1RR
status	cqww	8	false	0	false
mode	cqww	8	CW	CW
predict	cqww	8	{}
tooltip	cqww	8	ZZ9ZZ   14020.0 kHz\u000AM\u00F3d: CW (CW, vyhodnocuje se)\u000ASpotter: OK1RR
status	cqww	9	false	0	false
mode	cqww	9	CW	null
predict	cqww	9	{zone=15}
tooltip	cqww	9	OK1ABC   3000.0 kHz\u000AM\u00F3d: CW (neur\u010Diteln\u00FD, vyhodnocuje se)\u000ASpotter: OK1RR
status	cqww	10	false	0	false
mode	cqww	10	CW	CW
predict	cqww	10	{}
tooltip	cqww	10	   14015.0 kHz\u000AM\u00F3d: CW (CW, vyhodnocuje se)\u000ASpotter: OK1RR
status	cqww	11	false	0	false
mode	cqww	11	CW	CW
predict	cqww	11	{}
tooltip	cqww	11	      14015.0 kHz\u000AM\u00F3d: CW (CW, vyhodnocuje se)\u000ASpotter: OK1RR
status	cqww	12	false	2	true
mode	cqww	12	CW	CW
predict	cqww	12	{zone=14}
tooltip	cqww	12	DL3AA   10110.0 kHz\u000AM\u00F3d: CW (CW, vyhodnocuje se)\u000ASpotter: OK1RR\u000AKoment\u00E1\u0159: CW
status	cqww	13	false	2	true
mode	cqww	13	CW	CW
predict	cqww	13	{zone=5}
tooltip	cqww	13	W2XX   14005.0 kHz\u000AM\u00F3d: CW (CW, vyhodnocuje se)\u000ASpotter: OK1RR\u000AKoment\u00E1\u0159: CW 99999999999 dB
status	cqww	14	false	0	false
mode	cqww	14	RTTY	DIGI
predict	cqww	14	{zone=5}
tooltip	cqww	14	K1ABC   14040.0 kHz\u000AM\u00F3d: RTTY (DIGI, ignorov\u00E1no)\u000ASpotter: OK1RR\u000AKoment\u00E1\u0159: RTTY
status	cqww	15	false	2	true
mode	cqww	15	CW	CW
predict	cqww	15	{zone=5}
tooltip	cqww	15	K2ZZ   14045.0 kHz\u000AM\u00F3d: CW (CW, vyhodnocuje se)\u000ASpotter: OK1RR\u000AKoment\u00E1\u0159: XYZ
status	cqww	16	false	2	true
mode	cqww	16	CW	CW
predict	cqww	16	{zone=5}
tooltip	cqww	16	VE3ABC   14010.0 kHz\u000AM\u00F3d: CW (CW, vyhodnocuje se)\u000ASpotter: OK1RR\u000AKoment\u00E1\u0159: CW 7 dB
status	cqww	17	false	2	true
mode	cqww	17	CW	CW
predict	cqww	17	{zone=13}
tooltip	cqww	17	LU1ABC   3510.0 kHz\u000AM\u00F3d: CW (CW, vyhodnocuje se)\u000ASpotter: OK1ME
status	cqww	18	false	2	true
mode	cqww	18	CW	CW
predict	cqww	18	{zone=25}
tooltip	cqww	18	JA2ABC   28020.0 kHz\u000AM\u00F3d: CW (CW, vyhodnocuje se)\u000ASpotter: OK1RR
row	cqww	LU1ABC	3510000	239	CW	2	false	null	3	OK1ME	true
row	cqww	W1AW	7010000	309	CW	1	true	null	3	OK1RR	true
row	cqww	DL3AA	10110000	297	CW	2	false	null	1	OK1RR	true
row	cqww	W2XX	14005000	309	CW	2	false	null	3	OK1RR	true
row	cqww	W1AW	14010000	309	CW	2	false	null	3	OK1RR	true
row	cqww	VE3ABC	14010000	null	CW	2	false	7	3	OK1RR	true
row	cqww		14015000	null	CW	0	false	null	0	OK1RR	false
row	cqww	   	14015000	null	CW	0	false	null	0	OK1RR	false
row	cqww	ZZ9ZZ	14020000	null	CW	0	false	null	0	OK1RR	false
row	cqww	DL1ABC	14025000	297	CW	0	true	null	1	OK1RR	false
row	cqww	DL2XYZ	14030000	297	CW	0	false	18	1	DK0SK-#	false
row	cqww	K1ABC	14040000	309	RTTY	0	false	null	3	OK1RR	false
row	cqww	K2ZZ	14045000	309	CW	2	false	null	3	OK1RR	true
row	cqww	VE3ABC	14074000	null	FT8	0	false	null	3	OK1RR	false
row	cqww	LU1ABC	14250000	239	SSB	0	false	null	3	OK1RR	false
row	cqww	JA1ABC	21020000	43	CW	0	false	null	3	OK1RR	false
row	cqww	JA1ABC	28020000	43	CW	2	false	5	3	OK1RR	true
row	cqww	JA2ABC	28020000	43	CW	2	false	null	3	OK1RR	true
grid	cqww	dxcc	true 3 6 rows=6 | 503/Czech Republic/OK/EU  | 230/Germany/DL/EU 20m=WORKED, | 291/United States/K/NA 40m=WORKED,20m=SPOTTED_DBL, | 339/Japan/JA/AS 15m=WORKED,10m=SPOTTED_DBL, | 1/Canada/VE/NA 20m=SPOTTED_DBL, | 100/Argentina/LU/SA 80m=SPOTTED_DBL, spotAt=[100@80m=LU1ABC@3510000, 1@20m=VE3ABC@14010000, 230@20m=DL1ABC@14025000, 230@30m=DL3AA@10110000, 291@20m=W1AW@14010000, 291@40m=W1AW@7010000, 339@10m=JA1ABC@28020000, 339@15m=JA1ABC@21020000]
grid	cqww	grid	false 0 0 rows=0 spotAt=[]
grid	cqww	itu	false 0 0 rows=0 spotAt=[]
grid	cqww	cq	true 3 40 rows=40 | 1/1//  | 5/5// 40m=WORKED,20m=SPOTTED_DBL, | 13/13// 80m=SPOTTED_DBL, | 14/14// 20m=WORKED, | 25/25// 15m=WORKED,10m=SPOTTED_DBL, | 40/40//  spotAt=[13@80m=LU1ABC@3510000, 14@20m=DL1ABC@14025000, 14@30m=DL3AA@10110000, 25@10m=JA1ABC@28020000, 25@15m=JA1ABC@21020000, 5@20m=W1AW@14010000, 5@40m=W1AW@7010000]
grid	cqww	districts	false 0 0 rows=0 spotAt=[]
grid	cqww	sections	false 0 0 rows=0 spotAt=[]
grid	cqww	other	false 0 0 rows=0 spotAt=[]
grid	cqww	bogus	false 0 0 rows=0 spotAt=[]
needs	digi	true	true
status	digi	0	false	0	false
mode	digi	0	FT8	DIGI
predict	digi	0	{grid=JO52}
tooltip	digi	0	DL1AAH   14074.0 kHz\u000AM\u00F3d: FT8 (DIGI, vyhodnocuje se)\u000AGrid: JO52 \u2192 pole JO\u000ASpotter: OK1RR\u000AKoment\u00E1\u0159: FT8 -12 dB JO52
status	digi	1	true	0	false
mode	digi	1	FT8	DIGI
predict	digi	1	{grid=JO31}
tooltip	digi	1	DL1AE   14080.0 kHz\u000AM\u00F3d: FT8 (DIGI, vyhodnocuje se)\u000AGrid: JO31 \u2192 pole JO\u000ASpotter: OK1RR\u000AKoment\u00E1\u0159: FT8
status	digi	2	false	1	true
mode	digi	2	FT8	DIGI
predict	digi	2	{grid=PM95}
tooltip	digi	2	JA1XXX   14075.0 kHz\u000AM\u00F3d: FT8 (DIGI, vyhodnocuje se)\u000AGrid: PM95 \u2192 pole PM\u000ASpotter: OK1RR\u000AKoment\u00E1\u0159: FT8 PM95
status	digi	3	false	0	false
mode	digi	3	FT8	DIGI
predict	digi	3	{grid=PM96}
tooltip	digi	3	JA1XXX   21075.0 kHz\u000AM\u00F3d: FT8 (DIGI, vyhodnocuje se)\u000AGrid: PM96 \u2192 pole PM\u000ASpotter: OK1RR\u000AKoment\u00E1\u0159: FT8 jo52 pm96
status	digi	4	false	1	true
mode	digi	4	FT8	DIGI
predict	digi	4	{grid=JN79}
tooltip	digi	4	W1AW   14076.0 kHz\u000AM\u00F3d: FT8 (DIGI, vyhodnocuje se)\u000AGrid: JN79 \u2192 pole JN\u000ASpotter: OK1RR\u000AKoment\u00E1\u0159: FT8 JN79
status	digi	5	false	0	false
mode	digi	5	FT8	DIGI
predict	digi	5	{}
tooltip	digi	5	K9ZZZ   14077.0 kHz\u000AM\u00F3d: FT8 (DIGI, vyhodnocuje se)\u000ASpotter: OK1RR\u000AKoment\u00E1\u0159: FT8
status	digi	6	false	0	false
mode	digi	6	CW	CW
predict	digi	6	{}
tooltip	digi	6	OK1ABC   7010.0 kHz\u000AM\u00F3d: CW (CW, ignorov\u00E1no)\u000ASpotter: OK1RR\u000AKoment\u00E1\u0159: CW
status	digi	7	false	1	true
mode	digi	7	FT4	DIGI
predict	digi	7	{grid=GG66}
tooltip	digi	7	LU1ABC   21074.0 kHz\u000AM\u00F3d: FT4 (DIGI, vyhodnocuje se)\u000AGrid: GG66 \u2192 pole GG\u000ASpotter: OK1RR\u000AKoment\u00E1\u0159: FT4 GG66
status	digi	8	false	1	true
mode	digi	8	FT8	DIGI
predict	digi	8	{grid=PM95}
tooltip	digi	8	JA1ABC   28074.0 kHz\u000AM\u00F3d: FT8 (DIGI, vyhodnocuje se)\u000AGrid: PM95 \u2192 pole PM\u000ASpotter: OK1RR
status	digi	9	false	1	true
mode	digi	9	FT8	DIGI
predict	digi	9	{grid=JO52}
tooltip	digi	9	DL1AAH   7074.0 kHz\u000AM\u00F3d: FT8 (DIGI, vyhodnocuje se)\u000AGrid: JO52 \u2192 pole JO\u000ASpotter: OK1RR
row	digi	OK1ABC	7010000	0	CW	0	false	null	1	OK1RR	false
row	digi	DL1AAH	7074000	297	FT8	1	false	null	1	OK1RR	true
row	digi	DL1AAH	14074000	297	FT8	0	false	12	1	OK1RR	false
row	digi	JA1XXX	14075000	43	FT8	1	false	null	4	OK1RR	true
row	digi	W1AW	14076000	309	FT8	1	false	null	1	OK1RR	true
row	digi	K9ZZZ	14077000	309	FT8	0	false	null	1	OK1RR	false
row	digi	DL1AE	14080000	297	FT8	0	true	null	1	OK1RR	false
row	digi	LU1ABC	21074000	239	FT4	1	false	null	4	OK1RR	true
row	digi	JA1XXX	21075000	43	FT8	0	false	null	3	OK1RR	false
row	digi	JA1ABC	28074000	43	FT8	1	false	null	4	OK1RR	true
grid	digi	dxcc	false 0 0 rows=0 spotAt=[]
grid	digi	grid	true 2 -1 rows=4 | JO/JO// 40m=SPOTTED,20m=WORKED, | PM/PM// 20m=SPOTTED,15m=WORKED,10m=SPOTTED, | GG/GG// 15m=SPOTTED, | JN/JN// 20m=SPOTTED, spotAt=[GG@15m=LU1ABC@21074000, JN@20m=W1AW@14076000, JO@20m=DL1AAH@14074000, JO@40m=DL1AAH@7074000, PM@10m=JA1ABC@28074000, PM@15m=JA1XXX@21075000, PM@20m=JA1XXX@14075000]
grid	digi	itu	false 0 0 rows=0 spotAt=[]
grid	digi	cq	false 0 0 rows=0 spotAt=[]
grid	digi	districts	false 0 0 rows=0 spotAt=[]
grid	digi	sections	false 0 0 rows=0 spotAt=[]
grid	digi	other	false 0 0 rows=0 spotAt=[]
grid	digi	bogus	false 0 0 rows=0 spotAt=[]
gridLog	DL1AAH (DL): \u201EFT8 -12 dB JO52\u201C
gridLog	  kandid\u00E1t JO52: pole JO pat\u0159\u00ED DL (dle dat) \u2192 P\u0158IJAT
gridLog	  \u2192 JO52 (z t\u011Bla zpr\u00E1vy)
gridLog	DL1AE (DL): \u201EFT8\u201C
gridLog	  \u2192 JO31 (z CSV)
gridLog	JA1XXX (JA): \u201EFT8 PM95\u201C
gridLog	  kandid\u00E1t PM95: pole PM pat\u0159\u00ED JA (dle dat) \u2192 P\u0158IJAT
gridLog	  \u2192 PM95 (z t\u011Bla zpr\u00E1vy)
gridLog	W1AW (K): \u201EFT8 JN79\u201C
gridLog	  kandid\u00E1t JN79: pole JN pat\u0159\u00ED K (dle dat) \u2192 P\u0158IJAT
gridLog	  \u2192 JN79 (z t\u011Bla zpr\u00E1vy)
gridLog	K9ZZZ (K): \u201EFT8\u201C
gridLog	  \u2192 grid nezji\u0161t\u011Bn
gridLog	OK1ABC (OK): \u201ECW\u201C
gridLog	  \u2192 grid nezji\u0161t\u011Bn
gridLog	LU1ABC (LU): \u201EFT4 GG66\u201C
gridLog	  kandid\u00E1t GG66: pole GG pat\u0159\u00ED LU (dle dat) \u2192 P\u0158IJAT
gridLog	  \u2192 GG66 (z t\u011Bla zpr\u00E1vy)
gridLog	JA1ABC (JA): \u201E\u201C
gridLog	  \u2192 PM95 (z callbooku)
needs	digi2	true	true
status	digi2	0	false	0	false
mode	digi2	0	FT8	DIGI
predict	digi2	0	{grid=JO52}
tooltip	digi2	0	DL1AAH   14074.0 kHz\u000AM\u00F3d: FT8 (DIGI, vyhodnocuje se)\u000AGrid: JO52 \u2192 pole JO\u000ASpotter: OK1RR\u000AKoment\u00E1\u0159: FT8 -12 dB JO52
status	digi2	1	true	0	false
mode	digi2	1	FT8	DIGI
predict	digi2	1	{grid=JO31}
tooltip	digi2	1	DL1AE   14080.0 kHz\u000AM\u00F3d: FT8 (DIGI, vyhodnocuje se)\u000AGrid: JO31 \u2192 pole JO\u000ASpotter: OK1RR\u000AKoment\u00E1\u0159: FT8
status	digi2	2	false	1	true
mode	digi2	2	FT8	DIGI
predict	digi2	2	{grid=PM95}
tooltip	digi2	2	JA1XXX   14075.0 kHz\u000AM\u00F3d: FT8 (DIGI, vyhodnocuje se)\u000AGrid: PM95 \u2192 pole PM\u000ASpotter: OK1RR\u000AKoment\u00E1\u0159: FT8 PM95
status	digi2	3	false	0	false
mode	digi2	3	FT8	DIGI
predict	digi2	3	{grid=PM96}
tooltip	digi2	3	JA1XXX   21075.0 kHz\u000AM\u00F3d: FT8 (DIGI, vyhodnocuje se)\u000AGrid: PM96 \u2192 pole PM\u000ASpotter: OK1RR\u000AKoment\u00E1\u0159: FT8 jo52 pm96
status	digi2	4	false	1	true
mode	digi2	4	FT8	DIGI
predict	digi2	4	{grid=JN79}
tooltip	digi2	4	W1AW   14076.0 kHz\u000AM\u00F3d: FT8 (DIGI, vyhodnocuje se)\u000AGrid: JN79 \u2192 pole JN\u000ASpotter: OK1RR\u000AKoment\u00E1\u0159: FT8 JN79
status	digi2	5	false	0	false
mode	digi2	5	FT8	DIGI
predict	digi2	5	{}
tooltip	digi2	5	K9ZZZ   14077.0 kHz\u000AM\u00F3d: FT8 (DIGI, vyhodnocuje se)\u000ASpotter: OK1RR\u000AKoment\u00E1\u0159: FT8
status	digi2	6	false	0	false
mode	digi2	6	CW	CW
predict	digi2	6	{}
tooltip	digi2	6	OK1ABC   7010.0 kHz\u000AM\u00F3d: CW (CW, ignorov\u00E1no)\u000ASpotter: OK1RR\u000AKoment\u00E1\u0159: CW
status	digi2	7	false	1	true
mode	digi2	7	FT4	DIGI
predict	digi2	7	{grid=GG66}
tooltip	digi2	7	LU1ABC   21074.0 kHz\u000AM\u00F3d: FT4 (DIGI, vyhodnocuje se)\u000AGrid: GG66 \u2192 pole GG\u000ASpotter: OK1RR\u000AKoment\u00E1\u0159: FT4 GG66
status	digi2	8	false	1	true
mode	digi2	8	FT8	DIGI
predict	digi2	8	{grid=PM95}
tooltip	digi2	8	JA1ABC   28074.0 kHz\u000AM\u00F3d: FT8 (DIGI, vyhodnocuje se)\u000AGrid: PM95 \u2192 pole PM\u000ASpotter: OK1RR
status	digi2	9	false	1	true
mode	digi2	9	FT8	DIGI
predict	digi2	9	{grid=JO52}
tooltip	digi2	9	DL1AAH   7074.0 kHz\u000AM\u00F3d: FT8 (DIGI, vyhodnocuje se)\u000AGrid: JO52 \u2192 pole JO\u000ASpotter: OK1RR
row	digi2	OK1ABC	7010000	0	CW	0	false	null	1	OK1RR	false
row	digi2	DL1AAH	7074000	297	FT8	1	false	null	1	OK1RR	true
row	digi2	DL1AAH	14074000	297	FT8	0	false	12	1	OK1RR	false
row	digi2	JA1XXX	14075000	43	FT8	1	false	null	4	OK1RR	true
row	digi2	W1AW	14076000	309	FT8	1	false	null	1	OK1RR	true
row	digi2	K9ZZZ	14077000	309	FT8	0	false	null	1	OK1RR	false
row	digi2	DL1AE	14080000	297	FT8	0	true	null	1	OK1RR	false
row	digi2	LU1ABC	21074000	239	FT4	1	false	null	4	OK1RR	true
row	digi2	JA1XXX	21075000	43	FT8	0	false	null	3	OK1RR	false
row	digi2	JA1ABC	28074000	43	FT8	1	false	null	4	OK1RR	true
grid	digi2	dxcc	false 0 0 rows=0 spotAt=[]
grid	digi2	grid	true 2 -1 rows=4 | JO/JO// 40m=SPOTTED,20m=WORKED, | PM/PM// 20m=SPOTTED,15m=WORKED,10m=SPOTTED, | GG/GG// 15m=SPOTTED, | JN/JN// 20m=SPOTTED, spotAt=[GG@15m=LU1ABC@21074000, JN@20m=W1AW@14076000, JO@20m=DL1AAH@14074000, JO@40m=DL1AAH@7074000, PM@10m=JA1ABC@28074000, PM@15m=JA1XXX@21075000, PM@20m=JA1XXX@14075000]
grid	digi2	itu	false 0 0 rows=0 spotAt=[]
grid	digi2	cq	false 0 0 rows=0 spotAt=[]
grid	digi2	districts	false 0 0 rows=0 spotAt=[]
grid	digi2	sections	false 0 0 rows=0 spotAt=[]
grid	digi2	other	false 0 0 rows=0 spotAt=[]
grid	digi2	bogus	false 0 0 rows=0 spotAt=[]
gridLogAfter	0
gridLogReactivated	DL1AAH (DL): \u201EFT8 -12 dB JO52\u201C
gridLogReactivated	  kandid\u00E1t JO52: pole JO pat\u0159\u00ED DL (dle dat) \u2192 P\u0158IJAT
gridLogReactivated	  \u2192 JO52 (z t\u011Bla zpr\u00E1vy)
needs	iaru	false	false
status	iaru	0	true	0	false
mode	iaru	0	CW	CW
predict	iaru	0	{exch=DARC}
tooltip	iaru	0	DA0HQ   14030.0 kHz\u000AM\u00F3d: CW (CW, vyhodnocuje se)\u000ASpotter: OK1RR
status	iaru	1	false	1	true
mode	iaru	1	CW	CW
predict	iaru	1	{exch=DARC}
tooltip	iaru	1	DA0HQ   7030.0 kHz\u000AM\u00F3d: CW (CW, vyhodnocuje se)\u000ASpotter: OK1RR
status	iaru	2	false	1	true
mode	iaru	2	CW	CW
predict	iaru	2	{exch=ARRL}
tooltip	iaru	2	W1AW/4   14035.0 kHz\u000AM\u00F3d: CW (CW, vyhodnocuje se)\u000ASpotter: OK1RR
status	iaru	3	false	1	true
mode	iaru	3	CW	CW
predict	iaru	3	{exch=ARRL}
tooltip	iaru	3	w1aw/4    14036.0 kHz\u000AM\u00F3d: CW (CW, vyhodnocuje se)\u000ASpotter: OK1RR
status	iaru	4	false	1	true
mode	iaru	4	CW	CW
predict	iaru	4	{exch=JARL}
tooltip	iaru	4	8N1HQ   21030.0 kHz\u000AM\u00F3d: CW (CW, vyhodnocuje se)\u000ASpotter: OK1RR
status	iaru	5	false	1	true
mode	iaru	5	CW	CW
predict	iaru	5	{exch=28}
tooltip	iaru	5	DL5AA   14040.0 kHz\u000AM\u00F3d: CW (CW, vyhodnocuje se)\u000ASpotter: OK1RR
status	iaru	6	false	1	true
mode	iaru	6	SSB	PHONE
predict	iaru	6	{exch=8}
tooltip	iaru	6	W1AW   14200.0 kHz\u000AM\u00F3d: SSB (PHONE, vyhodnocuje se)\u000AGrid: FN31 \u2192 pole FN\u000ASpotter: OK1RR
row	iaru	DA0HQ	7030000	297	CW	1	false	null	1	OK1RR	true
row	iaru	DA0HQ	14030000	297	CW	0	true	null	1	OK1RR	false
row	iaru	W1AW/4	14035000	309	CW	1	false	null	1	OK1RR	true
row	iaru	w1aw/4 	14036000	309	CW	1	false	null	1	OK1RR	true
row	iaru	DL5AA	14040000	297	CW	1	false	null	1	OK1RR	true
row	iaru	W1AW	14200000	309	SSB	1	false	null	5	OK1RR	true
row	iaru	8N1HQ	21030000	null	CW	1	false	null	1	OK1RR	true
grid	iaru	dxcc	false 0 0 rows=0 spotAt=[]
grid	iaru	grid	false 0 0 rows=0 spotAt=[]
grid	iaru	itu	true 0 75 rows=75 | 1/1//  | 8/8// 20m=SPOTTED, | 28/28// 40m=SPOTTED,20m=SPOTTED, | 75/75//  spotAt=[28@20m=DA0HQ@14030000, 28@40m=DA0HQ@7030000, 8@20m=W1AW/4@14035000]
grid	iaru	cq	false 0 0 rows=0 spotAt=[]
grid	iaru	districts	false 0 0 rows=0 spotAt=[]
grid	iaru	sections	false 0 0 rows=0 spotAt=[]
grid	iaru	other	true 1 117 rows=117 | AARA///  | DARC/// 20m=WORKED, | ZRS///  spotAt=[]
grid	iaru	bogus	false 0 0 rows=0 spotAt=[]
needs	okom	false	false
status	okom	0	true	0	false
mode	okom	0	CW	CW
predict	okom	0	{}
tooltip	okom	0	OK1ABC   14025.0 kHz\u000AM\u00F3d: CW (CW, vyhodnocuje se)\u000ASpotter: OK1RR
status	okom	1	false	1	true
mode	okom	1	CW	CW
predict	okom	1	{}
tooltip	okom	1	OK1ABC   7025.0 kHz\u000AM\u00F3d: CW (CW, vyhodnocuje se)\u000ASpotter: OK1RR
status	okom	2	false	1	true
mode	okom	2	CW	CW
predict	okom	2	{}
tooltip	okom	2	DL1ABC   14030.0 kHz\u000AM\u00F3d: CW (CW, vyhodnocuje se)\u000ASpotter: OK1RR
row	okom	OK1ABC	7025000	0	CW	1	false	null	0	OK1RR	true
row	okom	OK1ABC	14025000	0	CW	0	true	null	0	OK1RR	false
row	okom	DL1ABC	14030000	297	CW	1	false	null	1	OK1RR	true
grid	okom	dxcc	true 1 6 rows=6 | 503/Czech Republic/OK/EU 40m=SPOTTED,20m=WORKED, | 230/Germany/DL/EU 20m=SPOTTED, | 100/Argentina/LU/SA  spotAt=[230@20m=DL1ABC@14030000, 503@20m=OK1ABC@14025000, 503@40m=OK1ABC@7025000]
grid	okom	grid	false 0 0 rows=0 spotAt=[]
grid	okom	itu	false 0 0 rows=0 spotAt=[]
grid	okom	cq	false 0 0 rows=0 spotAt=[]
grid	okom	districts	true 1 3 rows=3 | APA/Praha//  | APB/P\u0159\u00EDbram// 20m=WORKED, spotAt=[]
grid	okom	sections	false 0 0 rows=0 spotAt=[]
grid	okom	other	false 0 0 rows=0 spotAt=[]
grid	okom	bogus	false 0 0 rows=0 spotAt=[]
needs	arrl	false	false
status	arrl	0	true	0	false
mode	arrl	0	CW	CW
predict	arrl	0	{}
tooltip	arrl	0	W1AW   14025.0 kHz\u000AM\u00F3d: CW (CW, vyhodnocuje se)\u000AGrid: FN31 \u2192 pole FN\u000ASpotter: OK1RR
status	arrl	1	false	0	false
mode	arrl	1	CW	CW
predict	arrl	1	{}
tooltip	arrl	1	K2ZZ   7025.0 kHz\u000AM\u00F3d: CW (CW, vyhodnocuje se)\u000ASpotter: OK1RR
row	arrl	K2ZZ	7025000	309	CW	0	false	null	3	OK1RR	false
row	arrl	W1AW	14025000	309	CW	0	true	null	3	OK1RR	false
grid	arrl	dxcc	false 0 0 rows=0 spotAt=[]
grid	arrl	grid	false 0 0 rows=0 spotAt=[]
grid	arrl	itu	false 0 0 rows=0 spotAt=[]
grid	arrl	cq	false 0 0 rows=0 spotAt=[]
grid	arrl	districts	false 0 0 rows=0 spotAt=[]
grid	arrl	sections	true 1 64 rows=64 | AL/Alabama//  | CT/Connecticut// 20m=WORKED, | NU/Nunavut//  spotAt=[]
grid	arrl	other	false 0 0 rows=0 spotAt=[]
grid	arrl	bogus	false 0 0 rows=0 spotAt=[]
sortRows	FREQ	true	A4 A2 A1 A3 A6 A5
sortRows	FREQ	false	A5 A6 A3 A1 A2 A4
sortRows	DIR	true	A3 A1 A4 A6 A2 A5
sortRows	DIR	false	A6 A4 A1 A3 A2 A5
sortRows	PTS	true	A4 A2 A6 A1 A3 A5
sortRows	PTS	false	A5 A3 A1 A6 A2 A4
"""#
}
