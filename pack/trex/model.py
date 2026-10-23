import numpy as np
import numpy as np, struct, sys


# ---------- SDF primitives (mm; x forward, y left, z up) ----------
def ellipsoid(P, c, r):
    X, Y, Z = P
    q = [(X - c[0]) / r[0], (Y - c[1]) / r[1], (Z - c[2]) / r[2]]
    k = np.sqrt(q[0]**2 + q[1]**2 + q[2]**2)
    return (k - 1.0) * min(r)

def capsule(P, a, b, ra, rb):
    X, Y, Z = P
    a = np.array(a, float); b = np.array(b, float)
    ba = b - a; L2 = ba @ ba
    px, py, pz = X - a[0], Y - a[1], Z - a[2]
    t = np.clip((px*ba[0] + py*ba[1] + pz*ba[2]) / L2, 0, 1)
    dx, dy, dz = px - t*ba[0], py - t*ba[1], pz - t*ba[2]
    return np.sqrt(dx*dx + dy*dy + dz*dz) - (ra + (rb - ra) * t)

def chain(P, pts, rads):
    d = None
    for i in range(len(pts) - 1):
        c = capsule(P, pts[i], pts[i+1], rads[i], rads[i+1])
        d = c if d is None else smin(d, c, 2.0)
    return d

def sphere(P, c, r):
    X, Y, Z = P
    return np.sqrt((X-c[0])**2 + (Y-c[1])**2 + (Z-c[2])**2) - r

def boxy(P, c, r, p):
    # ellipsoid along x, squarish (superellipse) cross-section in y/z
    X, Y, Z = P
    qx = ((X - c[0]) / r[0])**2
    qyz = ((np.abs(Y - c[1]) / r[1])**p + (np.abs(Z - c[2]) / r[2])**p) ** (2.0 / p)
    return (np.sqrt(qx + qyz) - 1.0) * min(r)

def smin(a, b, k):
    h = np.clip(0.5 + 0.5*(b - a)/k, 0, 1)
    return b*(1-h) + a*h - k*h*(1-h)

def smax(a, b, k):
    return -smin(-a, -b, k)

def base(P):
    X, Y, Z = P
    rx, ry = 76.0, 40.0
    e = np.sqrt(((X + 32)/rx)**2 + (Y/ry)**2)
    d2 = (e - 1.0) * ry
    dz = np.abs(Z - 3.0) - 3.0
    outside = np.sqrt(np.maximum(d2, 0)**2 + np.maximum(dz, 0)**2)
    return outside + np.minimum(np.maximum(d2, dz), 0)

def leg(P, s, dx):
    y = 15.0 * s
    hip   = (-6 + dx, y, 62)
    knee  = (10 + dx, y + 3*s, 38)
    ankle = (-3 + dx, y + 2*s, 16)
    foot  = (6 + dx, y + 1*s, 9.2)
    thigh = capsule(P, hip, knee, 15.0, 9.0)
    shin  = capsule(P, knee, ankle, 9.0, 6.2)
    meta  = capsule(P, ankle, foot, 5.6, 4.4)
    d = smin(smin(thigh, shin, 4.0), meta, 2.5)
    fy = y + 1*s
    for ty, tx in ((0, 16), (5.5, 13), (-5.5, 13)):
        toe = capsule(P, foot, (foot[0] + tx, fy + ty*s, 8.8), 3.9, 2.6)
        d = smin(d, toe, 1.8)
    d = smin(d, capsule(P, foot, (foot[0] - 8, fy, 8.6), 3.3, 2.2), 1.8)
    return d

