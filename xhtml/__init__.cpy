# xhtml — read, scrape and query HTML from cpy.
#
#   import xhtml
#   doc = xhtml.parse("<ul><li class=a>x</li></ul>")
#   doc.select("li.a")[0].text
#   page = xhtml.fetch("https://example.com")
#   [l.href for l in page.links()]
from .core import (parse, Document, Element, Text, Comment, Doctype, Node)
from .selector import select, select_one, matches, SelectorError, compile_selector
from .entities import unescape, escape
from .url import urljoin, urlsplit, urlencode, quote, unquote, parse_qs, parse_qsl
from .extract import links, images, table_rows, table_dicts, form_fields, meta, text_of
from .http import fetch, fetch_text, follow, Page, FetchError

__version__ = "0.1.0-beta"
__all__ = [
    "parse", "Document", "Element", "Text", "Comment", "Doctype", "Node",
    "select", "select_one", "matches", "SelectorError", "compile_selector",
    "unescape", "escape",
    "urljoin", "urlsplit", "urlencode", "quote", "unquote", "parse_qs", "parse_qsl",
    "links", "images", "table_rows", "table_dicts", "form_fields", "meta", "text_of",
    "fetch", "fetch_text", "follow", "Page", "FetchError",
    "__version__",
]
