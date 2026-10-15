#!/usr/bin/env python3
"""palette-fix: make a wallust palette safe to use as a terminal / UI theme.

Wallust picks colours by how prominent they are in the wallpaper, so a slot can
come out as a dark brown that is unreadable on the background, the "white" slot
can come out darker than "black" (soft palettes), and the bright row can just be
a copy of the normal row. This script keeps every colour's HUE and only adjusts
lightness / chroma where a profile says it must:

  background    lightness (and chroma) capped, so gray wallpapers can't give a
                washed-out background that drags every contrast down
  foreground    lifted until it reaches `fg_contrast`
  colour 1-6    chroma scaled / floored / capped, lightness lifted until the
                colour reaches `accent_contrast` against the background
  colour 0/7/8/15   repaired (inverted soft palettes are rebuilt from bg / fg)
  colour 9-14   derived as a lighter copy when wallust gave an identical row
  cursor        lifted until it reaches `cursor_contrast`

Colours that already satisfy their profile are passed through byte-for-byte.
The one exception is `hue_shift`: a profile that sets it rotates every colour
(background and grays included) around the colour wheel first, so the same
wallpaper gives a different mood while keeping the colours distinct from each
other. The fixes above then run on the rotated palette.

Works on the dark-background palettes only: the background is always capped to
`bg_max_l`, so light wallpapers still produce a dark theme.

usage: palette-fix.py --in raw.json --out fixed.json [--profile NAME]
                      [--profiles FILE] [--report]
Input / output is either the flat quickshell format
  {"background": "#..", "foreground": "#..", "color0": "#..", ...}
or the pywal format wallust's `cs` subcommand reads
  {"special": {"background", "foreground", "cursor"}, "colors": {"color0": ..}}
The output has the same shape as the input.
"""
import argparse
import json
import math
import os
import sys

# ------------------------------------------------------------------ profiles

DEFAULTS = {
    # background
    "bg_max_l": 24.0,       # cap on the background's CIE L*
    "bg_max_c": 40.0,       # cap on the background's chroma
    # foreground
    "fg_contrast": 7.0,     # min WCAG contrast of fg against bg
    "fg_max_l": 96.0,
    # accents (colour1-6)
    "accent_contrast": 5.5, # min contrast against the background
    "accent_min_l": 0.0,    # hard lightness floor
    "accent_max_l": 92.0,   # lightness ceiling
    "chroma_scale": 1.0,    # multiply chroma
    "chroma_min": 0.0,      # chroma floor (not applied to near-gray colours)
    "chroma_max": 100.0,    # chroma ceiling
    "neutral_c": 6.0,       # below this chroma a colour counts as gray
    "spread": 0.0,          # min L* gap between accents (0 = off)
    "hue_shift": 0.0,       # rotate every colour's hue by this many degrees
    # bright row (9-14)
    "bright_step": 8.0,     # lightness added when the row has to be derived
    "bright_chroma_scale": 1.0,
    "bright_min_step": 4.0, # wallust's own bright colour must beat normal by this
    # neutrals
    "black_offset": 10.0,   # colour0 sits this far above the background (L*)
    "white_contrast": 6.0,  # colour7
    "dim_contrast": 4.5,    # colour8 (comments, autosuggestions)
    "cursor_contrast": 4.5,
}

SLOTS = ["color%d" % i for i in range(16)]


# --------------------------------------------------------------- colour math

_XN, _YN, _ZN = 0.95047, 1.0, 1.08883
_EPS = 216.0 / 24389.0
_KAPPA = 24389.0 / 27.0


def _to_lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _from_lin(c):
    c = max(0.0, min(1.0, c))
    return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def norm_hex(h):
    h = str(h).strip().lstrip("#")
    if len(h) == 8:  # drop alpha
        h = h[:6]
    if len(h) != 6:
        raise ValueError("not a #RRGGBB colour: %r" % h)
    int(h, 16)
    return "#" + h.upper()


