# xhtml/core.cpy - the heart of xhtml: a forgiving HTML parser and a small DOM.
#
#   parse(html, url=None) -> Document
#
# Design notes (read these before changing the tokenizer):
#
# * cpy strings are UTF-8 and are indexed *by character*, which is O(n) on
#   non-ASCII text.  Scanning a Vietnamese page character by character would be
#   quadratic, so the tokenizer never walks the whole document.  It splits the
#   markup on "<" once (fast, native) and then works on the resulting small
#   pieces; only the first few characters of a piece are ever indexed.
# * There is no `re` module in cpy, so every scanner here is hand written.
# * The parser is forgiving, not a full HTML5 tree builder: it does NOT invent
#   <html>/<head>/<body>/<tbody> that are missing from the source, but it does
#   close <p>/<li>/<td>/... the way browsers do, ignores stray end tags, honours
#   `<br/>`-style self-closing syntax, and keeps <script>/<style>/<textarea>/
#   <title> contents as raw text.
from .entities import unescape, escape

VOID = frozenset([
    "area", "base", "br", "col", "embed", "hr", "img", "input", "keygen",
    "link", "meta", "param", "source", "track", "wbr", "basefont", "bgsound",
    "frame", "command",
])
RAW_TEXT = frozenset(["script", "style"])          # contents are not decoded
RCDATA = frozenset(["textarea", "title"])          # text only, entities decoded
SKIP_TEXT = frozenset(["script", "style", "template"])   # not part of .text

# Nesting deeper than this is flattened (protects against pathological input
# and cpy's recursion limit).  Raise it if you really have deeper documents.
MAX_DEPTH = 256

_LETTERS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
_WS = " \t\n\r\f"
_NAME_END = " \t\n\r\f/>"
_ATTR_END = " \t\n\r\f/=>"
_UNQ_END = " \t\n\r\f>"

_HEADINGS = frozenset(["h1", "h2", "h3", "h4", "h5", "h6"])

_PHRASING = frozenset([
    "a", "abbr", "acronym", "b", "bdi", "bdo", "big", "br", "button", "cite",
    "code", "data", "del", "dfn", "em", "font", "i", "img", "input", "ins",
    "kbd", "label", "mark", "q", "s", "samp", "select", "small", "span",
    "strike", "strong", "sub", "sup", "textarea", "time", "tt", "u", "var",
    "wbr", "svg", "math", "nobr",
])

# A start tag of one of these closes an open <p>.
_P_CLOSERS = frozenset([
    "address", "article", "aside", "blockquote", "center", "details", "dialog",
    "dir", "div", "dl", "dd", "dt", "fieldset", "figcaption", "figure",
    "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6", "header", "hgroup",
    "hr", "li", "listing", "main", "menu", "nav", "ol", "p", "pre", "section",
    "summary", "table", "ul", "xmp",
])

# "Special" elements (HTML5 spec) minus address/div/p: they stop the search for
# an open <li>/<dd>/<dt> to close.
_SPECIAL = frozenset([
    "applet", "area", "article", "aside", "base", "basefont", "bgsound",
    "blockquote", "body", "br", "button", "caption", "center", "col",
    "colgroup", "details", "dir", "dl", "embed", "fieldset", "figcaption",
    "figure", "footer", "form", "frame", "frameset", "h1", "h2", "h3", "h4",
    "h5", "h6", "head", "header", "hgroup", "hr", "html", "iframe", "img",
    "input", "keygen", "link", "listing", "main", "marquee", "menu", "meta",
    "nav", "noembed", "noframes", "noscript", "object", "ol", "param",
    "plaintext", "pre", "script", "section", "select", "source", "style",
    "summary", "table", "tbody", "td", "template", "textarea", "tfoot", "th",
    "thead", "title", "tr", "track", "ul", "wbr", "xmp",
])

_TBL_SECTION = frozenset(["thead", "tbody", "tfoot"])