def arm(P, s):
    y = 13.0 * s
    sh = np.array((19.0, y, 82.0)); el = np.array((24.0, y + 9.5*s, 65.5)); wr = np.array((35.0, y + 7.0*s, 56.5))
    d = smin(capsule(P, sh, el, 6.6, 4.8), capsule(P, el, wr, 5.0, 3.6), 1.8)
    d = smin(d, sphere(P, (20.0, y + 1.2*s, 81.5), 7.6), 2.0)                # big rounded shoulder
    d = smin(d, ellipsoid(P, (24.0, y + 5.4*s, 74.5), (5.6, 5.0, 7.0)), 2.0)  # bicep
    d = smin(d, ellipsoid(P, (19.4, y + 6.0*s, 72.5), (3.8, 4.2, 6.0)), 1.6)  # tricep
    d = smin(d, ellipsoid(P, (28.0, y + 8.6*s, 62.5), (6.0, 4.8, 4.6)), 1.8)  # forearm bulk
    X, Y, Z = P
    # fingers: two big hooked claws + a smaller third
    # fingers curled into grasping hooks: knuckle reaches forward, then long talons hook down and back
    for dy, ln, r0 in ((2.6, 7.5, 2.3), (-2.2, 7.0, 2.1), (5.6, 4.8, 1.6)):
        base_ = wr + np.array((0, dy*s, 0))
        k1 = wr + np.array((0.85, 0, -0.30))*ln*0.55 + np.array((0, dy*1.3*s, 0))
        k2 = k1 + np.array((0.35, 0, -0.94))*ln*0.32
        c1 = k2 + np.array((0.08, 0, -1.0))*ln*0.45
        c2 = c1 + np.array((-0.62, 0, -0.5))*ln*0.30
        d = smin(d, capsule(P, base_, k1, r0, r0*0.78), 0.9)
        d = smin(d, capsule(P, k1, k2, r0*0.78, r0*0.6), 0.6)
        d = smin(d, capsule(P, k2, c1, r0*0.55, r0*0.34), 0.3)        # talon
        d = smin(d, capsule(P, c1, c2, r0*0.34, 0.2), 0.2)            # hooked claw tip
    # jagged spikes along the outer (elbow) edge of the forearm, raked toward the elbow
    t = (wr - el)[[0, 2]]; t = t / np.linalg.norm(t); n = np.array((t[1], -t[0]))
    if n[1] > 0: n = -n
    L = np.linalg.norm((wr - el)[[0, 2]])
    for fr, h, b in ((0.12, 5.5, 4.2), (0.38, 6.8, 4.6), (0.62, 5.8, 4.2), (0.84, 4.0, 3.4)):
        c = el[[0, 2]] + t*L*fr
        rad = 5.0 + (3.6 - 5.0)*fr
        o = c + n*(rad - 1.5)
        rx, rz = X - o[0], Z - o[1]
        u = rx*t[0] + rz*t[1]; v = rx*n[0] + rz*n[1]
        dd = sd_tri2(u, v, (-b/2, 0.0), (b/2, 0.0), (-h*0.55, h))
        thick = 0.9 + np.clip(1 - v/h, 0, 1) * 2.6
        d = smin(d, np.maximum(dd, np.abs(Y - (y + 8.6*s)) - thick/2), 0.6)
    return d

# ---------- menacing head: tilted up, jaws open, teeth, squinting eyes ----------
HEAD_PIVOT = (24.0, 104.0); HEAD_UP = np.radians(12)
JAW_HINGE = (27.0, 104.0); JAW_OPEN = np.radians(26)

def _rot(P, piv, ang):
    X, Y, Z = P
    dx, dz = X - piv[0], Z - piv[1]
    c, s = np.cos(ang), np.sin(ang)
    return (piv[0] + c*dx - s*dz, Y, piv[1] + s*dx + c*dz)

def _upper(P):
    skull = boxy(P, (35, 0, 113), (23, 12, 13), 3.2)
    snout = boxy(P, (51, 0, 109), (13, 8.5, 8.5), 4.0)
    return smin(skull, snout, 5)

def _jaw(P):
    return boxy(P, (42, 0, 101), (18.5, 9.5, 5.5), 3.6)

def _edge(fun, x, y, z0, z1, lowest):
    zs = np.linspace(z0, z1, 801)
    v = fun((np.full_like(zs, x), np.full_like(zs, y), zs))
    ins = np.nonzero(v < 0)[0]
    if len(ins) == 0: return None
    return zs[ins[0]] if lowest else zs[ins[-1]]

PALATE = 102.6; TONGUE_FLOOR = 105.2; MOUTH_W = 7.0
def _teeth_layout():
    up, lo = [], []
    for x, y, ln in ((33, 6.3, 3.0), (37, 6.3, 3.6), (41, 6.3, 4.2), (45, 6.2, 5.8), (49, 6.1, 4.4),
                     (52.5, 5.8, 4.0), (55.5, 5.0, 4.6), (57.5, 3.4, 3.6), (58.5, 1.4, 3.0)):
        for s in (1, -1):
            u = _edge(_upper, x, y*s, 95, 120, True)
            if u is None: continue
            zb = min(u, PALATE) + 1.2
            up.append(((x, y*s, zb), (x + 0.6, y*s*0.97, zb - 1.2 - ln), 1.25 if ln < 5 else 1.5))
    for x, y, ln in ((35, 6.6, 2.8), (39, 6.6, 3.4), (43, 6.6, 4.0), (47, 6.5, 5.2), (51, 6.3, 3.8),
                     (54.5, 5.6, 3.6), (57, 4.2, 3.2), (58.5, 1.8, 2.8)):
        for s in (1, -1):
            t = _edge(_jaw, x, y*s, 95, 110, False)
            if t is None: continue
            zb = min(t, TONGUE_FLOOR) - 1.0
            lo.append(((x, y*s, zb), (x + 0.4, y*s*0.96, zb + 1.0 + ln), 1.15 if ln < 5 else 1.4))
    return up, lo
