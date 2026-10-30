# Paths and helpers of the validation flow (sourced). The versions are the installed defaults of the sky130 and ASAP7
# notes, section 1; override them in the environment to validate another set (LIBRELANE, PDK_ROOT, OSSCAD, ORFS).
FLOW="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS="$(cd "$FLOW/../../tools" && pwd)"
LIBRELANE="${LIBRELANE:-/media/hardware_design_tools/librelane}"
PDK_ROOT="${PDK_ROOT:-/media/pdk/sky130_8afc834}"
PDK="${PDK:-sky130A}"
OSSCAD="${OSSCAD:-/media/hardware_design_tools/oss-cad-suite}"
ORFS="${ORFS:-/media/pdk/OpenROAD-flow-scripts-ef2cb37}"
SRAM22="${SRAM22:-/media/pdk/sram22_sky130_fixed-de0a9a7}"
THREADS="${JOBQ_THREADS:-4}"
export PATH="$OSSCAD/bin:$PATH"
export PYTHONPYCACHEPREFIX="${TMPDIR:-/tmp}/flow_notes_pycache"
source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh

in_librelane() {   # run a command inside LibreLane's Nix environment (OpenROAD, OpenSTA, Yosys of the flow)
  nice -n 19 nix --extra-experimental-features "nix-command flakes" develop --accept-flake-config "$LIBRELANE" -c "$@"
}

load_design() {    # <design dir>: sets D and sources its design.sh
  D="$(cd "$1" && pwd)"
  [[ -f "$D/design.sh" ]] || { echo "no design.sh in $D"; exit 2; }
  source "$D/design.sh"
}

sim_ok() {         # <sim.log>: the testbench passed (PASS_REGEX), printed no FAIL/MISMATCH, and met real time
  grep -qE "$PASS_REGEX" "$1" || return 1
  ! grep -qE "^FAIL|^MISMATCH" "$1" || return 1
  local o; o=$(grep -oE "overruns=[0-9]+" "$1" | tail -n 1 | cut -d= -f2)
  [[ -z "$o" || "$o" == 0 ]]
}

versions_json() {  # the tool and PDK versions of a result, as JSON
  python3 - "$LIBRELANE" "$PDK_ROOT/$PDK/SOURCES" "$OSSCAD" "$ORFS" "$TOOLS" <<'PY'
import json, os, subprocess, sys
librelane, sources, osscad, orfs, tools = sys.argv[1:]
def git(path):
    try:
        return subprocess.run(["git", "-C", path, "rev-parse", "--short", "HEAD"], capture_output=True, text=True).stdout.strip()
    except OSError:
        return ""
iv = subprocess.run([f"{osscad}/bin/iverilog", "-V"], capture_output=True, text=True).stdout.splitlines()
print(json.dumps({"librelane": os.path.realpath(librelane),
                  "pdk": open(sources).readline().strip() if os.path.exists(sources) else "",
                  "icarus": iv[0] if iv else "", "orfs": os.path.realpath(orfs) + " " + git(orfs),
                  "flow_notes": git(tools)}))
PY
}
