import math, sys
import numpy as np
from PIL import Image

S = 2048  # supersampled canvas
OUT = sys.argv[1]
SHAPE = sys.argv[2]  # round | square
SMALL = len(sys.argv) > 3 and sys.argv[3] == 'small'
Z = 1.32 if SMALL else 1.0
TH = 1.9 if SMALL else 1.0

yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
U = (xx + 0.5) / S - 0.5   # -0.5..0.5
V = (yy + 0.5) / S - 0.5
img = np.zeros((S, S, 4), np.float32)  # premultiplied rgba
AA = 1.5 / S


def hexc(h):
    h = h.lstrip('#')
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], np.float32)


def cov(d, aa=AA):
    """coverage from signed distance (negative inside)"""
    return np.clip(0.5 - d / aa, 0.0, 1.0)


def over(rgb, a, sl=(slice(None), slice(None))):
    """paint rgb (3,) or (h,w,3) with alpha a onto img[sl]"""
    tgt = img[sl]
    a = a[..., None]
    if np.ndim(rgb) == 1:
        rgb = rgb[None, None, :]
    tgt[..., :3] = rgb * a + tgt[..., :3] * (1 - a)
    tgt[..., 3:4] = a + tgt[..., 3:4] * (1 - a)


def capsule(ax, ay, bx, by, w, rgb, alpha=1.0):
    pad = w + 3 * AA
    x0 = int(max(0, (min(ax, bx) - pad + 0.5) * S)); x1 = int(min(S, (max(ax, bx) + pad + 0.5) * S) + 1)
    y0 = int(max(0, (min(ay, by) - pad + 0.5) * S)); y1 = int(min(S, (max(ay, by) + pad + 0.5) * S) + 1)
    if x1 <= x0 or y1 <= y0:
        return
    sl = (slice(y0, y1), slice(x0, x1))
    u, v = U[sl], V[sl]
    px, py = u - ax, v - ay
    dx, dy = bx - ax, by - ay
    h = np.clip((px * dx + py * dy) / max(dx * dx + dy * dy, 1e-12), 0, 1)
    d = np.hypot(px - dx * h, py - dy * h) - w
    over(rgb, cov(d) * alpha, sl)


def polyline(pts, w, rgb, alpha=1.0):
    for (a, b) in zip(pts[:-1], pts[1:]):
        capsule(a[0], a[1], b[0], b[1], w, rgb, alpha)


# ---- background --------------------------------------------------------
R = np.hypot(U, V)
if SHAPE == 'round':
    d_bg = R - 0.485
else:
    q = np.maximum(np.abs(np.stack([U, V])) - (0.5 - 0.035 - 0.095), 0)
    d_bg = np.hypot(q[0], q[1]) - 0.095
    # inner edge of square -> distance (approx) for interior
    inner = np.maximum(np.abs(U), np.abs(V)) - (0.5 - 0.035)
    d_bg = np.where(d_bg > 0, d_bg, np.maximum(d_bg, inner))
water_c = hexc('#F6FBFD'); water_e = hexc('#CFE6EE')
t = np.clip(np.hypot(U + 0.06, V + 0.08) / 0.62, 0, 1)[..., None] ** 1.6
bg = water_c * (1 - t) + water_e * t
over(bg, cov(d_bg))
over(hexc('#9CCBD9'), cov(np.abs(d_bg + 0.004) - 0.004))

# lab grid inside the dish (faint)
dish_r = 0.44 if SMALL else 0.405
grid = np.minimum(np.abs(((U / 0.0675) % 1) - 0.5), np.abs(((V / 0.0675) % 1) - 0.5))
gl = np.clip(1 - (0.5 - grid) * 0.0675 / (1.2 / S), 0, 1)
gl = np.clip(((0.5 - grid) * 0.0675 - (0.5 * 0.0675 - 1.1 / S)) / AA, 0, 1)
over(hexc('#9BCAD8'), gl * cov(R - dish_r) * (0.0 if SMALL else 0.22))

# dish glass ring
ring_c = hexc('#7FBFD1')
over(ring_c, cov(np.abs(R - dish_r) - 0.009 * TH) * 0.95)
over(hexc('#FFFFFF'), cov(np.abs(R - (dish_r - 0.016)) - 0.0035) * 0.85)
# cyan scanner ticks on the ring (lab accent)
ang = np.arctan2(V, U)
for k in ([] if SMALL else range(48)):
    a = k / 48 * math.tau
    big = k % 6 == 0
    r0, r1 = dish_r + 0.018, dish_r + (0.042 if big else 0.030)
    capsule(math.cos(a) * r0, math.sin(a) * r0, math.cos(a) * r1, math.sin(a) * r1,
            0.0042 if big else 0.0026, hexc('#2FB8D0'), 0.95 if big else 0.6)
# cyan arc highlight top-left
arc = (np.abs(R - dish_r) < 0.011) & (ang > math.radians(-160)) & (ang < math.radians(-110))
over(hexc('#22C3DD'), cov(np.abs(R - dish_r) - 0.0095) * (((ang > math.radians(-165)) & (ang < math.radians(-105)))).astype(np.float32))

# ---- the dividing cell ----------------------------------------------------
tilt = math.radians(-28)
ca, sa = math.cos(tilt), math.sin(tilt)
cx, cy = 0.012, 0.018


def to_local(u, v):
    u = (u - cx) / Z; v = (v - cy) / Z
    return u * ca + v * sa, -u * sa + v * ca


def to_world(lx, ly):
    return cx + Z * (lx * ca - ly * sa), cy + Z * (lx * sa + ly * ca)


LU, LV = to_local(U, V)
sep = 0.148
rx, ry = 0.178, 0.160


