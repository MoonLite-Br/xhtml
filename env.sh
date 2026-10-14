# source ./env.sh
if [ -n "${BASH_SOURCE-}" ]; then
  _r="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
  _r="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
fi
case ":${CPY_PATH-}:" in
  *":$_r:"*) ;;
  *) export CPY_PATH="$_r${CPY_PATH:+:$CPY_PATH}" ;;
esac
echo "CPY_PATH=$CPY_PATH"
unset _r
