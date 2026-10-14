# xhtml/selector.cpy - a CSS selector engine (no `re` needed).
#
#   select(root, "div.item > a[href^='http']:not(.ad)")   -> [Element, ...]
#   select_one(root, css)                                  -> Element | None
#   matches(el, css)                                       -> bool
#
# Supported
#   type  *  #id  .class  [attr]  [attr=v] ~= |= ^= $= *= !=  (optional  i / s  flag)
#   combinators:  descendant ' '   child >   adjacent +   general sibling ~
#   groups:       a, b
#   pseudo-classes:
#     :first-child :last-child :only-child  :first-of-type :last-of-type :only-of-type
#     :nth-child(an+b) :nth-last-child() :nth-of-type() :nth-last-of-type()   (odd/even too)
#     :not(sel, ...)  :is()/:where()/:matches()  :has(sel)  (relative: :has(> a), :has(+ b))
#     :empty :root :scope :checked :disabled :enabled :required :link/:any-link
#     :contains("x", "y") / :-soup-contains()   text of the element contains x or y
#     :contains-own("x") / :-soup-contains-own()  same, but only the element's own text
# Not supported: namespaces (ns|tag), pseudo-elements, :lang(), :nth-child(... of S).
from .core import _walk


class SelectorError(ValueError):
    pass


_ALPHA = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
_DIGITS = "0123456789"
_IDENT_START = _ALPHA + "_-"
_IDENT_CHARS = _ALPHA + _DIGITS + "_-"
_WS = " \t\n\r\f"
_FORM_TAGS = frozenset(["button", "input", "select", "textarea", "optgroup", "option", "fieldset"])
_SIMPLE_PSEUDOS = frozenset([
    "first-child", "last-child", "only-child", "first-of-type", "last-of-type", "only-of-type",
    "empty", "root", "scope", "checked", "disabled", "enabled", "required", "link", "any-link",
])
# State pseudo-classes that can never be true for a static document (they parse, match nothing).
_NEVER_MATCH = frozenset(["hover", "focus", "active", "visited", "target", "focus-within", "focus-visible"])


class Compound:
    def __init__(self):
        self.tag = None         # lower-cased type selector, None / "*" = any
        self.ids = []
        self.classes = []
        self.attrs = []         # (name, op, value, case_insensitive)
        self.pseudos = []       # (name, arg)  arg: parsed structure or None
        self.comb = None        # combinator linking this compound to the previous one
        self.anchor = False     # internal: the implicit scope compound of :has()


