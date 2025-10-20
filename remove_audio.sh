#!/usr/bin/env bash
# remove_audio.sh — strip audio from MP4/MOV files without re-encoding video.
# Writes <basename>_noaudio.<ext> into a per-folder "noaudio/" subdirectory.
set -euo pipefail

usage() {
  cat <<'EOF'
remove_audio.sh — remove audio tracks from MP4/MOV files (writes into ./noaudio)

USAGE:
  remove_audio.sh                    # process all *.mp4/*.MP4/*.mov/*.MOV in current directory
  remove_audio.sh <file|dir> [...]   # process specific files and/or directories
  remove_audio.sh -h | --help        # show this help

OUTPUTS:
  For each input video, the output is written to a "noaudio" subfolder in the
  same directory as the input, named <basename>_noaudio.<ext>. Example:
    /path/to/Video.MP4  ->  /path/to/noaudio/Video_noaudio.MP4
    /path/to/Clip.MOV   ->  /path/to/noaudio/Clip_noaudio.MOV

NOTES:
  • Existing outputs are not overwritten; we append (1), (2), ...
  • Files already ending with *_noaudio.<ext> are skipped.
  • Requires ffmpeg (install: brew install ffmpeg)
EOF
}

[[ "${1-}" == "-h" || "${1-}" == "--help" ]] && { usage; exit 0; }

# Locate ffmpeg (PATH, then common Homebrew paths)
FFMPEG_BIN="$(command -v ffmpeg || true)"
if [[ -z "$FFMPEG_BIN" ]]; then
  for p in /opt/homebrew/bin/ffmpeg /usr/local/bin/ffmpeg; do
    [[ -x "$p" ]] && { FFMPEG_BIN="$p"; break; }
  done
fi
[[ -z "$FFMPEG_BIN" ]] && { echo "Error: ffmpeg not found. Try: brew install ffmpeg" >&2; exit 1; }

# Portable absolute path (no GNU realpath)
abspath() {
  local t="$1"
  if [[ -d "$t" ]]; then (cd "$t" && pwd -P); else
    local d; d="$(cd "$(dirname "$t")" && pwd -P)" || return 1
    printf '%s/%s' "$d" "$(basename "$t")"
  fi
}

# Create a unique output path inside "<dir>/noaudio" like "<dir>/noaudio/<base>_noaudio.<ext>"
unique_outpath() {
  local in="$1" dir base ext out n outdir
  dir="$(dirname "$in")"
  base="$(basename "$in")"
  ext="${base##*.}"            # preserve original extension case
  base="${base%.*}"
  outdir="${dir}/noaudio"
  mkdir -p "$outdir"

  out="${outdir}/${base}_noaudio.${ext}"
  if [[ ! -e "$out" ]]; then printf '%s' "$out"; return; fi
  n=1
  while :; do
    local cand="${outdir}/${base}_noaudio(${n}).${ext}"
    [[ ! -e "$cand" ]] && { printf '%s' "$cand"; return; }
    ((n++))
  done
}

process_file() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  # Only .mp4/.MP4/.mov/.MOV
  [[ "$f" =~ \.([mM][pP]4|[mM][oO][vV])$ ]] || return 0

  local abs out base parentdir
  abs="$(abspath "$f")"

  # Skip files already *_noaudio.<ext>
  base="$(basename "$abs")"
  [[ "${base%.*}" == *"_noaudio" ]] && { echo "Skipping (already no-audio): $abs"; return 0; }

  # Also skip inputs that are already in a "noaudio" directory (avoid reprocessing outputs)
  parentdir="$(basename "$(dirname "$abs")")"
  if [[ "$parentdir" == "noaudio" ]]; then
    echo "Skipping (in noaudio dir): $abs"
    return 0
  fi

  out="$(unique_outpath "$abs")"
  echo "Processing: $abs"
  echo " -> Output : $out"
  # -an removes audio, -c:v copy avoids re-encoding (fast), +faststart improves playback start
  "$FFMPEG_BIN" -hide_banner -loglevel error -i "$abs" -an -c:v copy -movflags +faststart "$out"
  echo "Done."
}

# Enumerate targets directly (no temp files, no pipes)
shopt -s nullglob

processed=false
if [[ "$#" -gt 0 ]]; then
  for arg in "$@"; do
    if [[ -d "$arg" ]]; then
      # Non-recursive; expand all relevant extensions
      for f in "$arg"/*.mp4 "$arg"/*.MP4 "$arg"/*.mov "$arg"/*.MOV; do
        [[ -e "$f" ]] || continue
        process_file "$f"
        processed=true
      done
    elif [[ -f "$arg" ]]; then
      process_file "$arg"
      processed=true
    else
      echo "Warning: Skipping non-existent path: $arg" >&2
    fi
  done
else
  for f in ./*.mp4 ./*.MP4 ./*.mov ./*.MOV; do
    [[ -e "$f" ]] || continue
    process_file "$f"
    processed=true
  done
fi

$processed || {
  echo "No .mp4/.MP4/.mov/.MOV files found to process in the specified paths." >&2
  echo "Tip: run 'remove_audio.sh --help' for usage and examples." >&2
}
