# xhtml/url.cpy - URL helpers (cpy has no urllib.parse).
#
# urlsplit / urljoin (RFC 3986) / quote / unquote / urlencode / parse_qsl.
# cpy strings have no .encode(), so UTF-8 is encoded/decoded by hand.

_UNRESERVED = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-~"
_HEX = "0123456789abcdefABCDEF"
_ALPHA = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
_SCHEME_CHARS = _ALPHA + "0123456789+-."
_DEFAULT_PORTS = {"http": 80, "https": 443, "ftp": 21, "ws": 80, "wss": 443}


def _utf8(cp):
    if cp < 0x80:
        return [cp]
    if cp < 0x800:
        return [0xC0 | (cp >> 6), 0x80 | (cp & 0x3F)]
    if cp < 0x10000:
        return [0xE0 | (cp >> 12), 0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F)]
    return [0xF0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3F),
            0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F)]


def _decode_utf8(data):
    """Decode a list of byte values to str; invalid bytes become U+FFFD."""
    out = []
    i = 0
    n = len(data)
    while i < n:
        b = data[i]
        if b < 0x80:
            out.append(chr(b))
            i += 1
            continue
        if b >= 0xC2 and b < 0xE0:
            need, cp = 1, b & 0x1F
        elif b >= 0xE0 and b < 0xF0:
            need, cp = 2, b & 0x0F
        elif b >= 0xF0 and b < 0xF5:
            need, cp = 3, b & 0x07
        else:
            out.append("�")
            i += 1
            continue
        good = 0
        for k in range(1, need + 1):
            if i + k >= n:
                break
            c = data[i + k]
            if c < 0x80 or c > 0xBF:
                break
            cp = (cp << 6) | (c & 0x3F)
            good += 1
        if good == need and cp <= 0x10FFFF and not (cp >= 0xD800 and cp <= 0xDFFF):
            out.append(chr(cp))
            i += need + 1
        else:
            # one U+FFFD for the maximal invalid prefix, like CPython's decoder
            out.append("�")
            i += good + 1
    return "".join(out)


def quote(s, safe="/"):
    """Percent-encode `s` (UTF-8).  Characters in `safe` are left alone."""
    s = str(s)
    out = []
    for ch in s:
        if ch in _UNRESERVED or ch in safe:
            out.append(ch)
        else:
            for b in _utf8(ord(ch)):
                out.append("%%%02X" % b)
    return "".join(out)


def quote_plus(s, safe=""):
    return quote(s, safe + " ").replace(" ", "+")


def unquote(s):
    """Decode %XX sequences (UTF-8)."""
    s = str(s)
    if "%" not in s:
        return s
    parts = s.split("%")
    out = [parts[0]]
    buf = []
    for p in parts[1:]:
        if len(p) >= 2 and p[0] in _HEX and p[1] in _HEX:
            buf.append(int(p[:2], 16))
            rest = p[2:]
            if rest:
                out.append(_decode_utf8(buf))
                buf = []
                out.append(rest)
        else:
            if buf:
                out.append(_decode_utf8(buf))
                buf = []
            out.append("%" + p)
    if buf:
        out.append(_decode_utf8(buf))
    return "".join(out)


def unquote_plus(s):
    return unquote(str(s).replace("+", " "))


def urlencode(query, doseq=False):
    """{"a": 1, "b": "x y"} or [("a", 1), ...]  ->  "a=1&b=x+y"."""
    items = query.items() if hasattr(query, "items") else query
    out = []
    for k, v in items:
        if isinstance(v, (list, tuple)) and doseq:
            for x in v:
                out.append(quote_plus(k) + "=" + quote_plus(x))
        else:
            out.append(quote_plus(k) + "=" + quote_plus(v))
    return "&".join(out)


def parse_qsl(qs, keep_blank_values=False):
    """"a=1&b=x+y" -> [("a", "1"), ("b", "x y")]."""
    out = []
    if not qs:
        return out
    for pair in qs.replace(";", "&").split("&"):
        if not pair:
            continue
        k, _, v = pair.partition("=")
        if not v and not keep_blank_values:
            continue
        out.append((unquote_plus(k), unquote_plus(v)))
    return out


def parse_qs(qs, keep_blank_values=False):
    out = {}
    for k, v in parse_qsl(qs, keep_blank_values):
        out.setdefault(k, []).append(v)
    return out