def ell(lu, lv, ox):
    # approx ellipse sdf
    px, py = (lu - ox) / rx, lv / ry
    k = np.hypot(px, py)
    return (k - 1.0) * min(rx, ry) * Z


d1 = ell(LU, LV, -sep); d2 = ell(LU, LV, sep)
kk = 0.075
hh = np.clip(0.5 + 0.5 * (d2 - d1) / kk, 0, 1)
dc = d2 * (1 - hh) + d1 * hh - kk * hh * (1 - hh)
# pinch the waist a little more
dc = dc + 0.030 * np.exp(-(LU / 0.075) ** 2)

# soft shadow / glow under the cell (very light, no 3D)
over(hexc('#8CC4D4'), np.clip(1 - (dc + 0.0) / 0.05, 0, 1) * cov(-dc - 0.0) * 0 + np.clip(1 - np.maximum(dc, 0) / 0.045, 0, 1) * (dc > 0) * 0.28)

# cilia (drawn before the body so the membrane covers their roots)
cil_c = hexc('#2B6E82')
for lobe, ox in (() if SMALL else ((0, -sep), (1, sep))):
    n = 34
    for k in range(n):
        th = k / n * math.tau + (0.09 if lobe else 0.0)
        ex, ey = ox + rx * math.cos(th), ry * math.sin(th)
        # skip the waist side where the other lobe covers
        other = ell(np.float32(ex), np.float32(ey), sep if lobe == 0 else -sep)
        if other < 0.03:
            continue
        nx, ny = math.cos(th) / rx, math.sin(th) / ry
        nl = math.hypot(nx, ny); nx /= nl; ny /= nl
        L = 0.034 + 0.006 * math.sin(k * 2.3)
        bend = 0.25 * math.sin(k * 1.7 + lobe)
        mx, my = ex + nx * L * 0.55 - ny * L * bend * 0.3, ey + ny * L * 0.55 + nx * L * bend * 0.3
        tx, ty = ex + nx * L - ny * L * bend, ey + ny * L + nx * L * bend
        pts = [to_world(ex - nx * 0.01, ey - ny * 0.01), to_world(mx, my), to_world(tx, ty)]
        polyline(pts, 0.0034, cil_c, 0.85)

# flagellum from the left lobe's far end
fl = []
for j in range(60):
    s = j / 59
    lx = -sep - rx + 0.012 - s * 0.115
    ly = 0.022 * math.sin(s * math.tau * 1.3 + 0.3) * (0.35 + s) + 0.03 * s
    fl.append(to_world(lx, ly))
if not SMALL:
    polyline(fl, 0.0055 * TH, cil_c, 0.95)

# body
body_rgb = hexc('#BCE5EE')
inner_edge = hexc('#8FCFDD')
e = np.clip(-dc / 0.05, 0, 1)[..., None]
fill = inner_edge * (1 - e) + body_rgb * e
over(fill, cov(dc) * 0.96)
# a soft lighter core in each lobe (flat, just a tint step)
for ox in (-sep, sep):
    dl = ell(LU, LV, ox * 0.92) + 0.07
    over(hexc('#D3F0F5'), np.clip(-dl / 0.06, 0, 1) * cov(dc) * 0.55)
# membrane outline
over(hexc('#1D5B6E'), cov(np.abs(dc) - 0.0085 * TH))
# thin inner membrane highlight
over(hexc('#E9FAFC'), cov(np.abs(dc + 0.019) - 0.0028) * 0.7 * (LV < 0.02))

# spindle fibres between the nuclei
for off in (() if SMALL else (-0.022, 0.0, 0.022)):
    pts = []
    for j in range(24):
        s = j / 23
        lx = -sep * 0.62 + s * sep * 1.24
        ly = off * math.sin(s * math.pi) * 1.3
        pts.append(to_world(lx, ly))
    polyline(pts, 0.0024, hexc('#4D86A8'), 0.55)

# nuclei
for ox in (-sep * 0.62, sep * 0.62):
    nx, ny = to_world(ox, 0.004)
    dn = np.hypot(U - nx, V - ny) - 0.052 * Z
    over(hexc('#79A6D3'), cov(dn) * 0.92)
    over(hexc('#9CC0E3'), cov(np.hypot(U - nx + 0.012, V - ny + 0.014) - 0.024) * 0.6)
    over(hexc('#3E6E9F'), cov(np.abs(dn) - 0.0045 * TH) * 0.9)

# organelles
orgs = [(-sep - 0.06, -0.075, 0.020, '#6CC24A'), (-sep + 0.02, 0.09, 0.015, '#F08A3A'),
        (-sep - 0.095, 0.045, 0.012, '#E870A2'),
        (sep + 0.07, -0.06, 0.017, '#F08A3A'), (sep + 0.035, 0.088, 0.020, '#6CC24A'),
        (sep + 0.11, 0.035, 0.012, '#2FB9B0'), (-sep - 0.02, -0.11, 0.010, '#2FB9B0')]
for (lx, ly, r, c) in orgs:
    wx, wy = to_world(lx, ly)
    if SMALL and r < 0.016:
        continue
    do = np.hypot(U - wx, V - wy) - r * Z * (1.25 if SMALL else 1.0)
    col = hexc(c)
    over(col, cov(do) * 0.9)
    over(col * 0.62, cov(np.abs(do) - 0.0028) * 0.8)

# ---- out ------------------------------------------------------------------
a = img[..., 3:4]
rgb = np.where(a > 1e-6, img[..., :3] / np.maximum(a, 1e-6), 0)
out = np.concatenate([rgb, a], -1)
im = Image.fromarray((np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8), 'RGBA')
im = im.resize((1024, 1024), Image.LANCZOS)
im.save(OUT)
print('saved', OUT)
