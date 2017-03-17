## evmount
#### Mark McCurdy  
###### HP Enterprise Digital Investigative Services

Finally a solution to mounting your evidence in Linux to avoid all that manual labor
and steep learning curve for something that should be much simpler.  
  
VMDK's, EWF's, and Virtualbox VHD's are containers around partitions. VMDK's often
are stream-optimized and need to be converted before processing.  A mounted image can
contain any of a number of Windows or Linux filesystems.  They also could contain an
LVM partition that once mounted need additional parsing to mount the various logical
volumes.  
  
This requires the installation of per-image libraries. For the support of all images,
it requires libewf-tools, libvmdk, losetup, and libvhdi (compiled from 
https://github.com/libyal/libvhdi/releases).  If your VMDK needs to be converted to
a compatible format, you will need to install VMware-vix-disklib that contains
vmware-vdiskmanager.  
  
Run this with the expected DEVICE and optional MOUNTPOINT and sit back.  
  
evmount [-u] \<DEVICE_OR_FILE> [MOUNT_POINT]  
  
Unmounting is not automatic. The complexity there is a future addition. 
  
Happy Hunting!  
