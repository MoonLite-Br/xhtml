import xhtml

doc = xhtml.parse("""
<html><head><title>Demo</title></head>
<body>
  <h1 class="t">Hello</h1>
  <a href="/x">link</a>
</body></html>
""", url="https://example.com/")

print("title:", doc.title)
print("h1:", doc.select_one("h1.t").text)
for a in doc.select("a[href]"):
    print("a:", a["href"], a.text)
print("version:", xhtml.__version__)