def _rgb(h):
    h = norm_hex(h)[1:]
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def hex_to_lch(h):
    r, g, b = (_to_lin(c) for c in _rgb(h))
    x = 0.4124564 * r + 0.3575761 * g + 0.1804375 * b
    y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
    z = 0.0193339 * r + 0.1191920 * g + 0.9503041 * b

    def f(t):
        return t ** (1.0 / 3.0) if t > _EPS else (_KAPPA * t + 16.0) / 116.0

    fx, fy, fz = f(x / _XN), f(y / _YN), f(z / _ZN)
    lightness = 116.0 * fy - 16.0
    a, bb = 500.0 * (fx - fy), 200.0 * (fy - fz)
    return lightness, math.hypot(a, bb), math.degrees(math.atan2(bb, a)) % 360.0


def _lch_to_lin(lightness, chroma, hue):
    a = chroma * math.cos(math.radians(hue))
    bb = chroma * math.sin(math.radians(hue))
    fy = (lightness + 16.0) / 116.0
    fx, fz = fy + a / 500.0, fy - bb / 200.0

    def finv(t):
        return t ** 3 if t ** 3 > _EPS else (116.0 * t - 16.0) / _KAPPA

    x = _XN * finv(fx)
    z = _ZN * finv(fz)
    y = _YN * (fy ** 3 if lightness > _KAPPA * _EPS else lightness / _KAPPA)
    return (3.2404542 * x - 1.5371385 * y - 0.4985314 * z,
            -0.9692660 * x + 1.8760108 * y + 0.0415560 * z,
            0.0556434 * x - 0.2040259 * y + 1.0572252 * z)


def _in_gamut(lin):
    return all(-1e-4 <= c <= 1.0 + 1e-4 for c in lin)


def lch_to_hex(lightness, chroma, hue):
    """CIE LCh -> #RRGGBB. Out-of-gamut colours lose chroma, never hue."""
    lightness = max(0.0, min(100.0, lightness))
    chroma = max(0.0, chroma)
    lin = _lch_to_lin(lightness, chroma, hue)
    if not _in_gamut(lin):
        lo, hi = 0.0, chroma
        for _ in range(24):
            mid = (lo + hi) / 2.0
            if _in_gamut(_lch_to_lin(lightness, mid, hue)):
                lo = mid
            else:
                hi = mid
        lin = _lch_to_lin(lightness, lo, hue)
    return "#%02X%02X%02X" % tuple(int(round(_from_lin(c) * 255)) for c in lin)


def luminance(h):
    r, g, b = (_to_lin(c) for c in _rgb(h))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(h1, h2):
    a, b = luminance(h1), luminance(h2)
    if a < b:
        a, b = b, a
    return (a + 0.05) / (b + 0.05)


# ------------------------------------------------------------------- fixing

def lift_to_contrast(h, bg, target, max_l):
    """Raise lightness (hue and chroma kept) until contrast >= target."""
    if contrast(h, bg) >= target:
        return h
    lightness, chroma, hue = hex_to_lch(h)
    while lightness < max_l:
        lightness += 0.5
        cand = lch_to_hex(lightness, chroma, hue)
        if contrast(cand, bg) >= target:
            return cand
    return lch_to_hex(max_l, chroma, hue)


def fix_accent(h, bg, p):
    lightness, chroma, hue = hex_to_lch(h)
    c2 = chroma * p["chroma_scale"]
    if chroma >= p["neutral_c"]:
        c2 = max(c2, p["chroma_min"])
    c2 = min(c2, p["chroma_max"])

    l2 = max(lightness, p["accent_min_l"])
    cand = lch_to_hex(l2, c2, hue)
    while contrast(cand, bg) < p["accent_contrast"] and l2 < p["accent_max_l"]:
        l2 += 0.5
        cand = lch_to_hex(l2, c2, hue)
    l2 = min(l2, p["accent_max_l"])

    if abs(l2 - lightness) < 0.5 and abs(c2 - chroma) < 0.5:
        return norm_hex(h)  # already fine: keep the exact original
    return lch_to_hex(l2, c2, hue)


def derive_bright(h, p):
    lightness, chroma, hue = hex_to_lch(h)
    return lch_to_hex(min(95.0, lightness + p["bright_step"]),
                      chroma * p["bright_chroma_scale"], hue)


def shift_hue(hex_colour, degrees):
    """Rotate a colour's hue, keeping L* and chroma. Grays stay as they are."""
    lightness, chroma, hue = hex_to_lch(hex_colour)
    if chroma < 1.0:
        return hex_colour
    return lch_to_hex(lightness, chroma, (hue + degrees) % 360.0)


