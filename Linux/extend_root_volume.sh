#!/bin/bash
# This will attempt to automatically detect the LVM logical volume where / is mounted and then 
# expand the underlying physical partition, LVM physical volume, LVM volume group, LVM logical
# volume, and Linux filesystem to consume new free space on the disk. 
# Adapted from https://github.com/alpacacode/Homebrewn-Scripts/blob/master/linux-scripts/partresize.sh

extenddisk() {
    echo -e "\n+++Current partition layout of $disk:+++"
    parted $disk --script unit s print
    if [ $logical == 1 ]; then
        parted $disk --script rm $ext_partnum
        parted $disk --script "mkpart extended ${ext_startsector}s -1s"
        parted $disk --script "set $ext_partnum lba off"
        parted $disk --script "mkpart logical ext2 ${startsector}s -1s"
    else
        parted $disk --script rm $partnum
        parted $disk --script "mkpart primary ext2 ${startsector}s -1s"
    fi
    parted $disk --script set $partnum lvm on
    echo -e "\n\n+++New partition layout of $disk:+++"
    parted $disk --script unit s print
    partx -v -a $disk
    pvresize $pvname
    lvextend --extents +100%FREE --resize $lvpath 
    echo -e "\n+++New root partition size:+++"
    df -h / | grep -v Filesystem
}
export LVM_SUPPRESS_FD_WARNINGS=1
mountpoint=$(df --output=source / | grep -v Filesystem) # /dev/mapper/centos-root
lvdisplay $mountpoint > /dev/null
if [ $? != 0 ]; then
    echo "Error: $mountpoint does not look like a LVM logical volume. Aborting."
    exit 1
fi
echo -e "\n+++Current root partition size:+++"
df -h / | grep -v Filesystem
lvname=$(lvs --noheadings $mountpoint | awk '{print($1)}') # root
vgname=$(lvs --noheadings $mountpoint | awk '{print($2)}') # centos
lvpath="/dev/${vgname}/${lvname}" # /dev/centos/root
pvname=$(pvs | grep $vgname | tail -n1 | awk '{print($1)}') # /dev/sda2
disk=$(echo $pvname | rev | cut -c 2- | rev) # /dev/sda 
diskshort=$(echo $disk | grep -Po '[^\/]+$') # sda
partnum=$(echo $pvname | grep -Po '\d$') # 2
startsector=$(fdisk -u -l $disk | grep $pvname | awk '{print $2}') # 2099200
layout=$(parted $disk --script unit s print) # Model: VMware Virtual disk (scsi) Disk /dev/sda: 83886080s Sector size (logical/physical): 512B/512B Partition Table: msdos Disk Flags: Number Start End Size Type File system Flags 1 2048s 2099199s 2097152s primary xfs boot 2 2099200s 62914559s 60815360s primary lvm
if grep -Pq "^\s$partnum\s+.+?logical.+$" <<< "$layout"; then
    logical=1
    ext_partnum=$(parted $disk --script unit s print | grep extended | grep -Po '^\s\d\s' | tr -d ' ')
    ext_startsector=$(parted $disk --script unit s print | grep extended | awk '{print $2}' | tr -d 's')
else
    logical=0
fi
parted $disk --script unit s print | if ! grep -Pq "^\s$partnum\s+.+?[^,]+?lvm\s*$"; then
    echo -e "Error: $pvname seems to have some flags other than 'lvm' set."
    exit 1
fi
if ! (fdisk -u -l $disk | grep $disk | tail -1 | grep $pvname | grep -q "Linux LVM"); then
    echo -e "Error: $pvname is not the last LVM volume on disk $disk."
    exit 1
fi
ls /sys/class/scsi_device/*/device/rescan | while read path; do echo 1 > $path; done
ls /sys/class/scsi_host/host*/scan | while read path; do echo "- - -" > $path; done
extenddisk
