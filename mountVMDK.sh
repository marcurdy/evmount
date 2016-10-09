#!/bin/bash
# There is a huge learning curve to mounting VMDK's in Linux.  This aids that.
#
# 1) Detect the VMDK container type
# 2) Recommend a conversion of vmdk type if necessary
# 3) Mount the container to expose the FS if necessary
# 4) Detect a volume manager
# 5) Mount the raw FS
# 6) Avoid giving in to Windows

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

HALT=0
# Check OS prerequisites
vdiskmgr=`which vmware-vdiskmanager`
if [ -z "$vdiskmgr" ]; then
  echo "#INFO# vmware-vdiskmanager is missing. Install VMware-vix-disklib if vmdk is incompat with libvmdk"
fi

libvmdk=`which vmdkinfo`
if [ -z "$libvmdk" ]; then
  echo "#ERROR# libvmdk must be installed with vmdkinfo and vmdkmount in your path."
  HALT=1
fi
gentools=`which kpartx xmount losetup | wc -l`
if [ "$gentools" -lt 3 ]; then
  echo "#ERROR# Please install kpartx, xmount, and losetup"
  HALT=1
fi
if [ $HALT == 1 ]; then
  exit 1
fi

FILETYPE=`file $file | awk -F: '{ print $2 }' | sed 's?^ ??'`
echo ""
echo "#INFO# Analyzing $file of type: \"$FILETYPE\""

if [ "$FILETYPE" == "ASCII text" ] || [ "$FILETYPE" == "VMware4 disk image" ] || [ "$FILETYPE" == "VMWare3" ]; then 
  VMTYPE=`vmdkinfo $file | grep 'Disk type:' | awk -F: '{ print $2 }'`
  if [ -z "$VMTYPE" ]; then
    echo "#INFO# Your VMDK was not detected. Check input file integrity"
    exit 0
  elif [ -n "`echo $VMTYPE | egrep -i 'sparse|flat|raw'`" ]; then
    echo "#RUN# mkdir -p /media/${name}"
    echo "#RUN# mkdir -p /media/${name}_data"
    echo "#RUN# vmdkmount $file /media/${name}"
    echo "#RUN# $0 /media/${name}_data/*"
  else
    echo "#INFO# Your image is not compatible with libvmdk and must be converted"
    filebase=`echo $file | rev | cut -d'.' -f2- | rev`
    echo "#RUN# vmware-vdiskmanager -r $file -t 0 ${filebase}-converted.vmdk"
    echo "#INFO# Rerun $0 with ${filebase}-converted.vmdk"
  fi
# An LVM2 partition is a subset of x86 boot sector, and i don't want to reuse code
elif [ "$FILETYPE" == "x86 boot sector" ] || [ "$FILETYPE" == "LVM2" ]; then
  LVMS=$file
  if [ "$FILETYPE" == "x86 boot sector" ]; then
    LVMS=`mmls -Ma $file | grep 'Linux Logical'`
  fi
    echo $LVMS | while read FS; do
    echo "#INFO# Found partition of type Linux Logic Volume"
    OFFSET=$((`echo $FS | awk '{ print $3 }' | sed 's?^0*??'`*512))
    echo "#RUN# losetup -j -o $OFFSET $file | tail -1"
    echo "#RUN# lvs"
    echo "#RUN# mkdir -p /media/${name}"
    echo "#MANUAL# Mount root as /media/${name} from the lvs output"
    echo "#RUN# awk '{ print \"mount -t \" \$3 \" \" \$1 \" \" \$2 }' /media/${name}/etc/fstab"
  done
  mmls -Ma $file | grep 'Linux' | grep -v Logical | while read FS; do
    echo "#INFO# Found partition of type Linux Native"
    OFFSET=$((`echo $FS | awk '{ print $3 }' | sed 's?^0*??'`*512))
    echo "#RUN# mkdir -p /media/${name}"
    echo "#RUN# mount -o offset=$OFFSET $file /media/${name}/boot"
    echo "#RUN# cat /media/${name}/etc/fstab"
  done
  mmls -Ma $file | grep 'NTFS ' | while read FS; do
    echo "#INFO# Found partition of type NTFS"
    OFFSET=$((`echo $FS | awk '{ print $3 }' | sed 's?^0*??'`*512))
    echo "#RUN# mkdir -p /media/${name}"
    echo "#RUN# mount -o ro,show_sys_files,streams_interface=windows,offset=$OFFSET $file /media/${name}"
  done
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
fi
