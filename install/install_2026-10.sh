#!/usr/bin/env bash
# Tool and PDK update of 2026-10 (approved by the owner on 2026-10-24: install, validate, then make the new versions
# the defaults; the old versions stay installed for reproducing published numbers).
# Usage: install_2026-10.sh <step>   steps: librelane | pdk | osscad | sram22 | orfs
# Each step is submitted separately through jobq.
set -euo pipefail
T=/media/hardware_design_tools
P=/media/pdk
source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
NIX=(nix --extra-experimental-features "nix-command flakes")
LL=$T/librelane-3.0.16          # LibreLane 3.0.16 (01ddb25, 2026-10-06): OpenROAD dcf3613, OpenSTA 857316f
SKY130_REV=8afc8346a57fe1ab7934ba5a6056ea8b43078e71   # open_pdks pinned by LibreLane 3.0.16 (pdk_hashes.yaml)
OSSCAD_DATE=2026-10-24
ORFS_REV=ef2cb3768   # ORFS 2026-02-12, OpenROAD 6975124 (73 commits before LibreLane 3.0.16's dcf3613)
ORFS_FFLIB_FIX=3a376ac862ad1b13e3e767c9fe2da4038f067238   # re-characterised RVT FF liberty (2026-02-23)
SRAM22_REV=de0a9a7cdabf941c807a5ab35864f80d97fccfea   # ucb-substrate/sram22_sky130_macros HEAD on 2026-10-24

case "${1:?step}" in
  librelane)
    # Build or fetch the LibreLane Nix shell and print the tool versions.
    "${NIX[@]}" develop --accept-flake-config "$LL" -c bash -c \
      'python3 -m librelane --version; openroad -version; sta -version; yosys -V; klayout -v; magic --version </dev/null || true'
    ;;
  pdk)
    # Fetch (do not enable) the sky130 PDK version LibreLane 3.0.16 is validated with.
    "${NIX[@]}" develop --accept-flake-config "$LL" -c bash -c \
      "ciel fetch --pdk-root $P --pdk-family sky130 $SKY130_REV && ciel ls --pdk-root $P --pdk-family sky130"
    ;;
  osscad)
    # OSS CAD Suite nightly next to the old one (Icarus master, Yosys, Verilator).
    d=$T/oss-cad-suite-$OSSCAD_DATE
    [[ -d $d ]] && { echo "$d exists"; exit 0; }
    tmp=$(mktemp -d "$T/.osscad.XXXX")
    url=$(gh release view "$OSSCAD_DATE" --repo YosysHQ/oss-cad-suite-build --json assets \
          -q '.assets[] | select(.name | test("linux-x64.*tgz$")) | .url')
    curl -fL --retry 3 -o "$tmp/osscad.tgz" "$url"
    tar -C "$tmp" -xzf "$tmp/osscad.tgz"
    mv "$tmp/oss-cad-suite" "$d"
    rm -f "$tmp/osscad.tgz"; rmdir "$tmp"
    "$d/bin/iverilog" -V 2>&1 | head -1; "$d/bin/yosys" -V; "$d/bin/verilator" --version
    ;;
  sram22)
    d=$P/sram22_sky130_macros-${SRAM22_REV:0:7}
    [[ -d $d ]] || git clone -q https://github.com/ucb-substrate/sram22_sky130_macros.git "$d"
    git -C "$d" checkout -q "$SRAM22_REV"
    git -C "$d" log -1 --format='%h %ci %s'
    ;;
  orfs)
    # New ORFS checkout next to the old one; the SRAM-Vt patch is re-applied afterwards (patches/ in flow_notes/install).
    d=$P/OpenROAD-flow-scripts-${ORFS_REV:0:7}
    [[ -d $d ]] || git clone -q --filter=blob:none https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts.git "$d"
    git -C "$d" checkout -q -B local-2026-10 "$ORFS_REV"
    git -C "$d" -c user.name=flow_notes -c user.email=none cherry-pick -x "$ORFS_FFLIB_FIX" || {
      git -C "$d" cherry-pick --abort; echo "cherry-pick of the FF liberty fix failed"; exit 3; }
    git -C "$d" log --oneline -3
    ;;
  *) echo "unknown step $1"; exit 2 ;;
esac
