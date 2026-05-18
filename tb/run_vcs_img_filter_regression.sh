#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RTL_DIR="$ROOT_DIR/rtl"
TB_DIR="$ROOT_DIR/tb"

MODE="${1:-directed}"

case "$MODE" in
  smoke)
    TOP="tb_img_filter_smoke"
    TB_FILE="$TB_DIR/tb_img_filter_smoke.v"
    BUILD_DIR="${TMPDIR:-/tmp}/img_filter_vcs_regression_smoke"
    SIMV="$BUILD_DIR/simv_img_filter_smoke"
    ;;
  directed)
    TOP="tb_img_filter_directed"
    TB_FILE="$TB_DIR/tb_img_filter_directed.v"
    BUILD_DIR="${TMPDIR:-/tmp}/img_filter_vcs_regression_directed"
    SIMV="$BUILD_DIR/simv_img_filter_directed"
    ;;
  regression)
    TOP="tb_img_filter_regression"
    TB_FILE="$TB_DIR/tb_img_filter_regression.v"
    BUILD_DIR="${TMPDIR:-/tmp}/img_filter_vcs_regression_regression"
    SIMV="$BUILD_DIR/simv_img_filter_regression"
    ;;
  *)
    echo "Usage: $0 [smoke|directed|regression]" >&2
    exit 1
    ;;
esac

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

vcs -full64 \
  +incdir+"$RTL_DIR" \
  "$RTL_DIR/img_filter_def.v" \
  "$RTL_DIR/img_filter.v" \
  "$TB_FILE" \
  -top "$TOP" \
  -o "$SIMV"

"$SIMV"
