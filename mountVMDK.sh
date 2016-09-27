#!/bin/bash
# What's before an alpha release?
# That's what this is

if [ ! -f "$1" ]; then
  echo 'linuxMountAssist.sh <image file>'
  exit 1
fi
file=$1
name=`basename $file | awk -F\. '{ print $1 }'`
if [ -z "`echo $file | grep -i vmdk `" ]; then
  echo "Only supporting VMDK\'s now"
  exit 1
fi

FILETYPE=`file $file | awk -F: '{ print $2 }' | sed 's?^ ??'`
echo ""
echo "#INFO# Analyzing $file of type: \"$FILETYPE\""
echo "#RUN# mkdir -p /media/${name}"

if [ "$FILETYPE" == "ASCII text" ]; then
  echo "#INFO# This is not a valid VMDK file.  This is ASCII and points to the binary VMDK's"
  exit 0
elif [ "$FILETYPE" == "VMware4 disk image" ]; then
  if [ -n "`strings $file | head -10 | grep 'streamOptimized'`" ]; then
    echo "#INFO# Your VMDK is streamOptimized. It must be converted"
    echo "#RUN# /usr/local/bin/vmware-vdiskmanager -r $file -t 0 ${file}-converted"
    exit 0
  fi
  echo "#RUN# losetup -f $file"
  echo "#MANUAL# McCurdy needs feedback on if this mounts logical volumes automatically"

elif [ "$FILETYPE" == "LVM2" ]; then
  echo "#RUN# losetup -f $file"
  MEMVG="`vgs | tail -n +2  | awk '{ print $1 }' | tr '\n' ','`"
  echo "#INFO# Found these Volume Groups before losetup: $MEMVG"
  echo "#MANUAL# mount these logical volumes manually"
  echo "#RUN# vgs | tail -n +2  | awk '{ print \$1 }' | while read VG; do"
  echo "#RUN#   if [ -z \"\`echo \$MEMVG | grep \\\",\$VG,\\\"\`\" ]; then"
  echo "#MANUAL# Mount all the LVs from Volume Group \$VG"
  echo "#RUN#   fi"
  echo "#RUN# done"
elif [ "$FILETYPE" == "x86 boot sector" ]; then
  mmls -Ma $file | grep 'Linux Logical' | while read FS; do
    echo "#INFO# Found partition of type Linux Logic Volume"
    OFFSET=$((`echo $FS | awk '{ print $3 }' | sed 's?^0*??'`*512))
    echo "#RUN# losetup -f -o $OFFSET $file"
    echo "#RUN# lvs"
    echo "#MANUAL# Mount the root partition as /media/${name}"
    echo "#RUN# awk '{ print \"mount -t \" \$3 \" \" \$1 \" \" \$2 }' /media/${name}/etc/fstab"
  done
  mmls -Ma $file | grep 'Linux' | grep -v Logical | while read FS; do
    echo "#INFO# Found partition of type Linux Native"
    OFFSET=$((`echo $FS | awk '{ print $3 }' | sed 's?^0*??'`*512))
    echo "#RUN# mount -o offset=$OFFSET $file /media/${name}/boot"
    echo "#RUN# cat /media/${name}/etc/fstab"
  done
  mmls -Ma $file | grep 'NTFS ' | while read FS; do
    echo "#INFO# Found partition of type NTFS"
    OFFSET=$((`echo $FS | awk '{ print $3 }' | sed 's?^0*??'`*512))
    echo "#RUN# mount -o ro,show_sys_files,streams_interface=windows,offset=$OFFSET $file /media/${name}/XYZ"
  done
fi
