#!/bin/bash
# There is a huge learning curve to mounting VMDK's in Linux.  This aids that.
#
# 1) If VMDK, detect the VMDK container type and request a conversion if necessary
# 2) Mount the E01/VMDK container to expose the FS's
# 3) Detect a logical volume manager
# 4) Mount the raw FS
# 5) Avoid giving in to Windows

if [ "$1" == "-u" ]; then
  echo "Unmounting is complicated and can affect multiple mounted images.  Follow these steps"
  echo "1. Unmount all file partitions seen in \"mount\" output: umount /xxx/yyy"
  echo "2. Deactivate the VG if appl: vgchange -a n VGNAME"
  echo "3. Remove loopback devices seen in \"losetup\" -a output: losetup -d /dev/loopX"
  echo "4. Unmount any containers under /media: umount /media/*"
  echo "5. Optionally remove the empty mount directories"
  exit 0
fi

if [ ! -f "$1" ]; then
  echo 'Evidence Mounter'
  echo '$0 <image file> [mount directory]'
  echo '$0 -u[nmount all]'
  exit 1
fi

file="$1"
mountdir=`echo "$2" | sed 's?\/$??g'`

if [ -n "$mountdir" ] && [ -a $mountdir ] && ([ ! -d $mountdir ] || [ -n "`mount | awk '{ print $3 }' | $mountdir`" ]); then
  echo "Error: Preexisting mount directory is not a dir or already contains a mounted object."
  exit 1
fi

function randomdir {

  #Create a random mount name to avoid conflicts due to common names of devices
  cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 6 | head -n 1 | sed 's?^?LM?'
}

function checkmount {

  #Check if a file and optional offset are already mounted
  #Fuse FS don't readily expose their underlying disk+offset. Disabled for FUSE mounts.
  LOCHECK=`losetup -a | grep -F "$1" | grep -F "$2"`
  if [ -z "$LOCHECK" ]; then
    echo 0
  else
    echo 1
  fi
}

function lvmprocess {

  file=$1
  offset=$2

  losetup -f $file -o $offset >/dev/null 2>&1
  sleep 1
  if [ $? == 1 ]; then
    echo "ERROR: losetup of LVM2 device $file has failed"
    exit 1
  fi
  echo "Listing logical volumes underneath this LVM device"
  LB=`losetup -j $file | awk -F: '{ print $1 }'`
  VG=`pvs | grep $LB | awk '{ print $2 }'`
  if [ -n "$VG" ]; then
    if [ -z "$mountdir" ]; then
      mt=/media/`randomdir`
    else
      mt=$mountdir
    fi
    if [ ! -d $mt ]; then
      mkdir -p $mt
    fi
    vgdisplay -v $VG 2>/dev/null | grep 'LV Path' | awk '{ print $3 }' | while read LV; do
      LVMT=$mt/`randomdir`
      mkdir -p $LVMT
      echo "Automounting logical volume $LV as $LVMT"
      mount $LV $LVMT
    done
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
gentools=`which ewfmount losetup | wc -l`
if [ "$gentools" -lt 2 ]; then
  echo "ERROR: Please install ewfmount and losetup"
  HALT=1
fi
if [ $HALT == 1 ]; then
  exit 1
fi


# Clean up any past created mount points that aren't in use. rmdir only removes empty dirs
rmdir /media/LM* >/dev/null 2>&1

FILETYPE=`file $file | awk -F: '{ print $2 }' | sed 's?^ ??'`
echo "Analyzing $file of type: \"$FILETYPE\""

if [ "$FILETYPE" == "ASCII text" ] || [ "$FILETYPE" == "VMware4 disk image" ] || [ "$FILETYPE" == "VMWare3" ]; then 
  VMTYPE=`vmdkinfo $file 2>/dev/null | grep 'Disk type:' | awk -F: '{ print $2 }'`
  if [ -z "$VMTYPE" ]; then
    echo "ERROR: Your VMDK is invalid"
    echo "ERROR: Tips: Reference the parent vmdk. Check vmdk integrity/md5"
    exit 0
  elif [ -n "`echo $VMTYPE | egrep -i 'sparse|flat|raw'`" ]; then
    vmdkmt=/media/`randomdir`
    mkdir -p $vmdkmt
    echo "Mounting $file as $vmdkmt"
    vmdkmount $file $vmdkmt > /dev/null 2>/dev/null
    if [ $? == 1 ]; then
      echo "ERROR: vmdkmount failed mounting $file"
      exit 1
    fi
    $0 $vmdkmt/* $mountdir
    exit 0
  else
    echo "ERROR: Your image is not compatible with libvmdk and must be converted"
    filebase=`echo $file | rev | cut -d'.' -f2- | rev`
    echo "RUN: vmware-vdiskmanager -r $file -t 0 ${filebase}-converted.vmdk"
    echo "RUN: $0 ${filebase}-converted.vmdk"
  fi
# An LVM2 partition is a subset of x86 boot sector
elif [ "$FILETYPE" == "x86 boot sector" ]; then

  mmls -Ma $file | grep 'Linux Logical' | while read FS; do
    echo "Found partition of type Linux Logical Volume"
    OFFSET=$((`echo $FS | awk '{ print $3 }' | sed 's?^0*??'`*512))
    if [ -n "$OFFSET" ]; then
      lvmprocess $file $OFFSET
    else
      echo "ERROR: Failed to identify offset for Linux Logical partition. Skipping."
    fi
  done
  mmls -Ma $file | grep 'Linux (' | while read FS; do
    echo "Found partition of type Linux Native"
    OFFSET=$((`echo $FS | awk '{ print $3 }' | sed 's?^0*??'`*512))
    if [ `checkmount $file $OFFSET` == 1 ]; then
      echo "WARNING: Linux FS already mounted"
    else
      if [ -z "$mountdir" ]; then
        mt=/media/`randomdir`
      else
        mt=$mountdir/`randomdir`
      fi
      mkdir -p $mt
      echo "Mounting Linux partition $file offset $OFFSET as $mt"
      mount -o offset=$OFFSET $file $mt
    fi
  done
  mmls -Ma $file | grep 'NTFS ' | while read FS; do
    echo "Found partition of type NTFS"
    OFFSET=$((`echo $FS | awk '{ print $3 }' | sed 's?^0*??'`*512))
    if [ `checkmount $file $OFFSET` == 1 ]; then
      echo "WARNING: NTFS volume already mounted"
    else
      if [ -z "$mountdir" ]; then
        mt=/media/`randomdir`
      else
        mt=$mountdir/`randomdir`
      fi
      mkdir -p $mt
      echo "Mounting NTFS FS as $mt"
      mount -t ntfs -o ro,show_sys_files,streams_interface=windows,offset=$OFFSET $file $mt
    fi
  done
elif [ -n "`echo \"$FILETYPE\" | grep LVM2`" ]; then
  echo "Found partition of type LVM2"
  lvmprocess $file 0
elif [ -n "`echo "$file" | grep -i e01 2>/dev/null`" ]; then
  e01mt=/media/`randomdir`
  cachefile=/tmp/LM`randomdir`
  mkdir -p $e01mt
  echo "Mounting $file as $e01mt to expose raw ewf1 device"
  ewfmount $file $e01mt
  if [ $? == 1 ]; then
    echo "ERROR: xmount of e01 device $file has failed"
    exit 1
  fi
  $0 $e01mt/ewf1 $mountdir
else
  echo "You specified an unsupported image"
  exit 1
fi
