# pve-moosefs
MooseFS on Proxmox.

| Editing storage |
|:-------------:|
|![image](https://github.com/user-attachments/assets/f70d2908-7111-4b47-bcb8-eed793a85c11) |

Adding as storage             |  Viewing a MooseFS storage target
:-------------------------:|:-------------------------:
![image](https://github.com/user-attachments/assets/0a6fc0cb-46c5-4cd6-a2b6-f6930159e2ea) |  ![image](https://github.com/Zorlin/pve-moosefs/assets/1369772/b8218b51-c6df-4524-9f7d-358d59624f9a)


## DISCLAIMER
This is **HIGHLY EXPERIMENTAL!** I'm running it in production, but you should be careful.

Call it pre-alpha quality.

## Usage
Perform the following steps on your Proxmox host(s):

* Clone this Git repository and enter it with `cd`
* Make the Debian package: `make`
* Install the Debian package: `dpkg -i *.deb`

Now mount the storage:
`pvesm add moosefs moosefs-vm-storage --path /mnt/mfs`

In this example, we create a custom storage called "moosefs-vm-storage" using the moosefs plugin we just installed.

You can apply the following optional settings:
* --mfsmaster mfsmaster.my.hostname - Set the mfsmaster IP or hostname to help MooseFS find the metadata server(s).
* --mfspassword mypasswordhere - If your MooseFS exports require a password to mount MooseFS, set this.
* --mfssubfolder media - If you need to use 
* --mfsport 9421 - If you're running the mfsmaster on a custom port, you can set this. Note: Doesn't currently do anything 🚧

## Future features
* Instant snapshots, rollbacks etc
* mfsbdev support for high performance?
* mfssubfolder support

## Credits
Huge thanks to the following contributors:
* @anwright - Major fixes, snapshots, general cleanup
* @pkonopelko - General advice

Thanks to the following sources for code contributions:
* https://github.com/mityarzn/pve-storage-custom-mpnetapp - Initial plugin skeleton, packaging
* https://forums.servethehome.com/index.php?threads/custom-storage-plugins-for-proxmox.12558/ - Also used building the skeleton
* Proxmox GlusterFS and CephFS plugins - Also used in building the skeleton
