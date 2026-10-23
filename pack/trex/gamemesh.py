"""Turns the T-Rex SDF model into separate, animatable game meshes for the lofi room kaiju.
Writes kaiju_parts.npz: per part positions/normals/colors/indices in Godot coordinates (x forward, y up, z right),
relative to that part's pivot, plus the pivots. Spikes and teeth are explicit low-poly geometry."""
import numpy as np, sys
sys.path.insert(0, ".")
import model as M
from model import capsule, sphere, ellipsoid, smin, smax, boxy, sd_tri2

K = 1.0 / 125.0            # mm -> game units (about 1 unit tall)
XOFF = 20.5                # puts the head's middle near x = 0.5, where kaiju.gd expects it
GROUND = 6.0               # the 3D-print base top = the street


def to_g(p):               # model mm (x fwd, y left, z up) -> Godot (x fwd, y up, z right)
    p = np.asarray(p, float)
    return np.stack([(p[..., 0] + XOFF) * K, (p[..., 2] - GROUND) * K, -p[..., 1] * K], -1)


def vec_g(v):
    v = np.asarray(v, float)
    return np.stack([v[..., 0], v[..., 2], -v[..., 1]], -1)


# ---------------- part SDFs (rest pose, world mm) ----------------
LEG_DX = {1: 5, -1: -5}

def hip(s):   return np.array((-6 + LEG_DX[s], 15.0 * s, 62.0))
def knee(s):  return np.array((10 + LEG_DX[s], 15.0 * s + 3 * s, 38.0))

def body_sdf(P):
    X, Y, Z = P
    d = capsule(P, (-8, 0, 62), (13, 0, 86), 21, 17)
    d = smin(d, capsule(P, (-2, 0, 60), (10, 0, 74), 18, 16), 6)
    tail = M.chain(P, [(-16, 0, 60), (-40, 0, 44), (-58, 0, 27), (-72, 0, 15), (-86, 0, 11), (-98, 0, 15), (-106, 0, 28), (-109, 0, 44), (-107, 0, 58), (-103, 0, 66)],
                   [18, 15, 12.5, 10.5, 9.0, 8.0, 6.5, 5.0, 3.5, 2.0])
    d = smin(d, tail, 9)
    d = smin(d, capsule(P, (14, 0, 88), (23, 0, 106), 14, 12), 7)
    for s in (1, -1):                                  # hip flesh that the thighs swing inside
        d = smin(d, sphere(P, hip(s) + np.array((2, 0, -2)), 13.5), 8)
    return smax(d, GROUND - Z, 1.0)                    # tail rests flat on the street

def thigh_sdf(P, s):
    return capsule(P, hip(s), knee(s), 15.0, 9.0)

def shin_sdf(P, s):
    dx = LEG_DX[s]; y = 15.0 * s
    k = knee(s); ankle = (-3 + dx, y + 2 * s, 16); foot = (6 + dx, y + 1 * s, 9.2)
    d = smin(capsule(P, k, ankle, 9.0, 6.2), capsule(P, ankle, foot, 5.6, 4.4), 2.5)
    fy = y + 1 * s
    for ty, tx in ((0, 16), (5.5, 13), (-5.5, 13)):
        d = smin(d, capsule(P, foot, (foot[0] + tx, fy + ty * s, 8.8), 3.9, 2.6), 1.8)
    d = smin(d, capsule(P, foot, (foot[0] - 8, fy, 8.6), 3.3, 2.2), 1.8)
    return smin(d, sphere(P, k, 9.5), 2.0)             # rounded knee so it bends cleanly

