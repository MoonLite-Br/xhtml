#!/bin/sh
#   cd xhtml && source ./install.sh
#   cpy -c 'import xhtml; print(xhtml.__version__)'
#
# Do not name your script xhtml.cpy — it shadows the package.

if [ -n "${BASH_SOURCE-}" ]; then
  _ROOT="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
  _ROOT="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
fi

if [ ! -f "$_ROOT/xhtml/__init__.cpy" ]; then
  echo "error: missing $_ROOT/xhtml/__init__.cpy" >&2
  return 1 2>/dev/null || exit 1
fi

case ":${CPY_PATH-}:" in
  *":$_ROOT:"*) ;;
  *) export CPY_PATH="$_ROOT${CPY_PATH:+:$CPY_PATH}" ;;
esac

_LINE="export CPY_PATH=\"$_ROOT\${CPY_PATH:+:\$CPY_PATH}\""
_MARK="# xhtml CPY_PATH"

for _f in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
  touch "$_f" 2>/dev/null || continue
  if grep -Fq "$_ROOT" "$_f" 2>/dev/null || grep -Fq "$_MARK" "$_f" 2>/dev/null; then
    continue
  fi
  printf '\n%s\n%s\n' "$_MARK" "$_LINE" >> "$_f"
  echo "saved -> $_f"
done

echo "ok  CPY_PATH has $_ROOT"
echo "ok  try:  cpy -c 'import xhtml; print(xhtml.__version__)'"

if [ -n "${BASH_VERSION-}" ] && [ "${BASH_SOURCE[0]}" = "$0" ]; then
  echo ""
  echo "You ran ./install.sh (subshell). For this terminal also run:"
  echo "  source \"$_ROOT/install.sh\""
fi

unset _ROOT _LINE _MARK _f
