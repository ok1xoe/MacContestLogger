// Table measured on Java v1.1.1 (JDK 21.0.2, en_US) by the maintainer-only probe.
// Do not edit by hand — run the probe again and regenerate the file with
// a maintainer-only probe.

enum CallHistoryMeasured {

    /// Probe rows (TSV, probe escaping `esc`; described in the probe README).
    static let rows: String = #"""
CH.parse	# N1MM call history||!!Order!!,Call,Name,State,CQZone,Exch1||W1AW,Hiram,CT,5,||ok1xoe,Tomas,,15,JN79||DL1ABC,,,14,28	size=3 cols=[call, name, state, cqzone, exch1] recs=[W1AW:{call=W1AW, name=Hiram, state=CT, cqzone=5}; OK1XOE:{call=ok1xoe, name=Tomas, cqzone=15, exch1=JN79}; DL1ABC:{call=DL1ABC, cqzone=14, exch1=28}]
CH.parse	\uFEFF!!Order!!,Call,Name,Exch1||ok1abc,Pavel,15	size=2 cols=[call, name, loc1, loc2, sect, state, ck, birthdate, exch1, misc, usertext] recs=[\uFEFF!!ORDER!!:{call=\uFEFF!!Order!!, name=Call, loc1=Name, loc2=Exch1}; OK1ABC:{call=ok1abc, name=Pavel, loc1=15}]
CH.parse	!!order!!,CALL,Name||w1aw,x	size=1 cols=[call, name] recs=[W1AW:{call=w1aw, name=x}]
CH.parse	!!ORDER!!Call,Name||W1AW,x	size=0 cols=[name] recs=[]
CH.parse	!!Order!!,Name,Call||Hiram,W1AW||Bob||,||x,	size=1 cols=[name, call] recs=[W1AW:{name=Hiram, call=W1AW}]
CH.parse	!!Order!!,Call,Name,State||W1AW,Hiram,CT||w1aw,,MA	size=1 cols=[call, name, state] recs=[W1AW:{call=w1aw, state=MA}]
CH.parse	  # comment||\u3000W1AW,a\u3000||\u00A0K1AB,b||\u0001N1XX ,c||\u0009OK1A , d ,	size=4 cols=[call, name, loc1, loc2, sect, state, ck, birthdate, exch1, misc, usertext] recs=[W1AW:{call=W1AW, name=a}; \u00A0K1AB:{call=\u00A0K1AB, name=b}; N1XX:{call=N1XX, name=c}; OK1A:{call=OK1A, name=d}]
CH.parse	!!Order!!,Call,Na\u0130me,\u03A3\u0391\u03A3, ,Exch1||\u00DF1a,x,y,z,w,v||ok1\u00FF,\u00B5,,,,e	size=2 cols=[call, nai\u0307me, \u03C3\u03B1\u03C2, , exch1] recs=[SS1A:{call=\u00DF1a, nai\u0307me=x, \u03C3\u03B1\u03C2=y, exch1=w}; OK1\u0178:{call=ok1\u00FF, nai\u0307me=\u00B5}]
CH.parse	!!Order!!,Call,Name||A1,x||!!Order!!,Name,Call||y,B1	size=2 cols=[name, call] recs=[A1:{call=A1, name=x}; B1:{name=y, call=B1}]
CH.parse	!!Order!!,Name||x	size=0 cols=[name] recs=[]
CH.parse		size=0 cols=[call, name, loc1, loc2, sect, state, ck, birthdate, exch1, misc, usertext] recs=[]
CH.parse	   ||\u0009	size=0 cols=[call, name, loc1, loc2, sect, state, ck, birthdate, exch1, misc, usertext] recs=[]
CH.parse	!!Order!!,Call,Name,||A1,x,extra	size=1 cols=[call, name, ] recs=[A1:{call=A1, name=x}]
CH.parse	!!Order!!,Call||A1,x,y	size=1 cols=[call] recs=[A1:{call=A1}]
CH.parse	!!Order!!||A1,x	size=0 cols=[] recs=[]
CH.parse	\uD83D\uDE001,x||\uFF411,y	size=2 cols=[call, name, loc1, loc2, sect, state, ck, birthdate, exch1, misc, usertext] recs=[\uD83D\uDE001:{call=\uD83D\uDE001, name=x}; \uFF211:{call=\uFF411, name=y}]
CH.parse	\u00C51,a||A\u030A1,b	size=2 cols=[call, name, loc1, loc2, sect, state, ck, birthdate, exch1, misc, usertext] recs=[\u00C51:{call=\u00C51, name=a}; A\u030A1:{call=A\u030A1, name=b}]
CH.parse	W1AW,Hiram,,,,CT	size=1 cols=[call, name, loc1, loc2, sect, state, ck, birthdate, exch1, misc, usertext] recs=[W1AW:{call=W1AW, name=Hiram, state=CT}]
CH.parse	!!Order!! ,Call,Name||A1,x	size=1 cols=[call, name] recs=[A1:{call=A1, name=x}]
CH.parse	 !!ORDER!!,call,name ||b2,y	size=1 cols=[call, name] recs=[B2:{call=b2, name=y}]
CH.parse	!!Order!!,Call,Name||A1,x\u2028y||#B1,z|| #C1,w	size=1 cols=[call, name] recs=[A1:{call=A1, name=x\u2028y}]
CH.lookup	# N1MM call history||!!Order!!,Call,Name,State,CQZone,Exch1||W1AW,Hiram,CT,5,||ok1xoe,Tomas,,15,JN79||DL1ABC,,,14,28	 ok1xoe 	Optional[{call=ok1xoe, name=Tomas, cqzone=15, exch1=JN79}]
CH.lookup	# N1MM call history||!!Order!!,Call,Name,State,CQZone,Exch1||W1AW,Hiram,CT,5,||ok1xoe,Tomas,,15,JN79||DL1ABC,,,14,28	OK1XOE\u00A0	Optional.empty
CH.lookup	# N1MM call history||!!Order!!,Call,Name,State,CQZone,Exch1||W1AW,Hiram,CT,5,||ok1xoe,Tomas,,15,JN79||DL1ABC,,,14,28	null	Optional.empty
CH.lookup	# N1MM call history||!!Order!!,Call,Name,State,CQZone,Exch1||W1AW,Hiram,CT,5,||ok1xoe,Tomas,,15,JN79||DL1ABC,,,14,28	dl1abc	Optional[{call=DL1ABC, cqzone=14, exch1=28}]
CH.lookup	!!Order!!,Call,Na\u0130me,\u03A3\u0391\u03A3, ,Exch1||\u00DF1a,x,y,z,w,v||ok1\u00FF,\u00B5,,,,e	\u00DF1A	Optional[{call=\u00DF1a, nai\u0307me=x, \u03C3\u03B1\u03C2=y, exch1=w}]
CH.lookup	!!Order!!,Call,Na\u0130me,\u03A3\u0391\u03A3, ,Exch1||\u00DF1a,x,y,z,w,v||ok1\u00FF,\u00B5,,,,e	SS1A	Optional[{call=\u00DF1a, nai\u0307me=x, \u03C3\u03B1\u03C2=y, exch1=w}]
CH.lookup	!!Order!!,Call,Na\u0130me,\u03A3\u0391\u03A3, ,Exch1||\u00DF1a,x,y,z,w,v||ok1\u00FF,\u00B5,,,,e	OK1\u0178	Optional[{call=ok1\u00FF, nai\u0307me=\u00B5}]
CH.lookup	  # comment||\u3000W1AW,a\u3000||\u00A0K1AB,b||\u0001N1XX ,c||\u0009OK1A , d ,	\u00A0k1ab	Optional[{call=\u00A0K1AB, name=b}]
CH.lookup	\u00C51,a||A\u030A1,b	A\u030A1	Optional[{call=A\u030A1, name=b}]
CH.load	efbbbf21214f7264657221212c43616c6c2c4e616d652c45786368310d0a6f6b316162632c506176656c2c31350d0a	size=2 cols=[call, name, loc1, loc2, sect, state, ck, birthdate, exch1, misc, usertext] recs=[\uFEFF!!ORDER!!:{call=\uFEFF!!Order!!, name=Call, loc1=Name, loc2=Exch1}; OK1ABC:{call=ok1abc, name=Pavel, loc1=15}]
CH.load	21214f7264657221212c43616c6c2c4e616d650d41312c780d42312c79	size=2 cols=[call, name] recs=[A1:{call=A1, name=x}; B1:{call=B1, name=y}]
CH.load	21214f7264657221212c43616c6c2c4e616d650a6f6b31782c4af672670a	size=1 cols=[call, name] recs=[OK1X:{call=ok1x, name=J\u00F6rg}]
CH.load	21214f7264657221212c43616c6c2c4e616d650a6f6b31782c4ac3b672670a	size=1 cols=[call, name] recs=[OK1X:{call=ok1x, name=J\u00F6rg}]
CH.load	41312c78e280a8790a42312c7ac28577	size=2 cols=[call, name, loc1, loc2, sect, state, ck, birthdate, exch1, misc, usertext] recs=[A1:{call=A1, name=x\u2028y}; B1:{call=B1, name=z\u0085w}]
CH.load	41312c78eda0800a42312c79	size=2 cols=[call, name, loc1, loc2, sect, state, ck, birthdate, exch1, misc, usertext] recs=[A1:{call=A1, name=x\u00ED\u00A0\u0080}; B1:{call=B1, name=y}]
CH.load	41312c78c0af0a42312c79	size=2 cols=[call, name, loc1, loc2, sect, state, ck, birthdate, exch1, misc, usertext] recs=[A1:{call=A1, name=x\u00C0\u00AF}; B1:{call=B1, name=y}]
CH.load		size=0 cols=[call, name, loc1, loc2, sect, state, ck, birthdate, exch1, misc, usertext] recs=[]
CH.load	41312c7885e90a	size=1 cols=[call, name, loc1, loc2, sect, state, ck, birthdate, exch1, misc, usertext] recs=[A1:{call=A1, name=x\u0085\u00E9}]
CH.load	41312c780a0a42312c790a0a	size=2 cols=[call, name, loc1, loc2, sect, state, ck, birthdate, exch1, misc, usertext] recs=[A1:{call=A1, name=x}; B1:{call=B1, name=y}]
CH.load	41312cf09f98800a	size=1 cols=[call, name, loc1, loc2, sect, state, ck, birthdate, exch1, misc, usertext] recs=[A1:{call=A1, name=\uD83D\uDE00}]
CH.load	41312cf4908080	size=1 cols=[call, name, loc1, loc2, sect, state, ck, birthdate, exch1, misc, usertext] recs=[A1:{call=A1, name=\u00F4\u0090\u0080\u0080}]
CH.load	41312ce282	size=1 cols=[call, name, loc1, loc2, sect, state, ck, birthdate, exch1, misc, usertext] recs=[A1:{call=A1, name=\u00E2\u0082}]
CH.history	H	!!Order!!,Call,Name,State,Sect,CQZone,Zone,ITUZone,Loc1,Grid,District,Loc2,IOTA,Exch1,Misc||W1AW,hiram,ct,,5,,8,fn31,,,,NA-001,x1,m||DL1ABC,,,,,14,,,jo62,,dok,,28,||OK1XOE,\u00DFtrasse,,boh,,,,,,PHA,,,,||VE3XX,,,ON,,,,,,,,,ex,
CH.prefill	H	W1AW	v:RST	{}
CH.prefill	H	DL1ABC	v:RST	{}
CH.prefill	H	ok1xoe	v:RST	{}
CH.prefill	H	VE3XX	v:RST	{}
CH.prefill	H	K1XX	v:RST	{}
CH.prefill	H	null	v:RST	{}
CH.prefill	H	W1AW	v:RST;w:TEXT	{w=HIRAM}
CH.prefill	H	DL1ABC	v:RST;w:TEXT	{w=28}
CH.prefill	H	ok1xoe	v:RST;w:TEXT	{w=SSTRASSE}
CH.prefill	H	VE3XX	v:RST;w:TEXT	{w=EX}
CH.prefill	H	K1XX	v:RST;w:TEXT	{}
CH.prefill	H	null	v:RST;w:TEXT	{}
CH.prefill	H	W1AW	v:RS	{}
CH.prefill	H	DL1ABC	v:RS	{}
CH.prefill	H	ok1xoe	v:RS	{}
CH.prefill	H	VE3XX	v:RS	{}
CH.prefill	H	K1XX	v:RS	{}
CH.prefill	H	null	v:RS	{}
CH.prefill	H	W1AW	v:RS;w:TEXT	{w=HIRAM}
CH.prefill	H	DL1ABC	v:RS;w:TEXT	{w=28}
CH.prefill	H	ok1xoe	v:RS;w:TEXT	{w=SSTRASSE}
CH.prefill	H	VE3XX	v:RS;w:TEXT	{w=EX}
CH.prefill	H	K1XX	v:RS;w:TEXT	{}
CH.prefill	H	null	v:RS;w:TEXT	{}
CH.prefill	H	W1AW	v:SERIAL	{}
CH.prefill	H	DL1ABC	v:SERIAL	{}
CH.prefill	H	ok1xoe	v:SERIAL	{}
CH.prefill	H	VE3XX	v:SERIAL	{}
CH.prefill	H	K1XX	v:SERIAL	{}
CH.prefill	H	null	v:SERIAL	{}
CH.prefill	H	W1AW	v:SERIAL;w:TEXT	{w=HIRAM}
CH.prefill	H	DL1ABC	v:SERIAL;w:TEXT	{w=28}
CH.prefill	H	ok1xoe	v:SERIAL;w:TEXT	{w=SSTRASSE}
CH.prefill	H	VE3XX	v:SERIAL;w:TEXT	{w=EX}
CH.prefill	H	K1XX	v:SERIAL;w:TEXT	{}
CH.prefill	H	null	v:SERIAL;w:TEXT	{}
CH.prefill	H	W1AW	v:INTEGER	{v=X1}
CH.prefill	H	DL1ABC	v:INTEGER	{v=28}
CH.prefill	H	ok1xoe	v:INTEGER	{}
CH.prefill	H	VE3XX	v:INTEGER	{v=EX}
CH.prefill	H	K1XX	v:INTEGER	{}
CH.prefill	H	null	v:INTEGER	{}
CH.prefill	H	W1AW	v:INTEGER;w:TEXT	{v=X1, w=HIRAM}
CH.prefill	H	DL1ABC	v:INTEGER;w:TEXT	{v=28, w=28}
CH.prefill	H	ok1xoe	v:INTEGER;w:TEXT	{w=SSTRASSE}
CH.prefill	H	VE3XX	v:INTEGER;w:TEXT	{v=EX, w=EX}
CH.prefill	H	K1XX	v:INTEGER;w:TEXT	{}
CH.prefill	H	null	v:INTEGER;w:TEXT	{}
CH.prefill	H	W1AW	v:TEXT	{v=HIRAM}
CH.prefill	H	DL1ABC	v:TEXT	{v=28}
CH.prefill	H	ok1xoe	v:TEXT	{v=SSTRASSE}
CH.prefill	H	VE3XX	v:TEXT	{v=EX}
CH.prefill	H	K1XX	v:TEXT	{}
CH.prefill	H	null	v:TEXT	{}
CH.prefill	H	W1AW	v:TEXT;w:TEXT	{v=HIRAM, w=HIRAM}
CH.prefill	H	DL1ABC	v:TEXT;w:TEXT	{v=28, w=28}
CH.prefill	H	ok1xoe	v:TEXT;w:TEXT	{v=SSTRASSE, w=SSTRASSE}
CH.prefill	H	VE3XX	v:TEXT;w:TEXT	{v=EX, w=EX}
CH.prefill	H	K1XX	v:TEXT;w:TEXT	{}
CH.prefill	H	null	v:TEXT;w:TEXT	{}
CH.prefill	H	W1AW	v:LOCATOR	{v=FN31}
CH.prefill	H	DL1ABC	v:LOCATOR	{v=JO62}
CH.prefill	H	ok1xoe	v:LOCATOR	{}
CH.prefill	H	VE3XX	v:LOCATOR	{v=EX}
CH.prefill	H	K1XX	v:LOCATOR	{}
CH.prefill	H	null	v:LOCATOR	{}
CH.prefill	H	W1AW	v:LOCATOR;w:TEXT	{v=FN31, w=HIRAM}
CH.prefill	H	DL1ABC	v:LOCATOR;w:TEXT	{v=JO62, w=28}
CH.prefill	H	ok1xoe	v:LOCATOR;w:TEXT	{w=SSTRASSE}
CH.prefill	H	VE3XX	v:LOCATOR;w:TEXT	{v=EX, w=EX}
CH.prefill	H	K1XX	v:LOCATOR;w:TEXT	{}
CH.prefill	H	null	v:LOCATOR;w:TEXT	{}
CH.prefill	H	W1AW	v:CQ_ZONE	{v=5}
CH.prefill	H	DL1ABC	v:CQ_ZONE	{v=14}
CH.prefill	H	ok1xoe	v:CQ_ZONE	{}
CH.prefill	H	VE3XX	v:CQ_ZONE	{v=EX}
CH.prefill	H	K1XX	v:CQ_ZONE	{}
CH.prefill	H	null	v:CQ_ZONE	{}
CH.prefill	H	W1AW	v:CQ_ZONE;w:TEXT	{v=5, w=HIRAM}
CH.prefill	H	DL1ABC	v:CQ_ZONE;w:TEXT	{v=14, w=28}
CH.prefill	H	ok1xoe	v:CQ_ZONE;w:TEXT	{w=SSTRASSE}
CH.prefill	H	VE3XX	v:CQ_ZONE;w:TEXT	{v=EX, w=EX}
CH.prefill	H	K1XX	v:CQ_ZONE;w:TEXT	{}
CH.prefill	H	null	v:CQ_ZONE;w:TEXT	{}
CH.prefill	H	W1AW	v:ITU_ZONE	{v=8}
CH.prefill	H	DL1ABC	v:ITU_ZONE	{v=14}
CH.prefill	H	ok1xoe	v:ITU_ZONE	{}
CH.prefill	H	VE3XX	v:ITU_ZONE	{v=EX}
CH.prefill	H	K1XX	v:ITU_ZONE	{}
CH.prefill	H	null	v:ITU_ZONE	{}
CH.prefill	H	W1AW	v:ITU_ZONE;w:TEXT	{v=8, w=HIRAM}
CH.prefill	H	DL1ABC	v:ITU_ZONE;w:TEXT	{v=14, w=28}
CH.prefill	H	ok1xoe	v:ITU_ZONE;w:TEXT	{w=SSTRASSE}
CH.prefill	H	VE3XX	v:ITU_ZONE;w:TEXT	{v=EX, w=EX}
CH.prefill	H	K1XX	v:ITU_ZONE;w:TEXT	{}
CH.prefill	H	null	v:ITU_ZONE;w:TEXT	{}
CH.prefill	H	W1AW	v:DXCC	{v=X1}
CH.prefill	H	DL1ABC	v:DXCC	{v=28}
CH.prefill	H	ok1xoe	v:DXCC	{}
CH.prefill	H	VE3XX	v:DXCC	{v=EX}
CH.prefill	H	K1XX	v:DXCC	{}
CH.prefill	H	null	v:DXCC	{}
CH.prefill	H	W1AW	v:DXCC;w:TEXT	{v=X1, w=HIRAM}
CH.prefill	H	DL1ABC	v:DXCC;w:TEXT	{v=28, w=28}
CH.prefill	H	ok1xoe	v:DXCC;w:TEXT	{w=SSTRASSE}
CH.prefill	H	VE3XX	v:DXCC;w:TEXT	{v=EX, w=EX}
CH.prefill	H	K1XX	v:DXCC;w:TEXT	{}
CH.prefill	H	null	v:DXCC;w:TEXT	{}
CH.prefill	H	W1AW	v:PREFIX	{v=X1}
CH.prefill	H	DL1ABC	v:PREFIX	{v=28}
CH.prefill	H	ok1xoe	v:PREFIX	{}
CH.prefill	H	VE3XX	v:PREFIX	{v=EX}
CH.prefill	H	K1XX	v:PREFIX	{}
CH.prefill	H	null	v:PREFIX	{}
CH.prefill	H	W1AW	v:PREFIX;w:TEXT	{v=X1, w=HIRAM}
CH.prefill	H	DL1ABC	v:PREFIX;w:TEXT	{v=28, w=28}
CH.prefill	H	ok1xoe	v:PREFIX;w:TEXT	{w=SSTRASSE}
CH.prefill	H	VE3XX	v:PREFIX;w:TEXT	{v=EX, w=EX}
CH.prefill	H	K1XX	v:PREFIX;w:TEXT	{}
CH.prefill	H	null	v:PREFIX;w:TEXT	{}
CH.prefill	H	W1AW	v:HQ	{v=X1}
CH.prefill	H	DL1ABC	v:HQ	{v=28}
CH.prefill	H	ok1xoe	v:HQ	{}
CH.prefill	H	VE3XX	v:HQ	{v=EX}
CH.prefill	H	K1XX	v:HQ	{}
CH.prefill	H	null	v:HQ	{}
CH.prefill	H	W1AW	v:HQ;w:TEXT	{v=X1, w=HIRAM}
CH.prefill	H	DL1ABC	v:HQ;w:TEXT	{v=28, w=28}
CH.prefill	H	ok1xoe	v:HQ;w:TEXT	{w=SSTRASSE}
CH.prefill	H	VE3XX	v:HQ;w:TEXT	{v=EX, w=EX}
CH.prefill	H	K1XX	v:HQ;w:TEXT	{}
CH.prefill	H	null	v:HQ;w:TEXT	{}
CH.prefill	H	W1AW	v:NATIONAL	{v=X1}
CH.prefill	H	DL1ABC	v:NATIONAL	{v=28}
CH.prefill	H	ok1xoe	v:NATIONAL	{}
CH.prefill	H	VE3XX	v:NATIONAL	{v=EX}
CH.prefill	H	K1XX	v:NATIONAL	{}
CH.prefill	H	null	v:NATIONAL	{}
CH.prefill	H	W1AW	v:NATIONAL;w:TEXT	{v=X1, w=HIRAM}
CH.prefill	H	DL1ABC	v:NATIONAL;w:TEXT	{v=28, w=28}
CH.prefill	H	ok1xoe	v:NATIONAL;w:TEXT	{w=SSTRASSE}
CH.prefill	H	VE3XX	v:NATIONAL;w:TEXT	{v=EX, w=EX}
CH.prefill	H	K1XX	v:NATIONAL;w:TEXT	{}
CH.prefill	H	null	v:NATIONAL;w:TEXT	{}
CH.prefill	H	W1AW	v:STATE	{v=CT}
CH.prefill	H	DL1ABC	v:STATE	{v=28}
CH.prefill	H	ok1xoe	v:STATE	{v=BOH}
CH.prefill	H	VE3XX	v:STATE	{v=ON}
CH.prefill	H	K1XX	v:STATE	{}
CH.prefill	H	null	v:STATE	{}
CH.prefill	H	W1AW	v:STATE;w:TEXT	{v=CT, w=HIRAM}
CH.prefill	H	DL1ABC	v:STATE;w:TEXT	{v=28, w=28}
CH.prefill	H	ok1xoe	v:STATE;w:TEXT	{v=BOH, w=SSTRASSE}
CH.prefill	H	VE3XX	v:STATE;w:TEXT	{v=ON, w=EX}
CH.prefill	H	K1XX	v:STATE;w:TEXT	{}
CH.prefill	H	null	v:STATE;w:TEXT	{}
CH.prefill	H	W1AW	v:PROVINCE	{v=CT}
CH.prefill	H	DL1ABC	v:PROVINCE	{v=28}
CH.prefill	H	ok1xoe	v:PROVINCE	{v=BOH}
CH.prefill	H	VE3XX	v:PROVINCE	{v=ON}
CH.prefill	H	K1XX	v:PROVINCE	{}
CH.prefill	H	null	v:PROVINCE	{}
CH.prefill	H	W1AW	v:PROVINCE;w:TEXT	{v=CT, w=HIRAM}
CH.prefill	H	DL1ABC	v:PROVINCE;w:TEXT	{v=28, w=28}
CH.prefill	H	ok1xoe	v:PROVINCE;w:TEXT	{v=BOH, w=SSTRASSE}
CH.prefill	H	VE3XX	v:PROVINCE;w:TEXT	{v=ON, w=EX}
CH.prefill	H	K1XX	v:PROVINCE;w:TEXT	{}
CH.prefill	H	null	v:PROVINCE;w:TEXT	{}
CH.prefill	H	W1AW	v:DISTRICT	{v=X1}
CH.prefill	H	DL1ABC	v:DISTRICT	{v=DOK}
CH.prefill	H	ok1xoe	v:DISTRICT	{v=PHA}
CH.prefill	H	VE3XX	v:DISTRICT	{v=EX}
CH.prefill	H	K1XX	v:DISTRICT	{}
CH.prefill	H	null	v:DISTRICT	{}
CH.prefill	H	W1AW	v:DISTRICT;w:TEXT	{v=X1, w=HIRAM}
CH.prefill	H	DL1ABC	v:DISTRICT;w:TEXT	{v=DOK, w=28}
CH.prefill	H	ok1xoe	v:DISTRICT;w:TEXT	{v=PHA, w=SSTRASSE}
CH.prefill	H	VE3XX	v:DISTRICT;w:TEXT	{v=EX, w=EX}
CH.prefill	H	K1XX	v:DISTRICT;w:TEXT	{}
CH.prefill	H	null	v:DISTRICT;w:TEXT	{}
CH.prefill	H	W1AW	v:IOTA	{v=NA-001}
CH.prefill	H	DL1ABC	v:IOTA	{v=28}
CH.prefill	H	ok1xoe	v:IOTA	{}
CH.prefill	H	VE3XX	v:IOTA	{v=EX}
CH.prefill	H	K1XX	v:IOTA	{}
CH.prefill	H	null	v:IOTA	{}
CH.prefill	H	W1AW	v:IOTA;w:TEXT	{v=NA-001, w=HIRAM}
CH.prefill	H	DL1ABC	v:IOTA;w:TEXT	{v=28, w=28}
CH.prefill	H	ok1xoe	v:IOTA;w:TEXT	{w=SSTRASSE}
CH.prefill	H	VE3XX	v:IOTA;w:TEXT	{v=EX, w=EX}
CH.prefill	H	K1XX	v:IOTA;w:TEXT	{}
CH.prefill	H	null	v:IOTA;w:TEXT	{}
CH.prefill	H	W1AW	v:QTC	{v=X1}
CH.prefill	H	DL1ABC	v:QTC	{v=28}
CH.prefill	H	ok1xoe	v:QTC	{}
CH.prefill	H	VE3XX	v:QTC	{v=EX}
CH.prefill	H	K1XX	v:QTC	{}
CH.prefill	H	null	v:QTC	{}
CH.prefill	H	W1AW	v:QTC;w:TEXT	{v=X1, w=HIRAM}
CH.prefill	H	DL1ABC	v:QTC;w:TEXT	{v=28, w=28}
CH.prefill	H	ok1xoe	v:QTC;w:TEXT	{w=SSTRASSE}
CH.prefill	H	VE3XX	v:QTC;w:TEXT	{v=EX, w=EX}
CH.prefill	H	K1XX	v:QTC;w:TEXT	{}
CH.prefill	H	null	v:QTC;w:TEXT	{}
CH.prefill	H	W1AW	v:null	{v=X1}
CH.prefill	H	DL1ABC	v:null	{v=28}
CH.prefill	H	ok1xoe	v:null	{}
CH.prefill	H	VE3XX	v:null	{v=EX}
CH.prefill	H	K1XX	v:null	{}
CH.prefill	H	null	v:null	{}
CH.prefill	H	W1AW	v:null;w:TEXT	{w=HIRAM}
CH.prefill	H	DL1ABC	v:null;w:TEXT	{w=28}
CH.prefill	H	ok1xoe	v:null;w:TEXT	{w=SSTRASSE}
CH.prefill	H	VE3XX	v:null;w:TEXT	{w=EX}
CH.prefill	H	K1XX	v:null;w:TEXT	{}
CH.prefill	H	null	v:null;w:TEXT	{}
CH.prefill	H	W1AW	Name:TEXT;STATE:CQ_ZONE	{Name=HIRAM, STATE=CT}
CH.prefill	H	DL1ABC	Name:TEXT;STATE:CQ_ZONE	{Name=28, STATE=14}
CH.prefill	H	ok1xoe	Name:TEXT;STATE:CQ_ZONE	{Name=SSTRASSE}
CH.prefill	H	VE3XX	Name:TEXT;STATE:CQ_ZONE	{Name=EX, STATE=EX}
CH.prefill	H	K1XX	Name:TEXT;STATE:CQ_ZONE	{}
CH.prefill	H	null	Name:TEXT;STATE:CQ_ZONE	{}
CH.prefill	H	W1AW	misc:INTEGER	{misc=M}
CH.prefill	H	DL1ABC	misc:INTEGER	{misc=28}
CH.prefill	H	ok1xoe	misc:INTEGER	{}
CH.prefill	H	VE3XX	misc:INTEGER	{misc=EX}
CH.prefill	H	K1XX	misc:INTEGER	{}
CH.prefill	H	null	misc:INTEGER	{}
CH.prefill	H	W1AW	rst:RST;nr:SERIAL;p:INTEGER	{p=X1}
CH.prefill	H	DL1ABC	rst:RST;nr:SERIAL;p:INTEGER	{p=28}
CH.prefill	H	ok1xoe	rst:RST;nr:SERIAL;p:INTEGER	{}
CH.prefill	H	VE3XX	rst:RST;nr:SERIAL;p:INTEGER	{p=EX}
CH.prefill	H	K1XX	rst:RST;nr:SERIAL;p:INTEGER	{}
CH.prefill	H	null	rst:RST;nr:SERIAL;p:INTEGER	{}
CH.prefill	H	W1AW	rst:RST;zone:CQ_ZONE	{zone=5}
CH.prefill	H	DL1ABC	rst:RST;zone:CQ_ZONE	{zone=14}
CH.prefill	H	ok1xoe	rst:RST;zone:CQ_ZONE	{}
CH.prefill	H	VE3XX	rst:RST;zone:CQ_ZONE	{zone=EX}
CH.prefill	H	K1XX	rst:RST;zone:CQ_ZONE	{}
CH.prefill	H	null	rst:RST;zone:CQ_ZONE	{}
CH.prefill	H	W1AW	rst:RST	{}
CH.prefill	H	DL1ABC	rst:RST	{}
CH.prefill	H	ok1xoe	rst:RST	{}
CH.prefill	H	VE3XX	rst:RST	{}
CH.prefill	H	K1XX	rst:RST	{}
CH.prefill	H	null	rst:RST	{}
CH.prefill	H	W1AW	<null>	{}
CH.reverse	H	v=CT	v:RST	10	[]
CH.reverse	H	v=5	v:RST	10	[]
CH.reverse	H	v= x1 	v:RST	10	[]
CH.reverse	H	v=28	v:RST	10	[]
CH.reverse	H	v=pha	v:RST	10	[]
CH.reverse	H	v=ex	v:RST	10	[]
CH.reverse	H	v=ex	v:RST	1	[]
CH.reverse	H	v=ex	v:RST	0	[]
CH.reverse	H	v=ex	v:RST	-1	[]
CH.reverse	H	v=;w=hiram	v:RST	10	[]
CH.reverse	H	v=ON;w=	v:RST	10	[]
CH.reverse	H	w=hiram	v:RST	10	[]
CH.reverse	H	w=hiram	v:RST	1	[]
CH.reverse	H	w=hiram	v:RST	0	[]
CH.reverse	H	w=hiram	v:RST	-1	[]
CH.reverse	H	v=\u00DFtrasse	v:RST	10	[]
CH.reverse	H	v=SSTRASSE	v:RST	10	[]
CH.reverse	H		v:RST	10	[]
CH.reverse	H	v=\u00A0	v:RST	10	[]
CH.reverse	H	v=14;w=	v:RST	10	[]
CH.reverse	H	v=m	v:RST	10	[]
CH.reverse	H	v=CT	v:RST;w:TEXT	10	[]
CH.reverse	H	v=5	v:RST;w:TEXT	10	[]
CH.reverse	H	v= x1 	v:RST;w:TEXT	10	[]
CH.reverse	H	v=28	v:RST;w:TEXT	10	[]
CH.reverse	H	v=pha	v:RST;w:TEXT	10	[]
CH.reverse	H	v=ex	v:RST;w:TEXT	10	[]
CH.reverse	H	v=ex	v:RST;w:TEXT	1	[]
CH.reverse	H	v=ex	v:RST;w:TEXT	0	[]
CH.reverse	H	v=ex	v:RST;w:TEXT	-1	[]
CH.reverse	H	v=;w=hiram	v:RST;w:TEXT	10	[W1AW]
CH.reverse	H	v=ON;w=	v:RST;w:TEXT	10	[]
CH.reverse	H	w=hiram	v:RST;w:TEXT	10	[W1AW]
CH.reverse	H	w=hiram	v:RST;w:TEXT	1	[W1AW]
CH.reverse	H	w=hiram	v:RST;w:TEXT	0	[]
CH.reverse	H	w=hiram	v:RST;w:TEXT	-1	[]
CH.reverse	H	v=\u00DFtrasse	v:RST;w:TEXT	10	[]
CH.reverse	H	v=SSTRASSE	v:RST;w:TEXT	10	[]
CH.reverse	H		v:RST;w:TEXT	10	[]
CH.reverse	H	v=\u00A0	v:RST;w:TEXT	10	[]
CH.reverse	H	v=14;w=	v:RST;w:TEXT	10	[]
CH.reverse	H	v=m	v:RST;w:TEXT	10	[]
CH.reverse	H	v=CT	v:RS	10	[]
CH.reverse	H	v=5	v:RS	10	[]
CH.reverse	H	v= x1 	v:RS	10	[]
CH.reverse	H	v=28	v:RS	10	[]
CH.reverse	H	v=pha	v:RS	10	[]
CH.reverse	H	v=ex	v:RS	10	[]
CH.reverse	H	v=ex	v:RS	1	[]
CH.reverse	H	v=ex	v:RS	0	[]
CH.reverse	H	v=ex	v:RS	-1	[]
CH.reverse	H	v=;w=hiram	v:RS	10	[]
CH.reverse	H	v=ON;w=	v:RS	10	[]
CH.reverse	H	w=hiram	v:RS	10	[]
CH.reverse	H	w=hiram	v:RS	1	[]
CH.reverse	H	w=hiram	v:RS	0	[]
CH.reverse	H	w=hiram	v:RS	-1	[]
CH.reverse	H	v=\u00DFtrasse	v:RS	10	[]
CH.reverse	H	v=SSTRASSE	v:RS	10	[]
CH.reverse	H		v:RS	10	[]
CH.reverse	H	v=\u00A0	v:RS	10	[]
CH.reverse	H	v=14;w=	v:RS	10	[]
CH.reverse	H	v=m	v:RS	10	[]
CH.reverse	H	v=CT	v:RS;w:TEXT	10	[]
CH.reverse	H	v=5	v:RS;w:TEXT	10	[]
CH.reverse	H	v= x1 	v:RS;w:TEXT	10	[]
CH.reverse	H	v=28	v:RS;w:TEXT	10	[]
CH.reverse	H	v=pha	v:RS;w:TEXT	10	[]
CH.reverse	H	v=ex	v:RS;w:TEXT	10	[]
CH.reverse	H	v=ex	v:RS;w:TEXT	1	[]
CH.reverse	H	v=ex	v:RS;w:TEXT	0	[]
CH.reverse	H	v=ex	v:RS;w:TEXT	-1	[]
CH.reverse	H	v=;w=hiram	v:RS;w:TEXT	10	[W1AW]
CH.reverse	H	v=ON;w=	v:RS;w:TEXT	10	[]
CH.reverse	H	w=hiram	v:RS;w:TEXT	10	[W1AW]
CH.reverse	H	w=hiram	v:RS;w:TEXT	1	[W1AW]
CH.reverse	H	w=hiram	v:RS;w:TEXT	0	[]
CH.reverse	H	w=hiram	v:RS;w:TEXT	-1	[]
CH.reverse	H	v=\u00DFtrasse	v:RS;w:TEXT	10	[]
CH.reverse	H	v=SSTRASSE	v:RS;w:TEXT	10	[]
CH.reverse	H		v:RS;w:TEXT	10	[]
CH.reverse	H	v=\u00A0	v:RS;w:TEXT	10	[]
CH.reverse	H	v=14;w=	v:RS;w:TEXT	10	[]
CH.reverse	H	v=m	v:RS;w:TEXT	10	[]
CH.reverse	H	v=CT	v:SERIAL	10	[]
CH.reverse	H	v=5	v:SERIAL	10	[]
CH.reverse	H	v= x1 	v:SERIAL	10	[]
CH.reverse	H	v=28	v:SERIAL	10	[]
CH.reverse	H	v=pha	v:SERIAL	10	[]
CH.reverse	H	v=ex	v:SERIAL	10	[]
CH.reverse	H	v=ex	v:SERIAL	1	[]
CH.reverse	H	v=ex	v:SERIAL	0	[]
CH.reverse	H	v=ex	v:SERIAL	-1	[]
CH.reverse	H	v=;w=hiram	v:SERIAL	10	[]
CH.reverse	H	v=ON;w=	v:SERIAL	10	[]
CH.reverse	H	w=hiram	v:SERIAL	10	[]
CH.reverse	H	w=hiram	v:SERIAL	1	[]
CH.reverse	H	w=hiram	v:SERIAL	0	[]
CH.reverse	H	w=hiram	v:SERIAL	-1	[]
CH.reverse	H	v=\u00DFtrasse	v:SERIAL	10	[]
CH.reverse	H	v=SSTRASSE	v:SERIAL	10	[]
CH.reverse	H		v:SERIAL	10	[]
CH.reverse	H	v=\u00A0	v:SERIAL	10	[]
CH.reverse	H	v=14;w=	v:SERIAL	10	[]
CH.reverse	H	v=m	v:SERIAL	10	[]
CH.reverse	H	v=CT	v:SERIAL;w:TEXT	10	[]
CH.reverse	H	v=5	v:SERIAL;w:TEXT	10	[]
CH.reverse	H	v= x1 	v:SERIAL;w:TEXT	10	[]
CH.reverse	H	v=28	v:SERIAL;w:TEXT	10	[]
CH.reverse	H	v=pha	v:SERIAL;w:TEXT	10	[]
CH.reverse	H	v=ex	v:SERIAL;w:TEXT	10	[]
CH.reverse	H	v=ex	v:SERIAL;w:TEXT	1	[]
CH.reverse	H	v=ex	v:SERIAL;w:TEXT	0	[]
CH.reverse	H	v=ex	v:SERIAL;w:TEXT	-1	[]
CH.reverse	H	v=;w=hiram	v:SERIAL;w:TEXT	10	[W1AW]
CH.reverse	H	v=ON;w=	v:SERIAL;w:TEXT	10	[]
CH.reverse	H	w=hiram	v:SERIAL;w:TEXT	10	[W1AW]
CH.reverse	H	w=hiram	v:SERIAL;w:TEXT	1	[W1AW]
CH.reverse	H	w=hiram	v:SERIAL;w:TEXT	0	[]
CH.reverse	H	w=hiram	v:SERIAL;w:TEXT	-1	[]
CH.reverse	H	v=\u00DFtrasse	v:SERIAL;w:TEXT	10	[]
CH.reverse	H	v=SSTRASSE	v:SERIAL;w:TEXT	10	[]
CH.reverse	H		v:SERIAL;w:TEXT	10	[]
CH.reverse	H	v=\u00A0	v:SERIAL;w:TEXT	10	[]
CH.reverse	H	v=14;w=	v:SERIAL;w:TEXT	10	[]
CH.reverse	H	v=m	v:SERIAL;w:TEXT	10	[]
CH.reverse	H	v=CT	v:INTEGER	10	[]
CH.reverse	H	v=5	v:INTEGER	10	[]
CH.reverse	H	v= x1 	v:INTEGER	10	[W1AW]
CH.reverse	H	v=28	v:INTEGER	10	[DL1ABC]
CH.reverse	H	v=pha	v:INTEGER	10	[]
CH.reverse	H	v=ex	v:INTEGER	10	[VE3XX]
CH.reverse	H	v=ex	v:INTEGER	1	[VE3XX]
CH.reverse	H	v=ex	v:INTEGER	0	[]
CH.reverse	H	v=ex	v:INTEGER	-1	[]
CH.reverse	H	v=;w=hiram	v:INTEGER	10	[]
CH.reverse	H	v=ON;w=	v:INTEGER	10	[]
CH.reverse	H	w=hiram	v:INTEGER	10	[]
CH.reverse	H	w=hiram	v:INTEGER	1	[]
CH.reverse	H	w=hiram	v:INTEGER	0	[]
CH.reverse	H	w=hiram	v:INTEGER	-1	[]
CH.reverse	H	v=\u00DFtrasse	v:INTEGER	10	[]
CH.reverse	H	v=SSTRASSE	v:INTEGER	10	[]
CH.reverse	H		v:INTEGER	10	[]
CH.reverse	H	v=\u00A0	v:INTEGER	10	[]
CH.reverse	H	v=14;w=	v:INTEGER	10	[]
CH.reverse	H	v=m	v:INTEGER	10	[]
CH.reverse	H	v=CT	v:INTEGER;w:TEXT	10	[]
CH.reverse	H	v=5	v:INTEGER;w:TEXT	10	[]
CH.reverse	H	v= x1 	v:INTEGER;w:TEXT	10	[W1AW]
CH.reverse	H	v=28	v:INTEGER;w:TEXT	10	[DL1ABC]
CH.reverse	H	v=pha	v:INTEGER;w:TEXT	10	[]
CH.reverse	H	v=ex	v:INTEGER;w:TEXT	10	[VE3XX]
CH.reverse	H	v=ex	v:INTEGER;w:TEXT	1	[VE3XX]
CH.reverse	H	v=ex	v:INTEGER;w:TEXT	0	[]
CH.reverse	H	v=ex	v:INTEGER;w:TEXT	-1	[]
CH.reverse	H	v=;w=hiram	v:INTEGER;w:TEXT	10	[W1AW]
CH.reverse	H	v=ON;w=	v:INTEGER;w:TEXT	10	[]
CH.reverse	H	w=hiram	v:INTEGER;w:TEXT	10	[W1AW]
CH.reverse	H	w=hiram	v:INTEGER;w:TEXT	1	[W1AW]
CH.reverse	H	w=hiram	v:INTEGER;w:TEXT	0	[]
CH.reverse	H	w=hiram	v:INTEGER;w:TEXT	-1	[]
CH.reverse	H	v=\u00DFtrasse	v:INTEGER;w:TEXT	10	[]
CH.reverse	H	v=SSTRASSE	v:INTEGER;w:TEXT	10	[]
CH.reverse	H		v:INTEGER;w:TEXT	10	[]
CH.reverse	H	v=\u00A0	v:INTEGER;w:TEXT	10	[]
CH.reverse	H	v=14;w=	v:INTEGER;w:TEXT	10	[]
CH.reverse	H	v=m	v:INTEGER;w:TEXT	10	[]
CH.reverse	H	v=CT	v:TEXT	10	[]
CH.reverse	H	v=5	v:TEXT	10	[]
CH.reverse	H	v= x1 	v:TEXT	10	[]
CH.reverse	H	v=28	v:TEXT	10	[DL1ABC]
CH.reverse	H	v=pha	v:TEXT	10	[]
CH.reverse	H	v=ex	v:TEXT	10	[VE3XX]
CH.reverse	H	v=ex	v:TEXT	1	[VE3XX]
CH.reverse	H	v=ex	v:TEXT	0	[]
CH.reverse	H	v=ex	v:TEXT	-1	[]
CH.reverse	H	v=;w=hiram	v:TEXT	10	[]
CH.reverse	H	v=ON;w=	v:TEXT	10	[]
CH.reverse	H	w=hiram	v:TEXT	10	[]
CH.reverse	H	w=hiram	v:TEXT	1	[]
CH.reverse	H	w=hiram	v:TEXT	0	[]
CH.reverse	H	w=hiram	v:TEXT	-1	[]
CH.reverse	H	v=\u00DFtrasse	v:TEXT	10	[OK1XOE]
CH.reverse	H	v=SSTRASSE	v:TEXT	10	[]
CH.reverse	H		v:TEXT	10	[]
CH.reverse	H	v=\u00A0	v:TEXT	10	[]
CH.reverse	H	v=14;w=	v:TEXT	10	[]
CH.reverse	H	v=m	v:TEXT	10	[]
CH.reverse	H	v=CT	v:TEXT;w:TEXT	10	[]
CH.reverse	H	v=5	v:TEXT;w:TEXT	10	[]
CH.reverse	H	v= x1 	v:TEXT;w:TEXT	10	[]
CH.reverse	H	v=28	v:TEXT;w:TEXT	10	[DL1ABC]
CH.reverse	H	v=pha	v:TEXT;w:TEXT	10	[]
CH.reverse	H	v=ex	v:TEXT;w:TEXT	10	[VE3XX]
CH.reverse	H	v=ex	v:TEXT;w:TEXT	1	[VE3XX]
CH.reverse	H	v=ex	v:TEXT;w:TEXT	0	[]
CH.reverse	H	v=ex	v:TEXT;w:TEXT	-1	[]
CH.reverse	H	v=;w=hiram	v:TEXT;w:TEXT	10	[W1AW]
CH.reverse	H	v=ON;w=	v:TEXT;w:TEXT	10	[]
CH.reverse	H	w=hiram	v:TEXT;w:TEXT	10	[W1AW]
CH.reverse	H	w=hiram	v:TEXT;w:TEXT	1	[W1AW]
CH.reverse	H	w=hiram	v:TEXT;w:TEXT	0	[]
CH.reverse	H	w=hiram	v:TEXT;w:TEXT	-1	[]
CH.reverse	H	v=\u00DFtrasse	v:TEXT;w:TEXT	10	[OK1XOE]
CH.reverse	H	v=SSTRASSE	v:TEXT;w:TEXT	10	[]
CH.reverse	H		v:TEXT;w:TEXT	10	[]
CH.reverse	H	v=\u00A0	v:TEXT;w:TEXT	10	[]
CH.reverse	H	v=14;w=	v:TEXT;w:TEXT	10	[]
CH.reverse	H	v=m	v:TEXT;w:TEXT	10	[]
CH.reverse	H	v=CT	v:LOCATOR	10	[]
CH.reverse	H	v=5	v:LOCATOR	10	[]
CH.reverse	H	v= x1 	v:LOCATOR	10	[]
CH.reverse	H	v=28	v:LOCATOR	10	[]
CH.reverse	H	v=pha	v:LOCATOR	10	[]
CH.reverse	H	v=ex	v:LOCATOR	10	[VE3XX]
CH.reverse	H	v=ex	v:LOCATOR	1	[VE3XX]
CH.reverse	H	v=ex	v:LOCATOR	0	[]
CH.reverse	H	v=ex	v:LOCATOR	-1	[]
CH.reverse	H	v=;w=hiram	v:LOCATOR	10	[]
CH.reverse	H	v=ON;w=	v:LOCATOR	10	[]
CH.reverse	H	w=hiram	v:LOCATOR	10	[]
CH.reverse	H	w=hiram	v:LOCATOR	1	[]
CH.reverse	H	w=hiram	v:LOCATOR	0	[]
CH.reverse	H	w=hiram	v:LOCATOR	-1	[]
CH.reverse	H	v=\u00DFtrasse	v:LOCATOR	10	[]
CH.reverse	H	v=SSTRASSE	v:LOCATOR	10	[]
CH.reverse	H		v:LOCATOR	10	[]
CH.reverse	H	v=\u00A0	v:LOCATOR	10	[]
CH.reverse	H	v=14;w=	v:LOCATOR	10	[]
CH.reverse	H	v=m	v:LOCATOR	10	[]
CH.reverse	H	v=CT	v:LOCATOR;w:TEXT	10	[]
CH.reverse	H	v=5	v:LOCATOR;w:TEXT	10	[]
CH.reverse	H	v= x1 	v:LOCATOR;w:TEXT	10	[]
CH.reverse	H	v=28	v:LOCATOR;w:TEXT	10	[]
CH.reverse	H	v=pha	v:LOCATOR;w:TEXT	10	[]
CH.reverse	H	v=ex	v:LOCATOR;w:TEXT	10	[VE3XX]
CH.reverse	H	v=ex	v:LOCATOR;w:TEXT	1	[VE3XX]
CH.reverse	H	v=ex	v:LOCATOR;w:TEXT	0	[]
CH.reverse	H	v=ex	v:LOCATOR;w:TEXT	-1	[]
CH.reverse	H	v=;w=hiram	v:LOCATOR;w:TEXT	10	[W1AW]
CH.reverse	H	v=ON;w=	v:LOCATOR;w:TEXT	10	[]
CH.reverse	H	w=hiram	v:LOCATOR;w:TEXT	10	[W1AW]
CH.reverse	H	w=hiram	v:LOCATOR;w:TEXT	1	[W1AW]
CH.reverse	H	w=hiram	v:LOCATOR;w:TEXT	0	[]
CH.reverse	H	w=hiram	v:LOCATOR;w:TEXT	-1	[]
CH.reverse	H	v=\u00DFtrasse	v:LOCATOR;w:TEXT	10	[]
CH.reverse	H	v=SSTRASSE	v:LOCATOR;w:TEXT	10	[]
CH.reverse	H		v:LOCATOR;w:TEXT	10	[]
CH.reverse	H	v=\u00A0	v:LOCATOR;w:TEXT	10	[]
CH.reverse	H	v=14;w=	v:LOCATOR;w:TEXT	10	[]
CH.reverse	H	v=m	v:LOCATOR;w:TEXT	10	[]
CH.reverse	H	v=CT	v:CQ_ZONE	10	[]
CH.reverse	H	v=5	v:CQ_ZONE	10	[W1AW]
CH.reverse	H	v= x1 	v:CQ_ZONE	10	[]
CH.reverse	H	v=28	v:CQ_ZONE	10	[]
CH.reverse	H	v=pha	v:CQ_ZONE	10	[]
CH.reverse	H	v=ex	v:CQ_ZONE	10	[VE3XX]
CH.reverse	H	v=ex	v:CQ_ZONE	1	[VE3XX]
CH.reverse	H	v=ex	v:CQ_ZONE	0	[]
CH.reverse	H	v=ex	v:CQ_ZONE	-1	[]
CH.reverse	H	v=;w=hiram	v:CQ_ZONE	10	[]
CH.reverse	H	v=ON;w=	v:CQ_ZONE	10	[]
CH.reverse	H	w=hiram	v:CQ_ZONE	10	[]
CH.reverse	H	w=hiram	v:CQ_ZONE	1	[]
CH.reverse	H	w=hiram	v:CQ_ZONE	0	[]
CH.reverse	H	w=hiram	v:CQ_ZONE	-1	[]
CH.reverse	H	v=\u00DFtrasse	v:CQ_ZONE	10	[]
CH.reverse	H	v=SSTRASSE	v:CQ_ZONE	10	[]
CH.reverse	H		v:CQ_ZONE	10	[]
CH.reverse	H	v=\u00A0	v:CQ_ZONE	10	[]
CH.reverse	H	v=14;w=	v:CQ_ZONE	10	[DL1ABC]
CH.reverse	H	v=m	v:CQ_ZONE	10	[]
CH.reverse	H	v=CT	v:CQ_ZONE;w:TEXT	10	[]
CH.reverse	H	v=5	v:CQ_ZONE;w:TEXT	10	[W1AW]
CH.reverse	H	v= x1 	v:CQ_ZONE;w:TEXT	10	[]
CH.reverse	H	v=28	v:CQ_ZONE;w:TEXT	10	[]
CH.reverse	H	v=pha	v:CQ_ZONE;w:TEXT	10	[]
CH.reverse	H	v=ex	v:CQ_ZONE;w:TEXT	10	[VE3XX]
CH.reverse	H	v=ex	v:CQ_ZONE;w:TEXT	1	[VE3XX]
CH.reverse	H	v=ex	v:CQ_ZONE;w:TEXT	0	[]
CH.reverse	H	v=ex	v:CQ_ZONE;w:TEXT	-1	[]
CH.reverse	H	v=;w=hiram	v:CQ_ZONE;w:TEXT	10	[W1AW]
CH.reverse	H	v=ON;w=	v:CQ_ZONE;w:TEXT	10	[]
CH.reverse	H	w=hiram	v:CQ_ZONE;w:TEXT	10	[W1AW]
CH.reverse	H	w=hiram	v:CQ_ZONE;w:TEXT	1	[W1AW]
CH.reverse	H	w=hiram	v:CQ_ZONE;w:TEXT	0	[]
CH.reverse	H	w=hiram	v:CQ_ZONE;w:TEXT	-1	[]
CH.reverse	H	v=\u00DFtrasse	v:CQ_ZONE;w:TEXT	10	[]
CH.reverse	H	v=SSTRASSE	v:CQ_ZONE;w:TEXT	10	[]
CH.reverse	H		v:CQ_ZONE;w:TEXT	10	[]
CH.reverse	H	v=\u00A0	v:CQ_ZONE;w:TEXT	10	[]
CH.reverse	H	v=14;w=	v:CQ_ZONE;w:TEXT	10	[DL1ABC]
CH.reverse	H	v=m	v:CQ_ZONE;w:TEXT	10	[]
CH.reverse	H	v=CT	v:ITU_ZONE	10	[]
CH.reverse	H	v=5	v:ITU_ZONE	10	[]
CH.reverse	H	v= x1 	v:ITU_ZONE	10	[]
CH.reverse	H	v=28	v:ITU_ZONE	10	[]
CH.reverse	H	v=pha	v:ITU_ZONE	10	[]
CH.reverse	H	v=ex	v:ITU_ZONE	10	[VE3XX]
CH.reverse	H	v=ex	v:ITU_ZONE	1	[VE3XX]
CH.reverse	H	v=ex	v:ITU_ZONE	0	[]
CH.reverse	H	v=ex	v:ITU_ZONE	-1	[]
CH.reverse	H	v=;w=hiram	v:ITU_ZONE	10	[]
CH.reverse	H	v=ON;w=	v:ITU_ZONE	10	[]
CH.reverse	H	w=hiram	v:ITU_ZONE	10	[]
CH.reverse	H	w=hiram	v:ITU_ZONE	1	[]
CH.reverse	H	w=hiram	v:ITU_ZONE	0	[]
CH.reverse	H	w=hiram	v:ITU_ZONE	-1	[]
CH.reverse	H	v=\u00DFtrasse	v:ITU_ZONE	10	[]
CH.reverse	H	v=SSTRASSE	v:ITU_ZONE	10	[]
CH.reverse	H		v:ITU_ZONE	10	[]
CH.reverse	H	v=\u00A0	v:ITU_ZONE	10	[]
CH.reverse	H	v=14;w=	v:ITU_ZONE	10	[DL1ABC]
CH.reverse	H	v=m	v:ITU_ZONE	10	[]
CH.reverse	H	v=CT	v:ITU_ZONE;w:TEXT	10	[]
CH.reverse	H	v=5	v:ITU_ZONE;w:TEXT	10	[]
CH.reverse	H	v= x1 	v:ITU_ZONE;w:TEXT	10	[]
CH.reverse	H	v=28	v:ITU_ZONE;w:TEXT	10	[]
CH.reverse	H	v=pha	v:ITU_ZONE;w:TEXT	10	[]
CH.reverse	H	v=ex	v:ITU_ZONE;w:TEXT	10	[VE3XX]
CH.reverse	H	v=ex	v:ITU_ZONE;w:TEXT	1	[VE3XX]
CH.reverse	H	v=ex	v:ITU_ZONE;w:TEXT	0	[]
CH.reverse	H	v=ex	v:ITU_ZONE;w:TEXT	-1	[]
CH.reverse	H	v=;w=hiram	v:ITU_ZONE;w:TEXT	10	[W1AW]
CH.reverse	H	v=ON;w=	v:ITU_ZONE;w:TEXT	10	[]
CH.reverse	H	w=hiram	v:ITU_ZONE;w:TEXT	10	[W1AW]
CH.reverse	H	w=hiram	v:ITU_ZONE;w:TEXT	1	[W1AW]
CH.reverse	H	w=hiram	v:ITU_ZONE;w:TEXT	0	[]
CH.reverse	H	w=hiram	v:ITU_ZONE;w:TEXT	-1	[]
CH.reverse	H	v=\u00DFtrasse	v:ITU_ZONE;w:TEXT	10	[]
CH.reverse	H	v=SSTRASSE	v:ITU_ZONE;w:TEXT	10	[]
CH.reverse	H		v:ITU_ZONE;w:TEXT	10	[]
CH.reverse	H	v=\u00A0	v:ITU_ZONE;w:TEXT	10	[]
CH.reverse	H	v=14;w=	v:ITU_ZONE;w:TEXT	10	[DL1ABC]
CH.reverse	H	v=m	v:ITU_ZONE;w:TEXT	10	[]
CH.reverse	H	v=CT	v:DXCC	10	[]
CH.reverse	H	v=5	v:DXCC	10	[]
CH.reverse	H	v= x1 	v:DXCC	10	[W1AW]
CH.reverse	H	v=28	v:DXCC	10	[DL1ABC]
CH.reverse	H	v=pha	v:DXCC	10	[]
CH.reverse	H	v=ex	v:DXCC	10	[VE3XX]
CH.reverse	H	v=ex	v:DXCC	1	[VE3XX]
CH.reverse	H	v=ex	v:DXCC	0	[]
CH.reverse	H	v=ex	v:DXCC	-1	[]
CH.reverse	H	v=;w=hiram	v:DXCC	10	[]
CH.reverse	H	v=ON;w=	v:DXCC	10	[]
CH.reverse	H	w=hiram	v:DXCC	10	[]
CH.reverse	H	w=hiram	v:DXCC	1	[]
CH.reverse	H	w=hiram	v:DXCC	0	[]
CH.reverse	H	w=hiram	v:DXCC	-1	[]
CH.reverse	H	v=\u00DFtrasse	v:DXCC	10	[]
CH.reverse	H	v=SSTRASSE	v:DXCC	10	[]
CH.reverse	H		v:DXCC	10	[]
CH.reverse	H	v=\u00A0	v:DXCC	10	[]
CH.reverse	H	v=14;w=	v:DXCC	10	[]
CH.reverse	H	v=m	v:DXCC	10	[]
CH.reverse	H	v=CT	v:DXCC;w:TEXT	10	[]
CH.reverse	H	v=5	v:DXCC;w:TEXT	10	[]
CH.reverse	H	v= x1 	v:DXCC;w:TEXT	10	[W1AW]
CH.reverse	H	v=28	v:DXCC;w:TEXT	10	[DL1ABC]
CH.reverse	H	v=pha	v:DXCC;w:TEXT	10	[]
CH.reverse	H	v=ex	v:DXCC;w:TEXT	10	[VE3XX]
CH.reverse	H	v=ex	v:DXCC;w:TEXT	1	[VE3XX]
CH.reverse	H	v=ex	v:DXCC;w:TEXT	0	[]
CH.reverse	H	v=ex	v:DXCC;w:TEXT	-1	[]
CH.reverse	H	v=;w=hiram	v:DXCC;w:TEXT	10	[W1AW]
CH.reverse	H	v=ON;w=	v:DXCC;w:TEXT	10	[]
CH.reverse	H	w=hiram	v:DXCC;w:TEXT	10	[W1AW]
CH.reverse	H	w=hiram	v:DXCC;w:TEXT	1	[W1AW]
CH.reverse	H	w=hiram	v:DXCC;w:TEXT	0	[]
CH.reverse	H	w=hiram	v:DXCC;w:TEXT	-1	[]
CH.reverse	H	v=\u00DFtrasse	v:DXCC;w:TEXT	10	[]
CH.reverse	H	v=SSTRASSE	v:DXCC;w:TEXT	10	[]
CH.reverse	H		v:DXCC;w:TEXT	10	[]
CH.reverse	H	v=\u00A0	v:DXCC;w:TEXT	10	[]
CH.reverse	H	v=14;w=	v:DXCC;w:TEXT	10	[]
CH.reverse	H	v=m	v:DXCC;w:TEXT	10	[]
CH.reverse	H	v=CT	v:PREFIX	10	[]
CH.reverse	H	v=5	v:PREFIX	10	[]
CH.reverse	H	v= x1 	v:PREFIX	10	[W1AW]
CH.reverse	H	v=28	v:PREFIX	10	[DL1ABC]
CH.reverse	H	v=pha	v:PREFIX	10	[]
CH.reverse	H	v=ex	v:PREFIX	10	[VE3XX]
CH.reverse	H	v=ex	v:PREFIX	1	[VE3XX]
CH.reverse	H	v=ex	v:PREFIX	0	[]
CH.reverse	H	v=ex	v:PREFIX	-1	[]
CH.reverse	H	v=;w=hiram	v:PREFIX	10	[]
CH.reverse	H	v=ON;w=	v:PREFIX	10	[]
CH.reverse	H	w=hiram	v:PREFIX	10	[]
CH.reverse	H	w=hiram	v:PREFIX	1	[]
CH.reverse	H	w=hiram	v:PREFIX	0	[]
CH.reverse	H	w=hiram	v:PREFIX	-1	[]
CH.reverse	H	v=\u00DFtrasse	v:PREFIX	10	[]
CH.reverse	H	v=SSTRASSE	v:PREFIX	10	[]
CH.reverse	H		v:PREFIX	10	[]
CH.reverse	H	v=\u00A0	v:PREFIX	10	[]
CH.reverse	H	v=14;w=	v:PREFIX	10	[]
CH.reverse	H	v=m	v:PREFIX	10	[]
CH.reverse	H	v=CT	v:PREFIX;w:TEXT	10	[]
CH.reverse	H	v=5	v:PREFIX;w:TEXT	10	[]
CH.reverse	H	v= x1 	v:PREFIX;w:TEXT	10	[W1AW]
CH.reverse	H	v=28	v:PREFIX;w:TEXT	10	[DL1ABC]
CH.reverse	H	v=pha	v:PREFIX;w:TEXT	10	[]
CH.reverse	H	v=ex	v:PREFIX;w:TEXT	10	[VE3XX]
CH.reverse	H	v=ex	v:PREFIX;w:TEXT	1	[VE3XX]
CH.reverse	H	v=ex	v:PREFIX;w:TEXT	0	[]
CH.reverse	H	v=ex	v:PREFIX;w:TEXT	-1	[]
CH.reverse	H	v=;w=hiram	v:PREFIX;w:TEXT	10	[W1AW]
CH.reverse	H	v=ON;w=	v:PREFIX;w:TEXT	10	[]
CH.reverse	H	w=hiram	v:PREFIX;w:TEXT	10	[W1AW]
CH.reverse	H	w=hiram	v:PREFIX;w:TEXT	1	[W1AW]
CH.reverse	H	w=hiram	v:PREFIX;w:TEXT	0	[]
CH.reverse	H	w=hiram	v:PREFIX;w:TEXT	-1	[]
CH.reverse	H	v=\u00DFtrasse	v:PREFIX;w:TEXT	10	[]
CH.reverse	H	v=SSTRASSE	v:PREFIX;w:TEXT	10	[]
CH.reverse	H		v:PREFIX;w:TEXT	10	[]
CH.reverse	H	v=\u00A0	v:PREFIX;w:TEXT	10	[]
CH.reverse	H	v=14;w=	v:PREFIX;w:TEXT	10	[]
CH.reverse	H	v=m	v:PREFIX;w:TEXT	10	[]
CH.reverse	H	v=CT	v:HQ	10	[]
CH.reverse	H	v=5	v:HQ	10	[]
CH.reverse	H	v= x1 	v:HQ	10	[W1AW]
CH.reverse	H	v=28	v:HQ	10	[DL1ABC]
CH.reverse	H	v=pha	v:HQ	10	[]
CH.reverse	H	v=ex	v:HQ	10	[VE3XX]
CH.reverse	H	v=ex	v:HQ	1	[VE3XX]
CH.reverse	H	v=ex	v:HQ	0	[]
CH.reverse	H	v=ex	v:HQ	-1	[]
CH.reverse	H	v=;w=hiram	v:HQ	10	[]
CH.reverse	H	v=ON;w=	v:HQ	10	[]
CH.reverse	H	w=hiram	v:HQ	10	[]
CH.reverse	H	w=hiram	v:HQ	1	[]
CH.reverse	H	w=hiram	v:HQ	0	[]
CH.reverse	H	w=hiram	v:HQ	-1	[]
CH.reverse	H	v=\u00DFtrasse	v:HQ	10	[]
CH.reverse	H	v=SSTRASSE	v:HQ	10	[]
CH.reverse	H		v:HQ	10	[]
CH.reverse	H	v=\u00A0	v:HQ	10	[]
CH.reverse	H	v=14;w=	v:HQ	10	[]
CH.reverse	H	v=m	v:HQ	10	[]
CH.reverse	H	v=CT	v:HQ;w:TEXT	10	[]
CH.reverse	H	v=5	v:HQ;w:TEXT	10	[]
CH.reverse	H	v= x1 	v:HQ;w:TEXT	10	[W1AW]
CH.reverse	H	v=28	v:HQ;w:TEXT	10	[DL1ABC]
CH.reverse	H	v=pha	v:HQ;w:TEXT	10	[]
CH.reverse	H	v=ex	v:HQ;w:TEXT	10	[VE3XX]
CH.reverse	H	v=ex	v:HQ;w:TEXT	1	[VE3XX]
CH.reverse	H	v=ex	v:HQ;w:TEXT	0	[]
CH.reverse	H	v=ex	v:HQ;w:TEXT	-1	[]
CH.reverse	H	v=;w=hiram	v:HQ;w:TEXT	10	[W1AW]
CH.reverse	H	v=ON;w=	v:HQ;w:TEXT	10	[]
CH.reverse	H	w=hiram	v:HQ;w:TEXT	10	[W1AW]
CH.reverse	H	w=hiram	v:HQ;w:TEXT	1	[W1AW]
CH.reverse	H	w=hiram	v:HQ;w:TEXT	0	[]
CH.reverse	H	w=hiram	v:HQ;w:TEXT	-1	[]
CH.reverse	H	v=\u00DFtrasse	v:HQ;w:TEXT	10	[]
CH.reverse	H	v=SSTRASSE	v:HQ;w:TEXT	10	[]
CH.reverse	H		v:HQ;w:TEXT	10	[]
CH.reverse	H	v=\u00A0	v:HQ;w:TEXT	10	[]
CH.reverse	H	v=14;w=	v:HQ;w:TEXT	10	[]
CH.reverse	H	v=m	v:HQ;w:TEXT	10	[]
CH.reverse	H	v=CT	v:NATIONAL	10	[]
CH.reverse	H	v=5	v:NATIONAL	10	[]
CH.reverse	H	v= x1 	v:NATIONAL	10	[W1AW]
CH.reverse	H	v=28	v:NATIONAL	10	[DL1ABC]
CH.reverse	H	v=pha	v:NATIONAL	10	[]
CH.reverse	H	v=ex	v:NATIONAL	10	[VE3XX]
CH.reverse	H	v=ex	v:NATIONAL	1	[VE3XX]
CH.reverse	H	v=ex	v:NATIONAL	0	[]
CH.reverse	H	v=ex	v:NATIONAL	-1	[]
CH.reverse	H	v=;w=hiram	v:NATIONAL	10	[]
CH.reverse	H	v=ON;w=	v:NATIONAL	10	[]
CH.reverse	H	w=hiram	v:NATIONAL	10	[]
CH.reverse	H	w=hiram	v:NATIONAL	1	[]
CH.reverse	H	w=hiram	v:NATIONAL	0	[]
CH.reverse	H	w=hiram	v:NATIONAL	-1	[]
CH.reverse	H	v=\u00DFtrasse	v:NATIONAL	10	[]
CH.reverse	H	v=SSTRASSE	v:NATIONAL	10	[]
CH.reverse	H		v:NATIONAL	10	[]
CH.reverse	H	v=\u00A0	v:NATIONAL	10	[]
CH.reverse	H	v=14;w=	v:NATIONAL	10	[]
CH.reverse	H	v=m	v:NATIONAL	10	[]
CH.reverse	H	v=CT	v:NATIONAL;w:TEXT	10	[]
CH.reverse	H	v=5	v:NATIONAL;w:TEXT	10	[]
CH.reverse	H	v= x1 	v:NATIONAL;w:TEXT	10	[W1AW]
CH.reverse	H	v=28	v:NATIONAL;w:TEXT	10	[DL1ABC]
CH.reverse	H	v=pha	v:NATIONAL;w:TEXT	10	[]
CH.reverse	H	v=ex	v:NATIONAL;w:TEXT	10	[VE3XX]
CH.reverse	H	v=ex	v:NATIONAL;w:TEXT	1	[VE3XX]
CH.reverse	H	v=ex	v:NATIONAL;w:TEXT	0	[]
CH.reverse	H	v=ex	v:NATIONAL;w:TEXT	-1	[]
CH.reverse	H	v=;w=hiram	v:NATIONAL;w:TEXT	10	[W1AW]
CH.reverse	H	v=ON;w=	v:NATIONAL;w:TEXT	10	[]
CH.reverse	H	w=hiram	v:NATIONAL;w:TEXT	10	[W1AW]
CH.reverse	H	w=hiram	v:NATIONAL;w:TEXT	1	[W1AW]
CH.reverse	H	w=hiram	v:NATIONAL;w:TEXT	0	[]
CH.reverse	H	w=hiram	v:NATIONAL;w:TEXT	-1	[]
CH.reverse	H	v=\u00DFtrasse	v:NATIONAL;w:TEXT	10	[]
CH.reverse	H	v=SSTRASSE	v:NATIONAL;w:TEXT	10	[]
CH.reverse	H		v:NATIONAL;w:TEXT	10	[]
CH.reverse	H	v=\u00A0	v:NATIONAL;w:TEXT	10	[]
CH.reverse	H	v=14;w=	v:NATIONAL;w:TEXT	10	[]
CH.reverse	H	v=m	v:NATIONAL;w:TEXT	10	[]
CH.reverse	H	v=CT	v:STATE	10	[W1AW]
CH.reverse	H	v=5	v:STATE	10	[]
CH.reverse	H	v= x1 	v:STATE	10	[]
CH.reverse	H	v=28	v:STATE	10	[DL1ABC]
CH.reverse	H	v=pha	v:STATE	10	[]
CH.reverse	H	v=ex	v:STATE	10	[]
CH.reverse	H	v=ex	v:STATE	1	[]
CH.reverse	H	v=ex	v:STATE	0	[]
CH.reverse	H	v=ex	v:STATE	-1	[]
CH.reverse	H	v=;w=hiram	v:STATE	10	[]
CH.reverse	H	v=ON;w=	v:STATE	10	[VE3XX]
CH.reverse	H	w=hiram	v:STATE	10	[]
CH.reverse	H	w=hiram	v:STATE	1	[]
CH.reverse	H	w=hiram	v:STATE	0	[]
CH.reverse	H	w=hiram	v:STATE	-1	[]
CH.reverse	H	v=\u00DFtrasse	v:STATE	10	[]
CH.reverse	H	v=SSTRASSE	v:STATE	10	[]
CH.reverse	H		v:STATE	10	[]
CH.reverse	H	v=\u00A0	v:STATE	10	[]
CH.reverse	H	v=14;w=	v:STATE	10	[]
CH.reverse	H	v=m	v:STATE	10	[]
CH.reverse	H	v=CT	v:STATE;w:TEXT	10	[W1AW]
CH.reverse	H	v=5	v:STATE;w:TEXT	10	[]
CH.reverse	H	v= x1 	v:STATE;w:TEXT	10	[]
CH.reverse	H	v=28	v:STATE;w:TEXT	10	[DL1ABC]
CH.reverse	H	v=pha	v:STATE;w:TEXT	10	[]
CH.reverse	H	v=ex	v:STATE;w:TEXT	10	[]
CH.reverse	H	v=ex	v:STATE;w:TEXT	1	[]
CH.reverse	H	v=ex	v:STATE;w:TEXT	0	[]
CH.reverse	H	v=ex	v:STATE;w:TEXT	-1	[]
CH.reverse	H	v=;w=hiram	v:STATE;w:TEXT	10	[W1AW]
CH.reverse	H	v=ON;w=	v:STATE;w:TEXT	10	[VE3XX]
CH.reverse	H	w=hiram	v:STATE;w:TEXT	10	[W1AW]
CH.reverse	H	w=hiram	v:STATE;w:TEXT	1	[W1AW]
CH.reverse	H	w=hiram	v:STATE;w:TEXT	0	[]
CH.reverse	H	w=hiram	v:STATE;w:TEXT	-1	[]
CH.reverse	H	v=\u00DFtrasse	v:STATE;w:TEXT	10	[]
CH.reverse	H	v=SSTRASSE	v:STATE;w:TEXT	10	[]
CH.reverse	H		v:STATE;w:TEXT	10	[]
CH.reverse	H	v=\u00A0	v:STATE;w:TEXT	10	[]
CH.reverse	H	v=14;w=	v:STATE;w:TEXT	10	[]
CH.reverse	H	v=m	v:STATE;w:TEXT	10	[]
CH.reverse	H	v=CT	v:PROVINCE	10	[W1AW]
CH.reverse	H	v=5	v:PROVINCE	10	[]
CH.reverse	H	v= x1 	v:PROVINCE	10	[]
CH.reverse	H	v=28	v:PROVINCE	10	[DL1ABC]
CH.reverse	H	v=pha	v:PROVINCE	10	[]
CH.reverse	H	v=ex	v:PROVINCE	10	[]
CH.reverse	H	v=ex	v:PROVINCE	1	[]
CH.reverse	H	v=ex	v:PROVINCE	0	[]
CH.reverse	H	v=ex	v:PROVINCE	-1	[]
CH.reverse	H	v=;w=hiram	v:PROVINCE	10	[]
CH.reverse	H	v=ON;w=	v:PROVINCE	10	[VE3XX]
CH.reverse	H	w=hiram	v:PROVINCE	10	[]
CH.reverse	H	w=hiram	v:PROVINCE	1	[]
CH.reverse	H	w=hiram	v:PROVINCE	0	[]
CH.reverse	H	w=hiram	v:PROVINCE	-1	[]
CH.reverse	H	v=\u00DFtrasse	v:PROVINCE	10	[]
CH.reverse	H	v=SSTRASSE	v:PROVINCE	10	[]
CH.reverse	H		v:PROVINCE	10	[]
CH.reverse	H	v=\u00A0	v:PROVINCE	10	[]
CH.reverse	H	v=14;w=	v:PROVINCE	10	[]
CH.reverse	H	v=m	v:PROVINCE	10	[]
CH.reverse	H	v=CT	v:PROVINCE;w:TEXT	10	[W1AW]
CH.reverse	H	v=5	v:PROVINCE;w:TEXT	10	[]
CH.reverse	H	v= x1 	v:PROVINCE;w:TEXT	10	[]
CH.reverse	H	v=28	v:PROVINCE;w:TEXT	10	[DL1ABC]
CH.reverse	H	v=pha	v:PROVINCE;w:TEXT	10	[]
CH.reverse	H	v=ex	v:PROVINCE;w:TEXT	10	[]
CH.reverse	H	v=ex	v:PROVINCE;w:TEXT	1	[]
CH.reverse	H	v=ex	v:PROVINCE;w:TEXT	0	[]
CH.reverse	H	v=ex	v:PROVINCE;w:TEXT	-1	[]
CH.reverse	H	v=;w=hiram	v:PROVINCE;w:TEXT	10	[W1AW]
CH.reverse	H	v=ON;w=	v:PROVINCE;w:TEXT	10	[VE3XX]
CH.reverse	H	w=hiram	v:PROVINCE;w:TEXT	10	[W1AW]
CH.reverse	H	w=hiram	v:PROVINCE;w:TEXT	1	[W1AW]
CH.reverse	H	w=hiram	v:PROVINCE;w:TEXT	0	[]
CH.reverse	H	w=hiram	v:PROVINCE;w:TEXT	-1	[]
CH.reverse	H	v=\u00DFtrasse	v:PROVINCE;w:TEXT	10	[]
CH.reverse	H	v=SSTRASSE	v:PROVINCE;w:TEXT	10	[]
CH.reverse	H		v:PROVINCE;w:TEXT	10	[]
CH.reverse	H	v=\u00A0	v:PROVINCE;w:TEXT	10	[]
CH.reverse	H	v=14;w=	v:PROVINCE;w:TEXT	10	[]
CH.reverse	H	v=m	v:PROVINCE;w:TEXT	10	[]
CH.reverse	H	v=CT	v:DISTRICT	10	[]
CH.reverse	H	v=5	v:DISTRICT	10	[]
CH.reverse	H	v= x1 	v:DISTRICT	10	[W1AW]
CH.reverse	H	v=28	v:DISTRICT	10	[]
CH.reverse	H	v=pha	v:DISTRICT	10	[OK1XOE]
CH.reverse	H	v=ex	v:DISTRICT	10	[VE3XX]
CH.reverse	H	v=ex	v:DISTRICT	1	[VE3XX]
CH.reverse	H	v=ex	v:DISTRICT	0	[]
CH.reverse	H	v=ex	v:DISTRICT	-1	[]
CH.reverse	H	v=;w=hiram	v:DISTRICT	10	[]
CH.reverse	H	v=ON;w=	v:DISTRICT	10	[]
CH.reverse	H	w=hiram	v:DISTRICT	10	[]
CH.reverse	H	w=hiram	v:DISTRICT	1	[]
CH.reverse	H	w=hiram	v:DISTRICT	0	[]
CH.reverse	H	w=hiram	v:DISTRICT	-1	[]
CH.reverse	H	v=\u00DFtrasse	v:DISTRICT	10	[]
CH.reverse	H	v=SSTRASSE	v:DISTRICT	10	[]
CH.reverse	H		v:DISTRICT	10	[]
CH.reverse	H	v=\u00A0	v:DISTRICT	10	[]
CH.reverse	H	v=14;w=	v:DISTRICT	10	[]
CH.reverse	H	v=m	v:DISTRICT	10	[]
CH.reverse	H	v=CT	v:DISTRICT;w:TEXT	10	[]
CH.reverse	H	v=5	v:DISTRICT;w:TEXT	10	[]
CH.reverse	H	v= x1 	v:DISTRICT;w:TEXT	10	[W1AW]
CH.reverse	H	v=28	v:DISTRICT;w:TEXT	10	[]
CH.reverse	H	v=pha	v:DISTRICT;w:TEXT	10	[OK1XOE]
CH.reverse	H	v=ex	v:DISTRICT;w:TEXT	10	[VE3XX]
CH.reverse	H	v=ex	v:DISTRICT;w:TEXT	1	[VE3XX]
CH.reverse	H	v=ex	v:DISTRICT;w:TEXT	0	[]
CH.reverse	H	v=ex	v:DISTRICT;w:TEXT	-1	[]
CH.reverse	H	v=;w=hiram	v:DISTRICT;w:TEXT	10	[W1AW]
CH.reverse	H	v=ON;w=	v:DISTRICT;w:TEXT	10	[]
CH.reverse	H	w=hiram	v:DISTRICT;w:TEXT	10	[W1AW]
CH.reverse	H	w=hiram	v:DISTRICT;w:TEXT	1	[W1AW]
CH.reverse	H	w=hiram	v:DISTRICT;w:TEXT	0	[]
CH.reverse	H	w=hiram	v:DISTRICT;w:TEXT	-1	[]
CH.reverse	H	v=\u00DFtrasse	v:DISTRICT;w:TEXT	10	[]
CH.reverse	H	v=SSTRASSE	v:DISTRICT;w:TEXT	10	[]
CH.reverse	H		v:DISTRICT;w:TEXT	10	[]
CH.reverse	H	v=\u00A0	v:DISTRICT;w:TEXT	10	[]
CH.reverse	H	v=14;w=	v:DISTRICT;w:TEXT	10	[]
CH.reverse	H	v=m	v:DISTRICT;w:TEXT	10	[]
CH.reverse	H	v=CT	v:IOTA	10	[]
CH.reverse	H	v=5	v:IOTA	10	[]
CH.reverse	H	v= x1 	v:IOTA	10	[]
CH.reverse	H	v=28	v:IOTA	10	[DL1ABC]
CH.reverse	H	v=pha	v:IOTA	10	[]
CH.reverse	H	v=ex	v:IOTA	10	[VE3XX]
CH.reverse	H	v=ex	v:IOTA	1	[VE3XX]
CH.reverse	H	v=ex	v:IOTA	0	[]
CH.reverse	H	v=ex	v:IOTA	-1	[]
CH.reverse	H	v=;w=hiram	v:IOTA	10	[]
CH.reverse	H	v=ON;w=	v:IOTA	10	[]
CH.reverse	H	w=hiram	v:IOTA	10	[]
CH.reverse	H	w=hiram	v:IOTA	1	[]
CH.reverse	H	w=hiram	v:IOTA	0	[]
CH.reverse	H	w=hiram	v:IOTA	-1	[]
CH.reverse	H	v=\u00DFtrasse	v:IOTA	10	[]
CH.reverse	H	v=SSTRASSE	v:IOTA	10	[]
CH.reverse	H		v:IOTA	10	[]
CH.reverse	H	v=\u00A0	v:IOTA	10	[]
CH.reverse	H	v=14;w=	v:IOTA	10	[]
CH.reverse	H	v=m	v:IOTA	10	[]
CH.reverse	H	v=CT	v:IOTA;w:TEXT	10	[]
CH.reverse	H	v=5	v:IOTA;w:TEXT	10	[]
CH.reverse	H	v= x1 	v:IOTA;w:TEXT	10	[]
CH.reverse	H	v=28	v:IOTA;w:TEXT	10	[DL1ABC]
CH.reverse	H	v=pha	v:IOTA;w:TEXT	10	[]
CH.reverse	H	v=ex	v:IOTA;w:TEXT	10	[VE3XX]
CH.reverse	H	v=ex	v:IOTA;w:TEXT	1	[VE3XX]
CH.reverse	H	v=ex	v:IOTA;w:TEXT	0	[]
CH.reverse	H	v=ex	v:IOTA;w:TEXT	-1	[]
CH.reverse	H	v=;w=hiram	v:IOTA;w:TEXT	10	[W1AW]
CH.reverse	H	v=ON;w=	v:IOTA;w:TEXT	10	[]
CH.reverse	H	w=hiram	v:IOTA;w:TEXT	10	[W1AW]
CH.reverse	H	w=hiram	v:IOTA;w:TEXT	1	[W1AW]
CH.reverse	H	w=hiram	v:IOTA;w:TEXT	0	[]
CH.reverse	H	w=hiram	v:IOTA;w:TEXT	-1	[]
CH.reverse	H	v=\u00DFtrasse	v:IOTA;w:TEXT	10	[]
CH.reverse	H	v=SSTRASSE	v:IOTA;w:TEXT	10	[]
CH.reverse	H		v:IOTA;w:TEXT	10	[]
CH.reverse	H	v=\u00A0	v:IOTA;w:TEXT	10	[]
CH.reverse	H	v=14;w=	v:IOTA;w:TEXT	10	[]
CH.reverse	H	v=m	v:IOTA;w:TEXT	10	[]
CH.reverse	H	v=CT	v:QTC	10	[]
CH.reverse	H	v=5	v:QTC	10	[]
CH.reverse	H	v= x1 	v:QTC	10	[W1AW]
CH.reverse	H	v=28	v:QTC	10	[DL1ABC]
CH.reverse	H	v=pha	v:QTC	10	[]
CH.reverse	H	v=ex	v:QTC	10	[VE3XX]
CH.reverse	H	v=ex	v:QTC	1	[VE3XX]
CH.reverse	H	v=ex	v:QTC	0	[]
CH.reverse	H	v=ex	v:QTC	-1	[]
CH.reverse	H	v=;w=hiram	v:QTC	10	[]
CH.reverse	H	v=ON;w=	v:QTC	10	[]
CH.reverse	H	w=hiram	v:QTC	10	[]
CH.reverse	H	w=hiram	v:QTC	1	[]
CH.reverse	H	w=hiram	v:QTC	0	[]
CH.reverse	H	w=hiram	v:QTC	-1	[]
CH.reverse	H	v=\u00DFtrasse	v:QTC	10	[]
CH.reverse	H	v=SSTRASSE	v:QTC	10	[]
CH.reverse	H		v:QTC	10	[]
CH.reverse	H	v=\u00A0	v:QTC	10	[]
CH.reverse	H	v=14;w=	v:QTC	10	[]
CH.reverse	H	v=m	v:QTC	10	[]
CH.reverse	H	v=CT	v:QTC;w:TEXT	10	[]
CH.reverse	H	v=5	v:QTC;w:TEXT	10	[]
CH.reverse	H	v= x1 	v:QTC;w:TEXT	10	[W1AW]
CH.reverse	H	v=28	v:QTC;w:TEXT	10	[DL1ABC]
CH.reverse	H	v=pha	v:QTC;w:TEXT	10	[]
CH.reverse	H	v=ex	v:QTC;w:TEXT	10	[VE3XX]
CH.reverse	H	v=ex	v:QTC;w:TEXT	1	[VE3XX]
CH.reverse	H	v=ex	v:QTC;w:TEXT	0	[]
CH.reverse	H	v=ex	v:QTC;w:TEXT	-1	[]
CH.reverse	H	v=;w=hiram	v:QTC;w:TEXT	10	[W1AW]
CH.reverse	H	v=ON;w=	v:QTC;w:TEXT	10	[]
CH.reverse	H	w=hiram	v:QTC;w:TEXT	10	[W1AW]
CH.reverse	H	w=hiram	v:QTC;w:TEXT	1	[W1AW]
CH.reverse	H	w=hiram	v:QTC;w:TEXT	0	[]
CH.reverse	H	w=hiram	v:QTC;w:TEXT	-1	[]
CH.reverse	H	v=\u00DFtrasse	v:QTC;w:TEXT	10	[]
CH.reverse	H	v=SSTRASSE	v:QTC;w:TEXT	10	[]
CH.reverse	H		v:QTC;w:TEXT	10	[]
CH.reverse	H	v=\u00A0	v:QTC;w:TEXT	10	[]
CH.reverse	H	v=14;w=	v:QTC;w:TEXT	10	[]
CH.reverse	H	v=m	v:QTC;w:TEXT	10	[]
CH.reverse	H	v=CT	v:null	10	[]
CH.reverse	H	v=5	v:null	10	[]
CH.reverse	H	v= x1 	v:null	10	[W1AW]
CH.reverse	H	v=28	v:null	10	[DL1ABC]
CH.reverse	H	v=pha	v:null	10	[]
CH.reverse	H	v=ex	v:null	10	[VE3XX]
CH.reverse	H	v=ex	v:null	1	[VE3XX]
CH.reverse	H	v=ex	v:null	0	[]
CH.reverse	H	v=ex	v:null	-1	[]
CH.reverse	H	v=;w=hiram	v:null	10	[]
CH.reverse	H	v=ON;w=	v:null	10	[]
CH.reverse	H	w=hiram	v:null	10	[]
CH.reverse	H	w=hiram	v:null	1	[]
CH.reverse	H	w=hiram	v:null	0	[]
CH.reverse	H	w=hiram	v:null	-1	[]
CH.reverse	H	v=\u00DFtrasse	v:null	10	[]
CH.reverse	H	v=SSTRASSE	v:null	10	[]
CH.reverse	H		v:null	10	[]
CH.reverse	H	v=\u00A0	v:null	10	[]
CH.reverse	H	v=14;w=	v:null	10	[]
CH.reverse	H	v=m	v:null	10	[]
CH.reverse	H	v=CT	v:null;w:TEXT	10	[]
CH.reverse	H	v=5	v:null;w:TEXT	10	[]
CH.reverse	H	v= x1 	v:null;w:TEXT	10	[]
CH.reverse	H	v=28	v:null;w:TEXT	10	[]
CH.reverse	H	v=pha	v:null;w:TEXT	10	[]
CH.reverse	H	v=ex	v:null;w:TEXT	10	[]
CH.reverse	H	v=ex	v:null;w:TEXT	1	[]
CH.reverse	H	v=ex	v:null;w:TEXT	0	[]
CH.reverse	H	v=ex	v:null;w:TEXT	-1	[]
CH.reverse	H	v=;w=hiram	v:null;w:TEXT	10	[W1AW]
CH.reverse	H	v=ON;w=	v:null;w:TEXT	10	[]
CH.reverse	H	w=hiram	v:null;w:TEXT	10	[W1AW]
CH.reverse	H	w=hiram	v:null;w:TEXT	1	[W1AW]
CH.reverse	H	w=hiram	v:null;w:TEXT	0	[]
CH.reverse	H	w=hiram	v:null;w:TEXT	-1	[]
CH.reverse	H	v=\u00DFtrasse	v:null;w:TEXT	10	[]
CH.reverse	H	v=SSTRASSE	v:null;w:TEXT	10	[]
CH.reverse	H		v:null;w:TEXT	10	[]
CH.reverse	H	v=\u00A0	v:null;w:TEXT	10	[]
CH.reverse	H	v=14;w=	v:null;w:TEXT	10	[]
CH.reverse	H	v=m	v:null;w:TEXT	10	[]
CH.reverse	H	v=CT	Name:TEXT;STATE:CQ_ZONE	10	[]
CH.reverse	H	v=5	Name:TEXT;STATE:CQ_ZONE	10	[]
CH.reverse	H	v= x1 	Name:TEXT;STATE:CQ_ZONE	10	[]
CH.reverse	H	v=28	Name:TEXT;STATE:CQ_ZONE	10	[]
CH.reverse	H	v=pha	Name:TEXT;STATE:CQ_ZONE	10	[]
CH.reverse	H	v=ex	Name:TEXT;STATE:CQ_ZONE	10	[]
CH.reverse	H	v=ex	Name:TEXT;STATE:CQ_ZONE	1	[]
CH.reverse	H	v=ex	Name:TEXT;STATE:CQ_ZONE	0	[]
CH.reverse	H	v=ex	Name:TEXT;STATE:CQ_ZONE	-1	[]
CH.reverse	H	v=;w=hiram	Name:TEXT;STATE:CQ_ZONE	10	[]
CH.reverse	H	v=ON;w=	Name:TEXT;STATE:CQ_ZONE	10	[]
CH.reverse	H	w=hiram	Name:TEXT;STATE:CQ_ZONE	10	[]
CH.reverse	H	w=hiram	Name:TEXT;STATE:CQ_ZONE	1	[]
CH.reverse	H	w=hiram	Name:TEXT;STATE:CQ_ZONE	0	[]
CH.reverse	H	w=hiram	Name:TEXT;STATE:CQ_ZONE	-1	[]
CH.reverse	H	v=\u00DFtrasse	Name:TEXT;STATE:CQ_ZONE	10	[]
CH.reverse	H	v=SSTRASSE	Name:TEXT;STATE:CQ_ZONE	10	[]
CH.reverse	H		Name:TEXT;STATE:CQ_ZONE	10	[]
CH.reverse	H	v=\u00A0	Name:TEXT;STATE:CQ_ZONE	10	[]
CH.reverse	H	v=14;w=	Name:TEXT;STATE:CQ_ZONE	10	[]
CH.reverse	H	v=m	Name:TEXT;STATE:CQ_ZONE	10	[]
CH.reverse	H	v=CT	misc:INTEGER	10	[]
CH.reverse	H	v=5	misc:INTEGER	10	[]
CH.reverse	H	v= x1 	misc:INTEGER	10	[]
CH.reverse	H	v=28	misc:INTEGER	10	[]
CH.reverse	H	v=pha	misc:INTEGER	10	[]
CH.reverse	H	v=ex	misc:INTEGER	10	[]
CH.reverse	H	v=ex	misc:INTEGER	1	[]
CH.reverse	H	v=ex	misc:INTEGER	0	[]
CH.reverse	H	v=ex	misc:INTEGER	-1	[]
CH.reverse	H	v=;w=hiram	misc:INTEGER	10	[]
CH.reverse	H	v=ON;w=	misc:INTEGER	10	[]
CH.reverse	H	w=hiram	misc:INTEGER	10	[]
CH.reverse	H	w=hiram	misc:INTEGER	1	[]
CH.reverse	H	w=hiram	misc:INTEGER	0	[]
CH.reverse	H	w=hiram	misc:INTEGER	-1	[]
CH.reverse	H	v=\u00DFtrasse	misc:INTEGER	10	[]
CH.reverse	H	v=SSTRASSE	misc:INTEGER	10	[]
CH.reverse	H		misc:INTEGER	10	[]
CH.reverse	H	v=\u00A0	misc:INTEGER	10	[]
CH.reverse	H	v=14;w=	misc:INTEGER	10	[]
CH.reverse	H	v=m	misc:INTEGER	10	[]
CH.reverse	H	v=CT	rst:RST;nr:SERIAL;p:INTEGER	10	[]
CH.reverse	H	v=5	rst:RST;nr:SERIAL;p:INTEGER	10	[]
CH.reverse	H	v= x1 	rst:RST;nr:SERIAL;p:INTEGER	10	[]
CH.reverse	H	v=28	rst:RST;nr:SERIAL;p:INTEGER	10	[]
CH.reverse	H	v=pha	rst:RST;nr:SERIAL;p:INTEGER	10	[]
CH.reverse	H	v=ex	rst:RST;nr:SERIAL;p:INTEGER	10	[]
CH.reverse	H	v=ex	rst:RST;nr:SERIAL;p:INTEGER	1	[]
CH.reverse	H	v=ex	rst:RST;nr:SERIAL;p:INTEGER	0	[]
CH.reverse	H	v=ex	rst:RST;nr:SERIAL;p:INTEGER	-1	[]
CH.reverse	H	v=;w=hiram	rst:RST;nr:SERIAL;p:INTEGER	10	[]
CH.reverse	H	v=ON;w=	rst:RST;nr:SERIAL;p:INTEGER	10	[]
CH.reverse	H	w=hiram	rst:RST;nr:SERIAL;p:INTEGER	10	[]
CH.reverse	H	w=hiram	rst:RST;nr:SERIAL;p:INTEGER	1	[]
CH.reverse	H	w=hiram	rst:RST;nr:SERIAL;p:INTEGER	0	[]
CH.reverse	H	w=hiram	rst:RST;nr:SERIAL;p:INTEGER	-1	[]
CH.reverse	H	v=\u00DFtrasse	rst:RST;nr:SERIAL;p:INTEGER	10	[]
CH.reverse	H	v=SSTRASSE	rst:RST;nr:SERIAL;p:INTEGER	10	[]
CH.reverse	H		rst:RST;nr:SERIAL;p:INTEGER	10	[]
CH.reverse	H	v=\u00A0	rst:RST;nr:SERIAL;p:INTEGER	10	[]
CH.reverse	H	v=14;w=	rst:RST;nr:SERIAL;p:INTEGER	10	[]
CH.reverse	H	v=m	rst:RST;nr:SERIAL;p:INTEGER	10	[]
CH.reverse	H	v=CT	rst:RST;zone:CQ_ZONE	10	[]
CH.reverse	H	v=5	rst:RST;zone:CQ_ZONE	10	[]
CH.reverse	H	v= x1 	rst:RST;zone:CQ_ZONE	10	[]
CH.reverse	H	v=28	rst:RST;zone:CQ_ZONE	10	[]
CH.reverse	H	v=pha	rst:RST;zone:CQ_ZONE	10	[]
CH.reverse	H	v=ex	rst:RST;zone:CQ_ZONE	10	[]
CH.reverse	H	v=ex	rst:RST;zone:CQ_ZONE	1	[]
CH.reverse	H	v=ex	rst:RST;zone:CQ_ZONE	0	[]
CH.reverse	H	v=ex	rst:RST;zone:CQ_ZONE	-1	[]
CH.reverse	H	v=;w=hiram	rst:RST;zone:CQ_ZONE	10	[]
CH.reverse	H	v=ON;w=	rst:RST;zone:CQ_ZONE	10	[]
CH.reverse	H	w=hiram	rst:RST;zone:CQ_ZONE	10	[]
CH.reverse	H	w=hiram	rst:RST;zone:CQ_ZONE	1	[]
CH.reverse	H	w=hiram	rst:RST;zone:CQ_ZONE	0	[]
CH.reverse	H	w=hiram	rst:RST;zone:CQ_ZONE	-1	[]
CH.reverse	H	v=\u00DFtrasse	rst:RST;zone:CQ_ZONE	10	[]
CH.reverse	H	v=SSTRASSE	rst:RST;zone:CQ_ZONE	10	[]
CH.reverse	H		rst:RST;zone:CQ_ZONE	10	[]
CH.reverse	H	v=\u00A0	rst:RST;zone:CQ_ZONE	10	[]
CH.reverse	H	v=14;w=	rst:RST;zone:CQ_ZONE	10	[]
CH.reverse	H	v=m	rst:RST;zone:CQ_ZONE	10	[]
CH.reverse	H	v=CT	rst:RST	10	[]
CH.reverse	H	v=5	rst:RST	10	[]
CH.reverse	H	v= x1 	rst:RST	10	[]
CH.reverse	H	v=28	rst:RST	10	[]
CH.reverse	H	v=pha	rst:RST	10	[]
CH.reverse	H	v=ex	rst:RST	10	[]
CH.reverse	H	v=ex	rst:RST	1	[]
CH.reverse	H	v=ex	rst:RST	0	[]
CH.reverse	H	v=ex	rst:RST	-1	[]
CH.reverse	H	v=;w=hiram	rst:RST	10	[]
CH.reverse	H	v=ON;w=	rst:RST	10	[]
CH.reverse	H	w=hiram	rst:RST	10	[]
CH.reverse	H	w=hiram	rst:RST	1	[]
CH.reverse	H	w=hiram	rst:RST	0	[]
CH.reverse	H	w=hiram	rst:RST	-1	[]
CH.reverse	H	v=\u00DFtrasse	rst:RST	10	[]
CH.reverse	H	v=SSTRASSE	rst:RST	10	[]
CH.reverse	H		rst:RST	10	[]
CH.reverse	H	v=\u00A0	rst:RST	10	[]
CH.reverse	H	v=14;w=	rst:RST	10	[]
CH.reverse	H	v=m	rst:RST	10	[]
CH.reverse	H	w=hiram	<null>	10	[]
CH.history	H0	!!Order!!,Call,Name,State,Sect,CQZone,Zone,ITUZone,Loc1,Grid,District,Loc2,IOTA,Exch1,Misc||W1AW,hiram,ct,,5,,8,fn31,,,,NA-001,x1,m||DL1ABC,,,,,14,,,jo62,,dok,,28,||OK1XOE,\u00DFtrasse,,boh,,,,,,PHA,,,,||VE3XX,,,ON,,,,,,,,,ex,
CH.columnFor	H0	v:RST	v
CH.columnFor	H0	Name:RST	name
CH.columnFor	H0	v:RS	v
CH.columnFor	H0	Name:RS	name
CH.columnFor	H0	v:SERIAL	v
CH.columnFor	H0	Name:SERIAL	name
CH.columnFor	H0	v:INTEGER	v
CH.columnFor	H0	Name:INTEGER	name
CH.columnFor	H0	v:TEXT	name
CH.columnFor	H0	Name:TEXT	name
CH.columnFor	H0	v:LOCATOR	loc1
CH.columnFor	H0	Name:LOCATOR	name
CH.columnFor	H0	v:CQ_ZONE	cqzone
CH.columnFor	H0	Name:CQ_ZONE	name
CH.columnFor	H0	v:ITU_ZONE	ituzone
CH.columnFor	H0	Name:ITU_ZONE	name
CH.columnFor	H0	v:DXCC	v
CH.columnFor	H0	Name:DXCC	name
CH.columnFor	H0	v:PREFIX	v
CH.columnFor	H0	Name:PREFIX	name
CH.columnFor	H0	v:HQ	v
CH.columnFor	H0	Name:HQ	name
CH.columnFor	H0	v:NATIONAL	v
CH.columnFor	H0	Name:NATIONAL	name
CH.columnFor	H0	v:STATE	state
CH.columnFor	H0	Name:STATE	name
CH.columnFor	H0	v:PROVINCE	state
CH.columnFor	H0	Name:PROVINCE	name
CH.columnFor	H0	v:DISTRICT	district
CH.columnFor	H0	Name:DISTRICT	name
CH.columnFor	H0	v:IOTA	iota
CH.columnFor	H0	Name:IOTA	name
CH.columnFor	H0	v:QTC	v
CH.columnFor	H0	Name:QTC	name
CH.columnFor	H0	Zone:null	zone
CH.history	H1	!!Order!!,Call,Name
CH.columnFor	H1	v:RST	v
CH.columnFor	H1	Name:RST	name
CH.columnFor	H1	v:RS	v
CH.columnFor	H1	Name:RS	name
CH.columnFor	H1	v:SERIAL	v
CH.columnFor	H1	Name:SERIAL	name
CH.columnFor	H1	v:INTEGER	v
CH.columnFor	H1	Name:INTEGER	name
CH.columnFor	H1	v:TEXT	name
CH.columnFor	H1	Name:TEXT	name
CH.columnFor	H1	v:LOCATOR	loc1
CH.columnFor	H1	Name:LOCATOR	name
CH.columnFor	H1	v:CQ_ZONE	cqzone
CH.columnFor	H1	Name:CQ_ZONE	name
CH.columnFor	H1	v:ITU_ZONE	ituzone
CH.columnFor	H1	Name:ITU_ZONE	name
CH.columnFor	H1	v:DXCC	v
CH.columnFor	H1	Name:DXCC	name
CH.columnFor	H1	v:PREFIX	v
CH.columnFor	H1	Name:PREFIX	name
CH.columnFor	H1	v:HQ	v
CH.columnFor	H1	Name:HQ	name
CH.columnFor	H1	v:NATIONAL	v
CH.columnFor	H1	Name:NATIONAL	name
CH.columnFor	H1	v:STATE	state
CH.columnFor	H1	Name:STATE	name
CH.columnFor	H1	v:PROVINCE	state
CH.columnFor	H1	Name:PROVINCE	name
CH.columnFor	H1	v:DISTRICT	district
CH.columnFor	H1	Name:DISTRICT	name
CH.columnFor	H1	v:IOTA	iota
CH.columnFor	H1	Name:IOTA	name
CH.columnFor	H1	v:QTC	v
CH.columnFor	H1	Name:QTC	name
CH.columnFor	H1	Zone:null	zone
CH.history	H2	
CH.columnFor	H2	v:RST	v
CH.columnFor	H2	Name:RST	name
CH.columnFor	H2	v:RS	v
CH.columnFor	H2	Name:RS	name
CH.columnFor	H2	v:SERIAL	v
CH.columnFor	H2	Name:SERIAL	name
CH.columnFor	H2	v:INTEGER	v
CH.columnFor	H2	Name:INTEGER	name
CH.columnFor	H2	v:TEXT	name
CH.columnFor	H2	Name:TEXT	name
CH.columnFor	H2	v:LOCATOR	loc1
CH.columnFor	H2	Name:LOCATOR	name
CH.columnFor	H2	v:CQ_ZONE	cqzone
CH.columnFor	H2	Name:CQ_ZONE	name
CH.columnFor	H2	v:ITU_ZONE	ituzone
CH.columnFor	H2	Name:ITU_ZONE	name
CH.columnFor	H2	v:DXCC	v
CH.columnFor	H2	Name:DXCC	name
CH.columnFor	H2	v:PREFIX	v
CH.columnFor	H2	Name:PREFIX	name
CH.columnFor	H2	v:HQ	v
CH.columnFor	H2	Name:HQ	name
CH.columnFor	H2	v:NATIONAL	v
CH.columnFor	H2	Name:NATIONAL	name
CH.columnFor	H2	v:STATE	state
CH.columnFor	H2	Name:STATE	name
CH.columnFor	H2	v:PROVINCE	state
CH.columnFor	H2	Name:PROVINCE	name
CH.columnFor	H2	v:DISTRICT	district
CH.columnFor	H2	Name:DISTRICT	name
CH.columnFor	H2	v:IOTA	iota
CH.columnFor	H2	Name:IOTA	name
CH.columnFor	H2	v:QTC	v
CH.columnFor	H2	Name:QTC	name
CH.columnFor	H2	Zone:null	zone
CH.history	H3	!!Order!!,Call,Zone,Exch1
CH.columnFor	H3	v:RST	v
CH.columnFor	H3	Name:RST	name
CH.columnFor	H3	v:RS	v
CH.columnFor	H3	Name:RS	name
CH.columnFor	H3	v:SERIAL	v
CH.columnFor	H3	Name:SERIAL	name
CH.columnFor	H3	v:INTEGER	v
CH.columnFor	H3	Name:INTEGER	name
CH.columnFor	H3	v:TEXT	name
CH.columnFor	H3	Name:TEXT	name
CH.columnFor	H3	v:LOCATOR	loc1
CH.columnFor	H3	Name:LOCATOR	loc1
CH.columnFor	H3	v:CQ_ZONE	cqzone
CH.columnFor	H3	Name:CQ_ZONE	cqzone
CH.columnFor	H3	v:ITU_ZONE	ituzone
CH.columnFor	H3	Name:ITU_ZONE	ituzone
CH.columnFor	H3	v:DXCC	v
CH.columnFor	H3	Name:DXCC	name
CH.columnFor	H3	v:PREFIX	v
CH.columnFor	H3	Name:PREFIX	name
CH.columnFor	H3	v:HQ	v
CH.columnFor	H3	Name:HQ	name
CH.columnFor	H3	v:NATIONAL	v
CH.columnFor	H3	Name:NATIONAL	name
CH.columnFor	H3	v:STATE	state
CH.columnFor	H3	Name:STATE	state
CH.columnFor	H3	v:PROVINCE	state
CH.columnFor	H3	Name:PROVINCE	state
CH.columnFor	H3	v:DISTRICT	district
CH.columnFor	H3	Name:DISTRICT	district
CH.columnFor	H3	v:IOTA	iota
CH.columnFor	H3	Name:IOTA	iota
CH.columnFor	H3	v:QTC	v
CH.columnFor	H3	Name:QTC	name
CH.columnFor	H3	Zone:null	zone
CH.history	H4	!!Order!!,Call,V
CH.columnFor	H4	v:RST	v
CH.columnFor	H4	Name:RST	name
CH.columnFor	H4	v:RS	v
CH.columnFor	H4	Name:RS	name
CH.columnFor	H4	v:SERIAL	v
CH.columnFor	H4	Name:SERIAL	name
CH.columnFor	H4	v:INTEGER	v
CH.columnFor	H4	Name:INTEGER	name
CH.columnFor	H4	v:TEXT	v
CH.columnFor	H4	Name:TEXT	name
CH.columnFor	H4	v:LOCATOR	v
CH.columnFor	H4	Name:LOCATOR	loc1
CH.columnFor	H4	v:CQ_ZONE	v
CH.columnFor	H4	Name:CQ_ZONE	cqzone
CH.columnFor	H4	v:ITU_ZONE	v
CH.columnFor	H4	Name:ITU_ZONE	ituzone
CH.columnFor	H4	v:DXCC	v
CH.columnFor	H4	Name:DXCC	name
CH.columnFor	H4	v:PREFIX	v
CH.columnFor	H4	Name:PREFIX	name
CH.columnFor	H4	v:HQ	v
CH.columnFor	H4	Name:HQ	name
CH.columnFor	H4	v:NATIONAL	v
CH.columnFor	H4	Name:NATIONAL	name
CH.columnFor	H4	v:STATE	v
CH.columnFor	H4	Name:STATE	state
CH.columnFor	H4	v:PROVINCE	v
CH.columnFor	H4	Name:PROVINCE	state
CH.columnFor	H4	v:DISTRICT	v
CH.columnFor	H4	Name:DISTRICT	district
CH.columnFor	H4	v:IOTA	v
CH.columnFor	H4	Name:IOTA	iota
CH.columnFor	H4	v:QTC	v
CH.columnFor	H4	Name:QTC	name
CH.columnFor	H4	Zone:null	zone
CH.update	!!Order!!,Call,Name||W1AW,Hiram	W1AW>>cqzone==5 ;; ok1xoe>>cqzone==15,,name==Tomas	size=2 cols=[call, name, cqzone] recs=[W1AW:{call=W1AW, name=Hiram, cqzone=5}; OK1XOE:{call=OK1XOE, cqzone=15, name=Tomas}]	# Call history \u2014 MacContestLogger (form\u00E1t N1MM+)||!!Order!!,Call,Name,CQZone||OK1XOE,Tomas,15||W1AW,Hiram,5
CH.update	!!Order!!,Name||x	A1>>name==a	size=1 cols=[call, name] recs=[A1:{call=A1, name=a}]	# Call history \u2014 MacContestLogger (form\u00E1t N1MM+)||!!Order!!,Call,Name||A1,a
CH.update	!!Order!!,Call,Name	 k1abc >>Name== a,b ,,state==,,misc==  ,,newcol==v,,nul==<null> ;; >>x==y ;;   >>x==y	size=1 cols=[call, name, newcol] recs=[K1ABC:{call=K1ABC, name=a b, newcol=v}]	# Call history \u2014 MacContestLogger (form\u00E1t N1MM+)||!!Order!!,Call,Name,newcol||K1ABC,a b,v
CH.update		b1>>name==v ;; a1>>name==v ;; B1>>name==v ;; \u00A0c1>>name==v ;; \uD83D\uDE00>>name==v ;; \uFF411>>name==v ;; \u00C5>>name==v ;; A\u030A>>name==v	size=7 cols=[call, name, loc1, loc2, sect, state, ck, birthdate, exch1, misc, usertext] recs=[B1:{call=B1, name=v}; A1:{call=A1, name=v}; \u00A0C1:{call=\u00A0C1, name=v}; \uD83D\uDE00:{call=\uD83D\uDE00, name=v}; \uFF211:{call=\uFF211, name=v}; \u00C5:{call=\u00C5, name=v}; A\u030A:{call=A\u030A, name=v}]	# Call history \u2014 MacContestLogger (form\u00E1t N1MM+)||!!Order!!,Call,Name,Loc1,Loc2,Sect,State,CK,BirthDate,Exch1,Misc,UserText||A1,v,,,,,,,,,||A\u030A,v,,,,,,,,,||B1,v,,,,,,,,,||\u00A0C1,v,,,,,,,,,||\u00C5,v,,,,,,,,,||\uD83D\uDE00,v,,,,,,,,,||\uFF211,v,,,,,,,,,
CH.update	!!Order!!,Call,Name,State	CQZONE>>CQZONE==5,,\u0130==i ;; \u00DF1>>name==x	size=2 cols=[call, name, state, cqzone, i\u0307] recs=[CQZONE:{call=CQZONE, cqzone=5, i\u0307=i}; SS1:{call=SS1, name=x}]	# Call history \u2014 MacContestLogger (form\u00E1t N1MM+)||!!Order!!,Call,Name,State,CQZone,i\u0307||CQZONE,,,5,i||SS1,x,,,
CH.update	!!Order!!,Call,Name||W1AW,Hiram,||K1AB,,x	W1AW>>name==Bob ;; K1AB>>state==CT	size=2 cols=[call, name, state] recs=[W1AW:{call=W1AW, name=Bob}; K1AB:{call=K1AB, state=CT}]	# Call history \u2014 MacContestLogger (form\u00E1t N1MM+)||!!Order!!,Call,Name,State||K1AB,,CT||W1AW,Bob,
CH.update	!!Order!!,Name,Call,Name||A,B1,C	B1>>name==D	size=1 cols=[name, call, name] recs=[B1:{name=D, call=B1}]	# Call history \u2014 MacContestLogger (form\u00E1t N1MM+)||!!Order!!,Name,Call,Name||D,B1,D
CH.toLines	<empty>	# Call history \u2014 MacContestLogger (form\u00E1t N1MM+)||!!Order!!,Call,Name,Loc1,Loc2,Sect,State,CK,BirthDate,Exch1,Misc,UserText
CH.save	new	232043616c6c20686973746f727920e28094204d6163436f6e746573744c6f676765722028666f726dc3a174204e314d4d2b290a21214f7264657221212c43616c6c2c4e616d652c43515a6f6e650a4f4b31584f452c546f6dc3a1c5a12c31350a573141572c486972616d2c0a	rw-------
CH.save	overwrite	232043616c6c20686973746f727920e28094204d6163436f6e746573744c6f676765722028666f726dc3a174204e314d4d2b290a21214f7264657221212c43616c6c2c4e616d652c4c6f63312c4c6f63322c536563742c53746174652c434b2c4269727468446174652c45786368312c4d6973632c55736572546578740a	rw-------
CH.save	tmpLeft	0
CH.saveError	parentIsFile	FileSystemException: <work>/plainfile/sub: Not a directory
CH.saveError	parentIsFileDirect	FileAlreadyExistsException: <work>/plainfile
CH.saveError	readOnlyDir	AccessDeniedException: <work>/readonly/callhistory<n>.tmp
CH.saveError	readOnlyDirSub	AccessDeniedException: <work>/readonly/sub
CH.saveError	targetIsNonEmptyDir	FileSystemException: <work>/callhistory<n>.tmp -> <work>/fulldir: Is a directory
CH.updater	cq-ww-ssb		5|W1AW|59 5|;0|W1AW|59 4|;1|DL1ABC|59 14|	{W1AW={cqzone=5}, DL1ABC={cqzone=14}}
CH.updater	cq-ww-ssb		5|W1AW|59 5|;null|W1AW|59 3|;2|DL1ABC|59 14|D;3|DL1ABC|59 15|X;1|  |59 1|;4|ok1xoe|59|;6|K1AB|59 5 extra|;6|k1ab|59 6|;null|N1XX|59 7|;null|N1XX|59 8|	{W1AW={cqzone=5}, N1XX={cqzone=8}, K1AB={cqzone=6}}
CH.updater	cq-ww-ssb	!!Order!!,Call,Zone	5|W1AW|59 5|	{W1AW={zone=5}}
CH.updater	cq-ww-rtty		1|W1AW|599 5 CT|;2|DL1ABC|599 14 XX|;3|VE3XX|599 4|;4|W1AW|599 5 ma|	{W1AW={cqzone=5, state=ma}, DL1ABC={cqzone=14}, VE3XX={cqzone=4}}
CH.updater	cq-ww-rtty	!!Order!!,Call,Sect	1|W1AW|599 5 CT|	{W1AW={cqzone=5, state=CT}}
CH.updater	cq-wpx-cw		1|W1AW|599 123|;2|DL1ABC|599 7|	{}
"""#
}