SHOULDER = {s: np.array((19.0, 13.0 * s, 82.0)) for s in (1, -1)}
def arm_sdf(P, s):
    y = 13.0 * s
    sh = np.array((19.0, y, 82.0)); el = np.array((24.0, y + 9.5 * s, 65.5)); wr = np.array((35.0, y + 7.0 * s, 56.5))
    d = smin(capsule(P, sh, el, 6.6, 4.8), capsule(P, el, wr, 5.0, 3.6), 1.8)
    d = smin(d, sphere(P, (20.0, y + 1.2 * s, 81.5), 7.6), 2.0)
    d = smin(d, ellipsoid(P, (24.0, y + 5.4 * s, 74.5), (5.6, 5.0, 7.0)), 2.0)
    d = smin(d, ellipsoid(P, (19.4, y + 6.0 * s, 72.5), (3.8, 4.2, 6.0)), 1.6)
    d = smin(d, ellipsoid(P, (28.0, y + 8.6 * s, 62.5), (6.0, 4.8, 4.6)), 1.8)
    for dy, ln, r0 in ((2.6, 7.5, 2.3), (-2.2, 7.0, 2.1), (5.6, 4.8, 1.6)):
        base_ = wr + np.array((0, dy * s, 0))
        k1 = wr + np.array((0.85, 0, -0.30)) * ln * 0.55 + np.array((0, dy * 1.3 * s, 0))
        k2 = k1 + np.array((0.35, 0, -0.94)) * ln * 0.32
        c1 = k2 + np.array((0.08, 0, -1.0)) * ln * 0.45
        c2 = c1 + np.array((-0.62, 0, -0.5)) * ln * 0.30
        d = smin(d, capsule(P, base_, k1, r0, r0 * 0.78), 0.9)
        d = smin(d, capsule(P, k1, k2, r0 * 0.78, r0 * 0.6), 0.6)
        d = smin(d, capsule(P, k2, c1, r0 * 0.55, max(r0 * 0.34, 0.6)), 0.3)
        d = smin(d, capsule(P, c1, c2, max(r0 * 0.34, 0.6), 0.45), 0.2)
    return d

def _frames(P):
    Ph = M._rot(P, M.HEAD_PIVOT, -M.HEAD_UP)
    Pj = M._rot(Ph, M.JAW_HINGE, M.JAW_OPEN)
    return Ph, Pj

def _cav(Ph, Pj):
    Xh, Yh, Zh = Ph; Xj, Yj, Zj = Pj
    return np.maximum.reduce([Zh - M.PALATE, M.TONGUE_FLOOR - Zj, np.abs(Yh) - M.MOUTH_W, 31 - Xh])

def head_sdf(P):
    Ph, Pj = _frames(P)
    h = smax(M._upper(Ph), -_cav(Ph, Pj), 0.8)
    for s in (1, -1):
        h = smax(h, -sphere(Ph, (55.6, 6.6 * s, 117.4), 3.2), 1.1)
        h = smin(h, sphere(Ph, (51.9, 6.6 * s, 117.3), 2.4), 0.3)
        h = smin(h, capsule(Ph, (49.2, 8.6 * s, 120.3), (55.0, 3.8 * s, 118.7), 1.3, 1.2), 1.8)
        h = smin(h, capsule(Ph, (51.5, 8.4 * s, 115.0), (54.9, 4.6 * s, 115.3), 0.8, 0.75), 1.2)
        h = smax(h, -ellipsoid(Ph, (63.0, 2.9 * s, 111.4), (1.4, 1.6, 1.0)), 0.3)
        for cx in (57.2, 59.6):
            h = smax(h, -capsule(Ph, (cx, 1.0 * s, 117.2 - (cx - 57) * 0.55), (cx - 0.6, 4.8 * s, 116.2 - (cx - 57) * 0.55), 0.45, 0.3), 0.3)
    return h

def jaw_sdf(P):
    Ph, Pj = _frames(P)
    j = smax(M._jaw(Pj), -_cav(Ph, Pj), 0.8)
    return smin(j, ellipsoid(Pj, (41, 0, M.TONGUE_FLOOR + 0.2), (12, 4.6, 1.6)), 1.0)

def jaw_sdf_tongue(P):   # tongue separately, so it gets its own colour
    Ph, Pj = _frames(P)
    return ellipsoid(Pj, (41, 0, M.TONGUE_FLOOR + 0.2), (12, 4.6, 1.6))

def jaw_sdf_bone(P):
    Ph, Pj = _frames(P)
    return smax(M._jaw(Pj), -_cav(Ph, Pj), 0.8)


def head_to_world(p):    # head frame -> world
    X, Y, Z = M._rot((np.array([p[0]]), np.array([p[1]]), np.array([p[2]])), M.HEAD_PIVOT, M.HEAD_UP)
    return np.array([X[0], Y[0], Z[0]])

