#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (C) 2019 Netronome Systems, Inc.

cc=clang
output_dir=build_clang/
ncpu=$(grep -c processor /proc/cpuinfo)
build_flags="-Oline -j $ncpu W=1"
tmpfile_o=$(mktemp)
tmpfile_n=$(mktemp)
rc=0

prep_config() {
  make LLVM=1 O=$output_dir allmodconfig
  ./scripts/config --file $output_dir/.config -d werror
}

echo "Using $build_flags redirect to $tmpfile_o and $tmpfile_n"
echo "LLVM=1 cc=$cc"
$cc --version | head -n1

HEAD=$(git rev-parse HEAD)

echo "Tree base:"
git log -1 --pretty='%h ("%s")' HEAD~

if [ x$FIRST_IN_SERIES == x0 ]; then
    echo "Skip baseline build, not the first patch"
else
    echo "Baseline building the tree"

    prep_config
    make LLVM=1 O=$output_dir $build_flags
fi

git checkout -q HEAD~

echo "Building the tree before the patch"

prep_config
make LLVM=1 O=$output_dir $build_flags 2> >(tee $tmpfile_o >&2)
incumbent=$(grep -i -c "\(warn\|error\)" $tmpfile_o)

echo "Building the tree with the patch"

git checkout -q $HEAD

prep_config
make LLVM=1 O=$output_dir $build_flags 2> >(tee $tmpfile_n >&2) || rc=1

current=$(grep -i -c "\(warn\|error\)" $tmpfile_n)

echo "Errors and warnings before: $incumbent this patch: $current" >&$DESC_FD

if [ $current -gt $incumbent ]; then
  echo "New errors added" 1>&2
  diff -U 0 $tmpfile_o $tmpfile_n 1>&2

  echo "Per-file breakdown" 1>&2
  tmpfile_fo=$(mktemp)
  tmpfile_fn=$(mktemp)

  grep -i "\(warn\|error\)" $tmpfile_o | sed -n 's@\(^\.\./[/a-zA-Z0-9_.-]*.[ch]\):.*@\1@p' | sort | uniq -c \
    > $tmpfile_fo
  grep -i "\(warn\|error\)" $tmpfile_n | sed -n 's@\(^\.\./[/a-zA-Z0-9_.-]*.[ch]\):.*@\1@p' | sort | uniq -c \
    > $tmpfile_fn

  diff -U 0 $tmpfile_fo $tmpfile_fn 1>&2
  rm $tmpfile_fo $tmpfile_fn

  rc=1
fi

echo "Output lengths:" $(wc -l $tmpfile_n) $(wc -l $tmpfile_o)

rm $tmpfile_o $tmpfile_n

exit $rc
