# xhtml/http.cpy - fetch a page and hand back a parsed Document.
#
#   page = fetch("https://example.com")      # -> Page (a Document + response info)
#   page.select("a")                          # everything on Document works
#   page.status, page.headers, page.url
#
# Built on cpy's own `urllib` (HTTP/1.1 over `socket`, https:// via OpenSSL).
# Limits worth knowing:
#   * no gzip/deflate support (there is no zlib in cpy), so we send
#     "Accept-Encoding: identity"; servers that insist on compression will fail.
#   * cpy has no bytes type: bodies come back as text, so pages that are not
#     UTF-8 (Latin-1, Shift-JIS, ...) will not decode correctly.
#   * this is a plain HTTP client.  It does not execute JavaScript and does not
#     imitate a browser's TLS fingerprint - pages that need either will not work.
import urllib
from .core import parse, Document
from .url import urljoin, urlencode

DEFAULT_HEADERS = {
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
    "Accept-Encoding": "identity",
}


class Page(Document):
    """A parsed Document plus the response it came from."""

    def __init__(self, url, status, headers, text):
        Document.__init__(self, url)
        self.status = status
        self.headers = headers          # list of (name, value) pairs
        self.raw = text

    def header(self, name, default=None):
        name = name.lower()
        for k, v in self.headers:
            if k.lower() == name:
                return v
        return default

    def __repr__(self):
        return "<Page " + str(self.status) + " " + self.url + ">"


def fetch_text(url, params=None, headers=None, data=None, method=None, timeout=15, max_redirects=5):
    """Low-level request.  Returns (final_url, status, headers, body_text).
    `params` (dict) is appended to the query string; `data` (dict or str) is the body."""
    if params:
        url = url + ("&" if "?" in url else "?") + urlencode(params)
    hdrs = dict(DEFAULT_HEADERS)
    if headers:
        for k, v in headers.items():
            for existing in list(hdrs.keys()):
                if existing.lower() == k.lower():
                    del hdrs[existing]
            hdrs[k] = v
    body = None
    if data is not None:
        if isinstance(data, dict):
            body = urlencode(data)
            has_ct = False
            for k in hdrs:
                if k.lower() == "content-type":
                    has_ct = True
            if not has_ct:
                hdrs["Content-Type"] = "application/x-www-form-urlencoded"
        else:
            body = data
    if method is None:
        method = "POST" if body is not None else "GET"
    try:
        r = urllib.request(method, url, data=body, headers=hdrs, timeout=timeout, max_redirects=max_redirects)
    except urllib.HTTPError as e:
        raise FetchError(url, e.code, str(e), e.body)
    except urllib.URLError as e:
        raise FetchError(url, None, str(e), "")
    return r.url, r.status, r.headers, r.read()


class FetchError(Exception):
    def __init__(self, url, status, message, body):
        Exception.__init__(self, message)
        self.url = url
        self.status = status
        self.body = body


def fetch(url, params=None, headers=None, data=None, method=None, timeout=15, max_redirects=5):
    """GET (or POST when `data` is given) and parse the HTML response."""
    final, status, hdrs, body = fetch_text(url, params, headers, data, method, timeout, max_redirects)
    page = Page(final, status, hdrs, body)
    parsed = parse(body, final)
    page.children = parsed.children
    for c in page.children:
        c.parent = page
    return page


def follow(page, href, **kwargs):
    """Fetch `href` (possibly relative) relative to a page that was already fetched."""
    return fetch(urljoin(page.base_url() or page.url, href), **kwargs)
