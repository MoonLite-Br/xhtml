# xhtml/extract.cpy - turn parsed HTML into plain Python data.
#
#   links(root, base)        -> [Link]   (text, href resolved against base, rel, title)
#   images(root, base)       -> [Image]
#   table_rows(table)        -> [[cell text, ...], ...]
#   table_dicts(table)       -> [{header: cell, ...}, ...]
#   form_fields(form)        -> {name: value}   (what a browser would submit)
#   meta(doc)                -> {"title":..., "description":..., "og:title":..., ...}
#   text_of(el)              -> collapsed-whitespace text
from .url import urljoin


def _base_of(root, base):
    if base is not None:
        return base
    d = root
    while d.parent is not None:
        d = d.parent
    return d.base_url() if hasattr(d, "base_url") else None


def _clean(s):
    return " ".join(s.replace(" ", " ").split())


def text_of(el):
    """Visible text of `el` with all whitespace runs collapsed to single spaces."""
    return _clean(el.get_text(" "))


class Link:
    def __init__(self, href, text, rel, title, element):
        self.href = href
        self.text = text
        self.rel = rel
        self.title = title
        self.element = element

    def __repr__(self):
        return "Link(" + repr(self.href) + ", " + repr(self.text) + ")"

    def __str__(self):
        return self.href


class Image:
    def __init__(self, src, alt, width, height, element):
        self.src = src
        self.alt = alt
        self.width = width
        self.height = height
        self.element = element

    def __repr__(self):
        return "Image(" + repr(self.src) + ", " + repr(self.alt) + ")"

    def __str__(self):
        return self.src


_SKIP_SCHEMES = ("javascript:", "mailto:", "tel:", "data:", "sms:")


def _resolve(base, href):
    if base:
        return urljoin(base, href)
    return href


def links(root, base=None, skip_special=False):
    """Every <a href> / <area href> below `root`, hrefs made absolute.
    skip_special=True drops javascript:/mailto:/tel:/data: and bare "#" links."""
    base = _base_of(root, base)
    out = []
    for el in root.iter_elements():
        if el.tag != "a" and el.tag != "area":
            continue
        href = el.attrs.get("href")
        if href is None:
            continue
        href = href.strip()
        if skip_special:
            low = href.lower()
            if href == "" or href.startswith("#") or low.startswith(_SKIP_SCHEMES):
                continue
        out.append(Link(_resolve(base, href) if href else (base or ""), text_of(el),
                        el.attrs.get("rel", ""), el.attrs.get("title", ""), el))
    return out


def _first_src(srcset):
    # "a.jpg 1x, b.jpg 2x" -> "a.jpg"
    first = srcset.split(",")[0].strip()
    return first.split()[0] if first else ""


def images(root, base=None):
    """Every <img> below `root` (src, or the first srcset/data-src candidate)."""
    base = _base_of(root, base)
    out = []
    for el in root.iter_elements("img"):
        a = el.attrs
        src = a.get("src") or a.get("data-src") or a.get("data-original")
        if not src and a.get("srcset"):
            src = _first_src(a["srcset"])
        if not src:
            continue
        src = src.strip()
        out.append(Image(_resolve(base, src), a.get("alt", ""), a.get("width"), a.get("height"), el))
    return out


def _table_of(el):
    return el if el.tag == "table" else el.find("table")


def _own_rows(table):
    """<tr> elements that belong to `table` itself (not to a nested table)."""
    rows = []
    stack = list(reversed(table.children))
    while stack:
        n = stack.pop()
        if not n.is_element:
            continue
        if n.tag == "tr":
            rows.append(n)
        elif n.tag in ("thead", "tbody", "tfoot"):
            stack.extend(reversed(n.children))
    return rows


def _span(el, name):
    v = el.attrs.get(name, "1").strip()
    if v.isdigit() and int(v) > 0:
        return min(int(v), 100)
    return 1


def table_rows(el, strip=True):
    """Rows of the (first) table at/below `el` as lists of cell text.
    colspan/rowspan are expanded so every row lines up."""
    table = _table_of(el)
    if table is None:
        return []
    grid = []
    pending = {}                 # column -> [remaining rows, text]
    for tr in _own_rows(table):
        row = []
        col = 0
        cells = [c for c in tr.children if c.is_element and (c.tag == "td" or c.tag == "th")]
        k = 0
        while k < len(cells) or col in pending:
            if col in pending:
                rem, txt = pending[col]
                row.append(txt)
                if rem <= 1:
                    del pending[col]
                else:
                    pending[col] = [rem - 1, txt]
                col += 1
                continue
            c = cells[k]
            k += 1
            txt = text_of(c) if strip else c.get_text()
            cs = _span(c, "colspan")
            rs = _span(c, "rowspan")
            for j in range(cs):
                row.append(txt)
                if rs > 1:
                    pending[col] = [rs - 1, txt]
                col += 1
        grid.append(row)
    return grid


def table_dicts(el):
    """Table -> list of dicts keyed by the header row (first row, or <thead>)."""
    rows = table_rows(el)
    if len(rows) < 2:
        return []
    head = rows[0]
    out = []
    for r in rows[1:]:
        d = {}
        for i in range(len(r)):
            key = head[i] if i < len(head) and head[i] else "col" + str(i)
            d[key] = r[i]
        out.append(d)
    return out


def form_fields(form):
    """Name -> value for the controls of a <form>, as a browser would submit them.
    Unchecked checkboxes/radios, disabled controls and buttons are left out."""
    out = {}
    for el in form.iter_elements():
        a = el.attrs
        name = a.get("name")
        if not name or "disabled" in a:
            continue
        tag = el.tag
        if tag == "input":
            t = a.get("type", "text").lower()
            if t in ("submit", "button", "reset", "image", "file"):
                continue
            if t == "checkbox" or t == "radio":
                if "checked" not in a:
                    continue
                out[name] = a.get("value", "on")
            else:
                out[name] = a.get("value", "")
        elif tag == "textarea":
            out[name] = el.get_text()
        elif tag == "select":
            chosen = None
            first = None
            for o in el.iter_elements("option"):
                if "disabled" in o.attrs:
                    continue
                v = o.attrs.get("value")
                if v is None:
                    v = text_of(o)
                if first is None:
                    first = v
                if "selected" in o.attrs:
                    chosen = v
            if chosen is None:
                chosen = first
            if chosen is not None:
                out[name] = chosen
    return out


def meta(doc):
    """<title> plus every <meta name|property|http-equiv content> as a dict."""
    out = {}
    t = doc.find("title")
    if t is not None:
        out["title"] = text_of(t)
    for m in doc.iter_elements("meta"):
        a = m.attrs
        key = a.get("name") or a.get("property") or a.get("http-equiv")
        if key is not None and "content" in a:
            out[key.lower()] = a["content"]
        elif "charset" in a:
            out["charset"] = a["charset"]
    return out
