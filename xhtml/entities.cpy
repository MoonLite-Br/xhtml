# xhtml/entities.cpy - HTML entity decoding / escaping.
#
# cpy has no `re` and no `html` module, so this is a small hand-written
# replacement.  `unescape` understands numeric references (&#233; &#xE9;) and a
# table of ~250 common named entities; unknown entities are left untouched,
# exactly like a browser does.
#
# Performance note: cpy indexes strings by *character*, which is O(n) on
# non-ASCII text.  Everything here therefore works with split/find/replace on
# whole strings and only ever indexes the first few characters of a piece.

_LATIN1 = (
    "nbsp iexcl cent pound curren yen brvbar sect uml copy ordf laquo not shy reg macr "
    "deg plusmn sup2 sup3 acute micro para middot cedil sup1 ordm raquo frac14 frac12 "
    "frac34 iquest Agrave Aacute Acirc Atilde Auml Aring AElig Ccedil Egrave Eacute "
    "Ecirc Euml Igrave Iacute Icirc Iuml ETH Ntilde Ograve Oacute Ocirc Otilde Ouml "
    "times Oslash Ugrave Uacute Ucirc Uuml Yacute THORN szlig agrave aacute acirc "
    "atilde auml aring aelig ccedil egrave eacute ecirc euml igrave iacute icirc iuml "
    "eth ntilde ograve oacute ocirc otilde ouml divide oslash ugrave uacute ucirc uuml "
    "yacute thorn yuml"
)

_GREEK_UPPER = (
    "Alpha Beta Gamma Delta Epsilon Zeta Eta Theta Iota Kappa Lambda Mu Nu Xi Omicron "
    "Pi Rho - Sigma Tau Upsilon Phi Chi Psi Omega"
)
_GREEK_LOWER = (
    "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron "
    "pi rho sigmaf sigma tau upsilon phi chi psi omega"
)

_OTHER = {
    "amp": 38, "lt": 60, "gt": 62, "quot": 34, "apos": 39,
    "OElig": 338, "oelig": 339, "Scaron": 352, "scaron": 353, "Yuml": 376,
    "fnof": 402, "circ": 710, "tilde": 732,
    "ensp": 8194, "emsp": 8195, "thinsp": 8201, "zwnj": 8204, "zwj": 8205,
    "lrm": 8206, "rlm": 8207, "ndash": 8211, "mdash": 8212,
    "lsquo": 8216, "rsquo": 8217, "sbquo": 8218, "ldquo": 8220, "rdquo": 8221,
    "bdquo": 8222, "dagger": 8224, "Dagger": 8225, "bull": 8226, "hellip": 8230,
    "permil": 8240, "prime": 8242, "Prime": 8243, "lsaquo": 8249, "rsaquo": 8250,
    "oline": 8254, "frasl": 8260, "euro": 8364, "image": 8465, "weierp": 8472,
    "real": 8476, "trade": 8482, "alefsym": 8501,
    "larr": 8592, "uarr": 8593, "rarr": 8594, "darr": 8595, "harr": 8596,
    "crarr": 8629, "lArr": 8656, "uArr": 8657, "rArr": 8658, "dArr": 8659,
    "hArr": 8660, "forall": 8704, "part": 8706, "exist": 8707, "empty": 8709,
    "nabla": 8711, "isin": 8712, "notin": 8713, "ni": 8715, "prod": 8719,
    "sum": 8721, "minus": 8722, "lowast": 8727, "radic": 8730, "prop": 8733,
    "infin": 8734, "ang": 8736, "and": 8743, "or": 8744, "cap": 8745, "cup": 8746,
    "int": 8747, "there4": 8756, "sim": 8764, "cong": 8773, "asymp": 8776,
    "ne": 8800, "equiv": 8801, "le": 8804, "ge": 8805, "sub": 8834, "sup": 8835,
    "nsub": 8836, "sube": 8838, "supe": 8839, "oplus": 8853, "otimes": 8855,
    "perp": 8869, "sdot": 8901, "lceil": 8968, "rceil": 8969, "lfloor": 8970,
    "rfloor": 8971, "lang": 9001, "rang": 9002, "loz": 9674,
    "spades": 9824, "clubs": 9827, "hearts": 9829, "diams": 9830,
    "star": 9734, "starf": 9733, "check": 10003, "cross": 10007,
}


def _build():
    t = {}
    i = 160
    for name in _LATIN1.split(" "):
        t[name] = chr(i)
        i += 1
    i = 913
    for name in _GREEK_UPPER.split(" "):
        if name != "-":
            t[name] = chr(i)
        i += 1
    i = 945
    for name in _GREEK_LOWER.split(" "):
        t[name] = chr(i)
        i += 1
    for name, cp in _OTHER.items():
        t[name] = chr(cp)
    return t


NAMED = _build()

# Entities browsers accept even without the trailing semicolon.
_LEGACY = frozenset(["amp", "lt", "gt", "quot", "nbsp", "copy", "reg"])

# Windows-1252 remapping that HTML applies to numeric references 128..159.
_CP1252 = {
    128: 8364, 130: 8218, 131: 402, 132: 8222, 133: 8230, 134: 8224, 135: 8225,
    136: 710, 137: 8240, 138: 352, 139: 8249, 140: 338, 142: 381, 145: 8216,
    146: 8217, 147: 8220, 148: 8221, 149: 8226, 150: 8211, 151: 8212, 152: 732,
    153: 8482, 154: 353, 155: 8250, 156: 339, 158: 382, 159: 376,
}

_DIGITS = "0123456789"
_HEXDIGITS = "0123456789abcdefABCDEF"
_NAMECHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"


def _codepoint(cp):
    if cp in _CP1252:
        cp = _CP1252[cp]
    if cp == 0 or cp > 0x10FFFF or (cp >= 0xD800 and cp <= 0xDFFF):
        return "�"
    return chr(cp)


def _decode_piece(p):
    """`p` is the text that followed an '&'.  Return its decoded form."""
    if p[:1] == "#":
        k = 1
        base = 10
        digits = _DIGITS
        if p[1:2] == "x" or p[1:2] == "X":
            k = 2
            base = 16
            digits = _HEXDIGITS
        start = k
        n = len(p)
        while k < n and k - start < 10 and p[k] in digits:
            k += 1
        if k == start:
            return "&" + p
        ch = _codepoint(int(p[start:k], base))
        if p[k:k + 1] == ";":
            k += 1
        return ch + p[k:]
    k = 0
    n = len(p)
    while k < n and k < 32 and p[k] in _NAMECHARS:
        k += 1
    if k == 0:
        return "&" + p
    name = p[:k]
    if p[k:k + 1] == ";":
        if name in NAMED:
            return NAMED[name] + p[k + 1:]
    elif name in _LEGACY:
        return NAMED[name] + p[k:]
    return "&" + p


def unescape(s):
    """Decode HTML entities in `s` ("&lt;b&gt; &amp; &#233;" -> "<b> & é")."""
    if "&" not in s:
        return s
    parts = s.split("&")
    out = [parts[0]]
    for p in parts[1:]:
        out.append(_decode_piece(p))
    return "".join(out)


def escape(s, quote=True):
    """Escape & < > (and " when `quote`) so `s` is safe in HTML text/attributes."""
    s = s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    if quote:
        s = s.replace('"', "&quot;")
    return s
