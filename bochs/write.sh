#!/bin/bash
rm a.img
cp empty.img a.img
dd if=./Image of=./a.img bs=10240 conv=notrunc
