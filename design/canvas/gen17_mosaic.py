"""Playlist covers in lists -> 2x2 mosaic of song pictures (playlists with 4+ songs).
Detail headers, event banners, categories stay as they are. Idempotent."""
import re, glob, hashlib, sys
P = sys.argv[1]
ALLOW = {  # board -> cover widths that are playlist covers in lists
    'Desktop_Playlist_DS': {'100%'}, 'Desktop_PlaylistCuaToi': {'100%'}, 'Desktop_ThuVien_TQ': {'100%'},
    'Desktop_KhamPha': {'100%'}, 'Desktop_TimKiem': {'44px'}, 'TimKiem': {'148px'},
    'CaNhan': {'52px'}, 'PlaylistCuaToi': {'56px'},
    'Desktop_TrangChu': {'100%'}, 'Desktop_TrangChu_Khach': {'100%'}, 'Desktop_TrangChu_Toi': {'100%'},
    'Desktop_1024': {'100%'}, 'Desktop_CtrlK': {'100%'},
}
IMG = re.compile(r'<img src="/_blob/([0-9a-f]+)" alt="[^"]*" style="([^"]*)">')
# pool: song thumbnails from song lists (square, not round)
pool = []
for f in ['Desktop_Playlist', 'Desktop_BXH', 'Desktop_YeuThich', 'Desktop_NgheGanDay', 'Desktop_TheLoai']:
    try: s = open(f'{P}/{f}.dc.html').read()
    except FileNotFoundError: continue
    for m in IMG.finditer(s):
        st = m.group(2)
        if '50%' in st or 'border-radius: 999' in st: continue
        w = re.search(r'width: (\d+)px', st)
        if w and 36 <= int(w.group(1)) <= 64 and m.group(1) not in pool: pool.append(m.group(1))
assert len(pool) >= 8, pool

def tiles(first, title):
    k = int(hashlib.md5(title.encode()).hexdigest(), 16)
    out = [first]; i = k % len(pool)
    while len(out) < 4:
        b = pool[i % len(pool)]; i += 1
        if b not in out: out.append(b)
    return out

def mosaic(blob, st, title):
    st2 = re.sub(r'\s*object-fit: cover;?', '', st).rstrip('; ')
    if 'display:' in st2: st2 = re.sub(r'display: [^;]+', 'display: grid', st2)
    else: st2 += '; display: grid'
    st2 += '; grid-template-columns: 1fr 1fr; grid-template-rows: 1fr 1fr; overflow: hidden; flex-shrink: 0'
    cell = 'width: 100%; height: 100%; min-width: 0; min-height: 0; object-fit: cover; display: block'
    return f'<span data-mosaic="1" style="{st2}">' + ''.join(f'<img src="/_blob/{b}" alt="" style="{cell}">' for b in tiles(blob, title)) + '</span>'

total = 0
for f in sorted(glob.glob(f'{P}/*.dc.html')):
    b = f.split('/')[-1][:-8]; s = open(f).read(); n = 0
    def rep(m):
        global n
        st = m.group(2)
        if 'min-height: 0' in st: return m.group(0)
        w = re.search(r'(?<!-)width: ([^;]+)', st); w = w.group(1) if w else ''
        rest = s[m.end():m.end() + 1500]
        text = re.sub(r'\s+', ' ', re.sub(r'<[^>]+>', ' ', rest)).strip()
        ok = b in ALLOW and w in ALLOW[b]
        # sidebar playlists (desktop chrome)
        side = b.startswith('Desktop') and re.match(r'3[0-6]px', w) and re.match(r'(Chiến thắng Điện|Tình ca địa chất)', text)
        if side:
            n += 1; return mosaic(m.group(1), st, text[:40])
        if not ok or text.startswith('Nghe tiếp'): return m.group(0)
        c = re.search(r'(\d+)\s*bài', text[:120]); 
        if not c or '<img' in rest[:rest.find(c.group(0)) if c.group(0) in rest else 0]: return m.group(0)
        if int(c.group(1)) < 4: return m.group(0)
        n += 1; return mosaic(m.group(1), st, text[:40])
    s2 = IMG.sub(rep, s)
    if n: open(f, 'w').write(s2); print(b, n); total += n
print('total', total)
