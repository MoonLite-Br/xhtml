import xhtml

html = """<html><head><title>T &amp; X</title></head>
<body><h1 id="t" class="x">Hi</h1>
<ul><li class="i">a</li><li class="i on">b</li></ul>
<a href="/p">p</a></body></html>"""

doc = xhtml.parse(html, url="https://ex.com/")
assert doc.title == "T & X"
assert doc.select_one("h1#t").text.strip() == "Hi"
assert len(doc.select("li.i")) == 2
assert doc.select_one("li.i.on").text.strip() == "b"
print("ok", xhtml.__version__)