class _Parser:
    def __init__(self, s):
        self.s = s
        self.n = len(s)
        self.i = 0

    def error(self, msg):
        raise SelectorError(msg + " at position " + str(self.i) + " in selector " + repr(self.s))

    def skip_ws(self):
        i = self.i
        while i < self.n and self.s[i] in _WS:
            i += 1
        had = i > self.i
        self.i = i
        return had

    def peek(self):
        return self.s[self.i] if self.i < self.n else ""

    def ident(self):
        s = self.s
        i = self.i
        out = []
        while i < self.n:
            ch = s[i]
            if ch in _IDENT_CHARS or ch >= "\u0080":
                out.append(ch)
                i += 1
            elif ch == "\\" and i + 1 < self.n:
                out.append(s[i + 1])
                i += 2
            else:
                break
        if not out:
            self.error("expected an identifier")
        self.i = i
        return "".join(out)

    def quoted(self):
        s = self.s
        q = s[self.i]
        i = self.i + 1
        out = []
        while i < self.n:
            ch = s[i]
            if ch == "\\" and i + 1 < self.n:
                out.append(s[i + 1])
                i += 2
                continue
            if ch == q:
                self.i = i + 1
                return "".join(out)
            out.append(ch)
            i += 1
        self.error("unterminated string")

    # group := complex (',' complex)*
    def group(self, relative=False, in_paren=False):
        out = []
        while True:
            out.append(self.complex(relative))
            self.skip_ws()
            ch = self.peek()
            if ch == ",":
                self.i += 1
                continue
            if ch == "" or (in_paren and ch == ")"):
                break
            self.error("unexpected " + repr(ch))
        return out

    def complex(self, relative):
        parts = []
        self.skip_ws()
        comb = None
        if relative:
            comb = " "
            if self.peek() in (">", "+", "~"):
                comb = self.peek()
                self.i += 1
                self.skip_ws()
        while True:
            comp = self.compound()
            comp.comb = comb
            parts.append(comp)
            had_ws = self.skip_ws()
            ch = self.peek()
            if ch == "" or ch == "," or ch == ")":
                break
            if ch == ">" or ch == "+" or ch == "~":
                comb = ch
                self.i += 1
                self.skip_ws()
            elif had_ws:
                comb = " "
            else:
                self.error("unexpected " + repr(ch))
        if relative:
            anchor = Compound()
            anchor.anchor = True
            parts.insert(0, anchor)
        return parts

    def compound(self):
        c = Compound()
        s = self.s
        got = False
        ch = self.peek()
        if ch == "*":
            c.tag = "*"
            self.i += 1
            got = True
        elif ch != "" and (ch in _IDENT_START or ch >= "\u0080" or ch == "\\"):
            c.tag = self.ident().lower()
            got = True
        while self.i < self.n:
            ch = s[self.i]
            if ch == "#":
                self.i += 1
                c.ids.append(self.ident())
            elif ch == ".":
                self.i += 1
                c.classes.append(self.ident())
            elif ch == "[":
                self.i += 1
                c.attrs.append(self.attribute())
            elif ch == ":":
                self.i += 1
                if self.peek() == ":":
                    self.error("pseudo-elements are not supported")
                c.pseudos.append(self.pseudo())
            else:
                break
            got = True
        if not got:
            self.error("expected a selector")
        return c

    def attribute(self):
        self.skip_ws()
        name = self.ident().lower()
        self.skip_ws()
        ch = self.peek()
        if ch == "]":
            self.i += 1
            return (name, None, None, False)
        op = None
        if ch == "=":
            op = "="
            self.i += 1
        elif ch in ("~", "|", "^", "$", "*", "!") and self.i + 1 < self.n and self.s[self.i + 1] == "=":
            op = ch + "="
            self.i += 2
        else:
            self.error("bad attribute selector")
        self.skip_ws()
        ch = self.peek()
        if ch == '"' or ch == "'":
            value = self.quoted()
        else:
            j = self.i
            while j < self.n and self.s[j] not in _WS and self.s[j] != "]":
                j += 1
            value = self.s[self.i:j]
            self.i = j
        self.skip_ws()
        ci = False
        ch = self.peek()
        if ch == "i" or ch == "I":
            ci = True
            self.i += 1
        elif ch == "s" or ch == "S":
            self.i += 1
        self.skip_ws()
        if self.peek() != "]":
            self.error("expected ]")
        self.i += 1
        return (name, op, value, ci)

    def paren_arg(self):
        """Return the raw text between the parentheses and advance past ')'."""
        s = self.s
        depth = 1
        i = self.i
        start = i
        while i < self.n:
            ch = s[i]
            if ch == "\\":
                i += 2
                continue
            if ch == '"' or ch == "'":
                j = i + 1
                while j < self.n and s[j] != ch:
                    if s[j] == "\\":
                        j += 1
                    j += 1
                i = j + 1
                continue
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
                if depth == 0:
                    self.i = i + 1
                    return s[start:i]
            i += 1
        self.error("unbalanced parentheses")

    def pseudo(self):
        name = self.ident().lower()
        if self.peek() != "(":
            if name in _SIMPLE_PSEUDOS or name in _NEVER_MATCH:
                return (name, None)
            self.error("unsupported pseudo-class :" + name)
        self.i += 1
        raw = self.paren_arg()
        if name in ("nth-child", "nth-last-child", "nth-of-type", "nth-last-of-type"):
            return (name, _parse_nth(raw, self))
        if name in ("not", "is", "where", "matches", "any"):
            sub = _Parser(raw)
            return (name, sub.group())
        if name == "has":
            sub = _Parser(raw)
            return (name, sub.group(relative=True))
        if name in ("contains", "-soup-contains", "contains-own", "-soup-contains-own"):
            return (name, _parse_strings(raw, self))
        self.error("unsupported pseudo-class :" + name + "()")


def _parse_strings(raw, parent):
    sub = _Parser(raw)
    out = []
    while True:
        sub.skip_ws()
        ch = sub.peek()
        if ch == '"' or ch == "'":
            out.append(sub.quoted())
        elif ch == "":
            break
        else:
            j = sub.i
            while j < sub.n and sub.s[j] not in _WS and sub.s[j] != ",":
                j += 1
            out.append(sub.s[sub.i:j])
            sub.i = j
        sub.skip_ws()
        if sub.peek() == ",":
            sub.i += 1
            continue
        if sub.peek() != "":
            parent.error("bad :contains() argument")
        break
    if not out:
        parent.error(":contains() needs an argument")
    return out


