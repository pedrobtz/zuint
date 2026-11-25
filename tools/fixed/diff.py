#!/usr/bin/env python3
"""Random fixed-point cases with Python's decimal's answers (design 2.2).

    python3 tools/fixed/diff.py N SEED | tools/fixed/fixed diff

Writes N tab-separated cases, one per line, for `fixed diff`: parse,
format, rescale, to and from double, compare, and the 128-bit arithmetic.
The answers come from decimal at 100 digits and from Python's exact
integers, written from DuckDB 2.0.0's rules as design 2.2 states them,
weighted to the edges: 10^p - 1, 10^p, +-(2^127 - 1) and the halfway
points.

Text cases have no exponent. With one, DuckDB refuses some texts whose
value fits (design 2.2), which only its own state machine knows; the R
tests compare those with DuckDB itself.
"""

import decimal
import random
import struct
import sys

D = decimal.Decimal
CTX = decimal.Context(prec=100, rounding=decimal.ROUND_HALF_UP, Emax=999999, Emin=-999999)
decimal.setcontext(CTX)

I128_MIN, I128_MAX = -(2 ** 127), 2 ** 127 - 1
SPACES = " \t\n\v\f\r"


def pick_type(r):
    p = r.choice([1, 2, 4, 5, 9, 10, 18, 19, 20, 37, 38, r.randint(1, 38)])
    s = r.choice([0, p, max(p - 1, 0), p // 2, r.randint(0, p)])
    return p, s


def coef(r, p):
    """A coefficient below 10^p, weighted to the edges."""
    top = 10 ** p - 1
    k = r.random()
    if k < 0.1:
        c = top
    elif k < 0.15:
        c = top - 1
    elif k < 0.25:
        j = r.randint(1, p)
        c = r.randint(0, 10 ** (p - j) - 1) * 10 ** j + 5 * 10 ** (j - 1)
        c = min(c, top)
    elif k < 0.3:
        c = r.randint(0, 9)
    else:
        c = r.randint(0, top)
    return -c if r.random() < 0.5 else c


def half_away(q):
    """q (a Decimal) rounded half away from zero to an integer."""
    return int(q.to_integral_value(rounding=decimal.ROUND_HALF_UP))


def fmt(c, p, s):
    """DuckDB's DecimalToString."""
    neg, m = c < 0, abs(c)
    if s == 0:
        return ("-" if neg else "") + str(m)
    q, f = divmod(m, 10 ** s)
    whole = "" if (q == 0 and p == s) else str(q)
    return ("-" if neg else "") + whole + "." + str(f).rjust(s, "0")


def underscore(r, digits):
    if len(digits) >= 2 and r.random() < 0.15:
        k = r.randint(1, len(digits) - 1)
        return digits[:k] + "_" + digits[k:]
    return digits


def case_parse(r):
    p, s = pick_type(r)
    ni = r.randint(0, p - s + 2)
    nf = r.randint(0, s + 3)
    if ni == 0 and nf == 0:
        ni = 1
    int_digits = "".join(r.choice("0123456789") for _ in range(ni))
    if r.random() < 0.2:
        int_digits = "9" * ni
    frac = "".join(r.choice("0123456789") for _ in range(nf))
    if nf and r.random() < 0.25:
        frac = frac[:-1] + "5"
    lead = "0" * r.choice([0, 0, 0, 1, 3])
    neg = r.random() < 0.4
    sign = "-" if neg else ("+" if r.random() < 0.1 else "")
    point = "." if (frac or r.random() < 0.1) else ""
    body = underscore(r, lead + int_digits) + point + underscore(r, frac)
    if body in (".",):
        body = "0."
    text = "".join(r.choice(SPACES) for _ in range(r.choice([0, 0, 1, 2]))) + sign + body
    text += "".join(r.choice(SPACES) for _ in range(r.choice([0, 0, 1])))
    # DuckDB: the integer digits, leading zeros aside, must fit p - s; then
    # the value rounded half away from zero must be below 10^p
    sig_int = (lead + int_digits).lstrip("0")
    value = D((lead + int_digits or "0") + "." + (frac or "0"))
    c = half_away(value.scaleb(s))
    if neg:
        c = -c
    ok = len(sig_int) <= p - s and abs(c) < 10 ** p
    return ["parse", str(p), str(s), text.encode().hex(), str(c) if ok else "ERR"]


def case_format(r):
    p, s = pick_type(r)
    c = coef(r, p)
    if r.random() < 0.05:
        return ["format", str(p), str(s), str(10 ** p), "ERR"]
    return ["format", str(p), str(s), str(c), fmt(c, p, s)]


def case_rescale(r):
    p, s = pick_type(r)
    p2, s2 = pick_type(r)
    c = coef(r, p)
    q = half_away(D(c).scaleb(s2 - s))
    return ["rescale", str(s), str(p2), str(s2), str(c), str(q) if abs(q) < 10 ** p2 else "ERR"]


def to_double(c, p, s):
    if s == 0 and p > 18:
        # DuckDB's CastBigintToFloating<double>: the two words as doubles
        hi, lo = c >> 64, c & (2 ** 64 - 1)
        if hi == -1:
            return -float(2 ** 64 - 1 - lo) - 1.0
        return float(lo) + float(hi) * 18446744073709551616.0
    return c / 10 ** s  # int / int is correctly rounded


def bits(x):
    return struct.unpack("<Q", struct.pack("<d", x))[0]


def case_todouble(r):
    p, s = pick_type(r)
    c = coef(r, p)
    return ["todouble", str(p), str(s), str(c), "%016x" % bits(to_double(c, p, s))]


def case_fromdouble(r):
    p, s = pick_type(r)
    k = r.random()
    if k < 0.4:
        x = (r.randint(-(10 ** min(p, 15)), 10 ** min(p, 15)) + 0.5) / float("1e%d" % s)
    elif k < 0.8:
        x = r.uniform(-1, 1) * float("1e%d" % (p - s))
    elif k < 0.9:
        x = r.uniform(-1, 1) * float("1e%d" % (p - s + 1))
    else:
        x = r.choice([0.125, 2.675, 1.005, -0.0, 5e-324, float("1e%d" % (p - s)), float("nan"), float("inf")])
    if x != x or x in (float("inf"), float("-inf")):
        return ["fromdouble", str(p), str(s), "%016x" % bits(x), "INV"]
    v = x * float("1e%d" % s)  # DuckDB: input * DOUBLE_POWERS_OF_TEN[scale]
    if v != v or v in (float("inf"), float("-inf")):
        want = "ERR"
    else:
        rv = half_away(D(v))  # round(), exactly
        lim = float("1e%d" % p)
        want = "ERR" if (rv <= -lim or rv >= lim) else str(rv)
    return ["fromdouble", str(p), str(s), "%016x" % bits(x), want]


def case_compare(r):
    sa, sb = r.randint(0, 38), r.randint(0, 38)
    a = coef(r, 38)
    b = a * 10 ** (sb - sa) if (r.random() < 0.2 and sb >= sa and abs(a * 10 ** (sb - sa)) < 10 ** 38) else coef(r, 38)
    va, vb = D(a).scaleb(-sa), D(b).scaleb(-sb)
    return ["compare", str(sa), str(sb), str(a), str(b), str((va > vb) - (va < vb))]


def i128(r):
    k = r.random()
    if k < 0.2:
        return r.choice([I128_MAX, -I128_MAX, I128_MAX - 1, 0, 1, -1, 2 ** 64, -(2 ** 64), 2 ** 63])
    return r.randint(-I128_MAX, I128_MAX)


def case_arith(r):
    op = r.choice(["add", "sub", "mul"])
    a = i128(r)
    b = i128(r) if op != "mul" else (i128(r) >> r.randint(0, 127))
    v = a + b if op == "add" else a - b if op == "sub" else a * b
    if v == I128_MIN:
        return None  # valid to the table, but the driver's reader stops short of it
    return [op, str(a), str(b), str(v) if I128_MIN <= v <= I128_MAX else "ERR"]


CASES = [case_parse, case_parse, case_format, case_rescale, case_todouble, case_fromdouble, case_compare, case_arith]


def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 10000
    r = random.Random(int(sys.argv[2]) if len(sys.argv) > 2 else 1)
    out = sys.stdout
    written = 0
    while written < n:
        row = r.choice(CASES)(r)
        if row is None:
            continue
        out.write("\t".join(row) + "\n")
        written += 1


if __name__ == "__main__":
    main()
