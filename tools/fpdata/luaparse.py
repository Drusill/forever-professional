"""Minimal parser for Lua table constructors, enough for addon data files.

Supports: nested tables, `key = value`, `[expr] = value`, positional values, strings
('..', "..", [[..]]), numbers (int, float, hex), true/false/nil, comments (-- and --[[ ]]),
and dotted identifiers such as `ns.L.FACTION_2758`, which are returned as ``Ref`` objects.
Tables become ``dict`` when they have keys, ``list`` when purely positional; a mixed table
becomes a dict with integer keys for the positional values.
"""
import re


class LuaParseError(ValueError):
    pass


class Ref(str):
    """A bare identifier reference (e.g. ``ns.L.FACTION_2758``)."""


_NUM = re.compile(r"0[xX][0-9a-fA-F]+|(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?")
_IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*")
_ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", '"': '"', "'": "'", "\n": "\n", "0": "\0"}


class _Parser:
    def __init__(self, text, pos=0):
        self.s = text
        self.i = pos

    def error(self, msg):
        line = self.s.count("\n", 0, self.i) + 1
        raise LuaParseError("%s at line %d" % (msg, line))

    def skip(self):
        s, n = self.s, len(self.s)
        while self.i < n:
            c = s[self.i]
            if c in " \t\r\n,;":
                self.i += 1
            elif s.startswith("--", self.i):
                m = re.compile(r"--\[(=*)\[").match(s, self.i)
                if m:
                    end = s.find("]" + m.group(1) + "]", m.end())
                    self.i = n if end < 0 else end + len(m.group(1)) + 2
                else:
                    end = s.find("\n", self.i)
                    self.i = n if end < 0 else end + 1
            else:
                break

    def value(self):
        self.skip()
        s = self.s
        if self.i >= len(s):
            self.error("unexpected end of input")
        c = s[self.i]
        if c == "{":
            return self.table()
        if c in "\"'":
            return self.string(c)
        if s.startswith("[[", self.i) or re.compile(r"\[=+\[").match(s, self.i):
            return self.long_string()
        if c == "-" or c.isdigit() or (c == "." and self.i + 1 < len(s) and s[self.i + 1].isdigit()):
            neg = c == "-"
            if neg:
                self.i += 1
            m = _NUM.match(s, self.i)
            if not m:
                self.error("bad number")
            self.i = m.end()
            txt = m.group(0)
            v = int(txt, 16) if txt.lower().startswith("0x") else (float(txt) if any(ch in txt for ch in ".eE") else int(txt))
            return -v if neg else v
        m = _IDENT.match(s, self.i)
        if m:
            self.i = m.end()
            word = m.group(0)
            if word == "true":
                return True
            if word == "false":
                return False
            if word == "nil":
                return None
            return Ref(word)
        self.error("unexpected character %r" % c)

    def string(self, q):
        s = self.s
        self.i += 1
        out = []
        while True:
            if self.i >= len(s):
                self.error("unterminated string")
            c = s[self.i]
            if c == q:
                self.i += 1
                return "".join(out)
            if c == "\\":
                nxt = s[self.i + 1]
                if nxt.isdigit():
                    m = re.compile(r"\d{1,3}").match(s, self.i + 1)
                    out.append(chr(int(m.group(0))))
                    self.i = m.end()
                    continue
                out.append(_ESCAPES.get(nxt, nxt))
                self.i += 2
                continue
            out.append(c)
            self.i += 1

    def long_string(self):
        m = re.compile(r"\[(=*)\[").match(self.s, self.i)
        close = "]" + m.group(1) + "]"
        end = self.s.find(close, m.end())
        if end < 0:
            self.error("unterminated long string")
        text = self.s[m.end():end]
        self.i = end + len(close)
        return text[1:] if text.startswith("\n") else text

    def table(self):
        self.i += 1  # {
        keyed, positional = {}, []
        while True:
            self.skip()
            if self.i >= len(self.s):
                self.error("unterminated table")
            if self.s[self.i] == "}":
                self.i += 1
                break
            m = re.compile(r"([A-Za-z_][A-Za-z0-9_]*)\s*=(?!=)").match(self.s, self.i)
            if m:
                self.i = m.end()
                keyed[m.group(1)] = self.value()
                continue
            if self.s[self.i] == "[" and not self.s.startswith("[[", self.i) and not re.compile(r"\[=+\[").match(self.s, self.i):
                self.i += 1
                key = self.value()
                self.skip()
                if not self.s.startswith("]", self.i):
                    self.error("expected ]")
                self.i += 1
                self.skip()
                if not self.s.startswith("=", self.i):
                    self.error("expected =")
                self.i += 1
                keyed[key] = self.value()
                continue
            positional.append(self.value())
        if not keyed:
            return positional
        for n, v in enumerate(positional, 1):
            keyed.setdefault(n, v)
        return keyed


def parse_value(text, pos=0):
    """Parse one Lua value starting at ``pos``. Returns (value, end_position)."""
    p = _Parser(text, pos)
    v = p.value()
    return v, p.i


def find_assignments(text, pattern):
    """Yield (match, value) for each ``<pattern> = <table>`` assignment in ``text``.

    ``pattern`` is a regex for the left-hand side; its groups are available on the match.
    """
    for m in re.finditer(pattern + r"\s*=\s*(?=\{)", text):
        value, _ = parse_value(text, m.end())
        yield m, value
