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
  echo '$0 <image file>'
  exit 1
fi
file=$1
name=`basename $file | awk -F\. '{ print $1 }'`
if [ -z "`echo $file | grep -i vmdk `" ]; then
  echo "Only supporting VMDK\'s now"
  exit 1
fi

function randomdir {

  #Create a random mount name to avoid conflicts due to common names of devices
  cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 6 | head -n 1 | sed 's?^?LM?'
}

function checkmount {

  #Check if a file and optional offset are already mounted
  LOCHECK=`losetup -a | grep -F "$1" | grep -F "$2"`
  if [ -z "$LOCHECK" ]; then
    echo 0
  else
    echo 1
  fi
}

HALT=0
# Check OS prerequisites
vdiskmgr=`which vmware-vdiskmanager`
if [ -z "$vdiskmgr" ]; then
  echo "WARNING: vmware-vdiskmanager is missing. Install VMware-vix-disklib if vmdk is incompat with libvmdk"
fi

libvmdk=`which vmdkinfo`
if [ -z "$libvmdk" ]; then
  echo "ERROR: libvmdk must be installed with vmdkinfo and vmdkmount in your path."
  HALT=1
fi
gentools=`which kpartx xmount losetup | wc -l`
if [ "$gentools" -lt 3 ]; then
  echo "ERROR: Please install kpartx, xmount, and losetup"
  HALT=1
fi
if [ $HALT == 1 ]; then
  exit 1
fi


# Clean up any past created mount points that aren't in use
rmdir /media/LM*

FILETYPE=`file $file | awk -F: '{ print $2 }' | sed 's?^ ??'`
echo "Analyzing $file of type: \"$FILETYPE\""

if [ "$FILETYPE" == "ASCII text" ] || [ "$FILETYPE" == "VMware4 disk image" ] || [ "$FILETYPE" == "VMWare3" ]; then 
  VMTYPE=`vmdkinfo $file 2>/dev/null | grep 'Disk type:' | awk -F: '{ print $2 }'`
  if [ -z "$VMTYPE" ]; then
    echo "ERROR: Your VMDK was not detected"
    echo "ERROR: Troubleshoot: Point to ascii vmdk instead. Check vmdk integrity"
    exit 0
  elif [ -n "`echo $VMTYPE | egrep -i 'sparse|flat|raw'`" ]; then
    name=`randomdir`
    mkdir -p /media/${name}
    echo "Mounting $file as /media/${name}"
    vmdkmount $file /media/${name} > /dev/null 2>/dev/null
    if [ $? == 1 ]; then
      echo "ERROR: vmdkmount failed mounting $file"
      exit 1
    fi
    $0 /media/${name}/*
    exit 0
  else
    echo "ERROR: Your image is not compatible with libvmdk and must be converted"
    filebase=`echo $file | rev | cut -d'.' -f2- | rev`
    echo "RUN: vmware-vdiskmanager -r $file -t 0 ${filebase}-converted.vmdk"
    echo "RUN: $0 ${filebase}-converted.vmdk"
  fi
# An LVM2 partition is a subset of x86 boot sector, and i don't want to reuse code
elif [ "$FILETYPE" == "x86 boot sector" ]; then

  mmls -Ma $file | grep 'Linux Logical' | while read FS; do
    echo "Found partition of type Linux Logical Volume"
    OFFSET=$((`echo $FS | awk '{ print $3 }' | sed 's?^0*??'`*512))
    if [ -n "$OFFSET" ]; then
      #checkmount $file $OFFSET
      #if [ `checkmount $file $OFFSET` == 1 ]; then
      #  echo "WARNING: Logical Volume already mounted"
      #else
        losetup -f $file -o $OFFSET
      #fi
      LB=`losetup -j $file -o $OFFSET | tail -1 | awk -F: '{ print $1 }'`
      VG=`pvs | grep $LB | awk '{ print $2 }'`
      vgdisplay -v $VG 2>/dev/null | grep 'LV Path' | awk '{ print $3 }'
      echo "NOTE: Mount these logical volumes manually. If the root FS is included, mount"
      echo "  root before any mounts in its subdirectory. See root's etc/fstab for LVM mapping."
      echo "  Use fls -rupF /device/name to look within without first mounting"
    else
      echo "ERROR: Failed to identify offset for Linux Logical partition. Skipping."
    fi
  done
  mmls -Ma $file | grep 'Linux (' | while read FS; do
    echo "Found partition of type Linux Native"
    name=`randomdir`
    OFFSET=$((`echo $FS | awk '{ print $3 }' | sed 's?^0*??'`*512))
    if [ `checkmount $file $OFFSET` == 1 ]; then
      echo "WARNING: Linux FS already mounted"
    else
      mkdir -p /media/${name}
      echo "Mounting Linux partition $file offset $OFFSET as /media/${name}"
      mount -o offset=$OFFSET $file /media/${name}
    fi
  done
  mmls -Ma $file | grep 'NTFS ' | while read FS; do
    echo "Found partition of type NTFS"
    name=`randomdir`
    OFFSET=$((`echo $FS | awk '{ print $3 }' | sed 's?^0*??'`*512))
    if [ `checkmount $file $OFFSET` == 1 ]; then
      echo "WARNING: NTFS volume already mounted"
    else
      mkdir -p /media/${name}
      echo "Mounting NTFS FS as /media/${name}"
      mount -o ro,show_sys_files,streams_interface=windows,offset=$OFFSET $file /media/${name}
    fi
  done
elif [ -n "`echo \"$FILETYPE\" | grep LVM2`" ]; then
  #if [ `checkmount $file` == 1 ]; then
  #  echo "WARNING: Logical Volume already mounted"
  #else
    losetup -f $file >/dev/null 2>&1
    if [ $? == 1 ]; then
      echo "ERROR: losetup of LVM2 device $file has failed"
      exit 1
    fi
  #fi
  echo "Listing logical volumes underneath this LVM device"
  LB=`losetup -j $file | awk -F: '{ print $1 }'`
  VG=`pvs | grep $LB | awk '{ print $2 }'`
  vgdisplay -v $VG 2>/dev/null | grep 'LV Path' | awk '{ print $3 }'
  echo "NOTE: Mount these logical volumes manually. If the root FS is included,"
  echo "  mount root before any mounts in a root subdirectory. See root's etc/fstab for LVM mapping"
  echo "  Use fls -rupF /device/name to look within without first mounting"
  exit 0
fi
