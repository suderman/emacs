#!/usr/bin/env bash

set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

emacs --batch -l init.el -l test/run.el
bash test/install-fonts-test.sh
bash test/android-installer-test.sh