def jaw_to_world(p):
    X, Y, Z = M._rot((np.array([p[0]]), np.array([p[1]]), np.array([p[2]])), M.JAW_HINGE, -M.JAW_OPEN)
    return head_to_world((X[0], Y[0], Z[0]))

HEAD_PIV = np.array((M.HEAD_PIVOT[0], 0.0, M.HEAD_PIVOT[1]))
JAW_PIV = head_to_world((M.JAW_HINGE[0], 0.0, M.JAW_HINGE[1]))


# ---------------- surface nets mesher ----------------
def mesh_sdf(f, lo, hi, h):
    xs = np.arange(lo[0], hi[0] + h, h); ys = np.arange(lo[1], hi[1] + h, h); zs = np.arange(lo[2], hi[2] + h, h)
    nx, ny, nz = len(xs), len(ys), len(zs)
    F = np.empty((nx, ny, nz))
    YY, ZZ = np.meshgrid(ys, zs, indexing="ij")
    for i, x in enumerate(xs):
        F[i] = f((np.full_like(YY, x), YY, ZZ))
    F[F == 0] = 1e-7
    S = np.zeros((nx - 1, ny - 1, nz - 1, 3)); C = np.zeros((nx - 1, ny - 1, nz - 1))
    grid = (xs, ys, zs)
    # accumulate edge crossings into the cells that share each edge
    for ax in range(3):
        a = [slice(None)] * 3; b = [slice(None)] * 3
        a[ax] = slice(0, -1); b[ax] = slice(1, None)
        fa, fb = F[tuple(a)], F[tuple(b)]
        cross = (fa < 0) != (fb < 0)
        t = np.where(cross, fa / (fa - fb + 1e-30), 0)
        idx = np.nonzero(cross)
        tt = t[idx]
        pos = np.stack([grid[0][idx[0]], grid[1][idx[1]], grid[2][idx[2]]], 1).astype(float)
        pos[:, ax] += tt * h
        others = [o for o in range(3) if o != ax]
        for d0 in (0, -1):
            for d1 in (0, -1):
                ci = [idx[0].copy(), idx[1].copy(), idx[2].copy()]
                ci[others[0]] += d0; ci[others[1]] += d1
                ok = (ci[others[0]] >= 0) & (ci[others[0]] < F.shape[others[0]] - 1) & (ci[others[1]] >= 0) & (ci[others[1]] < F.shape[others[1]] - 1)
                c3 = tuple(c[ok] for c in ci)
                np.add.at(S, c3, pos[ok]); np.add.at(C, c3, 1)
    active = C > 0
    vid = -np.ones(C.shape, np.int64); vid[active] = np.arange(active.sum())
    V = S[active] / C[active][:, None]
    quads = []
    for ax in range(3):
        a = [slice(None)] * 3; b = [slice(None)] * 3
        a[ax] = slice(0, -1); b[ax] = slice(1, None)
        fa, fb = F[tuple(a)], F[tuple(b)]
        cross = (fa < 0) != (fb < 0)
        idx = np.array(np.nonzero(cross))
        o0, o1 = [o for o in range(3) if o != ax]
        keep = (idx[o0] >= 1) & (idx[o0] < F.shape[o0] - 1) & (idx[o1] >= 1) & (idx[o1] < F.shape[o1] - 1)
        idx = idx[:, keep]
        inside_low = fa[tuple(idx)] < 0
        cyc = [(-1, -1), (0, -1), (0, 0), (-1, 0)]
        q = []
        for d0, d1 in cyc:
            ci = idx.copy(); ci[o0] += d0; ci[o1] += d1
            ci[ax] = np.minimum(ci[ax], F.shape[ax] - 2)
            q.append(vid[ci[0], ci[1], ci[2]])
        q = np.stack(q, 1)
        q[~inside_low] = q[~inside_low][:, ::-1]
        quads.append(q)
    Q = np.concatenate(quads)
    Q = Q[(Q >= 0).all(1)]
    # split each quad along its shorter diagonal
    d02 = np.linalg.norm(V[Q[:, 0]] - V[Q[:, 2]], axis=1); d13 = np.linalg.norm(V[Q[:, 1]] - V[Q[:, 3]], axis=1)
    use02 = d02 <= d13
    T = np.concatenate([np.where(use02[:, None], Q[:, [0, 1, 2]], Q[:, [0, 1, 3]]), np.where(use02[:, None], Q[:, [0, 2, 3]], Q[:, [1, 2, 3]])])
    # smooth normals from the field gradient; fix any triangle that faces inward
    e = h * 0.5; N = np.zeros_like(V)
    for k in range(3):
        dp = np.zeros(3); dp[k] = e
        a = V + dp; b = V - dp
        N[:, k] = f((a[:, 0], a[:, 1], a[:, 2])) - f((b[:, 0], b[:, 1], b[:, 2]))
    N /= np.linalg.norm(N, axis=1, keepdims=True) + 1e-12
    fn = np.cross(V[T[:, 1]] - V[T[:, 0]], V[T[:, 2]] - V[T[:, 0]])
    flip = (fn * N[T].mean(1)).sum(1) < 0
    T[flip] = T[flip][:, ::-1]
    return V, N, T