UP_TEETH, LO_TEETH = _teeth_layout()

def head(P):
    Ph = _rot(P, HEAD_PIVOT, -HEAD_UP)            # head frame
    Pj = _rot(Ph, JAW_HINGE, JAW_OPEN)            # jaw frame
    Xh, Yh, Zh = Ph; Xj, Yj, Zj = Pj
    h = smin(_upper(Ph), _jaw(Pj), 3)
    # mouth cavity
    cav = np.maximum.reduce([Zh - PALATE, TONGUE_FLOOR - Zj, np.abs(Yh) - MOUTH_W, 31 - Xh])
    h = smax(h, -cav, 0.8)
    # tongue
    h = smin(h, ellipsoid(Pj, (41, 0, TONGUE_FLOOR + 0.2), (12, 4.6, 1.6)), 1.0)
    for a, b, r in UP_TEETH:
        h = smin(h, capsule(Ph, a, b, r, 0.22), 0.3)
    for a, b, r in LO_TEETH:
        h = smin(h, capsule(Pj, a, b, r, 0.22), 0.3)
    for s in (1, -1):
        # deep, narrow eye sockets
        h = smax(h, -sphere(Ph, (55.6, 6.6*s, 117.4), 3.2), 1.1)
        h = smin(h, sphere(Ph, (51.9, 6.6*s, 117.3), 2.4), 0.3)
        # heavy angry lid/brow sloping down toward the nose (squint)
        h = smin(h, capsule(Ph, (49.2, 8.6*s, 120.3), (55.0, 3.8*s, 118.7), 1.3, 1.2), 1.8)
        # lower lid narrows the eye from below
        h = smin(h, capsule(Ph, (51.5, 8.4*s, 115.0), (54.9, 4.6*s, 115.3), 0.8, 0.75), 1.2)
        # flared nostrils
        h = smax(h, -ellipsoid(Ph, (63.0, 2.9*s, 111.4), (1.4, 1.6, 1.0)), 0.3)
        # snarl creases across the top of the snout
        for cx in (57.2, 59.6):
            h = smax(h, -capsule(Ph, (cx, 1.0*s, 117.2 - (cx - 57)*0.55), (cx - 0.6, 4.8*s, 116.2 - (cx - 57)*0.55), 0.45, 0.3), 0.3)
    return h

def trex(P):
    # torso tilted ~45 degrees up from hips to chest
    d = capsule(P, (-8, 0, 62), (13, 0, 86), 21, 17)
    d = smin(d, capsule(P, (-2, 0, 60), (10, 0, 74), 18, 16), 6)   # belly
    tail = chain(P, [(-16, 0, 60), (-40, 0, 44), (-58, 0, 27), (-72, 0, 15), (-86, 0, 11), (-98, 0, 15), (-106, 0, 28), (-109, 0, 44), (-107, 0, 58), (-103, 0, 66)],
                 [18, 15, 12.5, 10.5, 9.0, 8.0, 6.5, 5.0, 3.5, 2.0])
    d = smin(d, tail, 9)
    d = smin(d, capsule(P, (14, 0, 88), (23, 0, 106), 14, 12), 7)    # neck
    d = smin(d, head(P), 6)
    d = smin(d, leg(P, 1, 5), 10)
    d = smin(d, leg(P, -1, -5), 10)
    d = smin(d, arm(P, 1), 1.5)
    d = smin(d, arm(P, -1), 1.5)
    d = smin(d, base(P), 2.0)
    return d

# ---------- jagged dorsal spikes ----------
def sd_tri2(px, py, A, B, C):
    # exact 2D triangle SDF (vectorized)
    def seg(px, py, a, b):
        ex, ey = b[0]-a[0], b[1]-a[1]; wx, wy = px-a[0], py-a[1]
        t = np.clip((wx*ex + wy*ey)/(ex*ex+ey*ey), 0, 1)
        dx, dy = wx-ex*t, wy-ey*t
        return dx*dx+dy*dy, ex*wy - ey*wx
    d0, c0 = seg(px, py, A, B); d1, c1 = seg(px, py, B, C); d2, c2 = seg(px, py, C, A)
    d = np.sqrt(np.minimum(np.minimum(d0, d1), d2))
    s = (np.sign(c0) == np.sign(c1)) & (np.sign(c1) == np.sign(c2))
    return np.where(s, -d, d)