# start tag -> (open elements it implicitly closes, elements that stop the search)
_RULES = {
    "li": (frozenset(["li"]), _SPECIAL),
    "dd": (frozenset(["dd", "dt"]), _SPECIAL),
    "dt": (frozenset(["dd", "dt"]), _SPECIAL),
    "option": (frozenset(["option"]), frozenset(["select", "datalist", "optgroup"])),
    "optgroup": (frozenset(["optgroup", "option"]), frozenset(["select"])),
    "tr": (frozenset(["tr", "td", "th"]), frozenset(["table", "tbody", "thead", "tfoot"])),
    "td": (frozenset(["td", "th"]), frozenset(["table", "tr", "tbody", "thead", "tfoot"])),
    "th": (frozenset(["td", "th"]), frozenset(["table", "tr", "tbody", "thead", "tfoot"])),
    "thead": (frozenset(["thead", "tbody", "tfoot", "tr", "td", "th"]), frozenset(["table"])),
    "tbody": (frozenset(["thead", "tbody", "tfoot", "tr", "td", "th"]), frozenset(["table"])),
    "tfoot": (frozenset(["thead", "tbody", "tfoot", "tr", "td", "th"]), frozenset(["table"])),
    "body": (frozenset(["head"]), frozenset()),
}

# Elements allowed to stay inside an (unclosed) <head>.
_HEAD_OK = frozenset(["title", "meta", "link", "script", "style", "base", "noscript", "template"])

# A stray end tag may not close an element that lies beyond one of these.
_END_STOP = frozenset(["table", "td", "th", "caption", "object", "applet", "marquee", "template"])
_TABLEISH = frozenset(["table", "tbody", "thead", "tfoot", "tr", "td", "th", "caption", "colgroup"])

# Block-level elements, used by Element.to_text().
BLOCK = frozenset([
    "address", "article", "aside", "blockquote", "body", "caption", "center",
    "dd", "details", "dialog", "div", "dl", "dt", "fieldset", "figcaption",
    "figure", "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6", "header",
    "hgroup", "hr", "html", "legend", "li", "main", "menu", "nav", "ol", "p",
    "pre", "section", "summary", "table", "tbody", "td", "tfoot", "th",
    "thead", "tr", "ul",
])
_PARA = frozenset(["p", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "pre", "ul", "ol", "table"])


# ---------------------------------------------------------------------------
# Node classes
# ---------------------------------------------------------------------------

class Node:
    """Base class of everything in the tree."""
    parent = None
    is_element = False
    is_text = False

    def _child_index(self):
        p = self.parent
        if p is None:
            return -1
        ch = p.children
        for i in range(len(ch)):
            if ch[i] is self:
                return i
        return -1

    def extract(self):
        """Detach this node from its parent (it stays usable on its own)."""
        k = self._child_index()
        if k >= 0:
            del self.parent.children[k]
        self.parent = None
        return self

    def replace_with(self, node):
        p = self.parent
        k = self._child_index()
        if p is None or k < 0:
            raise ValueError("node has no parent")
        node = _as_node(node)
        if node.parent is not None:
            node.extract()
            k = self._child_index()
        p.children[k] = node
        node.parent = p
        self.parent = None
        return node

    @property
    def next_sibling(self):
        k = self._child_index()
        if k < 0 or k + 1 >= len(self.parent.children):
            return None
        return self.parent.children[k + 1]

    @property
    def prev_sibling(self):
        k = self._child_index()
        if k <= 0:
            return None
        return self.parent.children[k - 1]

    @property
    def next_element_sibling(self):
        k = self._child_index()
        if k < 0:
            return None
        ch = self.parent.children
        for i in range(k + 1, len(ch)):
            if ch[i].is_element:
                return ch[i]
        return None

    @property
    def prev_element_sibling(self):
        k = self._child_index()
        if k < 0:
            return None
        ch = self.parent.children
        i = k - 1
        while i >= 0:
            if ch[i].is_element:
                return ch[i]
            i -= 1
        return None

    def parents(self):
        """Generator over ancestors, nearest first."""
        p = self.parent
        while p is not None:
            yield p
            p = p.parent


class Text(Node):
    is_text = True

    def __init__(self, data):
        self.data = data
        self.parent = None

    @property
    def text(self):
        return self.data

    @property
    def html(self):
        p = self.parent
        if p is not None and p.tag in RAW_TEXT:
            return self.data
        return escape(self.data, False)

    def __str__(self):
        return self.data

    def __repr__(self):
        d = self.data
        if len(d) > 40:
            d = d[:37] + "..."
        return "Text(" + repr(d) + ")"


class Comment(Node):
    """<!-- comment -->; `kind` is "comment", "pi" (<?xml ...?>) or "decl"."""

    def __init__(self, data, kind="comment"):
        self.data = data
        self.kind = kind
        self.parent = None

    @property
    def html(self):
        if self.kind == "pi":
            return "<?" + self.data + ">"
        if self.kind == "decl":
            return "<!" + self.data + ">"
        return "<!--" + self.data + "-->"

    def __str__(self):
        return self.html

    def __repr__(self):
        return "Comment(" + repr(self.data) + ")"


