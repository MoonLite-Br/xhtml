import xhtml

page = xhtml.fetch("https://example.com/")
print("status:", page.status)
print("title :", page.title)
for a in page.select("a[href]")[:5]:
    print(" ", a.attrs.get("href"), "|", " ".join(a.get_text().split()))