def _parse_nth(raw, parser):
    s = raw.strip().lower().replace(" ", "")
    try:
        if s == "odd":
            return (2, 1)
        if s == "even":
            return (2, 0)
        if "n" in s:
            a_part, _, b_part = s.partition("n")
            if a_part == "" or a_part == "+":
                a = 1
            elif a_part == "-":
                a = -1
            else:
                a = int(a_part)
            b = 0 if b_part == "" else int(b_part)
            return (a, b)
        return (0, int(s))
    except ValueError:
        parser.error("bad :nth-*() argument " + repr(raw))


_CACHE = {}


def compile_selector(css):
    """Parse a selector once; the result can be passed to select()/matches()."""
    g = _CACHE.get(css)
    if g is None:
        g = _Parser(css).group()
        if len(_CACHE) > 300:
            _CACHE.clear()
        _CACHE[css] = g
    return g


# ---------------------------------------------------------------------------
# matching
# ---------------------------------------------------------------------------

class _Ctx:
    def __init__(self, scope):
        self.scope = scope
        self.sib = {}       # parent -> (element children, {child: index})
        self.typ = {}       # parent -> {tag: (same-tag children, {child: index})}


def _siblings(ctx, el):
    p = el.parent
    info = ctx.sib.get(p)
    if info is None:
        elems = []
        idx = {}
        for c in p.children:
            if c.is_element:
                idx[c] = len(elems)
                elems.append(c)
        info = (elems, idx)
        ctx.sib[p] = info
    return info


def _of_type(ctx, el):
    p = el.parent
    d = ctx.typ.get(p)
    if d is None:
        d = {}
        ctx.typ[p] = d
    info = d.get(el.tag)
    if info is None:
        elems = []
        idx = {}
        for c in p.children:
            if c.is_element and c.tag == el.tag:
                idx[c] = len(elems)
                elems.append(c)
        info = (elems, idx)
        d[el.tag] = info
    return info


def _nth(a, b, pos):
    if a == 0:
        return pos == b
    d = pos - b
    if d % a != 0:
        return False
    return d // a >= 0


def _own_text(el):
    out = []
    for c in el.children:
        if c.is_text:
            out.append(c.data)
    return "".join(out)


def _match_pseudo(ctx, el, name, arg):
    if el.parent is None:
        return False
    if name == "first-child":
        return _siblings(ctx, el)[1][el] == 0
    if name == "last-child":
        e, i = _siblings(ctx, el)
        return i[el] == len(e) - 1
    if name == "only-child":
        return len(_siblings(ctx, el)[0]) == 1
    if name == "first-of-type":
        return _of_type(ctx, el)[1][el] == 0
    if name == "last-of-type":
        e, i = _of_type(ctx, el)
        return i[el] == len(e) - 1
    if name == "only-of-type":
        return len(_of_type(ctx, el)[0]) == 1
    if name == "nth-child":
        return _nth(arg[0], arg[1], _siblings(ctx, el)[1][el] + 1)
    if name == "nth-last-child":
        e, i = _siblings(ctx, el)
        return _nth(arg[0], arg[1], len(e) - i[el])
    if name == "nth-of-type":
        return _nth(arg[0], arg[1], _of_type(ctx, el)[1][el] + 1)
    if name == "nth-last-of-type":
        e, i = _of_type(ctx, el)
        return _nth(arg[0], arg[1], len(e) - i[el])
    if name == "not":
        for cx in arg:
            if _match_complex(ctx, el, cx, len(cx) - 1):
                return False
        return True
    if name == "is" or name == "where" or name == "matches" or name == "any":
        for cx in arg:
            if _match_complex(ctx, el, cx, len(cx) - 1):
                return True
        return False
    if name == "has":
        return _match_has(ctx, el, arg)
    if name == "empty":
        for c in el.children:
            if c.is_element:
                return False
            if c.is_text and c.data.strip() != "":
                return False
        return True
    if name == "root":
        return el.parent.tag == "[document]"
    if name == "scope":
        return el is ctx.scope
    if name == "checked":
        if el.tag == "option":
            return "selected" in el.attrs
        if el.tag == "input":
            return "checked" in el.attrs and el.attrs.get("type", "").lower() in ("checkbox", "radio")
        return False
    if name == "disabled":
        return el.tag in _FORM_TAGS and "disabled" in el.attrs
    if name == "enabled":
        return el.tag in _FORM_TAGS and "disabled" not in el.attrs
    if name == "required":
        return "required" in el.attrs
    if name == "link" or name == "any-link":
        return el.tag in ("a", "area", "link") and "href" in el.attrs
    if name == "contains" or name == "-soup-contains":
        t = el.get_text()
        for s in arg:
            if s in t:
                return True
        return False
    if name == "contains-own" or name == "-soup-contains-own":
        t = _own_text(el)
        for s in arg:
            if s in t:
                return True
        return False
    return False