class Doctype(Node):
    """<!DOCTYPE html> - `data` is everything after the "<!"."""

    def __init__(self, data):
        self.data = data
        self.parent = None

    @property
    def html(self):
        return "<!" + self.data + ">"

    def __str__(self):
        return self.html

    def __repr__(self):
        return "Doctype(" + repr(self.data) + ")"


def _as_node(x):
    if isinstance(x, Node):
        return x
    if isinstance(x, str):
        return Text(x)
    raise TypeError("expected a Node or str, got " + type(x).__name__)


def _attr_name(k):
    # class_ -> class, data_id -> data-id
    if k.endswith("_"):
        k = k[:-1]
    return k.replace("_", "-").lower()


def _want(attrs, kwargs):
    """Merge an `attrs` filter (dict, or a bare string = class) and **kwargs."""
    want = {}
    if attrs:
        if isinstance(attrs, str):
            want["class"] = attrs
        else:
            for k, v in attrs.items():
                want[k.lower()] = v
    for k, v in kwargs.items():
        want[_attr_name(k)] = v
    return want


def _value_match(spec, value):
    if spec is True:
        return value is not None
    if spec is False or spec is None:
        return value is None
    if value is None:
        return False
    if isinstance(spec, str):
        return value == spec
    if isinstance(spec, (list, tuple, set, frozenset)):
        for s in spec:
            if _value_match(s, value):
                return True
        return False
    if callable(spec):
        return bool(spec(value))
    return value == spec


def _attr_match(el, name, spec):
    v = el.attrs.get(name)
    if name == "class" and isinstance(spec, str) and v is not None:
        if v == spec:
            return True
        return spec in v.split()
    if name == "class" and isinstance(spec, (list, tuple)) and v is not None:
        toks = v.split()
        for s in spec:
            if s == v or s in toks:
                return True
        return False
    return _value_match(spec, v)


def _tag_match(el, tag):
    if tag is None or tag is True:
        return True
    if isinstance(tag, str):
        return el.tag == tag.lower()
    if isinstance(tag, (list, tuple, set, frozenset)):
        for t in tag:
            if isinstance(t, str) and el.tag == t.lower():
                return True
        return False
    if callable(tag):
        return bool(tag(el))
    return False


def _walk(root):
    """Yield every descendant node of `root` in document order (iterative)."""
    stack = list(reversed(root.children))
    while stack:
        n = stack.pop()
        yield n
        if n.is_element and n.children:
            stack.extend(reversed(n.children))


