/// The output of a maintainer-only probe over the Kotlin `AppState` integration code
/// (v1.1.1, JDK 21) — byte for byte `integrations.tsv`. Replayed by the integration tests of `MCLCoreTests`.
enum IntegrationsJava {
    static let tsv: String = #"""
ingest	none	n1mm	<contactinfo><call>DL1ABC</call><mode>CW</mode><txfreq>1402500</txfreq><snt>599</snt><rcv>579</rcv><sntnr>1</sntnr><rcvnr>14</rcvnr><timestamp>2026-10-03 10:00:00</timestamp></contactinfo>	status	N1MM: p\u0159ijato QSO DL1ABC, ale nen\u00ED aktivn\u00ED z\u00E1vod \u2014 neulo\u017Eeno
ingest	none	ADIF	<call:6>DL1ABC <qso_date:8>20261003 <time_on:6>101500 <band:3>20m <mode:2>CW <eor>	status	ADIF: p\u0159ijato QSO DL1ABC, ale nen\u00ED aktivn\u00ED z\u00E1vod \u2014 neulo\u017Eeno
ingest	none	WSJT-X	<call:6>DL1ABC <qso_date:8>20261003 <time_on:6>101500 <band:3>20m <mode:3>FT8 <eor>	status	WSJT-X: p\u0159ijato QSO DL1ABC, ale nen\u00ED aktivn\u00ED z\u00E1vod \u2014 neulo\u017Eeno
ingest	none	ADIF	<qso_date:8>20261003 <time_on:6>101500 <band:3>20m <mode:3>FT8 <eor>	status	ADIF: p\u0159ijat\u00FD ADIF bez vola\u010Dky, ignoruji
ingest	cqww	n1mm	<contactinfo><app>N1MM</app></contactinfo>	drop
ingest	cqww	n1mm	no xml at all	drop
ingest	cqww	n1mm		drop
ingest	cqww	n1mm	<contactinfo><app>MacContestLogger</app><call>DL1ABC</call><mode>CW</mode><txfreq>1402500</txfreq><snt>599</snt><rcv>579</rcv><sntnr>1</sntnr><rcvnr>14</rcvnr><timestamp>2026-10-03 10:00:00</timestamp></contactinfo>	drop
ingest	cqww	n1mm	<contactinfo><app>N1MM</app><call>DL1ABC</call><mode>CW</mode><txfreq>1402500</txfreq><snt>599</snt><rcv>579</rcv><sntnr>1</sntnr><rcvnr>14</rcvnr><timestamp>2026-10-03 10:00:00</timestamp><StationName>OK1XOE</StationName></contactinfo>	drop
ingest	cqww	n1mm	<contactinfo><app>N1MM</app><call>DL1ABC</call><mode>CW</mode><txfreq>1402500</txfreq><snt>599</snt><rcv>579</rcv><sntnr>1</sntnr><rcvnr>14</rcvnr><timestamp>2026-10-03 10:00:00</timestamp><StationName>OK1ZZZ</StationName></contactinfo>	log	true	N1MM: importov\u00E1no QSO DL1ABC	DL1ABC|20m|CW|14025000|599|579|<null>|579 14|1|14|<null>|SEARCH_AND_POUNCE|true|2026-10-03T10:00:00Z
ingest	cqww	n1mm	<contactinfo><app>N1MM</app><call>DL1ABC</call><mode>CW</mode><txfreq>1402500</txfreq><snt>599</snt><rcv>579</rcv><sntnr>1</sntnr><rcvnr>14</rcvnr><timestamp>2026-10-03 10:00:00</timestamp><StationName>OK1ZZZ</StationName></contactinfo>	drop
ingest	cqww	n1mm	<contactinfo><app>N1MM</app><call>DL1ABC</call><mode>CW</mode><txfreq>1402500</txfreq><snt>599</snt><rcv>579</rcv><sntnr>1</sntnr><rcvnr>14</rcvnr><timestamp>2026-10-03 10:01:59</timestamp><StationName>OK1ZZZ</StationName></contactinfo>	drop
ingest	cqww	n1mm	<contactinfo><app>N1MM</app><call>DL1ABC</call><mode>CW</mode><txfreq>1402500</txfreq><snt>599</snt><rcv>579</rcv><sntnr>1</sntnr><rcvnr>14</rcvnr><timestamp>2026-10-03 10:02:01</timestamp><StationName>OK1ZZZ</StationName></contactinfo>	log	true	N1MM: importov\u00E1no QSO DL1ABC	DL1ABC|20m|CW|14025000|599|579|<null>|579 14|2|14|<null>|SEARCH_AND_POUNCE|true|2026-10-03T10:02:01Z
ingest	cqww	n1mm	<contactinfo><app>N1MM</app><call>DL1ABC</call><mode>CW</mode><txfreq>1402500</txfreq><snt>599</snt><rcv>579</rcv><sntnr>1</sntnr><rcvnr>14</rcvnr><timestamp>2026-10-03 09:58:01</timestamp><StationName>OK1ZZZ</StationName></contactinfo>	drop
ingest	cqww	n1mm	<contactinfo><app>N1MM</app><call>DL1ABC</call><mode>CW</mode><txfreq>2102500</txfreq><snt>599</snt><rcv>579</rcv><sntnr>1</sntnr><rcvnr>14</rcvnr><timestamp>2026-10-03 10:00:00</timestamp><StationName>OK1ZZZ</StationName></contactinfo>	log	true	N1MM: importov\u00E1no QSO DL1ABC	DL1ABC|15m|CW|21025000|599|579|<null>|579 14|3|14|<null>|SEARCH_AND_POUNCE|true|2026-10-03T10:00:00Z
ingest	cqww	n1mm	<contactinfo><app>N1MM</app><call>JA1XYZ</call><mode>SSB</mode><txfreq>1425000</txfreq><snt>59</snt><rcv>59</rcv><sntnr>2</sntnr><rcvnr>25</rcvnr><timestamp>2026-10-03 10:05:00</timestamp><StationName>OK1ZZZ</StationName></contactinfo>	log	false	N1MM: QSO JA1XYZ v m\u00F3du SSB \u2014 z\u00E1vod ho nem\u00E1, do sk\u00F3re se nepo\u010D\u00EDt\u00E1	JA1XYZ|20m|SSB|14250000|59|59|<null>|59 25|4|25|<null>|SEARCH_AND_POUNCE|true|2026-10-03T10:05:00Z
ingest	cqww	n1mm	<contactinfo><app>N1MM</app><call>W1AW</call><timestamp>2026-10-03 10:06:00</timestamp><StationName>OK1ZZZ</StationName></contactinfo>	log	false	N1MM: QSO W1AW v m\u00F3du SSB \u2014 z\u00E1vod ho nem\u00E1, do sk\u00F3re se nepo\u010D\u00EDt\u00E1	W1AW|<null>|<null>|0|<null>|<null>|<null>|<null>|5|null|<null>|SEARCH_AND_POUNCE|true|2026-10-03T10:06:00Z
ingest	cqww	n1mm	<contactinfo><app>N1MM</app><call>VE3XYZ</call><mode>RTTY</mode><txfreq>700000</txfreq><snt>599</snt><rcv>599</rcv><sntnr>x</sntnr><rcvnr>5</rcvnr><timestamp>2026-10-03 10:07:00</timestamp><gridsquare>FN03</gridsquare><StationName>OK1ZZZ</StationName></contactinfo>	log	false	N1MM: QSO VE3XYZ v m\u00F3du RTTY \u2014 z\u00E1vod ho nem\u00E1, do sk\u00F3re se nepo\u010D\u00EDt\u00E1	VE3XYZ|40m|RTTY|7000000|599|599|<null>|599 5|6|5|<null>|SEARCH_AND_POUNCE|true|2026-10-03T10:07:00Z
ingest	cqww	n1mm	<contactinfo><app>N1MM</app><call>K1ABC</call><mode>CW</mode><txfreq>1402500</txfreq><snt>599</snt><rcv>579</rcv><sntnr>3</sntnr><rcvnr>5 4</rcvnr><timestamp>2026-10-03 10:08:00</timestamp><StationName>OK1ZZZ</StationName></contactinfo>	log	true	N1MM: importov\u00E1no QSO K1ABC	K1ABC|20m|CW|14025000|599|579|<null>|579 5|7|null|<null>|SEARCH_AND_POUNCE|true|2026-10-03T10:08:00Z
ingest	cqww	n1mm	<contactinfo><app>N1MM</app><call>K2ABC</call><mode>CW</mode><txfreq>1402500</txfreq><snt>599</snt><rcv>579</rcv><sntnr>3</sntnr><rcvnr>5</rcvnr><StationName>OK1ZZZ</StationName></contactinfo>	log	true	N1MM: importov\u00E1no QSO K2ABC	K2ABC|20m|CW|14025000|599|579|<null>|579 5|8|5|<null>|SEARCH_AND_POUNCE|true|-
ingest	cqww	n1mm	<contactinfo><app>N1MM</app><call>A&amp;B</call><mode>CW</mode><txfreq>1402500</txfreq><snt>599</snt><rcv>579</rcv><sntnr>3</sntnr><rcvnr>5</rcvnr><timestamp>2026-10-03 10:09:00</timestamp><StationName>OK1ZZZ</StationName></contactinfo>	log	true	N1MM: importov\u00E1no QSO A&AMP;B	A&AMP;B|20m|CW|14025000|599|579|<null>|579 5|9|5|<null>|SEARCH_AND_POUNCE|true|2026-10-03T10:09:00Z
ingest	cqww	n1mm	<contactinfo><app>N1MM</app><call>VK3ABC</call><mode>CW</mode><txfreq>700000</txfreq><snt>599</snt><rcv>579</rcv><sntnr>3</sntnr><rcvnr>30</rcvnr><timestamp>2026-10-03 10:10:00</timestamp><StationName>OK1ZZZ</StationName></contactinfo>	log	true	N1MM: importov\u00E1no QSO VK3ABC	VK3ABC|40m|CW|7000000|599|579|<null>|579 30|10|30|<null>|SEARCH_AND_POUNCE|true|2026-10-03T10:10:00Z
ingest	cqww	n1mm	<contactinfo><app>N1MM</app><call>VK3ABD</call><mode>CW</mode><txfreq>700000</txfreq><snt>599</snt><rcv>579</rcv><sntnr>3</sntnr><rcvnr>99</rcvnr><timestamp>2026-10-03 10:11:00</timestamp><StationName>OK1ZZZ</StationName></contactinfo>	log	true	N1MM: importov\u00E1no QSO VK3ABD	VK3ABD|40m|CW|7000000|599|579|<null>|579 99|11|99|<null>|SEARCH_AND_POUNCE|true|2026-10-03T10:11:00Z
ingest	cqww	n1mm	<contactinfo><call>ZL1ABC</call><mode>CW</mode><txfreq>2100000</txfreq><snt>599</snt><rcv>579</rcv><sntnr>1</sntnr><rcvnr>26</rcvnr><timestamp>not a time</timestamp></contactinfo>	log	true	N1MM: importov\u00E1no QSO ZL1ABC	ZL1ABC|15m|CW|21000000|599|579|<null>|579 26|12|26|<null>|SEARCH_AND_POUNCE|true|-
ingest	cqww	ADIF	<call:6>DL2ABC <qso_date:8>20261003 <time_on:6>110000 <band:3>20m <mode:2>CW <rst_rcvd:3>579 <srx_string:2>14 <eor>	log	true	ADIF: importov\u00E1no QSO DL2ABC	DL2ABC|20m|CW|0|<null>|579|<null>|579 14|13|null|<null>|SEARCH_AND_POUNCE|true|2026-10-03T11:00:00Z
ingest	cqww	WSJT-X	<call:6>DL2ABC <qso_date:8>20261003 <time_on:6>110000 <band:3>20m <mode:2>CW <rst_rcvd:3>579 <srx_string:2>14 <eor>	drop
ingest	cqww	ADIF	<call:6>DL3ABC <qso_date:8>20261003 <time_on:6>110100 <freq:6>14.074 <mode:3>FT8 <rst_rcvd:3>-12 <gridsquare:4>JO31 <eor>	log	false	ADIF: QSO DL3ABC v m\u00F3du FT8 \u2014 z\u00E1vod ho nem\u00E1, do sk\u00F3re se nepo\u010D\u00EDt\u00E1	DL3ABC|20m|FT8|14074000|<null>|-12|<null>|-12|14|null|<null>|SEARCH_AND_POUNCE|true|2026-10-03T11:01:00Z
ingest	cqww	WSJT-X	<call:6>DL4ABC <qso_date:8>20261003 <time_on:6>110200 <freq:6>14.025 <mode:2>CW <rst_rcvd:3>599 <rst_sent:3>589 <srx_string:6>579 15 <comment:4>note <eor>	log	true	WSJT-X: importov\u00E1no QSO DL4ABC	DL4ABC|20m|CW|14025000|589|599|<null>|599 579|15|null|note|SEARCH_AND_POUNCE|true|2026-10-03T11:02:00Z
ingest	cqww	ADIF	<call:6>DL5ABC <qso_date:8>20261003 <time_on:6>110300 <band:3>40m <mode:2>CW <srx:1>7 <rst_rcvd:3>599 <eor>	log	true	ADIF: importov\u00E1no QSO DL5ABC	DL5ABC|40m|CW|0|<null>|599|<null>|599 7|16|null|<null>|SEARCH_AND_POUNCE|true|2026-10-03T11:03:00Z
ingest	cqww	WSJT-X	<call:6>DL6ABC <qso_date:8>20261003 <time_on:6>110400 <band:3>40m <eor>	log	false	WSJT-X: QSO DL6ABC v m\u00F3du FT8 \u2014 z\u00E1vod ho nem\u00E1, do sk\u00F3re se nepo\u010D\u00EDt\u00E1	DL6ABC|40m|<null>|0|<null>|<null>|<null>|<null>|17|null|<null>|SEARCH_AND_POUNCE|true|2026-10-03T11:04:00Z
ingest	cqww	ADIF	<call:6>DL7ABC <mode:2>CW <band:3>40m <srx_string:2>22 <eor>	log	true	ADIF: importov\u00E1no QSO DL7ABC	DL7ABC|40m|CW|0|<null>|<null>|<null>|22|18|null|<null>|SEARCH_AND_POUNCE|true|-
ingest	cqww	WSJT-X	<call:1>  <qso_date:8>20261003 <time_on:6>110500 <band:3>20m <mode:2>CW <eor>	status	WSJT-X: p\u0159ijat\u00FD ADIF bez vola\u010Dky, ignoruji
ingest	cqww	ADIF	<qso_date:8>20261003 <time_on:6>110500 <band:3>20m <mode:2>CW <eor>	status	ADIF: p\u0159ijat\u00FD ADIF bez vola\u010Dky, ignoruji
ingest	cqww	WSJT-X		status	WSJT-X: p\u0159ijat\u00FD ADIF bez vola\u010Dky, ignoruji
ingest	cqww	ADIF	garbage without any tag	status	ADIF: p\u0159ijat\u00FD ADIF bez vola\u010Dky, ignoruji
ingest	cqww	WSJT-X	<call:5>DL8AB	log	false	WSJT-X: QSO DL8AB v m\u00F3du FT8 \u2014 z\u00E1vod ho nem\u00E1, do sk\u00F3re se nepo\u010D\u00EDt\u00E1	DL8AB|<null>|<null>|0|<null>|<null>|<null>|<null>|19|null|<null>|SEARCH_AND_POUNCE|true|-
ingest	cqww	ADIF	<call:6>DL9ABC <qso_date:8>20261003 <time_on:6>110600 <band:3>20m <mode:4>MFSK <submode:3>FT4 <srx_string:2>14 <eor>	log	false	ADIF: QSO DL9ABC v m\u00F3du FT8 \u2014 z\u00E1vod ho nem\u00E1, do sk\u00F3re se nepo\u010D\u00EDt\u00E1	DL9ABC|20m|<null>|0|<null>|<null>|<null>|14|20|null|<null>|SEARCH_AND_POUNCE|true|2026-10-03T11:06:00Z
ingest	wwdigi	WSJT-X	<call:5>DL1AE <qso_date:8>20261003 <time_on:6>120000 <freq:6>14.074 <mode:3>FT8 <gridsquare:4>JO31 <eor>	log	true	WSJT-X: importov\u00E1no QSO DL1AE	DL1AE|20m|FT8|14074000|<null>|<null>|<null>|JO31|1|null|<null>|SEARCH_AND_POUNCE|true|2026-10-03T12:00:00Z
ingest	wwdigi	WSJT-X	<call:5>DL1AE <qso_date:8>20261003 <time_on:6>120100 <freq:6>14.074 <mode:3>FT8 <gridsquare:4>JO31 <eor>	drop
ingest	wwdigi	WSJT-X	<call:6>JA1QQQ <qso_date:8>20261003 <time_on:6>120200 <freq:6>21.074 <mode:3>FT8 <srx_string:4>PM95 <eor>	log	true	WSJT-X: importov\u00E1no QSO JA1QQQ	JA1QQQ|15m|FT8|21074000|<null>|<null>|<null>|PM95|2|null|<null>|SEARCH_AND_POUNCE|true|2026-10-03T12:02:00Z
ingest	wwdigi	WSJT-X	<call:4>W1AW <qso_date:8>20261003 <time_on:6>120300 <freq:6>14.074 <mode:2>CW <gridsquare:4>FN31 <eor>	log	false	WSJT-X: QSO W1AW v m\u00F3du CW \u2014 z\u00E1vod ho nem\u00E1, do sk\u00F3re se nepo\u010D\u00EDt\u00E1	W1AW|20m|CW|14074000|<null>|<null>|<null>|FN31|3|null|<null>|SEARCH_AND_POUNCE|true|2026-10-03T12:03:00Z
ingest	wwdigi	WSJT-X	<call:5>K1ABC <qso_date:8>20261003 <time_on:6>120400 <freq:6>14.074 <gridsquare:4>FN42 <eor>	log	true	WSJT-X: importov\u00E1no QSO K1ABC	K1ABC|20m|<null>|14074000|<null>|<null>|<null>|FN42|4|null|<null>|SEARCH_AND_POUNCE|true|2026-10-03T12:04:00Z
ingest	wwdigi	WSJT-X	<call:5>K2ABC <qso_date:8>20261003 <time_on:6>120500 <freq:6>14.074 <mode:4>RTTY <gridsquare:4>FN42 <eor>	log	true	WSJT-X: importov\u00E1no QSO K2ABC	K2ABC|20m|RTTY|14074000|<null>|<null>|<null>|FN42|5|null|<null>|SEARCH_AND_POUNCE|true|2026-10-03T12:05:00Z
ingest	wwdigi	n1mm	<contactinfo><app>N1MM</app><call>DL2AE</call><mode>RTTY</mode><txfreq>1407400</txfreq><snt>599</snt><rcv>599</rcv><sntnr>1</sntnr><rcvnr>JO31</rcvnr><timestamp>2026-10-03 12:10:00</timestamp><gridsquare>JO31</gridsquare><StationName>OK1ZZZ</StationName></contactinfo>	log	true	N1MM: importov\u00E1no QSO DL2AE	DL2AE|20m|RTTY|14074000|599|599|<null>|JO31|6|null|<null>|SEARCH_AND_POUNCE|true|2026-10-03T12:10:00Z
ingest	wwdigi	n1mm	<contactinfo><app>N1MM</app><call>DL3AE</call><mode>CW</mode><txfreq>1407400</txfreq><snt>599</snt><rcv>599</rcv><sntnr>1</sntnr><rcvnr>JO32</rcvnr><timestamp>2026-10-03 12:11:00</timestamp><gridsquare>JO32</gridsquare><StationName>OK1ZZZ</StationName></contactinfo>	log	false	N1MM: QSO DL3AE v m\u00F3du CW \u2014 z\u00E1vod ho nem\u00E1, do sk\u00F3re se nepo\u010D\u00EDt\u00E1	DL3AE|20m|CW|14074000|599|599|<null>|JO32|7|null|<null>|SEARCH_AND_POUNCE|true|2026-10-03T12:11:00Z
ingest	wwdigi	n1mm	<contactinfo><app>N1MM</app><call>DL4AE</call><txfreq>1407400</txfreq><snt>599</snt><rcv>599</rcv><sntnr>1</sntnr><rcvnr>JO32</rcvnr><timestamp>2026-10-03 12:12:00</timestamp><gridsquare>JO32</gridsquare><StationName>OK1ZZZ</StationName></contactinfo>	log	false	N1MM: QSO DL4AE v m\u00F3du SSB \u2014 z\u00E1vod ho nem\u00E1, do sk\u00F3re se nepo\u010D\u00EDt\u00E1	DL4AE|20m|<null>|14074000|599|599|<null>|JO32|8|null|<null>|SEARCH_AND_POUNCE|true|2026-10-03T12:12:00Z
ingest	wpx	ADIF	<call:6>DL1WPX <qso_date:8>20261003 <time_on:6>130000 <band:3>20m <mode:2>CW <rst_rcvd:3>599 <srx:2>12 <eor>	log	true	ADIF: importov\u00E1no QSO DL1WPX	DL1WPX|20m|CW|0|<null>|599|<null>|599 12|1|12|<null>|SEARCH_AND_POUNCE|true|2026-10-03T13:00:00Z
ingest	wpx	ADIF	<call:6>DL2WPX <qso_date:8>20261003 <time_on:6>130100 <band:3>20m <mode:2>CW <rst_rcvd:3>599 <srx_string:7>599 013 <eor>	log	true	ADIF: importov\u00E1no QSO DL2WPX	DL2WPX|20m|CW|0|<null>|599|<null>|599 13|2|13|<null>|SEARCH_AND_POUNCE|true|2026-10-03T13:01:00Z
ingest	wpx	ADIF	<call:6>DL3WPX <qso_date:8>20261003 <time_on:6>130200 <band:3>20m <mode:2>CW <rst_rcvd:3>579 <srx_string:3>345 <eor>	log	true	ADIF: importov\u00E1no QSO DL3WPX	DL3WPX|20m|CW|0|<null>|579|<null>|579 345|3|345|<null>|SEARCH_AND_POUNCE|true|2026-10-03T13:02:00Z
ingest	wpx	ADIF	<call:6>DL4WPX <qso_date:8>20261003 <time_on:6>130300 <band:3>20m <mode:2>CW <srx:11>99999999999 <eor>	logfail	-	ADIF: import selhal (For input string: "99999999999")	DL4WPX|20m|CW|0|<null>|<null>|<null>|99999999999|4|null|<null>|SEARCH_AND_POUNCE|true|2026-10-03T13:03:00Z
ingest	wpx	ADIF	<call:6>DL5WPX <qso_date:8>20261003 <time_on:6>130400 <band:3>20m <mode:2>CW <srx:1>x <eor>	log	true	ADIF: importov\u00E1no QSO DL5WPX	DL5WPX|20m|CW|0|<null>|<null>|<null>|<null>|5|null|<null>|SEARCH_AND_POUNCE|true|2026-10-03T13:04:00Z
ingest	wpx	n1mm	<contactinfo><app>N1MM</app><call>DL6WPX</call><mode>CW</mode><txfreq>1402500</txfreq><snt>599</snt><rcv>579</rcv><sntnr>7</sntnr><rcvnr>21</rcvnr><timestamp>2026-10-03 13:10:00</timestamp><StationName>OK1ZZZ</StationName></contactinfo>	log	true	N1MM: importov\u00E1no QSO DL6WPX	DL6WPX|20m|CW|14025000|599|579|<null>|579 21|6|21|<null>|SEARCH_AND_POUNCE|true|2026-10-03T13:10:00Z
ingest	wpx	n1mm	<contactinfo><app>N1MM</app><call>DL7WPX</call><mode>CW</mode><txfreq>1402500</txfreq><snt>599</snt><rcv>579</rcv><sntnr>7</sntnr><rcvnr>21</rcvnr><timestamp>2026-10-03 13:11:00</timestamp><StationName>OK1ZZZ</StationName></contactinfo>	log	true	N1MM: importov\u00E1no QSO DL7WPX	DL7WPX|20m|CW|14025000|599|579|<null>|579 21|7|21|<null>|SEARCH_AND_POUNCE|true|2026-10-03T13:11:00Z
bcast	none	contact-full	<contactinfo><app>MacContestLogger</app><contestname></contestname><contestnr>123456789</contestnr><timestamp>2026-10-03 10:00:00</timestamp><mycall>OK1XOE</mycall><band>14</band><rxfreq>1402500</rxfreq><txfreq>1402500</txfreq><mode>CW</mode><call>DL1ABC</call><countryprefix></countryprefix><wpxprefix></wpxprefix><stationprefix>OK1XOE</stationprefix><continent>EU</continent><snt>599</snt><sntnr>5</sntnr><rcv>579</rcv><rcvnr>14</rcvnr><points>3</points><ismultiplier1>1</ismultiplier1><ismultiplier2>0</ismultiplier2><ismultiplier3>0</ismultiplier3><ID>11111111-2222-3333-4444-555555555555</ID><IsOriginal>True</IsOriginal><IsClaimedQso>1</IsClaimedQso><StationName>OK1XOE</StationName></contactinfo>
bcast	none	replace-full	<contactreplace><app>MacContestLogger</app><contestname></contestname><contestnr>123456789</contestnr><timestamp>2026-10-03 10:00:00</timestamp><mycall>OK1XOE</mycall><band>14</band><rxfreq>1402500</rxfreq><txfreq>1402500</txfreq><mode>CW</mode><call>DL1ABC</call><countryprefix></countryprefix><wpxprefix></wpxprefix><stationprefix>OK1XOE</stationprefix><continent>EU</continent><snt>599</snt><sntnr>5</sntnr><rcv>579</rcv><rcvnr>14</rcvnr><points>3</points><ismultiplier1>1</ismultiplier1><ismultiplier2>0</ismultiplier2><ismultiplier3>0</ismultiplier3><ID>11111111-2222-3333-4444-555555555555</ID><IsOriginal>True</IsOriginal><IsClaimedQso>1</IsClaimedQso><StationName>OK1XOE</StationName><oldcall>DL1ABC</oldcall><oldtimestamp>2026-10-03 10:00:00</oldtimestamp></contactreplace>
bcast	none	contact-bare	<contactinfo><app>MacContestLogger</app><contestname></contestname><contestnr>123456789</contestnr><timestamp></timestamp><mycall>OK1XOE</mycall><band></band><rxfreq>0</rxfreq><txfreq>0</txfreq><mode></mode><call></call><countryprefix></countryprefix><wpxprefix></wpxprefix><stationprefix>OK1XOE</stationprefix><continent></continent><snt></snt><sntnr></sntnr><rcv></rcv><rcvnr></rcvnr><points>0</points><ismultiplier1>0</ismultiplier1><ismultiplier2>0</ismultiplier2><ismultiplier3>0</ismultiplier3><ID></ID><IsOriginal>True</IsOriginal><IsClaimedQso>1</IsClaimedQso><StationName>OK1XOE</StationName></contactinfo>
bcast	none	replace-bare	<contactreplace><app>MacContestLogger</app><contestname></contestname><contestnr>123456789</contestnr><timestamp></timestamp><mycall>OK1XOE</mycall><band></band><rxfreq>0</rxfreq><txfreq>0</txfreq><mode></mode><call></call><countryprefix></countryprefix><wpxprefix></wpxprefix><stationprefix>OK1XOE</stationprefix><continent></continent><snt></snt><sntnr></sntnr><rcv></rcv><rcvnr></rcvnr><points>0</points><ismultiplier1>0</ismultiplier1><ismultiplier2>0</ismultiplier2><ismultiplier3>0</ismultiplier3><ID></ID><IsOriginal>True</IsOriginal><IsClaimedQso>1</IsClaimedQso><StationName>OK1XOE</StationName><oldcall></oldcall><oldtimestamp></oldtimestamp></contactreplace>
bcast	none	score	<null>
bcast	none	appinfo	<AppInfo><app>MacContestLogger</app><dbname>logbook.sqlite</dbname><contestnr>123456789</contestnr><contestname></contestname><StationName>OK1XOE</StationName><mycall>OK1XOE</mycall></AppInfo>
bcast	none	radio-0	<null>
bcast	none	radio-1	<null>
bcast	none	radio-2	<RadioInfo><app>MacContestLogger</app><StationName>OK1XOE</StationName><RadioNr>1</RadioNr><Freq>1402500</Freq><TXFreq>1402500</TXFreq><Mode>CW</Mode><OpCall>OK1XOE</OpCall><IsRunning>False</IsRunning><FocusRadioNr>1</FocusRadioNr><ActiveRadioNr>1</ActiveRadioNr><IsTransmitting>False</IsTransmitting><IsStereo>False</IsStereo><IsSplit>False</IsSplit></RadioInfo>
bcast	none	radio-3	<RadioInfo><app>MacContestLogger</app><StationName>OK1XOE</StationName><RadioNr>1</RadioNr><Freq>707400</Freq><TXFreq>707400</TXFreq><Mode>FT8</Mode><OpCall>OK1XOE</OpCall><IsRunning>True</IsRunning><FocusRadioNr>1</FocusRadioNr><ActiveRadioNr>1</ActiveRadioNr><IsTransmitting>False</IsTransmitting><IsStereo>False</IsStereo><IsSplit>False</IsSplit></RadioInfo>
bcast	none	radio-4	<RadioInfo><app>MacContestLogger</app><StationName>OK1XOE</StationName><RadioNr>1</RadioNr><Freq>360000</Freq><TXFreq>360000</TXFreq><Mode></Mode><OpCall>OK1XOE</OpCall><IsRunning>True</IsRunning><FocusRadioNr>1</FocusRadioNr><ActiveRadioNr>1</ActiveRadioNr><IsTransmitting>False</IsTransmitting><IsStereo>False</IsStereo><IsSplit>False</IsSplit></RadioInfo>
bcast	cq-ww-cw	contact-full	<contactinfo><app>MacContestLogger</app><contestname>CQ WW DX Contest \u2014 CW</contestname><contestnr>123456789</contestnr><timestamp>2026-10-03 10:00:00</timestamp><mycall>OK1XOE</mycall><band>14</band><rxfreq>1402500</rxfreq><txfreq>1402500</txfreq><mode>CW</mode><call>DL1ABC</call><countryprefix></countryprefix><wpxprefix></wpxprefix><stationprefix>OK1XOE</stationprefix><continent>EU</continent><snt>599</snt><sntnr>5</sntnr><rcv>579</rcv><rcvnr>14</rcvnr><points>3</points><ismultiplier1>1</ismultiplier1><ismultiplier2>0</ismultiplier2><ismultiplier3>0</ismultiplier3><ID>11111111-2222-3333-4444-555555555555</ID><IsOriginal>True</IsOriginal><IsClaimedQso>1</IsClaimedQso><StationName>OK1XOE</StationName></contactinfo>
bcast	cq-ww-cw	replace-full	<contactreplace><app>MacContestLogger</app><contestname>CQ WW DX Contest \u2014 CW</contestname><contestnr>123456789</contestnr><timestamp>2026-10-03 10:00:00</timestamp><mycall>OK1XOE</mycall><band>14</band><rxfreq>1402500</rxfreq><txfreq>1402500</txfreq><mode>CW</mode><call>DL1ABC</call><countryprefix></countryprefix><wpxprefix></wpxprefix><stationprefix>OK1XOE</stationprefix><continent>EU</continent><snt>599</snt><sntnr>5</sntnr><rcv>579</rcv><rcvnr>14</rcvnr><points>3</points><ismultiplier1>1</ismultiplier1><ismultiplier2>0</ismultiplier2><ismultiplier3>0</ismultiplier3><ID>11111111-2222-3333-4444-555555555555</ID><IsOriginal>True</IsOriginal><IsClaimedQso>1</IsClaimedQso><StationName>OK1XOE</StationName><oldcall>DL1ABC</oldcall><oldtimestamp>2026-10-03 10:00:00</oldtimestamp></contactreplace>
bcast	cq-ww-cw	contact-bare	<contactinfo><app>MacContestLogger</app><contestname>CQ WW DX Contest \u2014 CW</contestname><contestnr>123456789</contestnr><timestamp></timestamp><mycall>OK1XOE</mycall><band></band><rxfreq>0</rxfreq><txfreq>0</txfreq><mode></mode><call></call><countryprefix></countryprefix><wpxprefix></wpxprefix><stationprefix>OK1XOE</stationprefix><continent></continent><snt></snt><sntnr></sntnr><rcv></rcv><rcvnr></rcvnr><points>0</points><ismultiplier1>0</ismultiplier1><ismultiplier2>0</ismultiplier2><ismultiplier3>0</ismultiplier3><ID></ID><IsOriginal>True</IsOriginal><IsClaimedQso>1</IsClaimedQso><StationName>OK1XOE</StationName></contactinfo>
bcast	cq-ww-cw	replace-bare	<contactreplace><app>MacContestLogger</app><contestname>CQ WW DX Contest \u2014 CW</contestname><contestnr>123456789</contestnr><timestamp></timestamp><mycall>OK1XOE</mycall><band></band><rxfreq>0</rxfreq><txfreq>0</txfreq><mode></mode><call></call><countryprefix></countryprefix><wpxprefix></wpxprefix><stationprefix>OK1XOE</stationprefix><continent></continent><snt></snt><sntnr></sntnr><rcv></rcv><rcvnr></rcvnr><points>0</points><ismultiplier1>0</ismultiplier1><ismultiplier2>0</ismultiplier2><ismultiplier3>0</ismultiplier3><ID></ID><IsOriginal>True</IsOriginal><IsClaimedQso>1</IsClaimedQso><StationName>OK1XOE</StationName><oldcall></oldcall><oldtimestamp></oldtimestamp></contactreplace>
bcast	cq-ww-cw	score	<dynamicresults><contest>CQ WW DX Contest \u2014 CW</contest><call>OK1XOE</call><ops>OK1XOE</ops><score>16</score><timestamp><instant></timestamp></dynamicresults>
bcast	cq-ww-cw	appinfo	<AppInfo><app>MacContestLogger</app><dbname>logbook.sqlite</dbname><contestnr>123456789</contestnr><contestname>CQ WW DX Contest \u2014 CW</contestname><StationName>OK1XOE</StationName><mycall>OK1XOE</mycall></AppInfo>
bcast	cq-ww-cw	radio-0	<null>
bcast	cq-ww-cw	radio-1	<null>
bcast	cq-ww-cw	radio-2	<RadioInfo><app>MacContestLogger</app><StationName>OK1XOE</StationName><RadioNr>1</RadioNr><Freq>1402500</Freq><TXFreq>1402500</TXFreq><Mode>CW</Mode><OpCall>OK1XOE</OpCall><IsRunning>False</IsRunning><FocusRadioNr>1</FocusRadioNr><ActiveRadioNr>1</ActiveRadioNr><IsTransmitting>False</IsTransmitting><IsStereo>False</IsStereo><IsSplit>False</IsSplit></RadioInfo>
bcast	cq-ww-cw	radio-3	<RadioInfo><app>MacContestLogger</app><StationName>OK1XOE</StationName><RadioNr>1</RadioNr><Freq>707400</Freq><TXFreq>707400</TXFreq><Mode>FT8</Mode><OpCall>OK1XOE</OpCall><IsRunning>True</IsRunning><FocusRadioNr>1</FocusRadioNr><ActiveRadioNr>1</ActiveRadioNr><IsTransmitting>False</IsTransmitting><IsStereo>False</IsStereo><IsSplit>False</IsSplit></RadioInfo>
bcast	cq-ww-cw	radio-4	<RadioInfo><app>MacContestLogger</app><StationName>OK1XOE</StationName><RadioNr>1</RadioNr><Freq>360000</Freq><TXFreq>360000</TXFreq><Mode></Mode><OpCall>OK1XOE</OpCall><IsRunning>True</IsRunning><FocusRadioNr>1</FocusRadioNr><ActiveRadioNr>1</ActiveRadioNr><IsTransmitting>False</IsTransmitting><IsStereo>False</IsStereo><IsSplit>False</IsSplit></RadioInfo>
decode	none	0	CQ DL1AE JO31	1000	1	0 false 0 DL1AE  true JO31
decode	none	0	CQ DX JA1QQQ PM95	1001	1	0 false 0 JA1QQQ  true PM95
decode	none	0	OK1XOE DL1AE -12	1002	1	0 false 0 DL1AE OK1XOE false 
decode	none	0	DL1AE OK1XOE R-05	1003	1	0 false 0 OK1XOE DL1AE false 
decode	none	0	CQ W1AW FN31	1004	1	0 false 0 W1AW  true FN31
decode	none	0	CQ K2ABC FN42	1005	1	0 false 0 K2ABC  true FN42
decode	none	0	CQ TEST VE3XYZ FN03	1006	1	0 false 0 VE3XYZ  true FN03
decode	none	0	<DL9ABC> OK1XOE RR73	1007	1	0 false 0 OK1XOE DL9ABC false 
decode	none	0	73	1008	1	0 false 0   false 
decode	none	0		1009	1	0 false 0   false 
decode	none	0	CQ	1010	1	0 false 0   true 
decode	none	0	CQ NA 3Z1ABC	1011	1	0 false 0 3Z1ABC  true 
decode	none	1	CQ DL1AE JO31	1012	1	0 false 0 DL1AE  true JO31
decode	none	1	CQ DX JA1QQQ PM95	1013	1	0 false 0 JA1QQQ  true PM95
decode	none	1	OK1XOE DL1AE -12	1014	1	0 false 0 DL1AE OK1XOE false 
decode	none	1	DL1AE OK1XOE R-05	1015	1	0 false 0 OK1XOE DL1AE false 
decode	none	1	CQ W1AW FN31	1016	1	0 false 0 W1AW  true FN31
decode	none	1	CQ K2ABC FN42	1017	1	0 false 0 K2ABC  true FN42
decode	none	1	CQ TEST VE3XYZ FN03	1018	1	0 false 0 VE3XYZ  true FN03
decode	none	1	<DL9ABC> OK1XOE RR73	1019	1	0 false 0 OK1XOE DL9ABC false 
decode	none	1	73	1020	1	0 false 0   false 
decode	none	1		1021	1	0 false 0   false 
decode	none	1	CQ	1022	1	0 false 0   true 
decode	none	1	CQ NA 3Z1ABC	1023	1	0 false 0 3Z1ABC  true 
decode	none	2	CQ DL1AE JO31	1024	1	14075024 false 0 DL1AE  true JO31
decode	none	2	CQ DX JA1QQQ PM95	1025	1	14075025 false 0 JA1QQQ  true PM95
decode	none	2	OK1XOE DL1AE -12	1026	1	14075026 false 0 DL1AE OK1XOE false 
decode	none	2	DL1AE OK1XOE R-05	1027	1	14075027 false 0 OK1XOE DL1AE false 
decode	none	2	CQ W1AW FN31	1028	1	14075028 false 0 W1AW  true FN31
decode	none	2	CQ K2ABC FN42	1029	1	14075029 false 0 K2ABC  true FN42
decode	none	2	CQ TEST VE3XYZ FN03	1030	1	14075030 false 0 VE3XYZ  true FN03
decode	none	2	<DL9ABC> OK1XOE RR73	1031	1	14075031 false 0 OK1XOE DL9ABC false 
decode	none	2	73	1032	1	14075032 false 0   false 
decode	none	2		1033	1	14075033 false 0   false 
decode	none	2	CQ	1034	1	14075034 false 0   true 
decode	none	2	CQ NA 3Z1ABC	1035	1	14075035 false 0 3Z1ABC  true 
decode	none	3	CQ DL1AE JO31	1036	1	14075036 false 0 DL1AE  true JO31
decode	none	3	CQ DX JA1QQQ PM95	1037	1	14075037 false 0 JA1QQQ  true PM95
decode	none	3	OK1XOE DL1AE -12	1038	1	14075038 false 0 DL1AE OK1XOE false 
decode	none	3	DL1AE OK1XOE R-05	1039	1	14075039 false 0 OK1XOE DL1AE false 
decode	none	3	CQ W1AW FN31	1040	1	14075040 false 0 W1AW  true FN31
decode	none	3	CQ K2ABC FN42	1041	1	14075041 false 0 K2ABC  true FN42
decode	none	3	CQ TEST VE3XYZ FN03	1042	1	14075042 false 0 VE3XYZ  true FN03
decode	none	3	<DL9ABC> OK1XOE RR73	1043	1	14075043 false 0 OK1XOE DL9ABC false 
decode	none	3	73	1044	1	14075044 false 0   false 
decode	none	3		1045	1	14075045 false 0   false 
decode	none	3	CQ	1046	1	14075046 false 0   true 
decode	none	3	CQ NA 3Z1ABC	1047	1	14075047 false 0 3Z1ABC  true 
decode	none	4	CQ DL1AE JO31	1048	1	21075048 false 0 DL1AE  true JO31
decode	none	4	CQ DX JA1QQQ PM95	1049	1	21075049 false 0 JA1QQQ  true PM95
decode	none	4	OK1XOE DL1AE -12	1050	1	21075050 false 0 DL1AE OK1XOE false 
decode	none	4	DL1AE OK1XOE R-05	1051	1	21075051 false 0 OK1XOE DL1AE false 
decode	none	4	CQ W1AW FN31	1052	1	21075052 false 0 W1AW  true FN31
decode	none	4	CQ K2ABC FN42	1053	1	21075053 false 0 K2ABC  true FN42
decode	none	4	CQ TEST VE3XYZ FN03	1054	1	21075054 false 0 VE3XYZ  true FN03
decode	none	4	<DL9ABC> OK1XOE RR73	1055	1	21075055 false 0 OK1XOE DL9ABC false 
decode	none	4	73	1056	1	21075056 false 0   false 
decode	none	4		1057	1	21075057 false 0   false 
decode	none	4	CQ	1058	1	21075058 false 0   true 
decode	none	4	CQ NA 3Z1ABC	1059	1	21075059 false 0 3Z1ABC  true 
decode	none	5	CQ DL1AE JO31	1060	1	14026060 false 0 DL1AE  true JO31
decode	none	5	CQ DX JA1QQQ PM95	1061	1	14026061 false 0 JA1QQQ  true PM95
decode	none	5	OK1XOE DL1AE -12	1062	1	14026062 false 0 DL1AE OK1XOE false 
decode	none	5	DL1AE OK1XOE R-05	1063	1	14026063 false 0 OK1XOE DL1AE false 
decode	none	5	CQ W1AW FN31	1064	1	14026064 false 0 W1AW  true FN31
decode	none	5	CQ K2ABC FN42	1065	1	14026065 false 0 K2ABC  true FN42
decode	none	5	CQ TEST VE3XYZ FN03	1066	1	14026066 false 0 VE3XYZ  true FN03
decode	none	5	<DL9ABC> OK1XOE RR73	1067	1	14026067 false 0 OK1XOE DL9ABC false 
decode	none	5	73	1068	1	14026068 false 0   false 
decode	none	5		1069	1	14026069 false 0   false 
decode	none	5	CQ	1070	1	14026070 false 0   true 
decode	none	5	CQ NA 3Z1ABC	1071	1	14026071 false 0 3Z1ABC  true 
decode	none	6	CQ DL1AE JO31	1072	1	21026072 false 0 DL1AE  true JO31
decode	none	6	CQ DX JA1QQQ PM95	1073	1	21026073 false 0 JA1QQQ  true PM95
decode	none	6	OK1XOE DL1AE -12	1074	1	21026074 false 0 DL1AE OK1XOE false 
decode	none	6	DL1AE OK1XOE R-05	1075	1	21026075 false 0 OK1XOE DL1AE false 
decode	none	6	CQ W1AW FN31	1076	1	21026076 false 0 W1AW  true FN31
decode	none	6	CQ K2ABC FN42	1077	1	21026077 false 0 K2ABC  true FN42
decode	none	6	CQ TEST VE3XYZ FN03	1078	1	21026078 false 0 VE3XYZ  true FN03
decode	none	6	<DL9ABC> OK1XOE RR73	1079	1	21026079 false 0 OK1XOE DL9ABC false 
decode	none	6	73	1080	1	21026080 false 0   false 
decode	none	6		1081	1	21026081 false 0   false 
decode	none	6	CQ	1082	1	21026082 false 0   true 
decode	none	6	CQ NA 3Z1ABC	1083	1	21026083 false 0 3Z1ABC  true 
decodecap	none	299	300	299	0
decodecap	none	300	300	300	1
decodecap	none	304	300	304	5
decode	ww-digi	0	CQ DL1AE JO31	1000	1	0 false 0 DL1AE  true JO31
decode	ww-digi	0	CQ DX JA1QQQ PM95	1001	1	0 false 0 JA1QQQ  true PM95
decode	ww-digi	0	OK1XOE DL1AE -12	1002	1	0 false 0 DL1AE OK1XOE false 
decode	ww-digi	0	DL1AE OK1XOE R-05	1003	1	0 false 0 OK1XOE DL1AE false 
decode	ww-digi	0	CQ W1AW FN31	1004	1	0 false 0 W1AW  true FN31
decode	ww-digi	0	CQ K2ABC FN42	1005	1	0 false 0 K2ABC  true FN42
decode	ww-digi	0	CQ TEST VE3XYZ FN03	1006	1	0 false 0 VE3XYZ  true FN03
decode	ww-digi	0	<DL9ABC> OK1XOE RR73	1007	1	0 false 0 OK1XOE DL9ABC false 
decode	ww-digi	0	73	1008	1	0 false 0   false 
decode	ww-digi	0		1009	1	0 false 0   false 
decode	ww-digi	0	CQ	1010	1	0 false 0   true 
decode	ww-digi	0	CQ NA 3Z1ABC	1011	1	0 false 0 3Z1ABC  true 
decode	ww-digi	1	CQ DL1AE JO31	1012	1	0 false 0 DL1AE  true JO31
decode	ww-digi	1	CQ DX JA1QQQ PM95	1013	1	0 false 0 JA1QQQ  true PM95
decode	ww-digi	1	OK1XOE DL1AE -12	1014	1	0 false 0 DL1AE OK1XOE false 
decode	ww-digi	1	DL1AE OK1XOE R-05	1015	1	0 false 0 OK1XOE DL1AE false 
decode	ww-digi	1	CQ W1AW FN31	1016	1	0 false 0 W1AW  true FN31
decode	ww-digi	1	CQ K2ABC FN42	1017	1	0 false 0 K2ABC  true FN42
decode	ww-digi	1	CQ TEST VE3XYZ FN03	1018	1	0 false 0 VE3XYZ  true FN03
decode	ww-digi	1	<DL9ABC> OK1XOE RR73	1019	1	0 false 0 OK1XOE DL9ABC false 
decode	ww-digi	1	73	1020	1	0 false 0   false 
decode	ww-digi	1		1021	1	0 false 0   false 
decode	ww-digi	1	CQ	1022	1	0 false 0   true 
decode	ww-digi	1	CQ NA 3Z1ABC	1023	1	0 false 0 3Z1ABC  true 
decode	ww-digi	2	CQ DL1AE JO31	1024	1	14075024 true 0 DL1AE  true JO31
decode	ww-digi	2	CQ DX JA1QQQ PM95	1025	1	14075025 false 0 JA1QQQ  true PM95
decode	ww-digi	2	OK1XOE DL1AE -12	1026	1	14075026 true 0 DL1AE OK1XOE false 
decode	ww-digi	2	DL1AE OK1XOE R-05	1027	1	14075027 false 0 OK1XOE DL1AE false 
decode	ww-digi	2	CQ W1AW FN31	1028	1	14075028 false 0 W1AW  true FN31
decode	ww-digi	2	CQ K2ABC FN42	1029	1	14075029 false 0 K2ABC  true FN42
decode	ww-digi	2	CQ TEST VE3XYZ FN03	1030	1	14075030 false 0 VE3XYZ  true FN03
decode	ww-digi	2	<DL9ABC> OK1XOE RR73	1031	1	14075031 false 0 OK1XOE DL9ABC false 
decode	ww-digi	2	73	1032	1	14075032 false 0   false 
decode	ww-digi	2		1033	1	14075033 false 0   false 
decode	ww-digi	2	CQ	1034	1	14075034 false 0   true 
decode	ww-digi	2	CQ NA 3Z1ABC	1035	1	14075035 false 0 3Z1ABC  true 
decode	ww-digi	3	CQ DL1AE JO31	1036	1	14075036 true 0 DL1AE  true JO31
decode	ww-digi	3	CQ DX JA1QQQ PM95	1037	1	14075037 false 0 JA1QQQ  true PM95
decode	ww-digi	3	OK1XOE DL1AE -12	1038	1	14075038 true 0 DL1AE OK1XOE false 
decode	ww-digi	3	DL1AE OK1XOE R-05	1039	1	14075039 false 0 OK1XOE DL1AE false 
decode	ww-digi	3	CQ W1AW FN31	1040	1	14075040 false 0 W1AW  true FN31
decode	ww-digi	3	CQ K2ABC FN42	1041	1	14075041 false 0 K2ABC  true FN42
decode	ww-digi	3	CQ TEST VE3XYZ FN03	1042	1	14075042 false 0 VE3XYZ  true FN03
decode	ww-digi	3	<DL9ABC> OK1XOE RR73	1043	1	14075043 false 0 OK1XOE DL9ABC false 
decode	ww-digi	3	73	1044	1	14075044 false 0   false 
decode	ww-digi	3		1045	1	14075045 false 0   false 
decode	ww-digi	3	CQ	1046	1	14075046 false 0   true 
decode	ww-digi	3	CQ NA 3Z1ABC	1047	1	14075047 false 0 3Z1ABC  true 
decode	ww-digi	4	CQ DL1AE JO31	1048	1	21075048 false 1 DL1AE  true JO31
decode	ww-digi	4	CQ DX JA1QQQ PM95	1049	1	21075049 false 0 JA1QQQ  true PM95
decode	ww-digi	4	OK1XOE DL1AE -12	1050	1	21075050 false 1 DL1AE OK1XOE false 
decode	ww-digi	4	DL1AE OK1XOE R-05	1051	1	21075051 false 0 OK1XOE DL1AE false 
decode	ww-digi	4	CQ W1AW FN31	1052	1	21075052 false 0 W1AW  true FN31
decode	ww-digi	4	CQ K2ABC FN42	1053	1	21075053 false 0 K2ABC  true FN42
decode	ww-digi	4	CQ TEST VE3XYZ FN03	1054	1	21075054 false 0 VE3XYZ  true FN03
decode	ww-digi	4	<DL9ABC> OK1XOE RR73	1055	1	21075055 false 0 OK1XOE DL9ABC false 
decode	ww-digi	4	73	1056	1	21075056 false 0   false 
decode	ww-digi	4		1057	1	21075057 false 0   false 
decode	ww-digi	4	CQ	1058	1	21075058 false 0   true 
decode	ww-digi	4	CQ NA 3Z1ABC	1059	1	21075059 false 0 3Z1ABC  true 
decode	ww-digi	5	CQ DL1AE JO31	1060	1	14026060 true 0 DL1AE  true JO31
decode	ww-digi	5	CQ DX JA1QQQ PM95	1061	1	14026061 false 0 JA1QQQ  true PM95
decode	ww-digi	5	OK1XOE DL1AE -12	1062	1	14026062 true 0 DL1AE OK1XOE false 
decode	ww-digi	5	DL1AE OK1XOE R-05	1063	1	14026063 false 0 OK1XOE DL1AE false 
decode	ww-digi	5	CQ W1AW FN31	1064	1	14026064 false 0 W1AW  true FN31
decode	ww-digi	5	CQ K2ABC FN42	1065	1	14026065 false 0 K2ABC  true FN42
decode	ww-digi	5	CQ TEST VE3XYZ FN03	1066	1	14026066 false 0 VE3XYZ  true FN03
decode	ww-digi	5	<DL9ABC> OK1XOE RR73	1067	1	14026067 false 0 OK1XOE DL9ABC false 
decode	ww-digi	5	73	1068	1	14026068 false 0   false 
decode	ww-digi	5		1069	1	14026069 false 0   false 
decode	ww-digi	5	CQ	1070	1	14026070 false 0   true 
decode	ww-digi	5	CQ NA 3Z1ABC	1071	1	14026071 false 0 3Z1ABC  true 
decode	ww-digi	6	CQ DL1AE JO31	1072	1	21026072 false 0 DL1AE  true JO31
decode	ww-digi	6	CQ DX JA1QQQ PM95	1073	1	21026073 false 0 JA1QQQ  true PM95
decode	ww-digi	6	OK1XOE DL1AE -12	1074	1	21026074 false 0 DL1AE OK1XOE false 
decode	ww-digi	6	DL1AE OK1XOE R-05	1075	1	21026075 false 0 OK1XOE DL1AE false 
decode	ww-digi	6	CQ W1AW FN31	1076	1	21026076 false 0 W1AW  true FN31
decode	ww-digi	6	CQ K2ABC FN42	1077	1	21026077 false 0 K2ABC  true FN42
decode	ww-digi	6	CQ TEST VE3XYZ FN03	1078	1	21026078 false 0 VE3XYZ  true FN03
decode	ww-digi	6	<DL9ABC> OK1XOE RR73	1079	1	21026079 false 0 OK1XOE DL9ABC false 
decode	ww-digi	6	73	1080	1	21026080 false 0   false 
decode	ww-digi	6		1081	1	21026081 false 0   false 
decode	ww-digi	6	CQ	1082	1	21026082 false 0   true 
decode	ww-digi	6	CQ NA 3Z1ABC	1083	1	21026083 false 0 3Z1ABC  true 
decodecap	ww-digi	299	300	299	0
decodecap	ww-digi	300	300	300	1
decodecap	ww-digi	304	300	304	5
decode	cq-ww-cw	0	CQ DL1AE JO31	1000	1	0 false 0 DL1AE  true JO31
decode	cq-ww-cw	0	CQ DX JA1QQQ PM95	1001	1	0 false 0 JA1QQQ  true PM95
decode	cq-ww-cw	0	OK1XOE DL1AE -12	1002	1	0 false 0 DL1AE OK1XOE false 
decode	cq-ww-cw	0	DL1AE OK1XOE R-05	1003	1	0 false 0 OK1XOE DL1AE false 
decode	cq-ww-cw	0	CQ W1AW FN31	1004	1	0 false 0 W1AW  true FN31
decode	cq-ww-cw	0	CQ K2ABC FN42	1005	1	0 false 0 K2ABC  true FN42
decode	cq-ww-cw	0	CQ TEST VE3XYZ FN03	1006	1	0 false 0 VE3XYZ  true FN03
decode	cq-ww-cw	0	<DL9ABC> OK1XOE RR73	1007	1	0 false 0 OK1XOE DL9ABC false 
decode	cq-ww-cw	0	73	1008	1	0 false 0   false 
decode	cq-ww-cw	0		1009	1	0 false 0   false 
decode	cq-ww-cw	0	CQ	1010	1	0 false 0   true 
decode	cq-ww-cw	0	CQ NA 3Z1ABC	1011	1	0 false 0 3Z1ABC  true 
decode	cq-ww-cw	1	CQ DL1AE JO31	1012	1	0 false 0 DL1AE  true JO31
decode	cq-ww-cw	1	CQ DX JA1QQQ PM95	1013	1	0 false 0 JA1QQQ  true PM95
decode	cq-ww-cw	1	OK1XOE DL1AE -12	1014	1	0 false 0 DL1AE OK1XOE false 
decode	cq-ww-cw	1	DL1AE OK1XOE R-05	1015	1	0 false 0 OK1XOE DL1AE false 
decode	cq-ww-cw	1	CQ W1AW FN31	1016	1	0 false 0 W1AW  true FN31
decode	cq-ww-cw	1	CQ K2ABC FN42	1017	1	0 false 0 K2ABC  true FN42
decode	cq-ww-cw	1	CQ TEST VE3XYZ FN03	1018	1	0 false 0 VE3XYZ  true FN03
decode	cq-ww-cw	1	<DL9ABC> OK1XOE RR73	1019	1	0 false 0 OK1XOE DL9ABC false 
decode	cq-ww-cw	1	73	1020	1	0 false 0   false 
decode	cq-ww-cw	1		1021	1	0 false 0   false 
decode	cq-ww-cw	1	CQ	1022	1	0 false 0   true 
decode	cq-ww-cw	1	CQ NA 3Z1ABC	1023	1	0 false 0 3Z1ABC  true 
decode	cq-ww-cw	2	CQ DL1AE JO31	1024	1	14075024 true 0 DL1AE  true JO31
decode	cq-ww-cw	2	CQ DX JA1QQQ PM95	1025	1	14075025 false 0 JA1QQQ  true PM95
decode	cq-ww-cw	2	OK1XOE DL1AE -12	1026	1	14075026 true 0 DL1AE OK1XOE false 
decode	cq-ww-cw	2	DL1AE OK1XOE R-05	1027	1	14075027 false 0 OK1XOE DL1AE false 
decode	cq-ww-cw	2	CQ W1AW FN31	1028	1	14075028 false 0 W1AW  true FN31
decode	cq-ww-cw	2	CQ K2ABC FN42	1029	1	14075029 false 0 K2ABC  true FN42
decode	cq-ww-cw	2	CQ TEST VE3XYZ FN03	1030	1	14075030 false 0 VE3XYZ  true FN03
decode	cq-ww-cw	2	<DL9ABC> OK1XOE RR73	1031	1	14075031 false 0 OK1XOE DL9ABC false 
decode	cq-ww-cw	2	73	1032	1	14075032 false 0   false 
decode	cq-ww-cw	2		1033	1	14075033 false 0   false 
decode	cq-ww-cw	2	CQ	1034	1	14075034 false 0   true 
decode	cq-ww-cw	2	CQ NA 3Z1ABC	1035	1	14075035 false 0 3Z1ABC  true 
decode	cq-ww-cw	3	CQ DL1AE JO31	1036	1	14075036 true 0 DL1AE  true JO31
decode	cq-ww-cw	3	CQ DX JA1QQQ PM95	1037	1	14075037 false 0 JA1QQQ  true PM95
decode	cq-ww-cw	3	OK1XOE DL1AE -12	1038	1	14075038 true 0 DL1AE OK1XOE false 
decode	cq-ww-cw	3	DL1AE OK1XOE R-05	1039	1	14075039 false 0 OK1XOE DL1AE false 
decode	cq-ww-cw	3	CQ W1AW FN31	1040	1	14075040 false 0 W1AW  true FN31
decode	cq-ww-cw	3	CQ K2ABC FN42	1041	1	14075041 false 0 K2ABC  true FN42
decode	cq-ww-cw	3	CQ TEST VE3XYZ FN03	1042	1	14075042 false 0 VE3XYZ  true FN03
decode	cq-ww-cw	3	<DL9ABC> OK1XOE RR73	1043	1	14075043 false 0 OK1XOE DL9ABC false 
decode	cq-ww-cw	3	73	1044	1	14075044 false 0   false 
decode	cq-ww-cw	3		1045	1	14075045 false 0   false 
decode	cq-ww-cw	3	CQ	1046	1	14075046 false 0   true 
decode	cq-ww-cw	3	CQ NA 3Z1ABC	1047	1	14075047 false 0 3Z1ABC  true 
decode	cq-ww-cw	4	CQ DL1AE JO31	1048	1	21075048 false 0 DL1AE  true JO31
decode	cq-ww-cw	4	CQ DX JA1QQQ PM95	1049	1	21075049 false 0 JA1QQQ  true PM95
decode	cq-ww-cw	4	OK1XOE DL1AE -12	1050	1	21075050 false 0 DL1AE OK1XOE false 
decode	cq-ww-cw	4	DL1AE OK1XOE R-05	1051	1	21075051 false 0 OK1XOE DL1AE false 
decode	cq-ww-cw	4	CQ W1AW FN31	1052	1	21075052 false 0 W1AW  true FN31
decode	cq-ww-cw	4	CQ K2ABC FN42	1053	1	21075053 false 0 K2ABC  true FN42
decode	cq-ww-cw	4	CQ TEST VE3XYZ FN03	1054	1	21075054 false 0 VE3XYZ  true FN03
decode	cq-ww-cw	4	<DL9ABC> OK1XOE RR73	1055	1	21075055 false 0 OK1XOE DL9ABC false 
decode	cq-ww-cw	4	73	1056	1	21075056 false 0   false 
decode	cq-ww-cw	4		1057	1	21075057 false 0   false 
decode	cq-ww-cw	4	CQ	1058	1	21075058 false 0   true 
decode	cq-ww-cw	4	CQ NA 3Z1ABC	1059	1	21075059 false 0 3Z1ABC  true 
decode	cq-ww-cw	5	CQ DL1AE JO31	1060	1	14026060 true 0 DL1AE  true JO31
decode	cq-ww-cw	5	CQ DX JA1QQQ PM95	1061	1	14026061 false 2 JA1QQQ  true PM95
decode	cq-ww-cw	5	OK1XOE DL1AE -12	1062	1	14026062 true 0 DL1AE OK1XOE false 
decode	cq-ww-cw	5	DL1AE OK1XOE R-05	1063	1	14026063 false 2 OK1XOE DL1AE false 
decode	cq-ww-cw	5	CQ W1AW FN31	1064	1	14026064 false 2 W1AW  true FN31
decode	cq-ww-cw	5	CQ K2ABC FN42	1065	1	14026065 false 2 K2ABC  true FN42
decode	cq-ww-cw	5	CQ TEST VE3XYZ FN03	1066	1	14026066 false 2 VE3XYZ  true FN03
decode	cq-ww-cw	5	<DL9ABC> OK1XOE RR73	1067	1	14026067 false 2 OK1XOE DL9ABC false 
decode	cq-ww-cw	5	73	1068	1	14026068 false 0   false 
decode	cq-ww-cw	5		1069	1	14026069 false 0   false 
decode	cq-ww-cw	5	CQ	1070	1	14026070 false 0   true 
decode	cq-ww-cw	5	CQ NA 3Z1ABC	1071	1	14026071 false 0 3Z1ABC  true 
decode	cq-ww-cw	6	CQ DL1AE JO31	1072	1	21026072 false 2 DL1AE  true JO31
decode	cq-ww-cw	6	CQ DX JA1QQQ PM95	1073	1	21026073 false 2 JA1QQQ  true PM95
decode	cq-ww-cw	6	OK1XOE DL1AE -12	1074	1	21026074 false 2 DL1AE OK1XOE false 
decode	cq-ww-cw	6	DL1AE OK1XOE R-05	1075	1	21026075 false 2 OK1XOE DL1AE false 
decode	cq-ww-cw	6	CQ W1AW FN31	1076	1	21026076 false 2 W1AW  true FN31
decode	cq-ww-cw	6	CQ K2ABC FN42	1077	1	21026077 false 2 K2ABC  true FN42
decode	cq-ww-cw	6	CQ TEST VE3XYZ FN03	1078	1	21026078 false 2 VE3XYZ  true FN03
decode	cq-ww-cw	6	<DL9ABC> OK1XOE RR73	1079	1	21026079 false 2 OK1XOE DL9ABC false 
decode	cq-ww-cw	6	73	1080	1	21026080 false 0   false 
decode	cq-ww-cw	6		1081	1	21026081 false 0   false 
decode	cq-ww-cw	6	CQ	1082	1	21026082 false 0   true 
decode	cq-ww-cw	6	CQ NA 3Z1ABC	1083	1	21026083 false 0 3Z1ABC  true 
decodecap	cq-ww-cw	299	300	299	0
decodecap	cq-ww-cw	300	300	300	1
decodecap	cq-ww-cw	304	300	304	5
score	0	none	true	false	3600	false	200	-	posts=0	url=-	atMoved=false	rev=3	Sk\u00F3re se zat\u00EDm neodes\u00EDlalo	<none>
score	1	cq-ww-cw	false	false	3600	false	200	-	posts=0	url=-	atMoved=false	rev=3	Sk\u00F3re se zat\u00EDm neodes\u00EDlalo	<none>
score	2	cq-ww-cw	false	true	3600	false	200	-	posts=1	url=http://probe.invalid/post/	atMoved=true	rev=7	Sk\u00F3re 2 odesl\u00E1no <instant> (HTTP 200)	<?xml version="1.0"?>\u000A<dynamicresults>\u000A  <contest>CQ-WW-CW</contest>\u000A  <call>OK1XOE</call>\u000A  <ops>OK1XOE OK1ABC</ops>\u000A  <class power="LOW" assisted="" transmitter="" ops="SINGLE-OP" bands="" mode="" overlay=""/>\u000A  <club>OKCC</club>\u000A  <soft>MacContestLogger</soft>\u000A  <version>v\u00FDvojov\u00E1 verze</version>\u000A  <qth><cqzone>15</cqzone><iaruzone>28</iaruzone><grid6>JN79xx</grid6></qth>\u000A  <breakdown>\u000A    <qso band="total" mode="ALL">1</qso>\u000A    <point band="total" mode="ALL">1</point>\u000A    <mult band="total" mode="ALL">2</mult>\u000A    <qso band="20" mode="CW">1</qso>\u000A    <point band="20" mode="CW">1</point>\u000A    <mult band="20" mode="CW">2</mult>\u000A  </breakdown>\u000A  <score>2</score>\u000A  <timestamp><instant></timestamp>\u000A</dynamicresults>\u000A
score	3	cq-ww-cw	true	false	3600	false	200	-	posts=1	url=http://probe.invalid/post/	atMoved=true	rev=7	Sk\u00F3re 2 odesl\u00E1no <instant> (HTTP 200)	<?xml version="1.0"?>\u000A<dynamicresults>\u000A  <contest>CQ-WW-CW</contest>\u000A  <call>OK1XOE</call>\u000A  <ops>OK1XOE OK1ABC</ops>\u000A  <class power="LOW" assisted="" transmitter="" ops="SINGLE-OP" bands="" mode="" overlay=""/>\u000A  <club>OKCC</club>\u000A  <soft>MacContestLogger</soft>\u000A  <version>v\u00FDvojov\u00E1 verze</version>\u000A  <qth><cqzone>15</cqzone><iaruzone>28</iaruzone><grid6>JN79xx</grid6></qth>\u000A  <breakdown>\u000A    <qso band="total" mode="ALL">1</qso>\u000A    <point band="total" mode="ALL">1</point>\u000A    <mult band="total" mode="ALL">2</mult>\u000A    <qso band="20" mode="CW">1</qso>\u000A    <point band="20" mode="CW">1</point>\u000A    <mult band="20" mode="CW">2</mult>\u000A  </breakdown>\u000A  <score>2</score>\u000A  <timestamp><instant></timestamp>\u000A</dynamicresults>\u000A
score	4	cq-ww-cw	true	false	3600	true	200	-	posts=0	url=-	atMoved=false	rev=7	Sk\u00F3re se zat\u00EDm neodes\u00EDlalo	<none>
score	5	cq-ww-cw	true	false	120	false	200	-	posts=0	url=-	atMoved=false	rev=3	Sk\u00F3re se zat\u00EDm neodes\u00EDlalo	<none>
score	6	cq-ww-cw	true	false	1200	false	200	-	posts=1	url=http://probe.invalid/post/	atMoved=true	rev=7	Sk\u00F3re 2 odesl\u00E1no <instant> (HTTP 200)	<?xml version="1.0"?>\u000A<dynamicresults>\u000A  <contest>CQ-WW-CW</contest>\u000A  <call>OK1XOE</call>\u000A  <ops>OK1XOE OK1ABC</ops>\u000A  <class power="LOW" assisted="" transmitter="" ops="SINGLE-OP" bands="" mode="" overlay=""/>\u000A  <club>OKCC</club>\u000A  <soft>MacContestLogger</soft>\u000A  <version>v\u00FDvojov\u00E1 verze</version>\u000A  <qth><cqzone>15</cqzone><iaruzone>28</iaruzone><grid6>JN79xx</grid6></qth>\u000A  <breakdown>\u000A    <qso band="total" mode="ALL">1</qso>\u000A    <point band="total" mode="ALL">1</point>\u000A    <mult band="total" mode="ALL">2</mult>\u000A    <qso band="20" mode="CW">1</qso>\u000A    <point band="20" mode="CW">1</point>\u000A    <mult band="20" mode="CW">2</mult>\u000A  </breakdown>\u000A  <score>2</score>\u000A  <timestamp><instant></timestamp>\u000A</dynamicresults>\u000A
score	7	cq-ww-cw	true	true	10	true	200	-	posts=1	url=http://probe.invalid/post/	atMoved=true	rev=7	Sk\u00F3re 2 odesl\u00E1no <instant> (HTTP 200)	<?xml version="1.0"?>\u000A<dynamicresults>\u000A  <contest>CQ-WW-CW</contest>\u000A  <call>OK1XOE</call>\u000A  <ops>OK1XOE OK1ABC</ops>\u000A  <class power="LOW" assisted="" transmitter="" ops="SINGLE-OP" bands="" mode="" overlay=""/>\u000A  <club>OKCC</club>\u000A  <soft>MacContestLogger</soft>\u000A  <version>v\u00FDvojov\u00E1 verze</version>\u000A  <qth><cqzone>15</cqzone><iaruzone>28</iaruzone><grid6>JN79xx</grid6></qth>\u000A  <breakdown>\u000A    <qso band="total" mode="ALL">1</qso>\u000A    <point band="total" mode="ALL">1</point>\u000A    <mult band="total" mode="ALL">2</mult>\u000A    <qso band="20" mode="CW">1</qso>\u000A    <point band="20" mode="CW">1</point>\u000A    <mult band="20" mode="CW">2</mult>\u000A  </breakdown>\u000A  <score>2</score>\u000A  <timestamp><instant></timestamp>\u000A</dynamicresults>\u000A
score	8	cq-ww-cw	true	false	3600	false	204	-	posts=1	url=http://probe.invalid/post/	atMoved=true	rev=7	Sk\u00F3re 2 odesl\u00E1no <instant> (HTTP 204)	<?xml version="1.0"?>\u000A<dynamicresults>\u000A  <contest>CQ-WW-CW</contest>\u000A  <call>OK1XOE</call>\u000A  <ops>OK1XOE OK1ABC</ops>\u000A  <class power="LOW" assisted="" transmitter="" ops="SINGLE-OP" bands="" mode="" overlay=""/>\u000A  <club>OKCC</club>\u000A  <soft>MacContestLogger</soft>\u000A  <version>v\u00FDvojov\u00E1 verze</version>\u000A  <qth><cqzone>15</cqzone><iaruzone>28</iaruzone><grid6>JN79xx</grid6></qth>\u000A  <breakdown>\u000A    <qso band="total" mode="ALL">1</qso>\u000A    <point band="total" mode="ALL">1</point>\u000A    <mult band="total" mode="ALL">2</mult>\u000A    <qso band="20" mode="CW">1</qso>\u000A    <point band="20" mode="CW">1</point>\u000A    <mult band="20" mode="CW">2</mult>\u000A  </breakdown>\u000A  <score>2</score>\u000A  <timestamp><instant></timestamp>\u000A</dynamicresults>\u000A
score	9	cq-ww-cw	true	false	3600	false	299	-	posts=1	url=http://probe.invalid/post/	atMoved=true	rev=7	Sk\u00F3re 2 odesl\u00E1no <instant> (HTTP 299)	<?xml version="1.0"?>\u000A<dynamicresults>\u000A  <contest>CQ-WW-CW</contest>\u000A  <call>OK1XOE</call>\u000A  <ops>OK1XOE OK1ABC</ops>\u000A  <class power="LOW" assisted="" transmitter="" ops="SINGLE-OP" bands="" mode="" overlay=""/>\u000A  <club>OKCC</club>\u000A  <soft>MacContestLogger</soft>\u000A  <version>v\u00FDvojov\u00E1 verze</version>\u000A  <qth><cqzone>15</cqzone><iaruzone>28</iaruzone><grid6>JN79xx</grid6></qth>\u000A  <breakdown>\u000A    <qso band="total" mode="ALL">1</qso>\u000A    <point band="total" mode="ALL">1</point>\u000A    <mult band="total" mode="ALL">2</mult>\u000A    <qso band="20" mode="CW">1</qso>\u000A    <point band="20" mode="CW">1</point>\u000A    <mult band="20" mode="CW">2</mult>\u000A  </breakdown>\u000A  <score>2</score>\u000A  <timestamp><instant></timestamp>\u000A</dynamicresults>\u000A
score	10	cq-ww-cw	true	false	3600	false	300	-	posts=1	url=http://probe.invalid/post/	atMoved=true	rev=3	Server vr\u00E1til HTTP 300	<?xml version="1.0"?>\u000A<dynamicresults>\u000A  <contest>CQ-WW-CW</contest>\u000A  <call>OK1XOE</call>\u000A  <ops>OK1XOE OK1ABC</ops>\u000A  <class power="LOW" assisted="" transmitter="" ops="SINGLE-OP" bands="" mode="" overlay=""/>\u000A  <club>OKCC</club>\u000A  <soft>MacContestLogger</soft>\u000A  <version>v\u00FDvojov\u00E1 verze</version>\u000A  <qth><cqzone>15</cqzone><iaruzone>28</iaruzone><grid6>JN79xx</grid6></qth>\u000A  <breakdown>\u000A    <qso band="total" mode="ALL">1</qso>\u000A    <point band="total" mode="ALL">1</point>\u000A    <mult band="total" mode="ALL">2</mult>\u000A    <qso band="20" mode="CW">1</qso>\u000A    <point band="20" mode="CW">1</point>\u000A    <mult band="20" mode="CW">2</mult>\u000A  </breakdown>\u000A  <score>2</score>\u000A  <timestamp><instant></timestamp>\u000A</dynamicresults>\u000A
score	11	cq-ww-cw	true	false	3600	false	500	-	posts=1	url=http://probe.invalid/post/	atMoved=true	rev=3	Server vr\u00E1til HTTP 500	<?xml version="1.0"?>\u000A<dynamicresults>\u000A  <contest>CQ-WW-CW</contest>\u000A  <call>OK1XOE</call>\u000A  <ops>OK1XOE OK1ABC</ops>\u000A  <class power="LOW" assisted="" transmitter="" ops="SINGLE-OP" bands="" mode="" overlay=""/>\u000A  <club>OKCC</club>\u000A  <soft>MacContestLogger</soft>\u000A  <version>v\u00FDvojov\u00E1 verze</version>\u000A  <qth><cqzone>15</cqzone><iaruzone>28</iaruzone><grid6>JN79xx</grid6></qth>\u000A  <breakdown>\u000A    <qso band="total" mode="ALL">1</qso>\u000A    <point band="total" mode="ALL">1</point>\u000A    <mult band="total" mode="ALL">2</mult>\u000A    <qso band="20" mode="CW">1</qso>\u000A    <point band="20" mode="CW">1</point>\u000A    <mult band="20" mode="CW">2</mult>\u000A  </breakdown>\u000A  <score>2</score>\u000A  <timestamp><instant></timestamp>\u000A</dynamicresults>\u000A
score	12	cq-ww-cw	true	false	3600	false	200	Connection refused	posts=1	url=http://probe.invalid/post/	atMoved=true	rev=3	Odesl\u00E1n\u00ED sk\u00F3re selhalo: Connection refused	<?xml version="1.0"?>\u000A<dynamicresults>\u000A  <contest>CQ-WW-CW</contest>\u000A  <call>OK1XOE</call>\u000A  <ops>OK1XOE OK1ABC</ops>\u000A  <class power="LOW" assisted="" transmitter="" ops="SINGLE-OP" bands="" mode="" overlay=""/>\u000A  <club>OKCC</club>\u000A  <soft>MacContestLogger</soft>\u000A  <version>v\u00FDvojov\u00E1 verze</version>\u000A  <qth><cqzone>15</cqzone><iaruzone>28</iaruzone><grid6>JN79xx</grid6></qth>\u000A  <breakdown>\u000A    <qso band="total" mode="ALL">1</qso>\u000A    <point band="total" mode="ALL">1</point>\u000A    <mult band="total" mode="ALL">2</mult>\u000A    <qso band="20" mode="CW">1</qso>\u000A    <point band="20" mode="CW">1</point>\u000A    <mult band="20" mode="CW">2</mult>\u000A  </breakdown>\u000A  <score>2</score>\u000A  <timestamp><instant></timestamp>\u000A</dynamicresults>\u000A
score	13	cq-ww-cw	true	false	3600	false	200	<null>	posts=1	url=http://probe.invalid/post/	atMoved=true	rev=3	Odesl\u00E1n\u00ED sk\u00F3re selhalo: null	<?xml version="1.0"?>\u000A<dynamicresults>\u000A  <contest>CQ-WW-CW</contest>\u000A  <call>OK1XOE</call>\u000A  <ops>OK1XOE OK1ABC</ops>\u000A  <class power="LOW" assisted="" transmitter="" ops="SINGLE-OP" bands="" mode="" overlay=""/>\u000A  <club>OKCC</club>\u000A  <soft>MacContestLogger</soft>\u000A  <version>v\u00FDvojov\u00E1 verze</version>\u000A  <qth><cqzone>15</cqzone><iaruzone>28</iaruzone><grid6>JN79xx</grid6></qth>\u000A  <breakdown>\u000A    <qso band="total" mode="ALL">1</qso>\u000A    <point band="total" mode="ALL">1</point>\u000A    <mult band="total" mode="ALL">2</mult>\u000A    <qso band="20" mode="CW">1</qso>\u000A    <point band="20" mode="CW">1</point>\u000A    <mult band="20" mode="CW">2</mult>\u000A  </breakdown>\u000A  <score>2</score>\u000A  <timestamp><instant></timestamp>\u000A</dynamicresults>\u000A
score	14	ww-digi	true	true	3600	false	200	-	posts=1	url=http://probe.invalid/post/	atMoved=true	rev=7	Sk\u00F3re 0 odesl\u00E1no <instant> (HTTP 200)	<?xml version="1.0"?>\u000A<dynamicresults>\u000A  <contest>WW-DIGI</contest>\u000A  <call>OK1XOE</call>\u000A  <ops>OK1XOE OK1ABC</ops>\u000A  <class power="LOW" assisted="" transmitter="" ops="SINGLE-OP" bands="" mode="" overlay=""/>\u000A  <club>OKCC</club>\u000A  <soft>MacContestLogger</soft>\u000A  <version>v\u00FDvojov\u00E1 verze</version>\u000A  <qth><cqzone>15</cqzone><iaruzone>28</iaruzone><grid6>JN79xx</grid6></qth>\u000A  <breakdown>\u000A    <qso band="total" mode="ALL">0</qso>\u000A    <point band="total" mode="ALL">0</point>\u000A    <mult band="total" mode="ALL">0</mult>\u000A    <qso band="20" mode="CW">1</qso>\u000A    <point band="20" mode="CW">0</point>\u000A    <mult band="20" mode="CW">0</mult>\u000A  </breakdown>\u000A  <score>0</score>\u000A  <timestamp><instant></timestamp>\u000A</dynamicresults>\u000A
clublog	0	false	0	-	Club Log: zat\u00EDm nic neodesl\u00E1no
clublog	1	false	0	-	Club Log: zat\u00EDm nic neodesl\u00E1no
clublog	2	true	1	<QSO_DATE:8>20261003 <TIME_ON:6>100000 <CALL:6>DL1ABC <BAND:3>20m <FREQ:9>14.025000 <MODE:2>CW <APP_N1MM_RUNNING:1>Y <EOR>\u000A	Club Log: zat\u00EDm nic neodesl\u00E1no
clublog	3	true	1	<QSO_DATE:8>20261003 <TIME_ON:6>100000 <CALL:6>DL1ABC <BAND:3>20m <FREQ:9>14.025000 <MODE:2>CW <APP_N1MM_RUNNING:1>Y <EOR>\u000A	Club Log: zat\u00EDm nic neodesl\u00E1no
clublog	4	false	0	-	Club Log: zat\u00EDm nic neodesl\u00E1no
clublog	5	false	0	-	Club Log: zat\u00EDm nic neodesl\u00E1no
clock	0		false	0	-	calls=[]	offset=null	Synchronizace \u010Dasu vypnut\u00E1		msgs=0	-
clock	1	  	true	0	-	calls=[]	offset=null	Synchronizace \u010Dasu vypnut\u00E1		msgs=0	-
clock	2	pool.ntp.org	false	120	-	calls=[pool.ntp.org:123:3000]	offset=120	Hodiny: odchylka +0.12 s od pool.ntp.org		msgs=0	-
clock	3	pool.ntp.org	true	120	-	calls=[pool.ntp.org:123:3000]	offset=120	Hodiny: odchylka +0.12 s od pool.ntp.org (\u010Das QSO opravov\u00E1n)		msgs=0	-
clock	4	 time.example 	true	-2500	-	calls=[time.example:123:3000]	offset=-2500	Hodiny: odchylka -2.50 s od time.example (\u010Das QSO opravov\u00E1n)	\u23F0 Hodiny: odchylka -2.50 s od time.example (\u010Das QSO opravov\u00E1n) \u2014 srovnej hodiny po\u010D\u00EDta\u010De	msgs=1	Hodiny: odchylka -2.50 s od time.example (\u010Das QSO opravov\u00E1n)
clock	5	time.example	false	1000	-	calls=[time.example:123:3000]	offset=1000	Hodiny: odchylka +1.00 s od time.example		msgs=0	-
clock	6	time.example	true	1001	-	calls=[time.example:123:3000]	offset=1001	Hodiny: odchylka +1.00 s od time.example (\u010Das QSO opravov\u00E1n)	\u23F0 Hodiny: odchylka +1.00 s od time.example (\u010Das QSO opravov\u00E1n) \u2014 srovnej hodiny po\u010D\u00EDta\u010De	msgs=1	Hodiny: odchylka +1.00 s od time.example (\u010Das QSO opravov\u00E1n)
clock	7	time.example	true	-1001	-	calls=[time.example:123:3000]	offset=-1001	Hodiny: odchylka -1.00 s od time.example (\u010Das QSO opravov\u00E1n)	\u23F0 Hodiny: odchylka -1.00 s od time.example (\u010Das QSO opravov\u00E1n) \u2014 srovnej hodiny po\u010D\u00EDta\u010De	msgs=1	Hodiny: odchylka -1.00 s od time.example (\u010Das QSO opravov\u00E1n)
clock	8	time.example	true	-999	-	calls=[time.example:123:3000]	offset=-999	Hodiny: odchylka -1.00 s od time.example (\u010Das QSO opravov\u00E1n)		msgs=0	-
clock	9	time.example	true	123456	-	calls=[time.example:123:3000]	offset=123456	Hodiny: odchylka +123.46 s od time.example (\u010Das QSO opravov\u00E1n)	\u23F0 Hodiny: odchylka +123.46 s od time.example (\u010Das QSO opravov\u00E1n) \u2014 srovnej hodiny po\u010D\u00EDta\u010De	msgs=1	Hodiny: odchylka +123.46 s od time.example (\u010Das QSO opravov\u00E1n)
clock	10	time.example	true	0	timed out	calls=[time.example:123:3000]	offset=null	NTP time.example nedostupn\u00FD: timed out		msgs=0	-
clock	11	time.example	false	0		calls=[time.example:123:3000]	offset=null	NTP time.example nedostupn\u00FD: 		msgs=0	-
clock	12	time.example	false	0	<null>	calls=[time.example:123:3000]	offset=null	NTP time.example nedostupn\u00FD: null		msgs=0	-
clock	13	time.example	false	5	-	calls=[time.example:123:3000]	offset=5	Hodiny: odchylka +0.01 s od time.example		msgs=0	-
clock	14	time.example	false	15	-	calls=[time.example:123:3000]	offset=15	Hodiny: odchylka +0.02 s od time.example		msgs=0	-
clock	15	time.example	false	25	-	calls=[time.example:123:3000]	offset=25	Hodiny: odchylka +0.03 s od time.example		msgs=0	-
clock	16	time.example	false	125	-	calls=[time.example:123:3000]	offset=125	Hodiny: odchylka +0.13 s od time.example		msgs=0	-
clock	17	time.example	false	135	-	calls=[time.example:123:3000]	offset=135	Hodiny: odchylka +0.14 s od time.example		msgs=0	-
clock	18	time.example	false	1005	-	calls=[time.example:123:3000]	offset=1005	Hodiny: odchylka +1.01 s od time.example	\u23F0 Hodiny: odchylka +1.01 s od time.example \u2014 srovnej hodiny po\u010D\u00EDta\u010De	msgs=1	Hodiny: odchylka +1.01 s od time.example
clock	19	time.example	false	2675	-	calls=[time.example:123:3000]	offset=2675	Hodiny: odchylka +2.68 s od time.example	\u23F0 Hodiny: odchylka +2.68 s od time.example \u2014 srovnej hodiny po\u010D\u00EDta\u010De	msgs=1	Hodiny: odchylka +2.68 s od time.example
clock	20	time.example	false	-5	-	calls=[time.example:123:3000]	offset=-5	Hodiny: odchylka -0.01 s od time.example		msgs=0	-
clock	21	time.example	false	-125	-	calls=[time.example:123:3000]	offset=-125	Hodiny: odchylka -0.13 s od time.example		msgs=0	-
clock	22	time.example	false	-135	-	calls=[time.example:123:3000]	offset=-135	Hodiny: odchylka -0.14 s od time.example		msgs=0	-
clock	23	time.example	false	1	-	calls=[time.example:123:3000]	offset=1	Hodiny: odchylka +0.00 s od time.example		msgs=0	-
clock	24	time.example	false	-1	-	calls=[time.example:123:3000]	offset=-1	Hodiny: odchylka -0.00 s od time.example		msgs=0	-
clock	25	time.example	false	994	-	calls=[time.example:123:3000]	offset=994	Hodiny: odchylka +0.99 s od time.example		msgs=0	-
clock	26	time.example	false	995	-	calls=[time.example:123:3000]	offset=995	Hodiny: odchylka +1.00 s od time.example		msgs=0	-
clock	27	time.example	false	-995	-	calls=[time.example:123:3000]	offset=-995	Hodiny: odchylka -1.00 s od time.example		msgs=0	-
# java.version=21.0.2
"""#
}
