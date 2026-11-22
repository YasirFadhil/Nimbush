#!/bin/sh
# Run from this directory. Then: git add genie.vert.qsb genie.frag.qsb
set -e
nix shell nixpkgs#qt6.qtshadertools -c sh -c '
  qsb --qt6 -o genie.vert.qsb genie.vert &&
  qsb --qt6 -o genie.frag.qsb genie.frag
'