class Element(Node):
    """An HTML element: `tag`, `attrs` (dict of str), `children` (list of nodes)."""
    is_element = True

    def __init__(self, tag, attrs=None, children=None):
        self.tag = tag
        self.attrs = attrs if attrs is not None else {}
        self.children = []
        self.parent = None
        if children:
            for c in children:
                self.append(c)

    # -- attributes ---------------------------------------------------------
    @property
    def name(self):
        return self.tag

    @property
    def id(self):
        return self.attrs.get("id")

    @property
    def classes(self):
        v = self.attrs.get("class")
        return v.split() if v else []

    def has_class(self, name):
        return name in self.classes

    def get(self, name, default=None):
        return self.attrs.get(name.lower(), default)

    def has_attr(self, name):
        return name.lower() in self.attrs

    def set(self, name, value):
        self.attrs[name.lower()] = "" if value is None else str(value)
        return self

    def __getitem__(self, name):
        return self.attrs[name.lower()]

    def __setitem__(self, name, value):
        self.set(name, value)

    def __delitem__(self, name):
        del self.attrs[name.lower()]

    def __iter__(self):
        return iter(self.children)

    # -- tree editing -------------------------------------------------------
    def append(self, node):
        node = _as_node(node)
        if node.parent is not None:
            node.extract()
        node.parent = self
        self.children.append(node)
        return node

    def insert(self, index, node):
        node = _as_node(node)
        if node.parent is not None:
            node.extract()
        node.parent = self
        self.children.insert(index, node)
        return node

    def clear(self):
        for c in self.children:
            c.parent = None
        self.children = []

    def decompose(self):
        """Remove this element from the tree and drop its contents."""
        self.extract()
        self.clear()

    def unwrap(self):
        """Replace this element by its children."""
        p = self.parent
        k = self._child_index()
        if p is None or k < 0:
            raise ValueError("element has no parent")
        kids = self.children
        self.children = []
        for c in kids:
            c.parent = p
        p.children[k:k + 1] = kids
        self.parent = None

    def clone(self):
        """Deep copy (not attached to any parent)."""
        e = Element(self.tag, dict(self.attrs))
        for c in self.children:
            if c.is_element:
                e.append(c.clone())
            elif c.is_text:
                e.append(Text(c.data))
            elif isinstance(c, Comment):
                e.append(Comment(c.data, c.kind))
            else:
                e.append(Doctype(c.data))
        return e

    # -- iteration ----------------------------------------------------------
    def descendants(self):
        """Generator over all descendant nodes (elements, text, comments)."""
        return _walk(self)

    def iter_elements(self, tag=None):
        for n in _walk(self):
            if n.is_element and (tag is None or n.tag == tag):
                yield n

    @property
    def child_elements(self):
        return [c for c in self.children if c.is_element]

    # -- searching ----------------------------------------------------------
    def _matches(self, el, tag, want, text, contains):
        if not _tag_match(el, tag):
            return False
        for k, spec in want.items():
            if not _attr_match(el, k, spec):
                return False
        if text is not None:
            if not _value_match(text, el.get_text(strip=False).strip()):
                return False
        if contains is not None:
            if contains not in el.get_text():
                return False
        return True

    def iter_find(self, tag=None, attrs=None, recursive=True, text=None, contains=None, **kwargs):
        want = _want(attrs, kwargs)
        if isinstance(tag, str):
            tag = tag.lower()
        if recursive:
            for n in _walk(self):
                if n.is_element and self._matches(n, tag, want, text, contains):
                    yield n
        else:
            for n in self.children:
                if n.is_element and self._matches(n, tag, want, text, contains):
                    yield n

    def find_all(self, tag=None, attrs=None, recursive=True, text=None, contains=None, limit=None, **kwargs):
        """All matching descendant elements.

        tag       "a", ["h1", "h2"], True (any), or a function(el) -> bool
        attrs     {"href": True, "class": "btn"}; a bare string means a class
        **kwargs  attribute filters; trailing "_" is dropped (class_="x") and
                  "_" becomes "-" (data_id="3" matches data-id).  Values: a
                  string (exact; for class: any token), True/False/None
                  (present/absent), a list (any of), or a function(value).
        text      match the element's stripped text (str, list or function)
        contains  keep elements whose text contains this substring
        """
        out = []
        for el in self.iter_find(tag, attrs, recursive, text, contains, **kwargs):
            out.append(el)
            if limit is not None and len(out) >= limit:
                break
        return out

    def find(self, tag=None, attrs=None, recursive=True, text=None, contains=None, **kwargs):
        """First matching descendant element, or None."""
        for el in self.iter_find(tag, attrs, recursive, text, contains, **kwargs):
            return el
        return None

    def find_parent(self, tag=None, attrs=None, **kwargs):
        """Nearest ancestor element matching the filters, or None."""
        want = _want(attrs, kwargs)
        if isinstance(tag, str):
            tag = tag.lower()
        p = self.parent
        while p is not None:
            if p.tag != "[document]" and self._matches(p, tag, want, None, None):
                return p
            p = p.parent
        return None

    def find_next_sibling(self, tag=None, attrs=None, **kwargs):
        """Next sibling *element* matching the filters, or None."""
        want = _want(attrs, kwargs)
        if isinstance(tag, str):
            tag = tag.lower()
        sib = self.next_element_sibling
        while sib is not None:
            if self._matches(sib, tag, want, None, None):
                return sib
            sib = sib.next_element_sibling
        return None

    def find_previous_sibling(self, tag=None, attrs=None, **kwargs):
        """Previous sibling *element* matching the filters, or None."""
        want = _want(attrs, kwargs)
        if isinstance(tag, str):
            tag = tag.lower()
        sib = self.prev_element_sibling
        while sib is not None:
            if self._matches(sib, tag, want, None, None):
                return sib
            sib = sib.prev_element_sibling
        return None

    def select(self, css):
        """All descendants matching a CSS selector (see xhtml.selector)."""
        from .selector import select
        return select(self, css)

    def select_one(self, css):
        from .selector import select_one
        return select_one(self, css)

    def matches(self, css):
        """True if this element itself matches the CSS selector."""
        from .selector import matches
        return matches(self, css)

    def closest(self, css):
        """Nearest ancestor-or-self matching the CSS selector, or None."""
        from .selector import matches
        e = self
        while e is not None and e.is_element:
            if e.tag != "[document]" and matches(e, css):
                return e
            e = e.parent
        return None

    # -- text ---------------------------------------------------------------
    def strings(self, strip=False):
        """Generator over the text nodes' strings below this element.
        <script>, <style> and <template> contents are skipped."""
        stack = list(reversed(self.children))
        while stack:
            n = stack.pop()
            if n.is_text:
                d = n.data
                if strip:
                    d = d.strip()
                    if not d:
                        continue
                yield d
            elif n.is_element:
                if n.tag in SKIP_TEXT:
                    continue
                if n.children:
                    stack.extend(reversed(n.children))

    def get_text(self, sep="", strip=False):
        """Concatenated text.  strip=True strips each piece and drops empty ones."""
        return sep.join(self.strings(strip))

    @property
    def text(self):
        return self.get_text()

    @property
    def string(self):
        """The only text of this element, if it has exactly one text child
        (looking through single-child wrappers); otherwise None."""
        e = self
        while True:
            if len(e.children) != 1:
                return None
            c = e.children[0]
            if c.is_text:
                return c.data
            if not c.is_element:
                return None
            e = c

    def to_text(self):
        """Readable plain text: block elements on their own lines, <br> as a
        newline, list items as "- ", table cells joined by " | ", whitespace
        collapsed, <script>/<style>/<head> dropped."""
        out = []
        lists = []                  # stack of [ordered, counter]
        stack = [(c, False) for c in reversed(self.children)]
        pre = 0
        while stack:
            n, leaving = stack.pop()
            if n.is_text:
                d = n.data
                if pre:
                    out.append(d)
                    continue
                if not d:
                    continue
                words = d.replace(" ", " ").split()
                if not words:
                    if out and out[-1][-1:] not in " \n":
                        out.append(" ")
                    continue
                lead = d[0] in _WS or d[0] == " "
                trail = d[-1] in _WS or d[-1] == " "
                s = " ".join(words)
                if lead and out and out[-1][-1:] not in " \n":
                    s = " " + s
                if trail:
                    s = s + " "
                out.append(s)
                continue
            if not n.is_element:
                continue
            tag = n.tag
            if leaving:
                if tag == "pre":
                    pre -= 1
                if tag == "ul" or tag == "ol":
                    lists.pop()
                if tag in BLOCK:
                    _to_text_break(out, "\n\n" if tag in _PARA else "\n")
                continue
            if tag in SKIP_TEXT or tag == "head":
                continue
            if tag == "br":
                out.append("\n")
                continue
            if tag == "hr":
                _to_text_break(out, "\n")
                out.append("---")
                _to_text_break(out, "\n")
                continue
            if tag in BLOCK:
                _to_text_break(out, "\n\n" if tag in _PARA else "\n")
            if tag == "ul" or tag == "ol":
                lists.append([tag == "ol", 0])
            if tag == "pre":
                pre += 1
            if tag == "li":
                if lists and lists[-1][0]:
                    lists[-1][1] += 1
                    out.append(str(lists[-1][1]) + ". ")
                else:
                    out.append("- ")
            if tag == "td" or tag == "th":
                if out and out[-1][-1:] != "\n":
                    out[-1] = out[-1].rstrip(" ")
                    out.append(" | ")
            stack.append((n, True))
            if n.children:
                for c in reversed(n.children):
                    stack.append((c, False))
        res = "".join(out)
        lines = [ln.rstrip() for ln in res.split("\n")]
        res = "\n".join(lines)
        while "\n\n\n" in res:
            res = res.replace("\n\n\n", "\n\n")
        return res.strip()

    # -- serialisation ------------------------------------------------------
    @property
    def html(self):
        """Outer HTML."""
        out = []
        _ser(self, out)
        return "".join(out)

    outer_html = html

    @property
    def inner_html(self):
        out = []
        for c in self.children:
            _ser(c, out)
        return "".join(out)

    def prettify(self, indent=2):
        lines = []
        _pretty(self, 0, indent, lines)
        return "\n".join(lines)

    def __str__(self):
        return self.html

    def __repr__(self):
        a = ""
        for k, v in self.attrs.items():
            if k == "id" or k == "class":
                a = a + " " + k + '="' + v + '"'
        return "<Element " + self.tag + a + " children=" + str(len(self.children)) + ">"

    # -- extraction helpers (see xhtml.extract) -------------------------------
    def links(self, base=None):
        from .extract import links
        return links(self, base)

    def images(self, base=None):
        from .extract import images
        return images(self, base)

    def rows(self, strip=True):
        from .extract import table_rows
        return table_rows(self, strip)

    def to_dicts(self):
        from .extract import table_dicts
        return table_dicts(self)

    def form_fields(self):
        from .extract import form_fields
        return form_fields(self)


