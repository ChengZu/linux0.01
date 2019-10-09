#!/bin/bash
#qemu-system-i386 -fda Image
make clean
make
cp Image bochs/Image
cd bochs
bash write.sh
bash run.sh
