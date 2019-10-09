#!/bin/bash
if [ ! -f "hdb.img" ];then
unzip hdb.img.zip
fi
bochs -f linux.bxrc <<"EOF"

c
EOF