def _to_text_break(out, br):
    """Make `out` end with the separator `br` ("\\n" or "\\n\\n")."""
    if not out:
        return
    out[-1] = out[-1].rstrip(" ")
    tail = "".join(out[-3:])
    have = len(tail) - len(tail.rstrip("\n"))
    need = len(br) - have
    if need > 0:
        out.append("\n" * need)


def _ser(node, out):
    if node.is_text:
        out.append(node.html)
        return
    if not node.is_element:
        out.append(node.html)
        return
    tag = node.tag
    if tag == "[document]":
        for c in node.children:
            _ser(c, out)
        return
    out.append("<" + tag)
    for k, v in node.attrs.items():
        out.append(" " + k + '="' + escape(str(v)) + '"')
    out.append(">")
    if tag in VOID and not node.children:
        return
    for c in node.children:
        _ser(c, out)
    out.append("</" + tag + ">")


_PRETTY_RAW = frozenset(["pre", "textarea", "script", "style"])


def _pretty(node, depth, step, lines):
    pad = " " * (depth * step)
    if node.is_text:
        s = node.data.strip()
        if s:
            lines.append(pad + escape(s, False))
        return
    if not node.is_element:
        lines.append(pad + node.html)
        return
    tag = node.tag
    if tag == "[document]":
        for c in node.children:
            _pretty(c, depth, step, lines)
        return
    if tag in _PRETTY_RAW or tag in VOID or not node.children:
        lines.append(pad + node.html)
        return
    open_tag = "<" + tag
    for k, v in node.attrs.items():
        open_tag = open_tag + " " + k + '="' + escape(str(v)) + '"'
    open_tag = open_tag + ">"
    kids = node.children
    if len(kids) == 1 and kids[0].is_text and "\n" not in kids[0].data.strip():
        lines.append(pad + open_tag + escape(kids[0].data.strip(), False) + "</" + tag + ">")
        return
    lines.append(pad + open_tag)
    for c in kids:
        _pretty(c, depth + 1, step, lines)
    lines.append(pad + "</" + tag + ">")


