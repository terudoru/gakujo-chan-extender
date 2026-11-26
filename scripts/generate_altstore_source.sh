#!/usr/bin/env bash

altstore_python=python3
if [[ "$OSTYPE" == msys* ]] && command -v python >/dev/null 2>&1; then
  altstore_python=python
fi
exec "$altstore_python" "$(dirname "$0")/generate_altstore_source.py" "$@"
