#!/usr/bin/env python3
# Генерация всех иконок SB Client из пиксель-арт исходников.
# Правило ресемплинга: цель >= источник -> NEAREST (чёткий пиксель-апскейл),
# цель < источник -> BOX (сохраняет форму без рваных пикселей) либо NEAREST (аргумент "nearest").
import sys, struct, io, os
from PIL import Image, ImageDraw

ROOT = '/home/z/my-project/sb-client/branding'
SRC_APP = f'{ROOT}/source/SB-client.png'
SRC_SB = f'{ROOT}/source/skinbase-icon.png'
SMALL = sys.argv[1] if len(sys.argv) > 1 else 'box'  # box | nearest


def load(p):
    return Image.open(p).convert('RGBA')


def smart(img, size):
    if size >= img.width:
        return img.resize((size, size), Image.Resampling.NEAREST)
    m = Image.Resampling.BOX if SMALL == 'box' else Image.Resampling.NEAREST
    return img.resize((size, size), m)


def up(img, size):
    return img.resize((size, size), Image.Resampling.NEAREST)


def png_bytes(img):
    b = io.BytesIO()
    img.save(b, 'PNG', optimize=True)
    return b.getvalue()


def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)


def circle_mask(size):
    s = 4  # суперсэмплинг для гладкого края круга
    m = Image.new('L', (size * s, size * s), 0)
    d = ImageDraw.Draw(m)
    d.ellipse((s // 2, s // 2, size * s - s // 2 - 1, size * s - s // 2 - 1), fill=255)
    return m.resize((size, size), Image.Resampling.BOX)


def save_ico(img, path, sizes=(16, 24, 32, 48, 64, 128, 256)):
    # ICO-контейнер с PNG-записями (Windows Vista+, весь набор в одном файле)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    entries = b''
    blobs = b''
    offset = 6 + 16 * len(sizes)
    for s in sizes:
        data = png_bytes(smart(img, s))
        e = s if s < 256 else 0
        entries += struct.pack('<BBBBHHII', e, e, 0, 0, 1, 32, len(data), offset)
        blobs += data
        offset += len(data)
    with open(path, 'wb') as f:
        f.write(struct.pack('<HHH', 0, 1, len(sizes)) + entries + blobs)


def border_color(img):
    # доминирующий цвет по краям -> фон adaptive-иконки Android
    w, h = img.size
    px = img.load()
    tot = [0, 0, 0]
    n = 0
    band = max(2, int(min(w, h) * 0.08))
    for y in range(h):
        for x in range(w):
            if x < band or y < band or x >= w - band or y >= h - band:
                r, g, b, a = px[x, y]
                if a > 128:
                    tot[0] += r
                    tot[1] += g
                    tot[2] += b
                    n += 1
    return '#%02X%02X%02X' % tuple(t // n for t in tot) if n else '#3B3B98'


app = load(SRC_APP)
sb = load(SRC_SB)
print('app source:', app.size, '| skinbase source:', sb.size)

png_sizes = [16, 24, 32, 48, 64, 96, 128, 256, 512, 1024]

# PNG-лестница приложения
for s in png_sizes:
    save(smart(app, s), f'{ROOT}/app-icon/png/{s}.png')

# Tauri-набор (Windows/Linux)
tauri = f'{ROOT}/app-icon/tauri'
save(smart(app, 32), f'{tauri}/32x32.png')
save(smart(app, 128), f'{tauri}/128x128.png')
save(smart(app, 256), f'{tauri}/128x128@2x.png')
save(up(app, 1024), f'{tauri}/icon.png')
save_ico(app, f'{tauri}/icon.ico')

# Android mipmap: launcher + round + adaptive foreground
dens = {'mdpi': 1.0, 'hdpi': 1.5, 'xhdpi': 2.0, 'xxhdpi': 3.0, 'xxxhdpi': 4.0}
and_dir = f'{ROOT}/app-icon/android'
for d, f in dens.items():
    launcher = round(48 * f)
    fg_canvas = round(108 * f)
    dd = f'{and_dir}/mipmap-{d}'
    save(smart(app, launcher), f'{dd}/ic_launcher.png')
    r = smart(app, launcher).copy()
    r.putalpha(circle_mask(launcher))
    save(r, f'{dd}/ic_launcher_round.png')
    content = round(fg_canvas * 0.5)  # контент в безопасной зоне adaptive-иконки
    fg = Image.new('RGBA', (fg_canvas, fg_canvas), (0, 0, 0, 0))
    fg.alpha_composite(up(app, content), ((fg_canvas - content) // 2,) * 2)
    save(fg, f'{dd}/ic_launcher_foreground.png')

bg = border_color(app)
os.makedirs(f'{and_dir}/values', exist_ok=True)
with open(f'{and_dir}/values/ic_launcher_background.xml', 'w') as fp:
    fp.write('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
             f'    <color name="ic_launcher_background">{bg}</color>\n</resources>\n')
print('adaptive bg color:', bg)

# иконка 512 для стора / прочего
save(smart(app, 512), f'{ROOT}/app-icon/playstore-512.png')

# SkinBase: лестница размеров для UI приложения
for s in png_sizes:
    save(smart(sb, s), f'{ROOT}/skinbase-icon/png/{s}.png')

print('done, small resample =', SMALL)