class Document(Element):
    """The root of a parsed page.  `url` (if known) is the base for relative links."""

    def __init__(self, url=None):
        Element.__init__(self, "[document]")
        self.url = url

    @property
    def doctype(self):
        for c in self.children:
            if isinstance(c, Doctype):
                return c.data
        return None

    @property
    def root(self):
        """The <html> element (or the first element if there is none)."""
        first = None
        for c in self.children:
            if c.is_element:
                if c.tag == "html":
                    return c
                if first is None:
                    first = c
        return first

    @property
    def head(self):
        return self.find("head")

    @property
    def body(self):
        return self.find("body")

    @property
    def title(self):
        t = self.find("title")
        if t is None:
            return None
        return " ".join(t.get_text().split())

    def base_url(self):
        """URL that relative links resolve against: <base href> or `url`."""
        from .url import urljoin
        b = self.find("base", href=True)
        if b is not None:
            return urljoin(self.url, b.attrs["href"]) if self.url else b.attrs["href"]
        return self.url

    def __repr__(self):
        return "<Document url=" + repr(self.url) + " children=" + str(len(self.children)) + ">"


# ---------------------------------------------------------------------------
# Tokenizer / tree builder
# ---------------------------------------------------------------------------

def _parse_start(buf):
    """Parse a start tag.  `buf` is the text right after "<".

    Returns (name, attrs, self_closing, end_index) on success, or - when the
    tag is not finished yet - the single character that must appear in the
    following input for it to finish (">" or an opening quote)."""
    n = len(buf)
    k = 1
    while k < n and buf[k] not in _NAME_END:
        k += 1
    name = buf[:k].lower()
    attrs = {}
    while True:
        while k < n and buf[k] in _WS:
            k += 1
        if k >= n:
            return ">"
        ch = buf[k]
        if ch == ">":
            return (name, attrs, False, k + 1)
        if ch == "/":
            if k + 1 < n:
                if buf[k + 1] == ">":
                    return (name, attrs, True, k + 2)
                k += 1
                continue
            return ">"
        s = k
        while k < n and buf[k] not in _ATTR_END:
            k += 1
        if k == s:
            k += 1          # stray "=" or similar: skip it
            continue
        aname = buf[s:k].lower()
        while k < n and buf[k] in _WS:
            k += 1
        val = ""
        if k < n and buf[k] == "=":
            k += 1
            while k < n and buf[k] in _WS:
                k += 1
            if k >= n:
                return ">"
            q = buf[k]
            if q == '"' or q == "'":
                e = buf.find(q, k + 1)
                if e < 0:
                    return q
                val = buf[k + 1:e]
                k = e + 1
            else:
                s2 = k
                while k < n and buf[k] not in _UNQ_END:
                    k += 1
                val = buf[s2:k]
        if aname not in attrs:
            attrs[aname] = unescape(val) if "&" in val else val