def spread_accents(slots, p):
    """Keep accents distinguishable: at least `spread` L* apart."""
    gap = p["spread"]
    if gap <= 0:
        return slots
    order = sorted(slots, key=lambda k: hex_to_lch(slots[k])[0])
    prev = None
    for k in order:
        lightness, chroma, hue = hex_to_lch(slots[k])
        if prev is not None and lightness < prev + gap:
            lightness = min(p["accent_max_l"], prev + gap)
            slots[k] = lch_to_hex(lightness, chroma, hue)
        prev = lightness
    return slots


def fix_palette(pal, p):
    """pal: flat dict of '#RRGGBB'. Returns a new flat dict."""
    out = {k: norm_hex(v) for k, v in pal.items() if k in SLOTS + ["background", "foreground", "cursor"]}
    if p["hue_shift"]:
        out = {k: shift_hue(v, p["hue_shift"]) for k, v in out.items()}

    # background
    bl, bc, bh = hex_to_lch(out["background"])
    if bl > p["bg_max_l"] or bc > p["bg_max_c"]:
        out["background"] = lch_to_hex(min(bl, p["bg_max_l"]), min(bc, p["bg_max_c"]), bh)
    bg = out["background"]
    bl, bc, bh = hex_to_lch(bg)

    # foreground
    out["foreground"] = lift_to_contrast(out["foreground"], bg, p["fg_contrast"], p["fg_max_l"])
    fl, fc, fh = hex_to_lch(out["foreground"])

    # accents 1-6
    raw = dict(out)
    accents = {}
    for i in range(1, 7):
        accents["color%d" % i] = fix_accent(raw["color%d" % i], bg, p)
    accents = spread_accents(accents, p)
    out.update(accents)

    # neutrals 0 / 7 / 8 / 15
    c0, c7 = raw["color0"], raw["color7"]
    inverted = hex_to_lch(c0)[0] > hex_to_lch(c7)[0] - 5
    if inverted:
        out["color0"] = lch_to_hex(bl + p["black_offset"], min(bc, 10.0), bh)
        c7 = lch_to_hex(max(fl - 8.0, 40.0), min(fc, 8.0), fh)
        c8 = lch_to_hex(max(fl - 26.0, bl + p["black_offset"] + 14.0), min(fc, 8.0), fh)
    else:
        l0 = hex_to_lch(c0)[0]
        out["color0"] = c0 if l0 >= bl + 4.0 else lch_to_hex(bl + 4.0, hex_to_lch(c0)[1], hex_to_lch(c0)[2])
        c8 = raw["color8"]
    c7 = lift_to_contrast(c7, bg, p["white_contrast"], p["fg_max_l"])
    c8 = lift_to_contrast(c8, bg, p["dim_contrast"], p["fg_max_l"])
    l7, l8 = hex_to_lch(c7)[0], hex_to_lch(c8)[0]
    if l8 > l7 - 3.0:  # bright black must stay below white
        c7 = lch_to_hex(l8 + 4.0, hex_to_lch(c7)[1], hex_to_lch(c7)[2])
    out["color7"], out["color8"] = c7, c8
    l7, c7c, h7 = hex_to_lch(c7)
    raw15 = raw["color15"]
    if raw15 != raw["color7"] and not inverted and hex_to_lch(raw15)[0] >= l7 + 3.0:
        out["color15"] = lift_to_contrast(raw15, bg, p["fg_contrast"], 97.0)
    else:
        out["color15"] = lch_to_hex(min(97.0, max(l7 + p["bright_step"], fl)), min(c7c, fc), fh)

    # bright row 9-14
    for i in range(1, 7):
        n, rb = out["color%d" % i], raw["color%d" % (i + 8)]
        if rb == raw["color%d" % i]:
            out["color%d" % (i + 8)] = derive_bright(n, p)
            continue
        b = fix_accent(rb, bg, p)
        if hex_to_lch(b)[0] < hex_to_lch(n)[0] + p["bright_min_step"]:
            b = derive_bright(n, p)
        out["color%d" % (i + 8)] = b

    # cursor
    if "cursor" in out:
        out["cursor"] = lift_to_contrast(out["cursor"], bg, p["cursor_contrast"], p["fg_max_l"])
    return out


