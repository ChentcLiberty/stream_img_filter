#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RTL_DIR="$ROOT_DIR/rtl"
UVM_DIR="$ROOT_DIR/uvm"

CASE_ID="${CASE_ID:-1}"
UVM_TESTNAME="${UVM_TESTNAME:-img_filter_uvm_test}"
BUILD_DIR="${TMPDIR:-/tmp}/img_filter_vcs_uvm_case_${CASE_ID}"
SIMV="$BUILD_DIR/simv_img_filter_uvm"

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

vcs -full64 \
  -sverilog \
  -ntb_opts uvm-1.2 \
  -override_timescale=1ns/1ps \
  +incdir+"$RTL_DIR" \
  +incdir+"$UVM_DIR" \
  "$RTL_DIR/img_filter_def.v" \
  "$RTL_DIR/img_filter.v" \
  "$UVM_DIR/img_filter_if.sv" \
  "$UVM_DIR/img_filter_mem_model.sv" \
  "$UVM_DIR/img_filter_pkg.sv" \
  "$UVM_DIR/tb_img_filter_uvm_top.sv" \
  -top tb_img_filter_uvm_top \
  -o "$SIMV"

"$SIMV" +UVM_TESTNAME="$UVM_TESTNAME" +CASE_ID="$CASE_ID"