# ---------------- explicit pieces ----------------
def wedge(o, tu, tv, tw, tri2, thick_fn, col_fn):
    """A flat triangle in the (u, v) plane at o, given thickness across w. Returns flat-shaded verts/normals/colors/tris."""
    V, N, Cc, T = [], [], [], []
    p = [np.array(o) + tu * u + tv * v for u, v in tri2]
    th = [thick_fn(v) * 0.5 for _, v in tri2]
    top = [p[i] + tw * th[i] for i in range(3)]; bot = [p[i] - tw * th[i] for i in range(3)]
    cols = [col_fn(v) for _, v in tri2]
    faces = [((top[0], top[1], top[2]), (cols[0], cols[1], cols[2])), ((bot[0], bot[2], bot[1]), (cols[0], cols[2], cols[1]))]
    for i in range(3):
        j = (i + 1) % 3
        faces.append(((top[i], bot[i], bot[j]), (cols[i], cols[i], cols[j])))
        faces.append(((top[i], bot[j], top[j]), (cols[i], cols[j], cols[j])))
    for (a, b, c), (ca, cb, cc) in faces:
        n = np.cross(b - a, c - a); ln = np.linalg.norm(n)
        if ln < 1e-12: continue
        n = n / ln
        # make it face away from the blade's middle
        mid = np.mean(p, 0)
        if np.dot(n, (a + b + c) / 3 - mid) < 0:
            b, c = c, b; cb, cc = cc, cb; n = -n
        base = len(V)
        V += [a, b, c]; N += [n, n, n]; Cc += [ca, cb, cc]; T.append((base, base + 1, base + 2))
    return V, N, Cc, T

DEEP = np.array((0.05, 0.28, 0.75)); PALE = np.array((0.62, 0.92, 1.0))

def fin_geometry():
    V, N, Cc, T = [], [], [], []
    for o, t3, nn, w3, h, b, sweep, f1, f2 in M.FINS:
        A = (-b / 2, 0.0); B = (b / 2, 0.0); C = (sweep, h)
        tris = [(A, B, C)]
        BC = np.array(C) - np.array(B); e = BC / np.linalg.norm(BC); out = np.array([e[1], -e[0]])
        for fr, sz in ((f1, 0.42), (f2, 0.3)):
            Q1 = np.array(B) + BC * (fr - 0.14); Q2 = np.array(B) + BC * (fr + 0.04)
            tip = Q1 + (out * 0.75 + e * 0.9) * sz * h
            tris.append((tuple(Q1), tuple(Q2), tuple(tip)))
        CA = np.array(A) - np.array(C); e2 = CA / np.linalg.norm(CA); out2 = np.array([e2[1], -e2[0]])
        Q1 = np.array(C) + CA * 0.42; Q2 = np.array(C) + CA * 0.58
        tip = Q1 + (out2 * 0.8 - e2 * 0.6) * 0.22 * h
        tris.append((tuple(Q1), tuple(Q2), tuple(tip)))
        thick = lambda v, h=h, b=b: 0.9 + np.clip(1 - v / h, 0, 1) ** 1.2 * min(5.5, 0.45 * b)
        col = lambda v, h=h: DEEP * (1 - np.clip(v / (h * 0.9), 0, 1)) + PALE * np.clip(v / (h * 0.9), 0, 1)
        for tri in tris:
            v_, n_, c_, t_ = wedge(o, t3, nn, w3, tri, thick, col)
            base = len(V); V += v_; N += n_; Cc += c_; T += [(a + base, b_ + base, c + base) for a, b_, c in t_]
    return np.array(V), np.array(N), np.array(Cc), np.array(T)