# ----------------------------------------------------------------------- io

def load_profile(path, name):
    prof = dict(DEFAULTS)
    note = None
    data = {}
    if path and os.path.isfile(path):
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    prof.update({k: v for k, v in data.get("default", {}).items() if not k.startswith("_")})
    if name and name != "default":
        if name in data:
            prof.update({k: v for k, v in data[name].items() if not k.startswith("_")})
        else:
            note = "no profile %r in %s, using 'default'" % (name, path)
    unknown = [k for k in prof if k not in DEFAULTS]
    if unknown:
        raise ValueError("unknown profile key(s): %s" % ", ".join(unknown))
    return prof, note


def read_palette(path):
    fh = sys.stdin if path in (None, "-") else open(path, encoding="utf-8")
    with fh:
        data = json.load(fh)
    if "colors" in data and "special" in data:
        flat = dict(data["colors"])
        flat.update({k: v for k, v in data["special"].items()})
        return data, flat, "pywal"
    return data, {k: v for k, v in data.items() if isinstance(v, str)}, "flat"


def build_output(data, fixed, shape):
    out = json.loads(json.dumps(data))
    if shape == "pywal":
        for k in ("background", "foreground", "cursor"):
            if k in fixed:
                out["special"][k] = fixed[k]
        for k in SLOTS:
            out["colors"][k] = fixed[k]
    else:
        for k, v in fixed.items():
            out[k] = v
    return out


def report(before, after, profile_name):
    bg_b, bg_a = before["background"], after["background"]
    lines = ["palette-fix  profile=%s" % profile_name,
             "%-11s %-8s %5s %5s %6s   %-8s %5s %5s %6s" %
             ("slot", "before", "L*", "C*", "ctr", "after", "L*", "C*", "ctr")]
    for k in ["background", "foreground"] + SLOTS + (["cursor"] if "cursor" in after else []):
        b, a = before[k], after[k]
        lb, cb, _ = hex_to_lch(b)
        la, ca, _ = hex_to_lch(a)
        ctr_b = "" if k == "background" else "%.1f" % contrast(b, bg_b)
        ctr_a = "" if k == "background" else "%.1f" % contrast(a, bg_a)
        mark = "" if norm_hex(b) == a else "  *"
        lines.append("%-11s %-8s %5.0f %5.0f %6s   %-8s %5.0f %5.0f %6s%s" %
                     (k, norm_hex(b)[1:], lb, cb, ctr_b, a[1:], la, ca, ctr_a, mark))
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(description="Fix a wallust palette for readability.")
    ap.add_argument("--in", dest="inp", default="-", help="input JSON (default: stdin)")
    ap.add_argument("--out", default="-", help="output JSON (default: stdout)")
    ap.add_argument("--profile", default="default")
    ap.add_argument("--profiles", default=os.path.join(
        os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")), "wallust", "palette-fix.json"))
    ap.add_argument("--report", action="store_true", help="print a before/after table to stderr")
    args = ap.parse_args()

    try:
        prof, note = load_profile(args.profiles, args.profile)
        data, flat, shape = read_palette(args.inp)
        missing = [k for k in ["background", "foreground"] + SLOTS if k not in flat]
        if missing:
            raise ValueError("palette is missing: %s" % ", ".join(missing))
        fixed = fix_palette(flat, prof)
    except (ValueError, KeyError, OSError, json.JSONDecodeError) as e:
        print("palette-fix: %s" % e, file=sys.stderr)
        return 2

    if note:
        print("palette-fix: " + note, file=sys.stderr)
    if args.report:
        print(report({k: norm_hex(v) for k, v in flat.items() if k in fixed}, fixed, args.profile), file=sys.stderr)

    text = json.dumps(build_output(data, fixed, shape), indent=2) + "\n"
    if args.out in (None, "-"):
        sys.stdout.write(text)
    else:
        tmp = args.out + ".tmp%d" % os.getpid()
        with open(tmp, "w", encoding="utf-8") as fh:
            fh.write(text)
        os.replace(tmp, args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
