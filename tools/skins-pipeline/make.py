# Découpe les skins (image unique de 512 px) en 3 calques : châssis, canon, tourelle — vus du dessus, canon vers la droite
import cv2, numpy as np, json, os, sys
SRC = sys.argv[1]; OUT = sys.argv[2]; os.makedirs(OUT, exist_ok=True)
CX, CY, ROT = 223.0, 277.0, -27.6      # centre tourelle et rotation pour remettre le tank à plat
HALF = 215                              # demi-taille du cadre (px source)
TR = 80                                 # rayon tourelle (avec contour)
BY0, BY1, BX1 = 224, 332, 440           # canon : bande horizontale, jusqu'au bout
S = int(sys.argv[3]) if len(sys.argv) > 3 else 176   # taille finale d'un calque
NF = 16                                 # images gardées pour les skins animés
skins = json.load(open(os.path.join(SRC, 'skins.json')))
yy, xx = np.mgrid[0:512, 0:512]
turret = ((xx - CX) ** 2 + (yy - CY) ** 2) <= TR ** 2
barrel = (yy >= BY0) & (yy <= BY1) & (xx >= 296) & (xx <= BX1) & ~turret
hrep = (yy >= 210) & (yy <= 346) & (xx >= 296) & ~turret
def soft(m, r=1.2):
    return cv2.GaussianBlur(m.astype(np.float32), (0, 0), r)
mt, mb = soft(turret), soft(barrel)
def layers(img):
    M = cv2.getRotationMatrix2D((CX, CY), ROT, 1.0)
    r = cv2.warpAffine(img, M, (512, 512), flags=cv2.INTER_CUBIC, borderMode=cv2.BORDER_CONSTANT, borderValue=(0, 0, 0, 0)).astype(np.float32)
    def cut(mask):
        o = r.copy(); o[:, :, 3] *= mask; return o
    tur, bar = cut(mt), cut(mb)
    # châssis : sous le canon, on reconstitue avec le miroir du côté gauche
    hull = r.copy()
    mir = r[:, ::-1].copy()
    shift = int(round(2 * CX - 511))
    mir = np.roll(mir, shift, axis=1)
    if shift > 0: mir[:, :shift] = 0
    hb = soft(hrep, 2.0)[:, :, None]
    hull = hull * (1 - hb) + mir * hb
    def crop(o):
        x0, y0 = int(CX - HALF), int(CY - HALF)
        c = np.zeros((2 * HALF, 2 * HALF, 4), np.float32)
        sx0, sy0 = max(0, x0), max(0, y0); sx1, sy1 = min(512, x0 + 2 * HALF), min(512, y0 + 2 * HALF)
        c[sy0 - y0:sy1 - y0, sx0 - x0:sx1 - x0] = o[sy0:sy1, sx0:sx1]
        c = np.clip(c, 0, 255).astype(np.uint8)
        return cv2.resize(c, (S, S), interpolation=cv2.INTER_AREA)
    return crop(hull), crop(bar), crop(tur)
meta = []
for sk in skins:
    frames = []
    if sk['animated'] and sk['spritesheet']:
        sh = cv2.imread(os.path.join(SRC, sk['spritesheet']), cv2.IMREAD_UNCHANGED)
        cols = sh.shape[1] // 512
        idx = list(range(0, sk['frames'], max(1, sk['frames'] // NF)))[:NF]
        for i in idx:
            frames.append(sh[(i // cols) * 512:(i // cols + 1) * 512, (i % cols) * 512:(i % cols + 1) * 512])
    else:
        frames.append(cv2.imread(os.path.join(SRC, sk['file']), cv2.IMREAD_UNCHANGED))
    n = len(frames)
    sheet = np.zeros((3 * S, n * S, 4), np.uint8)
    for i, f in enumerate(frames):
        h, b, t = layers(f)
        sheet[0:S, i * S:(i + 1) * S] = h; sheet[S:2 * S, i * S:(i + 1) * S] = b; sheet[2 * S:3 * S, i * S:(i + 1) * S] = t
    name = sk['id'] + '.webp'
    cv2.imwrite(os.path.join(OUT, name), sheet, [cv2.IMWRITE_WEBP_QUALITY, 82])
    # vignette boutique (image d'origine)
    th = cv2.resize(cv2.imread(os.path.join(SRC, sk['file'] if sk['file'].endswith('.png') else sk['file'].replace('.gif', '.png')), cv2.IMREAD_UNCHANGED), (256, 256), interpolation=cv2.INTER_AREA)
    cv2.imwrite(os.path.join(OUT, sk['id'] + '_thumb.webp'), th, [cv2.IMWRITE_WEBP_QUALITY, 85])
    sz = os.path.getsize(os.path.join(OUT, name)) // 1024
    meta.append({'key': sk['id'], 'name': sk['name'], 'rarity': sk['rarity'], 'frames': n, 'ms': (sk['frame_ms'] or 40) * max(1, sk['frames'] // NF) if n > 1 else 0, 'kb': sz})
    print(sk['id'], n, 'frames', sz, 'Ko')
json.dump(meta, open(os.path.join(OUT, 'meta.json'), 'w'), ensure_ascii=False, indent=1)
