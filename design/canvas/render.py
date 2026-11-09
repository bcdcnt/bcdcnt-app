#!/usr/bin/env python3
"""Xuất ảnh xem trước các artboard của canvas ra preview/<Board>.png.

  python3 design/canvas/render.py            # tất cả artboard
  python3 design/canvas/render.py Main BaiHat

Không cần runtime của canvas: tự ghép TabBar/MiniPlayer (<dc-import>) vào
artboard, thay /_blob/<id> bằng assets/<id>.*, rồi chụp bằng chromium headless.
Cần `chromium` (brew install --cask chromium) và `node` (để đọc danh sách tab).
"""
import glob, json, os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
P = f'{HERE}/project'
A = f'{HERE}/assets'
O = f'{HERE}/preview'
SCALE = os.environ.get('SCALE', '1')
CHROME = os.environ.get('CHROME', 'chromium')

blobs = {os.path.splitext(os.path.basename(f))[0]: f for f in glob.glob(f'{A}/*')}


def xdc(name):
    t = open(f'{P}/{name}.dc.html').read()
    body = re.search(r'<x-dc>(.*)</x-dc>', t, re.S).group(1)
    helm = re.search(r'<helmet>(.*?)</helmet>', body, re.S)
    head = helm.group(1) if helm else ''
    body = re.sub(r'<helmet>.*?</helmet>', '', body, flags=re.S)
    pv = json.loads(re.search(r"data-props='([^']*)'", t).group(1))['$preview']
    return head, body, (pv.get('width', 390), pv['height'])


def tabbar(active):
    t = open(f'{P}/TabBar.dc.html').read()
    js = re.search(r'const defs = (\[.*?\n\]);', t, re.S).group(1)
    out = subprocess.run(['node', '-e', f'const defs={js};console.log(JSON.stringify(defs))'],
                         capture_output=True, text=True, check=True).stdout
    _, body, _ = xdc('TabBar')
    tpl = re.search(r'<sc-for[^>]*>(.*?)</sc-for>', body, re.S).group(1)
    items = ''
    for d in json.loads(out):
        on = d['key'] == active
        badge = '1' if d['key'] == 'me' else ''
        v = {'t.href': d['href'], 't.label': d['label'], 't.aria': d['label'],
             't.color': '#711313' if on else '#665C5E', 't.d': d['on'] if on else d['off'],
             't.badge': badge, 't.badgeDisplay': 'block' if badge else 'none'}
        items += re.sub(r'\{\{(.*?)\}\}', lambda m: v[m.group(1).strip()], tpl)
    return re.sub(r'<sc-for.*?</sc-for>', items, body, flags=re.S)


def expand(body):
    def rep(m):
        a = m.group(1)
        name = re.search(r'name="(\w+)"', a).group(1)
        if name == 'TabBar':
            act = re.search(r'active="(\w+)"', a)
            return tabbar(act.group(1) if act else 'home')
        return xdc(name)[1]
    return re.sub(r'<dc-import([^>]*)>\s*</dc-import>', rep, body)


def render(b):
    head, body, (w, h) = xdc(b)
    body = expand(body)
    body = re.sub(r'/_blob/([0-9a-f]{32})', lambda m: 'file://' + blobs[m.group(1)], body)
    html = (f'<!doctype html><html lang="vi"><head><meta charset="utf-8">{head}'
            f'<style>body{{margin:0}}</style></head><body>{body}</body></html>')
    hp = f'{O}/.{b}.html'
    open(hp, 'w').write(html)
    subprocess.run([CHROME, '--headless=new', '--disable-gpu', '--hide-scrollbars',
                    f'--force-device-scale-factor={SCALE}', f'--window-size={w},{h}',
                    '--virtual-time-budget=4000', '--allow-file-access-from-files',
                    f'--screenshot={O}/{b}.png', f'file://{hp}'], capture_output=True)
    os.remove(hp)
    print(b, h, 'ok' if os.path.exists(f'{O}/{b}.png') else 'FAILED')


if __name__ == '__main__':
    os.makedirs(O, exist_ok=True)
    order = json.load(open(f'{P}/canvas.json'))['order']
    boards = sys.argv[1:] or [f[:-len('.dc.html')] for f in order]
    for b in boards:
        render(b)