def forearm_spikes(s):
    V, N, Cc, T = [], [], [], []
    y = 13.0 * s
    el = np.array((24.0, y + 9.5 * s, 65.5)); wr = np.array((35.0, y + 7.0 * s, 56.5))
    t = (wr - el)[[0, 2]]; t = t / np.linalg.norm(t); n = np.array((t[1], -t[0]))
    if n[1] > 0: n = -n
    L = np.linalg.norm((wr - el)[[0, 2]])
    tu = np.array((t[0], 0, t[1])); tv = np.array((n[0], 0, n[1])); tw = np.array((0, 1.0, 0))
    for fr, h, b in ((0.12, 5.5, 4.2), (0.38, 6.8, 4.6), (0.62, 5.8, 4.2), (0.84, 4.0, 3.4)):
        c = el[[0, 2]] + t * L * fr
        rad = 5.0 + (3.6 - 5.0) * fr
        o2 = c + n * (rad - 1.5)
        o = np.array((o2[0], y + 8.6 * s, o2[1]))
        tri = ((-b / 2, 0.0), (b / 2, 0.0), (-h * 0.55, h))
        thick = lambda v, h=h: 0.9 + np.clip(1 - v / h, 0, 1) * 2.6
        col = lambda v, h=h: DEEP * (1 - np.clip(v / h, 0, 1)) + PALE * np.clip(v / h, 0, 1)
        v_, n_, c_, t_ = wedge(o, tu, tv, tw, tri, thick, col)
        base = len(V); V += v_; N += n_; Cc += c_; T += [(a + base, b_ + base, cc + base) for a, b_, cc in t_]
    return np.array(V), np.array(N), np.array(Cc), np.array(T)

def cone(a, b, r, seg=8):
    a = np.array(a, float); b = np.array(b, float)
    ax = b - a; ax /= np.linalg.norm(ax)
    u = np.cross(ax, (0, 0, 1) if abs(ax[2]) < 0.9 else (1, 0, 0)); u /= np.linalg.norm(u); w = np.cross(ax, u)
    V, N, T = [], [], []
    for k in range(seg):
        a0 = 2 * np.pi * k / seg; a1 = 2 * np.pi * (k + 1) / seg
        p0 = a + r * (np.cos(a0) * u + np.sin(a0) * w); p1 = a + r * (np.cos(a1) * u + np.sin(a1) * w)
        n0 = np.cos(a0) * u + np.sin(a0) * w; n1 = np.cos(a1) * u + np.sin(a1) * w
        base = len(V)
        V += [p0, p1, b]; N += [n0, n1, (n0 + n1) / np.linalg.norm(n0 + n1)]
        T.append((base, base + 1, base + 2))
    return V, N, T

def teeth(which):
    V, N, T = [], [], []
    src = M.UP_TEETH if which == "up" else M.LO_TEETH
    tf = head_to_world if which == "up" else jaw_to_world
    for a, b, r in src:
        v_, n_, t_ = cone(tf(a), tf(b), r)
        # normals live in the same frame as the points: rotate them too
        R = tf(np.array((1.0, 0, 0))) - tf(np.zeros(3)), tf(np.array((0, 1.0, 0))) - tf(np.zeros(3)), tf(np.array((0, 0, 1.0))) - tf(np.zeros(3))
        base = len(V); V += v_; N += n_; T += [(x + base, y + base, z + base) for x, y, z in t_]
    V = np.array(V); N = np.array(N)
    # cone() was built from transformed endpoints, so its normals are already in world space
    return V, N, np.array(T)


# ---------------- build all parts ----------------
def pack(V, N, T, piv, col=None):
    G = to_g(V) - to_g(piv)[None]
    NG = vec_g(N)
    TT = np.array(T)[:, ::-1].copy()               # Godot's front faces are clockwise
    out = {"v": G.astype(np.float32), "n": NG.astype(np.float32), "i": TT.astype(np.int32).ravel()}
    if col is not None:
        out["c"] = np.asarray(col, np.float32)
    return out

