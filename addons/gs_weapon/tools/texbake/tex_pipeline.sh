#!/usr/bin/env bash
# The shared weapon texture bake (GameSpice Weapon, addons/gs_weapon/tools/texbake). Rebuilds the textures of the named
# models from their pristine sources and writes the textured GLBs:
#   tex_pipeline.sh <src dir with <name>.glb> <work dir> <out dir> <samples> <name>[:<size>]...
# <size> is the texture tier (default 1024; python runs with -P so a user-site numpy is found; the shipped sets use 512 for pistols, knives and ammo, 1024 for the rest, 2048
# for hero guns). Needs blender 4.3 and a python with numpy, scipy and PIL (PYTHON=... overrides python3).
# Env per model: AW_MODE=orig|smart (orig keeps the source UVs where they are good; smart re-unwraps), AW_WELD=1 for
# triangle-soup sources, AW_ANGLE, AW_WELD_DIST; AW_DEBUG=1 keeps the debug maps. Normal maps should then be re-encoded
# (JPEG q92 / WebP) by the caller to keep the web download down.
# blender needs numpy: add a site-packages dir with --python-expr "import sys; sys.path.append(...)" if its python lacks it.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
[ $# -ge 5 ] || { sed -n "2,9p" "$0"; exit 2; }
srcd=$1 work=$2 outd=$3 samples=$4; shift 4
py=${PYTHON:-python3}
mkdir -p "$work" "$outd"
for spec in "$@"; do
	n=${spec%%:*} size=1024
	[ "$n" = "$spec" ] || size=${spec#*:}
	AW_MODE=${AW_MODE:-orig} blender -b -P "$here/tex_bake.py" -- "$srcd/$n.glb" "$work/$n" "$size" "$samples" > "$work/$n.bake.log" 2>&1 || { echo "BAKE FAILED $n"; tail -5 "$work/$n.bake.log"; continue; }
	"$py" -P "$here/tex_gen.py" "$srcd/$n.glb" "$work/$n" "$outd/$n.glb" ${AW_DEBUG:+--debug} || echo "GEN FAILED $n"
done
