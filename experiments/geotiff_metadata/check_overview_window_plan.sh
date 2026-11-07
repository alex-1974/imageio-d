#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
build="$root/.build"
mkdir -p "$build"
for compiler in dmd ldc2; do
    if [ "$compiler" = dmd ]; then version_flag=-version=OverviewWindowPlanProbe
    else version_flag=-d-version=OverviewWindowPlanProbe; fi
    "$compiler" -w -dip1000 "$version_flag" \
        -of="$build/overview-window-$compiler" "$root/overview_window_plan.d"
    "$build/overview-window-$compiler"
done
printf '%s\n' 'overview-aware window planning passed under DMD/LDC'