if __name__ == "__main__":
    H = float(sys.argv[1]) if len(sys.argv) > 1 else 1.0
    parts = {}
    piv = {}
    ORIGIN = np.array((-XOFF, 0.0, GROUND))
    V, N, T = mesh_sdf(body_sdf, (-125, -32, 3), (40, 32, 125), 1.7 * H); parts["body"] = pack(V, N, T, ORIGIN); piv["body"] = ORIGIN
    fv, fn, fc, ft = fin_geometry(); parts["spikes"] = pack(fv, fn, ft, ORIGIN, fc)
    V, N, T = mesh_sdf(head_sdf, (8, -16, 92), (72, 16, 134), 0.8 * H); parts["head"] = pack(V, N, T, HEAD_PIV); piv["head"] = HEAD_PIV
    tv, tn, tt = teeth("up"); parts["teeth_up"] = pack(tv, tn, tt, HEAD_PIV)
    V, N, T = mesh_sdf(jaw_sdf_bone, (14, -14, 80), (68, 14, 112), 0.8 * H); parts["jaw"] = pack(V, N, T, JAW_PIV); piv["jaw"] = JAW_PIV
    V, N, T = mesh_sdf(jaw_sdf_tongue, (24, -8, 84), (60, 8, 112), 0.9 * H); parts["tongue"] = pack(V, N, T, JAW_PIV)
    tv, tn, tt = teeth("lo"); parts["teeth_lo"] = pack(tv, tn, tt, JAW_PIV)
    for s, nm in ((1, "L"), (-1, "R")):            # model +y is the creature's left
        hp = hip(s); kn = knee(s)
        V, N, T = mesh_sdf(lambda P, s=s: thigh_sdf(P, s), hp + np.array((-20, -20, -38)), hp + np.array((24, 20, 20)), 1.4 * H)
        parts["thigh" + nm] = pack(V, N, T, hp); piv["leg" + nm] = hp
        V, N, T = mesh_sdf(lambda P, s=s: shin_sdf(P, s), kn + np.array((-26, -16, -36)), kn + np.array((30, 16, 12)), 1.1 * H)
        parts["shin" + nm] = pack(V, N, T, kn); piv["knee" + nm] = kn
        sh = SHOULDER[s]
        V, N, T = mesh_sdf(lambda P, s=s: arm_sdf(P, s), sh + np.array((-10, -12 if s > 0 else -24, -36)), sh + np.array((26, 24 if s > 0 else 12, 10)), 1.0 * H)
        parts["arm" + nm] = pack(V, N, T, sh); piv["arm" + nm] = sh
        sv, sn, sc, st = forearm_spikes(s); parts["armspikes" + nm] = pack(sv, sn, st, sh, sc)
    tot = 0
    for k, p in parts.items():
        nt = len(p["i"]) // 3; tot += nt
        print(f"{k:12s} {len(p['v']):7d} verts {nt:7d} tris")
    print("total tris", tot)
    flat = {}
    for k, p in parts.items():
        for a, v in p.items():
            flat[k + "__" + a] = v
    for k, p in piv.items():
        flat["pivot__" + k] = to_g(p).astype(np.float32)
    out = sys.argv[2] if len(sys.argv) > 2 else "kaiju_parts"
    np.savez(out + ".npz", **flat)
    import struct
    with open(out + ".bin", "wb") as fh:
        items = list(parts.items())
        fh.write(struct.pack("<I", len(items)))
        for k, p in items:
            nb = k.encode(); fh.write(struct.pack("<B", len(nb))); fh.write(nb)
            hasc = 1 if "c" in p else 0
            fh.write(struct.pack("<IIB", len(p["v"]), len(p["i"]), hasc))
            fh.write(p["v"].astype("<f4").tobytes()); fh.write(p["n"].astype("<f4").tobytes())
            if hasc: fh.write(p["c"].astype("<f4").tobytes())
            fh.write(p["i"].astype("<i4").tobytes())
        fh.write(struct.pack("<I", len(piv)))
        for k, p in piv.items():
            nb = k.encode(); fh.write(struct.pack("<B", len(nb))); fh.write(nb)
            fh.write(to_g(p).astype("<f4").tobytes())