def _find_close(pieces, i, off, needle, n):
    """Find `needle` (which contains no "<") starting in pieces[i] at `off`.
    Returns (piece_index, offset) or (-1, -1)."""
    k = pieces[i].find(needle, off)
    if k >= 0:
        return i, k
    j = i + 1
    while j < n:
        k = pieces[j].find(needle)
        if k >= 0:
            return j, k
        j += 1
    return -1, -1


class _Builder:
    def __init__(self, url):
        self.doc = Document(url)
        self.stack = [self.doc]
        self.text = []
        self.seen = {}

    # text -----------------------------------------------------------------
    def flush(self):
        if self.text:
            data = "".join(self.text)
            self.text = []
            if data:
                self._add(Text(unescape(data)))

    def _add(self, node):
        cur = self.stack[-1]
        node.parent = cur
        cur.children.append(node)

    # implicit closing -------------------------------------------------------
    def _close_phrasing(self, target):
        stack = self.stack
        k = len(stack) - 1
        while k > 0:
            t = stack[k].tag
            if t == target:
                del stack[k:]
                return
            if t not in _PHRASING:
                return
            k -= 1

    def _auto_close(self, name):
        stack = self.stack
        top = stack[-1].tag
        if top == "head" and name not in _HEAD_OK:
            stack.pop()
        if name in _P_CLOSERS:
            self._close_phrasing("p")
        if name in _HEADINGS:
            if stack[-1].tag in _HEADINGS:
                stack.pop()
        elif name == "a":
            self._close_phrasing("a")
        rule = _RULES.get(name)
        if rule is not None:
            targets, stoppers = rule
            low = -1
            k = len(stack) - 1
            while k > 0:
                t = stack[k].tag
                if t in targets:
                    low = k
                elif t in stoppers:
                    break
                k -= 1
            if low > 0:
                del stack[low:]

    def start(self, name, attrs, selfclose):
        if name == "html" or name == "body" or name == "head":
            prev = self.seen.get(name)
            if prev is not None:
                for k, v in attrs.items():
                    if k not in prev.attrs:
                        prev.attrs[k] = v
                if name == "body":
                    self._auto_close("body")
                return
        self._auto_close(name)
        el = Element(name, attrs)
        el.parent = self.stack[-1]
        self.stack[-1].children.append(el)
        if name == "html" or name == "body" or name == "head":
            self.seen[name] = el
        if name in VOID or (selfclose and name not in RAW_TEXT and name not in RCDATA):
            return
        if len(self.stack) < MAX_DEPTH:
            self.stack.append(el)
        return el

    def end(self, name):
        if name == "body" or name == "html":
            return                  # content after </body> still belongs to the page
        if name == "br":
            self.flush()
            self.start("br", {}, False)
            return
        stack = self.stack
        k = len(stack) - 1
        tableish = name in _TABLEISH
        while k > 0:
            t = stack[k].tag
            if t == name:
                self.flush()
                del stack[k:]
                return
            if not tableish and t in _END_STOP:
                return
            k -= 1


