#!/bin/sh

[ -L result ] && rm -f result

nix-build -A hls-musl

[ ! -L result ] && exit

out="hls-$(./result/bin/haskell-language-server-wrapper --version | awk '{ print $3 }' | sed 's@ @-@g')-musl-static-pie"
mkdir -p $out

for l in ./result/bin/*
do
  cp -f $(readlink $l) $out
done

rm -f result

