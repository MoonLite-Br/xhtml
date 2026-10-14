# xhtml

**Super-beta** HTML toolkit for [cpy](https://github.com/MoonLite-Br/Cpy): parse, CSS select, extract, `fetch()`.

Successor name for the old `cpypi` package.

## Install

```bash
git clone https://github.com/MoonLite-Br/xhtml.git
cd xhtml
source ./install.sh
cpy -c 'import xhtml; print(xhtml.__version__)'
```

Do **not** name your script `xhtml.cpy`.

## Use

```python
import xhtml

doc = xhtml.parse(html, url="https://example.com")
print(doc.title)
print(doc.select_one("h1").text)

page = xhtml.fetch("https://example.com/")
print(page.status, page.title)
for link in page.links():
    print(link.href, link.text)
```

```bash
cpy examples/demo.cpy
cpy examples/smoke.cpy
cpy examples/fetch.cpy    # needs network + OpenSSL build of cpy
```

## Package layout

```
xhtml/
  __init__.cpy   core.cpy   selector.cpy
  entities.cpy   url.cpy    extract.cpy   http.cpy
install.sh   env.sh   examples/
```

## License

MIT · **0.1.0-beta**
