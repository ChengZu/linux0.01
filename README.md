# linux0.01

花了几天修改好了，可以在ubuntu18.04中直接编译和在bochs中运行，学习linux方便多了

roofs自己创建方法,loop18换成自己主机的

```bash
su
cd bochs
dd if=/dev/zero of=hdb.img bs=1M count=120
losetup /dev/loop18 hdb.img
#-H 4 -S 20 -C 3072 config in include/linux/config.h
#input “n“ to make partition, done next input "w" to write
#on ubuntu18.04,First sector (2048-81919, default 2048),2048x512=1048576
fdisk -H 4 -S 20 -C 3072 /dev/loop18
losetup -d /dev/loop18

losetup -o 1048576 /dev/loop18 hdb.img
mkfs.minix -n 14 /dev/loop18

tar -xzvf rootfs.tar.gz -C ./
mkdir hd
mount /dev/loop18 hd
cp -R rootfs/* hd
losetup -d /dev/loop18
umount hd
```
