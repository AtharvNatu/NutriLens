#!/usr/bin/env bash
# Re-renders the looping exercise videos bundled with the app (original artwork; see tools/ExerciseAnimator).
# Usage: scripts/render_exercise_videos.sh [--preview <dir-for-contact-sheets>]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT="$PROJECT_DIR/NutriLens/Resources/ExerciseVideos"
mkdir -p "$OUT"
cd "$PROJECT_DIR/tools/ExerciseAnimator"
swift run -c release ExerciseAnimator "$OUT" "$@"
