"""Authored surface detail for a 'clean' bake (tex_gen.py LOOK key 'panels'): what a machined, finished part carries and the
clean pass dropped together with the AI source paint. Per UV island a finish value of its own (parts are machined and
coated separately), panel seams across the long parts (a dark cut with a lit bevel), screw heads near the corners, brushing
streaks along U, and crisp worn-through edges. Everything is drawn in UV pixel space, so it stays sharp at any texture size.
Own rng (seeded from the model name), so models without 'panels' keep their bytes. No Blender, no Godot: numpy + scipy."""
import numpy as np
from scipy.ndimage import label, binary_erosion, find_objects, gaussian_filter

STEEL = np.array([0.50, 0.485, 0.465], np.float32)
DEFAULTS = {'value': 0.3, 'lines': 2, 'screws': 0.6, 'brush': 0.14, 'wear': 0.7}


def _seams(lab, inner, sl, i, rng, k, n_lines, line, bevel):
    """Up to n_lines seams across island i (bounding box sl): a cut 1.5 px wide at 1024 with a lit bevel beside it."""
    hh, ww = sl[0].stop - sl[0].start, sl[1].stop - sl[1].start
    m = (lab[sl] == i) & inner[sl]
    wpx, along = max(1, int(round(1.5 * k))), ww >= hh
    span = ww if along else hh
    for _ in range(int(rng.integers(0, n_lines + 1)) if span > 60 * k else 0):
        p = int(span * rng.uniform(0.2, 0.8))
        cut = np.zeros_like(m)
        lit = np.zeros_like(m)
        if along:
            cut[:, p:p + wpx], lit[:, p + wpx:p + wpx + max(1, wpx // 2)] = True, True
        else:
            cut[p:p + wpx, :], lit[p + wpx:p + wpx + max(1, wpx // 2), :] = True, True
        line[sl] |= cut & m
        bevel[sl] |= lit & m


def _stamp(r, ang, k):
    """A screw head of radius r px: (dome height 0..1, slot mask), on a square of side 2*ceil(r)+3."""
    yy, xx = np.mgrid[-int(r) - 1:int(r) + 2, -int(r) - 1:int(r) + 2].astype(np.float32)
    d = np.sqrt(yy * yy + xx * xx)
    disc = np.clip(r + 0.5 - d, 0, 1) * np.clip(1 - (d / (r + 0.5)) ** 2, 0.25, 1)
    cut = (np.abs(xx * np.sin(ang) - yy * np.cos(ang)) < 0.45 * k + 0.3) & (d < r - 0.6)
    return disc, cut


def _screws(lab, inner, sl, i, rng, k, head, slot):
    """Screw heads at the inset corners of island i where the whole head lies inside it."""
    hh, ww = sl[0].stop - sl[0].start, sl[1].stop - sl[1].start
    r, inset = 3.0 * k, int(7 * k)
    if min(hh, ww) < 2 * inset + 4 * r:
        return
    disc, cut = _stamp(r, rng.uniform(0, np.pi), k)
    n = disc.shape[0]
    for cy in (sl[0].start + inset, sl[0].stop - inset - 1):
        for cx in (sl[1].start + inset, sl[1].stop - inset - 1):
            y0, x0 = cy - n // 2, cx - n // 2
            if y0 < 0 or x0 < 0 or y0 + n > lab.shape[0] or x0 + n > lab.shape[1]:
                continue
            win = np.s_[y0:y0 + n, x0:x0 + n]
            if not ((lab[win] == i) & inner[win]).all():
                continue
            np.maximum(head[win], disc, out=head[win])
            slot[win] |= cut


def _unit_noise(rng, size, sigma):
    n = gaussian_filter(rng.random((size, size)).astype(np.float32), sigma, mode='wrap')
    return (n - n.mean()) / max(float(n.std()), 1e-6)


def maps(size, seed, cover, edge, spec):
    """The detail layers: (island value multiplier, seam cut, seam bevel, screw head height, screw slot, brushing, wear, spec)."""
    spec = dict(DEFAULTS, **(spec if isinstance(spec, dict) else {}))
    k = size / 1024.0
    rng = np.random.default_rng(seed + 4111)
    lab, n = label(cover)
    # finishes come in a few distinct tones (dark polymer, blued steel, bare/parkerized metal), not a smooth spread
    tone = rng.choice(np.array([1 - spec['value'], 1.0, 1 + 1.2 * spec['value']]), n, p=[0.3, 0.4, 0.3])
    vmul = np.concatenate([[1.0], tone * (1 + 0.08 * (rng.random(n) * 2 - 1))]).astype(np.float32)[lab]
    inner = binary_erosion(cover, iterations=max(1, int(4 * k)))
    line = np.zeros((size, size), bool)
    bevel = np.zeros((size, size), bool)
    head = np.zeros((size, size), np.float32)
    slot = np.zeros((size, size), bool)
    for i, sl in enumerate(find_objects(lab), 1):
        if sl is None:
            continue
        _seams(lab, inner, sl, i, rng, k, spec['lines'], line, bevel)
        if rng.random() < spec['screws']:
            _screws(lab, inner, sl, i, rng, k, head, slot)
    bevel &= ~line
    # brushing: thin streaks along U (row noise smeared far along the row)
    brush = np.clip(_unit_noise(rng, size, (0.5 * k, 24 * k)), -2.5, 2.5)
    # worn-through edges: the baked edge map broken by fine noise, then thresholded so the wear has a hard border
    wear = np.clip((edge * 1.2 + _unit_noise(rng, size, 1.2 * k) * 0.12 - 0.42) * 6, 0, 1) * cover
    return vmul, line.astype(np.float32), bevel.astype(np.float32), head, slot.astype(np.float32), brush, wear * spec['wear'], spec


def apply(alb, rough, h, occl, cover, edge, size, seed, spec):
    """Lays the detail over a blended clean bake (linear albedo, roughness, height, occlusion) and returns the four."""
    vmul, line, bevel, head, slot, brush, wear, spec = maps(size, seed, cover, edge, spec)
    cv = cover.astype(np.float32)
    alb = np.where(cover[..., None], alb * vmul[..., None] * (1 + spec['brush'] * 0.5 * brush[..., None]), alb)
    alb = alb * (1 - 0.7 * line[..., None]) + bevel[..., None] * (alb * 1.0 + 0.06)
    alb = np.where((head > 0)[..., None], (alb * 0.5 + STEEL * 0.25) * (0.7 + 0.5 * head[..., None]), alb) * (1 - 0.8 * slot[..., None])
    alb = alb + (STEEL * (0.85 + 0.05 * brush)[..., None] - alb) * wear[..., None]
    rough = np.clip(rough + 0.15 * line - 0.22 * wear + 0.03 * brush * cv - 0.1 * (head > 0), 0, 1)
    h = h - 0.5 * line + 0.12 * bevel + 0.45 * head - 0.35 * slot + 0.02 * brush * cv - 0.08 * wear
    occl = occl * (1 - 0.5 * line) * (1 - 0.4 * slot)
    return np.clip(alb, 0, 1).astype(np.float32), rough.astype(np.float32), h.astype(np.float32), occl.astype(np.float32)
