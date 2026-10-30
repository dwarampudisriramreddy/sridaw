import re, html as htmllib, json, sys

BOOKS = [
    ('c', '37-the-chord-pattern-library.html'),
    ('m', '36-the-melody-motif-library.html'),
    ('b', '38-the-beat-and-rhythm-pattern-library.html'),
]
BASE = '/home/sri/my-e-books/music theory/'


def balanced(src, i, open_ch, close_ch):
    """src[i] == open_ch; return index just past the matching close."""
    depth = 0
    in_str = None
    while i < len(src):
        c = src[i]
        if in_str:
            if c == '\\':
                i += 2
                continue
            if c == in_str:
                in_str = None
        elif c in '\'"':
            in_str = c
        elif c == open_ch:
            depth += 1
        elif c == close_ch:
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    raise ValueError('unbalanced')


out = {}
for prefix, fname in BOOKS:
    src = open(BASE + fname, encoding='utf-8').read()
    meta = {}
    current_section = ''
    for m in re.finditer(r'<section class="chapter"[^>]*>\s*<h2>(.*?)</h2>|<div class="card" id="([a-z][0-9]+)">\s*<h3>(.*?)</h3>', src, re.S):
        if m.group(1) is not None:
            current_section = re.sub(r'<[^>]+>', ' ', m.group(1))
            current_section = re.sub(r'\s+', ' ', htmllib.unescape(current_section)).strip()
            current_section = re.sub(r'\s*[CMB]\d+\s*[–-]\s*[CMB]\d+\s*$', '', current_section).strip()
        else:
            cid = m.group(2)
            title = re.sub(r'<[^>]+>', '', m.group(3))
            title = re.sub(r'\s+', ' ', htmllib.unescape(title)).strip()
            title = re.sub(r'^[CMB]\d+\s*[·.]\s*', '', title)
            meta[cid] = (title, current_section)

    pats = []
    for wm in re.finditer(r"wire\('([a-z][0-9]+)'\s*,", src):
        pid = wm.group(1)
        j = src.index('[', wm.end())
        end_arr = balanced(src, j, '[', ']')
        body = src[j + 1:end_arr - 1]
        k = src.index('{', end_arr)
        end_opts = balanced(src, k, '{', '}')
        opts = src[k + 1:end_opts - 1]

        # split body on top-level CH(...) calls
        steps = []
        p = 0
        while True:
            ci = body.find('CH(', p)
            if ci < 0:
                break
            lp = ci + 2
            rp = balanced(body, lp, '(', ')')
            call = body[lp + 1:rp - 1]
            # call = [notes], dur[, [vels]]
            b1 = call.index('[')
            e1 = balanced(call, b1, '[', ']')
            notes = [int(x) for x in re.findall(r'\d+', call[b1 + 1:e1 - 1])]
            rest = call[e1:]
            nums = re.findall(r'\d+', rest)
            dur = int(nums[0])
            vel = None
            if '[' in rest:
                vb = rest.index('[')
                ve = balanced(rest, vb, '[', ']')
                vel = [int(x) for x in re.findall(r'\d+', rest[vb + 1:ve - 1])]
            steps.append((notes, dur, vel))
            p = rp

        bpm = re.search(r'bpm:\s*(\d+)', opts)
        bpb = re.search(r'beatsPerBar:\s*(\d+)', opts)
        chan = re.search(r'channel:\s*(\d+)', opts)
        title, section = meta.get(pid, ('', ''))
        pats.append({
            'id': pid,
            'title': title or pid.upper(),
            'section': section,
            'bpm': int(bpm.group(1)) if bpm else 100,
            'beatsPerBar': int(bpb.group(1)) if bpb else 4,
            'drums': bool(chan and int(chan.group(1)) == 9),
            'steps': steps,
        })
    out[prefix] = pats
    empty = sum(1 for p in pats if not p['steps'])
    print(f'{prefix}: {len(pats)} patterns, empty-steps: {empty}', file=sys.stderr)

json.dump(out, open('/tmp/patterns.json', 'w'))
print(json.dumps(out['c'][0], indent=1)[:900])
print('total steps:', sum(len(p['steps']) for v in out.values() for p in v))
