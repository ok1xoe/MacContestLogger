import json, sys
for path in sys.argv[1:]:
    text = open(path, errors='replace').read()
    head, _, body = text.partition('\n')
    try:
        d = json.loads(body)
    except Exception as e:
        print('parse error', e); print(body[:2000]); continue
    imgs = d.get('usedImages', [])
    ft = d.get('faultingThread')
    for ti, t in enumerate(d.get('threads', [])):
        frames = t.get('frames', [])
        if ti != ft and not t.get('triggered'):
            continue
        print('THREAD', ti, t.get('name'), t.get('queue'), 'frames', len(frames))
        def fmt(f):
            img = imgs[f['imageIndex']]['name'] if 'imageIndex' in f and f['imageIndex'] < len(imgs) else '?'
            return '%s %s +%s %s' % (img, f.get('symbol', '?'), f.get('symbolLocation', ''), f.get('imageOffset'))
        for i, f in enumerate(frames):
            if i < 120 or i >= len(frames) - 30:
                print(i, fmt(f))