body = trex
def _surf(p, n):
    # march from centerline outward until we leave the body
    for k in np.arange(0, 40, 0.1):
        q = p + n*k
        if body((np.array([q[0]]), np.array([0.0]), np.array([q[1]])))[0] > 0: return q
    return p

SPINE = [(22,108),(12,88),(-10,63),(-40,44),(-58,27),(-72,15),(-86,11),(-98,15),(-106,28),(-109,44),(-107,58),(-104,64)]
_PF = ([0.0, 0.12, 0.3, 0.5, 0.65, 0.8, 0.92, 1.0], [0.35, 0.75, 1.0, 0.8, 0.6, 0.45, 0.32, 0.2])

def _spine_frame(s, pts, cum, seglen):
    j = int(min(max(np.searchsorted(cum, s) - 1, 0), len(seglen) - 1)); f = (s - cum[j]) / seglen[j]
    c = pts[j] + f*(pts[j+1] - pts[j])
    # smooth tangent: blend neighbouring segment directions near joints
    t0 = (pts[j+1] - pts[j]) / seglen[j]
    if f > 0.5 and j + 1 < len(seglen):
        t1 = (pts[j+2] - pts[j+1]) / seglen[j+1]; w = (f - 0.5)
    elif f < 0.5 and j > 0:
        t1 = (pts[j] - pts[j-1]) / seglen[j-1]; w = (0.5 - f)
    else:
        t1 = t0; w = 0
    t = t0*(1 - w) + t1*w; t /= np.linalg.norm(t)
    return c, t

def _build_fins():
    pts = np.array(SPINE, float)
    seglen = np.linalg.norm(np.diff(pts, axis=0), axis=1); cum = np.r_[0, np.cumsum(seglen)]
    L = cum[-1]; rng = np.random.default_rng(11)
    fins = []
    rows = [(0.0, 34, 1.0, 0.0), (1, 27, 0.62, 0.5), (-1, 27, 0.62, 0.5)]   # (side, count, height scale, phase)
    for side, N, hs, ph in rows:
        for i in range(N):
            fr = (i + 0.5 + ph*0.5) / N
            s = fr * L * 0.985
            c, t = _spine_frame(s, pts, cum, seglen)
            n = np.array([t[1], -t[0]])                      # dorsal side
            prof = np.interp(fr, *_PF)
            o2 = _surf(c, n)
            ang = np.radians(38) * side                      # side rows lean outward
            t3 = np.array([t[0], 0.0, t[1]]); n3 = np.array([n[0], 0.0, n[1]])
            nn = np.cos(ang)*n3 + np.array([0, np.sin(ang), 0])
            w3 = np.cross(t3, nn)
            o = np.array([o2[0], 0.0, o2[1]]) - n3*2.5 + np.array([0, 3.5*side, 0])
            h = (8 + 15*prof) * hs * (1 + rng.uniform(-0.18, 0.18)) * (1.12 if i % 2 == 0 else 0.9)
            b = min(L / N * 2.1, 6 + 9*prof)
            sweep = h * rng.uniform(0.25, 0.45)
            fins.append((o, t3, nn, w3, h, b, sweep, rng.uniform(0.25, 0.4), rng.uniform(0.55, 0.7)))
    return fins
FINS = _build_fins()

def _fin(u, v, w, h, b, sweep, f1, f2):
    A = (-b/2, 0.0); B = (b/2, 0.0); C = (sweep, h)
    dd = sd_tri2(u, v, A, B, C)
    BC = np.array(C) - np.array(B); e = BC / np.linalg.norm(BC); out = np.array([e[1], -e[0]])
    for fr, sz in ((f1, 0.42), (f2, 0.3)):
        Q1 = np.array(B) + BC*(fr - 0.14); Q2 = np.array(B) + BC*(fr + 0.04)
        tip = Q1 + (out*0.75 + e*0.9) * sz * h
        dd = np.minimum(dd, sd_tri2(u, v, tuple(Q1), tuple(Q2), tuple(tip)))
    CA = np.array(A) - np.array(C); e2 = CA / np.linalg.norm(CA); out2 = np.array([e2[1], -e2[0]])
    Q1 = np.array(C) + CA*0.42; Q2 = np.array(C) + CA*0.58
    tip = Q1 + (out2*0.8 - e2*0.6) * 0.22 * h
    dd = np.minimum(dd, sd_tri2(u, v, tuple(Q1), tuple(Q2), tuple(tip)))
    thick = 0.9 + np.clip(1 - v/h, 0, 1)**1.2 * min(5.5, 0.45*b)
    return np.maximum(dd, np.abs(w) - thick/2)

