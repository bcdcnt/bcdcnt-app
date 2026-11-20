# 10 bộ màu đề xuất cho app (Sáng hiện tại + 9 bộ). Chữ mờ chỉnh ≥4.5:1 trên thẻ.
P = [
 # name, label, light, bg, surface, surfaceLight, accent(fill), accentFg(text on bg), deep(hero), text, sec, muted, border
 dict(n='sang', l='Sáng', light=True, bg='#FFFFFF', s='#F4F1F0', sl='#EDE9E8', a='#711313', fg='#711313', deep='#4A0C0C', t='#161112', t2='#4F4547', m='#665C5E', b='#ECE4E4'),
 dict(n='kem', l='Kem', light=True, bg='#F7F4EF', s='#FFFFFF', sl='#ECE7E0', a='#8B1A1A', fg='#8B1A1A', deep='#5A1010', t='#1A1414', t2='#5E4D4D', m='#6E5C5C', b='#E2DBD2'),
 dict(n='sepia', l='Nâu sepia', light=True, bg='#F1E6D2', s='#FAF3E6', sl='#E6D7BD', a='#6B3A1E', fg='#6B3A1E', deep='#3F2210', t='#2B1D12', t2='#5A4330', m='#6A5442', b='#D9C6A5'),
 dict(n='hong', l='Hồng phấn', light=True, bg='#FBF1F2', s='#FFFFFF', sl='#F3E2E4', a='#A3324A', fg='#A3324A', deep='#5E1426', t='#22141A', t2='#5C4049', m='#6E5560', b='#EBD5D9'),
 dict(n='troi', l='Xanh trời', light=True, bg='#EEF4F8', s='#FFFFFF', sl='#DFE9F0', a='#1F5E86', fg='#1F5E86', deep='#0E3350', t='#111C24', t2='#3E5160', m='#566878', b='#D3E0EA'),
 dict(n='toi', l='Đen', light=False, bg='#0E0A0A', s='#1B1515', sl='#271F1F', a='#8E1F1F', fg='#E0AEAC', deep='#4A0C0C', t='#FFFFFF', t2='#D5CACA', m='#A39494', b='#2A2222'),
 dict(n='xam', l='Xám', light=False, bg='#1A1A1E', s='#242428', sl='#2E2E33', a='#4F6274', fg='#BFCAD6', deep='#26313C', t='#E8E6E3', t2='#BDBBB8', m='#9E9E9E', b='#36363C'),
 dict(n='do', l='Đỏ đô', light=False, bg='#3D0C0C', s='#4E1212', sl='#5E1818', a='#C94444', fg='#F5B8B8', deep='#2A0808', t='#FFF8F5', t2='#F0D6D0', m='#D9AFA9', b='#6A2020'),
 dict(n='hophach', l='Hổ phách', light=False, bg='#1A1308', s='#241A0D', sl='#2E2212', a='#9A5F12', fg='#F0C987', deep='#4A2E08', t='#F6EEDF', t2='#DCCDB2', m='#AE9C80', b='#3A2C17'),
 dict(n='rêu', l='Xanh rêu', light=False, bg='#16150B', s='#201E10', sl='#2A2816', a='#66621A', fg='#D6CF86', deep='#3A370C', t='#F1EFE0', t2='#D3CFB4', m='#A6A182', b='#353220'),
 dict(n='la', l='Xanh lá', light=False, bg='#0A1A0C', s='#122016', sl='#1A2A1E', a='#287A33', fg='#9BD3A4', deep='#0F4418', t='#E8F0EA', t2='#C2D3C5', m='#93A897', b='#24382A'),
 dict(n='ngoc', l='Xanh ngọc', light=False, bg='#08171A', s='#0F2226', sl='#162D32', a='#1C6F75', fg='#8FD6D2', deep='#0B3B40', t='#E6F3F2', t2='#BFD6D4', m='#8CA9A7', b='#1F3A3F'),
 dict(n='duong', l='Xanh dương', light=False, bg='#0A0F1E', s='#111A2E', sl='#18233C', a='#2B62A0', fg='#9DC2EE', deep='#11305A', t='#E8EEF7', t2='#C3CEE0', m='#8E9DB6', b='#24314C'),
 dict(n='tim', l='Tím', light=False, bg='#1A0C17', s='#251220', sl='#30182A', a='#8E3A7E', fg='#E3A8D6', deep='#4A1640', t='#F7EAF3', t2='#DCC5D5', m='#B096A8', b='#3D2236'),
]


def lum(h):
    h = h.lstrip('#')
    r, g, b = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    f = lambda c: c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)


def cr(a, b):
    la, lb = lum(a), lum(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


if __name__ == '__main__':
    for p in P:
        print(f"{p['l']:12} muted/s {cr(p['m'], p['s']):.1f} muted/sl {cr(p['m'], p['sl']):.1f} fg/s {cr(p['fg'], p['s']):.1f} fg/bg {cr(p['fg'], p['bg']):.1f} white/a {cr('#FFFFFF', p['a']):.1f} t2/s {cr(p['t2'], p['s']):.1f}")
