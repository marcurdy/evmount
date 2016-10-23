## evmount
#### Mark McCurdy  

Finally a solution to mounting your evidence in Linux to avoid all that manual labor and steep learning
curve for something that should be much simpler.  
  
VMDK's and EWF's are continers for the filesystems, but they're not straight mounted.  VMDK's often come
stream-optimized and need to be converted before processing.  A "bootstrap" device can contain any of a
number of Windows or Linux filesystems.  They also could contain an LVM partition that once mounted need
additional parsing to mount the various logical volumes.  
  
Run this with the expected DEVICE and optional MOUNTPOINT and sit back.  
  
evmount [-u] <DEVICE_OR_FILE> [MOUNT_POINT]  
  
Unmounting is not automatic.  The steps to unmount are given if the -u argument is given.  
  
Happy Hunting!  