def fins(P):
    X, Y, Z = P; d = None
    for o, t3, nn, w3, h, b, sweep, f1, f2 in FINS:
        rx, ry, rz = X - o[0], Y - o[1], Z - o[2]
        # cheap bounding check: skip points far from this fin
        r = np.sqrt(rx*rx + ry*ry + rz*rz)
        R = h + b + sweep
        u = rx*t3[0] + ry*t3[1] + rz*t3[2]
        v = rx*nn[0] + ry*nn[1] + rz*nn[2]
        w = rx*w3[0] + ry*w3[1] + rz*w3[2]
        fd = _fin(u, v, w, h, b, sweep, f1, f2)
        fd = np.where(r > R + 3, np.maximum(fd, r - R), fd)
        d = fd if d is None else np.minimum(d, fd)
    return d

def trex(P):
    return smin(body(P), fins(P), 1.2)


# ---------- scale texture (3D cellular grooves) ----------
def _hash3(ix, iy, iz, seed):
    h = (ix.astype(np.uint64) * np.uint64(73856093)) ^ (iy.astype(np.uint64) * np.uint64(19349663)) ^ (iz.astype(np.uint64) * np.uint64(83492791)) ^ np.uint64(seed)
    h ^= h >> np.uint64(13); h *= np.uint64(0x5bd1e995); h ^= h >> np.uint64(15)
    return (h & np.uint64(0xFFFFFF)).astype(np.float64) / float(0xFFFFFF)

def worley_edge(X, Y, Z, c):
    px, py, pz = X / c, Y / c, Z / c
    cx, cy, cz = np.floor(px).astype(np.int64), np.floor(py).astype(np.int64), np.floor(pz).astype(np.int64)
    F1 = np.full(X.shape, 9.0); F2 = np.full(X.shape, 9.0)
    for ox in (-1, 0, 1):
        for oy in (-1, 0, 1):
            for oz in (-1, 0, 1):
                nx_, ny_, nz_ = cx + ox, cy + oy, cz + oz
                fx = nx_ + 0.1 + 0.8*_hash3(nx_, ny_, nz_, 1)
                fy = ny_ + 0.1 + 0.8*_hash3(nx_, ny_, nz_, 2)
                fz = nz_ + 0.1 + 0.8*_hash3(nx_, ny_, nz_, 3)
                dd = np.sqrt((px-fx)**2 + (py-fy)**2 + (pz-fz)**2)
                F2 = np.where(dd < F1, F1, np.minimum(F2, dd)); F1 = np.minimum(F1, dd)
    return (F2 - F1) * c, F1 * c   # distance to nearest cell border (approx, mm), distance to scale centre

SCALE_MM = 5.0; GROOVE_W = 0.75; GROOVE_D = 0.6; DOME = 0.5
def scaly_body(P):
    d = body(P)
    X, Y, Z = P
    band = np.abs(d) < 1.6
    if band.any():
        xb, yb, zb = X[band], Y[band], Z[band]
        # finer scales on the arms and head, bigger plates on the back and thighs
        c = np.where((xb > 14) & (zb < 100), SCALE_MM*0.75, SCALE_MM)
        e1, f1 = worley_edge(xb, yb, zb, SCALE_MM*0.75); e2, f2 = worley_edge(xb, yb, zb, SCALE_MM)
        fine = c < SCALE_MM
        edge = np.where(fine, e1, e2); cen = np.where(fine, f1, f2); cc = c
        g = np.clip(1 - edge / (GROOVE_W * (cc / SCALE_MM)), 0, 1)
        g = g*g*(3 - 2*g)
        disp = GROOVE_D * (cc / SCALE_MM) * g + DOME * np.clip(cen / (0.62*cc), 0, 1)**2
        mask = np.clip((zb - 7.0) / 3.0, 0, 1)        # keep the base smooth
        out = d.copy(); out[band] = d[band] + disp * mask
        return out
    return d

def trex(P):
    return smin(body(P), fins(P), 1.2)
