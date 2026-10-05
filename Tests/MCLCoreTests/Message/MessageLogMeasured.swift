// Table measured on Java v1.1.1 (JDK 21.0.2, en_US) by the maintainer-only probe.
// Do not edit by hand — run the probe again and regenerate the file with
// a maintainer-only probe.

enum MessageLogMeasured {

    /// Probe rows (TSV, probe escaping `esc`; described in the probe README).
    static let rows: String = #"""
MSG	-3	[-0001-06-01T23:00:00Z g]	2300Z  g
MSG	0	[-0001-06-01T23:00:00Z g]	2300Z  g
MSG	1	[-0001-06-01T23:00:00Z g]	2300Z  g
MSG	2	[+12026-01-01T00:07:00Z \u0085][-0001-06-01T23:00:00Z g]	0007Z  \u0085\u000A2300Z  g
MSG	5	[2026-08-19T12:34:56Z \u3000d\u3000][2026-08-19T12:34:56Z e\u2028][1969-12-31T23:59:59.999Z f][+12026-01-01T00:07:00Z \u0085][-0001-06-01T23:00:00Z g]	1234Z  \u3000d\u3000\u000A1234Z  e\u2028\u000A2359Z  f\u000A0007Z  \u0085\u000A2300Z  g
MSG	20	[2026-08-19T12:34:56Z a][1969-12-31T23:59:59.999Z b][+12026-01-01T00:07:00Z \u00A0][-0001-06-01T23:00:00Z \u00A0c\u00A0][2026-08-19T12:34:56Z \u3000d\u3000][2026-08-19T12:34:56Z e\u2028][1969-12-31T23:59:59.999Z f][+12026-01-01T00:07:00Z \u0085][-0001-06-01T23:00:00Z g]	1234Z  a\u000A2359Z  b\u000A0007Z  \u00A0\u000A2300Z  \u00A0c\u00A0\u000A1234Z  \u3000d\u3000\u000A1234Z  e\u2028\u000A2359Z  f\u000A0007Z  \u0085\u000A2300Z  g
MSG.times	1234Z  x\u000A2359Z  x\u000A0007Z  x\u000A2300Z  x\u000A0000Z  x
MSG.instantMin	1	throws DateTimeException
MSG.clear	0	
"""#
}