class SplitResult:
    def __init__(self, scheme, netloc, path, query, fragment):
        self.scheme = scheme
        self.netloc = netloc
        self.path = path
        self.query = query
        self.fragment = fragment

    def _hostport(self):
        h = self.netloc
        at = h.rfind("@")
        if at >= 0:
            h = h[at + 1:]
        return h

    @property
    def hostname(self):
        h = self._hostport()
        if not h:
            return None
        if h.startswith("["):
            return h[1:].partition("]")[0].lower()
        return h.partition(":")[0].lower()

    @property
    def port(self):
        h = self._hostport()
        if h.startswith("["):
            h = h.partition("]")[2]
        elif ":" in h:
            h = ":" + h.partition(":")[2]
        else:
            h = ""
        if h.startswith(":") and h[1:].isdigit():
            return int(h[1:])
        return None

    def geturl(self):
        return urlunsplit(self)

    def __iter__(self):
        yield self.scheme
        yield self.netloc
        yield self.path
        yield self.query
        yield self.fragment

    def __repr__(self):
        return (f"SplitResult(scheme={self.scheme!r}, netloc={self.netloc!r}, path={self.path!r}, "
                f"query={self.query!r}, fragment={self.fragment!r})")


def urlsplit(url, scheme=""):
    url = str(url).strip()
    fragment = ""
    query = ""
    netloc = ""
    if "#" in url:
        url, _, fragment = url.partition("#")
    # scheme:  letters first, then [alnum+-.], then ':'
    c = url.find(":")
    if c > 0 and url[0] in _ALPHA:
        cand = url[:c]
        good = True
        for ch in cand:
            if ch not in _SCHEME_CHARS:
                good = False
                break
        if good:
            after = url[c + 1:]
            first = after
            for ch in "/?":
                k = first.find(ch)
                if k >= 0:
                    first = first[:k]
            # "localhost:8080/x" is host:port, not a scheme
            if not first.isdigit():
                scheme = cand.lower()
                url = after
    if url.startswith("//"):
        rest = url[2:]
        end = len(rest)
        for ch in "/?":
            k = rest.find(ch)
            if k >= 0 and k < end:
                end = k
        netloc = rest[:end]
        url = rest[end:]
    if "?" in url:
        url, _, query = url.partition("?")
    return SplitResult(scheme, netloc, url, query, fragment)


def urlunsplit(parts):
    scheme, netloc, path, query, fragment = parts
    url = path
    if netloc or (scheme and scheme in _DEFAULT_PORTS and not url.startswith("//")):
        if url and not url.startswith("/"):
            url = "/" + url
        url = "//" + netloc + url
    if scheme:
        url = scheme + ":" + url
    if query:
        url = url + "?" + query
    if fragment:
        url = url + "#" + fragment
    return url


def _remove_dot_segments(path):
    if not path:
        return path
    segs = path.split("/")
    out = []
    last = len(segs) - 1
    for i in range(len(segs)):
        s = segs[i]
        if s == "..":
            if len(out) > 1 or (len(out) == 1 and out[0] != ""):
                out.pop()
            if i == last:
                out.append("")
        elif s == ".":
            if i == last:
                out.append("")
        else:
            out.append(s)
    res = "/".join(out)
    if path.startswith("/") and not res.startswith("/"):
        res = "/" + res
    return res


def urljoin(base, ref):
    """Resolve `ref` against `base` (RFC 3986), like urllib.parse.urljoin."""
    if not base:
        return ref
    if not ref:
        return base
    r = urlsplit(ref)
    b = urlsplit(base)
    if r.scheme and r.scheme != b.scheme:
        return ref
    scheme = r.scheme or b.scheme
    if r.netloc:
        return urlunsplit((scheme, r.netloc, _remove_dot_segments(r.path), r.query, r.fragment))
    if ref.startswith("//"):
        return urlunsplit((scheme, r.netloc, _remove_dot_segments(r.path), r.query, r.fragment))
    netloc = b.netloc
    if not r.path:
        path = b.path
        query = r.query if r.query else b.query
        if not r.query and not r.fragment and not ref.startswith("?"):
            query = b.query
        if ref.startswith("?"):
            query = r.query
        return urlunsplit((scheme, netloc, path, query, r.fragment))
    if r.path.startswith("/"):
        path = _remove_dot_segments(r.path)
    else:
        bp = b.path
        if not bp and netloc:
            bp = "/"
        cut = bp.rfind("/")
        merged = (bp[:cut + 1] if cut >= 0 else "") + r.path
        path = _remove_dot_segments(merged)
    return urlunsplit((scheme, netloc, path, r.query, r.fragment))


def urldefrag(url):
    base, _, frag = str(url).partition("#")
    return base, frag