def parse(markup, url=None):
    """Parse an HTML string into a Document."""
    if markup is None:
        markup = ""
    if "\r" in markup:
        markup = markup.replace("\r\n", "\n").replace("\r", "\n")
    b = _Builder(url)
    pieces = markup.split("<")
    n = len(pieces)
    b.text.append(pieces[0])
    i = 1
    while i < n:
        p = pieces[i]
        c = p[:1]
        if c == "":
            b.text.append("<")
            i += 1
            continue
        if c in _LETTERS:
            buf = p
            j = i
            res = _parse_start(buf)
            while isinstance(res, str):
                # the tag continues into the next pieces (a "<" inside an attribute value)
                need = res
                j += 1
                while j < n and need not in pieces[j]:
                    buf = buf + "<" + pieces[j]
                    j += 1
                if j >= n:
                    res = None
                    break
                buf = buf + "<" + pieces[j]
                res = _parse_start(buf)
            if res is None:
                # unterminated tag at end of input: dropped, like browsers do
                i = n
                break
            name, attrs, selfclose, end = res
            rest = buf[end:]
            i = j + 1
            b.flush()
            if name in RAW_TEXT or name in RCDATA:
                b.start(name, attrs, False)
                # raw content runs until the matching end tag
                chunks = [rest]
                m = len(name) + 1
                while i < n:
                    q = pieces[i]
                    if q[:m].lower() == "/" + name and (len(q) == m or q[m] in " \t\n\r\f/>"):
                        break
                    chunks.append("<" + q)
                    i += 1
                data = "".join(chunks)
                if data:
                    el = b.stack[-1]
                    if el.tag == name:
                        t = Text(unescape(data) if name in RCDATA else data)
                        t.parent = el
                        el.children.append(t)
                continue
            b.start(name, attrs, selfclose)
            if rest:
                b.text.append(rest)
            continue
        if c == "/":
            j = p.find(">")
            if j < 0:
                b.text.append("<" + p)
                i += 1
                continue
            body = p[1:j].split()
            name = body[0] if body else ""
            while name.endswith("/"):
                name = name[:-1]
            rest = p[j + 1:]
            if name and name[0] in _LETTERS:
                b.end(name.lower())
            if rest:
                b.text.append(rest)
            i += 1
            continue
        if c == "!":
            if p[:3] == "!--":
                if p[:4] == "!-->":
                    b.flush()
                    b._add(Comment(""))
                    if p[4:]:
                        b.text.append(p[4:])
                    i += 1
                    continue
                if p[:5] == "!--->":
                    b.flush()
                    b._add(Comment(""))
                    if p[5:]:
                        b.text.append(p[5:])
                    i += 1
                    continue
                j, k = _find_close(pieces, i, 3, "-->", n)
                b.flush()
                if j < 0:
                    parts = [p[3:]] + pieces[i + 1:]
                    b._add(Comment("<".join(parts)))
                    i = n
                    break
                if j == i:
                    data = p[3:k]
                else:
                    data = "<".join([p[3:]] + pieces[i + 1:j] + [pieces[j][:k]])
                b._add(Comment(data))
                tail = pieces[j][k + 3:]
                if tail:
                    b.text.append(tail)
                i = j + 1
                continue
            if p[:8] == "![CDATA[":
                j, k = _find_close(pieces, i, 8, "]]>", n)
                if j < 0:
                    data = "<".join([p[8:]] + pieces[i + 1:])
                    b.flush()
                    b._add(Text(data))
                    i = n
                    break
                if j == i:
                    data = p[8:k]
                else:
                    data = "<".join([p[8:]] + pieces[i + 1:j] + [pieces[j][:k]])
                b.flush()
                b._add(Text(data))
                tail = pieces[j][k + 3:]
                if tail:
                    b.text.append(tail)
                i = j + 1
                continue
            j = p.find(">")
            if j < 0:
                b.text.append("<" + p)
                i += 1
                continue
            b.flush()
            decl = p[1:j]
            if decl[:7].upper() == "DOCTYPE":
                b._add(Doctype(decl))
            else:
                b._add(Comment(decl, "decl"))
            if p[j + 1:]:
                b.text.append(p[j + 1:])
            i += 1
            continue
        if c == "?":
            j = p.find(">")
            if j < 0:
                b.text.append("<" + p)
                i += 1
                continue
            b.flush()
            b._add(Comment(p[1:j], "pi"))
            if p[j + 1:]:
                b.text.append(p[j + 1:])
            i += 1
            continue
        # a lone "<" that does not start markup is just text
        b.text.append("<" + p)
        i += 1
    b.flush()
    return b.doc
