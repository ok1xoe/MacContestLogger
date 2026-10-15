import subprocess,sys,re,glob
res=[]
for o in sys.argv[1:]:
    out=subprocess.run(['objdump','-d','--no-show-raw-insn',o],capture_output=True,text=True).stdout
    fn=None; pend=None
    for line in out.splitlines():
        m=re.match(r'^[0-9a-f]+ <(.+)>:',line)
        if m: fn=m.group(1); pend=None; continue
        m=re.search(r'mov\s+x16, #(0x[0-9a-f]+|\d+)',line)
        if m: pend=int(m.group(1),0); continue
        m=re.search(r'movk\s+x16, #(0x[0-9a-f]+|\d+), lsl #16',line)
        if m and pend is not None: pend+= int(m.group(1),0)<<16; continue
        if 'chkstk_darwin' in line and pend is not None and fn:
            res.append((pend,fn,o.split('/')[-1])); pend=None
        m=re.search(r'sub\s+sp, sp, #(0x[0-9a-f]+|\d+), lsl #12',line)
        if m and fn: res.append((int(m.group(1),0)<<12,fn,o.split('/')[-1]))
res.sort(reverse=True)
for r in res[:int(__import__("os").environ.get("TOP","80"))]: print(r[0], r[2], subprocess.run(['swift','demangle','--compact',r[1].lstrip('_')],capture_output=True,text=True).stdout.strip()[:200])