def _match_attr(el, name, op, value, ci):
    v = el.attrs.get(name)
    if op is None:
        return v is not None
    if op == "!=":
        if v is None:
            return True
        if ci:
            return v.lower() != value.lower()
        return v != value
    if v is None:
        return False
    if ci:
        v = v.lower()
        value = value.lower()
    if op == "=":
        return v == value
    if op == "~=":
        if value == "" or " " in value:
            return False
        return value in v.split()
    if op == "|=":
        return v == value or v.startswith(value + "-")
    if op == "^=":
        return value != "" and v.startswith(value)
    if op == "$=":
        return value != "" and v.endswith(value)
    if op == "*=":
        return value != "" and value in v
    return False


def _match_compound(ctx, el, c):
    if c.anchor:
        return el is ctx.scope
    if c.tag is not None and c.tag != "*" and el.tag != c.tag:
        return False
    if c.ids:
        eid = el.attrs.get("id")
        for i in c.ids:
            if eid != i:
                return False
    if c.classes:
        cls = el.attrs.get("class")
        if cls is None:
            return False
        toks = cls.split()
        for k in c.classes:
            if k not in toks:
                return False
    for name, op, value, ci in c.attrs:
        if not _match_attr(el, name, op, value, ci):
            return False
    for name, arg in c.pseudos:
        if not _match_pseudo(ctx, el, name, arg):
            return False
    return True


def _match_complex(ctx, el, parts, k):
    comp = parts[k]
    if not _match_compound(ctx, el, comp):
        return False
    if k == 0:
        return True
    comb = comp.comb
    if comb == ">":
        p = el.parent
        if p is None or p.tag == "[document]":
            return False
        return _match_complex(ctx, p, parts, k - 1)
    if comb == " ":
        p = el.parent
        while p is not None and p.tag != "[document]":
            if _match_complex(ctx, p, parts, k - 1):
                return True
            p = p.parent
        return False
    if el.parent is None:
        return False
    elems, idx = _siblings(ctx, el)
    pos = idx[el]
    if comb == "+":
        return pos > 0 and _match_complex(ctx, elems[pos - 1], parts, k - 1)
    if comb == "~":
        j = pos - 1
        while j >= 0:
            if _match_complex(ctx, elems[j], parts, k - 1):
                return True
            j -= 1
        return False
    return False


def _match_has(ctx, el, group):
    saved = ctx.scope
    ctx.scope = el
    found = False
    for cx in group:
        lead = cx[1].comb
        cands = []
        if lead == "+" or lead == "~":
            if el.parent is not None:
                elems, idx = _siblings(ctx, el)
                for sib in elems[idx[el] + 1:]:
                    cands.append(sib)
                    for d in _walk(sib):
                        if d.is_element:
                            cands.append(d)
        else:
            for d in _walk(el):
                if d.is_element:
                    cands.append(d)
        for c in cands:
            if _match_complex(ctx, c, cx, len(cx) - 1):
                found = True
                break
        if found:
            break
    ctx.scope = saved
    return found


def select(root, css, limit=None):
    """All descendant elements of `root` that match `css`, in document order."""
    group = css if isinstance(css, list) else compile_selector(css)
    ctx = _Ctx(root)
    out = []
    for el in _walk(root):
        if not el.is_element:
            continue
        for cx in group:
            if _match_complex(ctx, el, cx, len(cx) - 1):
                out.append(el)
                break
        if limit is not None and len(out) >= limit:
            break
    return out


def select_one(root, css):
    r = select(root, css, 1)
    return r[0] if r else None


def matches(el, css):
    """True if `el` itself matches the selector."""
    group = css if isinstance(css, list) else compile_selector(css)
    ctx = _Ctx(el)
    for cx in group:
        if _match_complex(ctx, el, cx, len(cx) - 1):
            return True
    return False
