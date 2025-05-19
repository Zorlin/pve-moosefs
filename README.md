# pve-moosefs
MooseFS on Proxmox.

Please give me feedback! Feel free to open issues or open discussions,

or email zorlin@gmail.com with comments.

![image](https://github.com/user-attachments/assets/f70d2908-7111-4b47-bcb8-eed793a85c11)

# Features
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/Zorlin/pve-moosefs)

* Natively use MooseFS storage on Proxmox.
* Support for MooseFS clusters with passwords and subfolders
* Live migrate VMs between Proxmox hosts with the VMs living on MooseFS storage
* Cleanly unmounts MooseFS when removed
* MooseFS block device (`mfsbdev`) support for high performance

## Future features
* Instant snapshots and rollbacks

## DISCLAIMER
This is **HIGHLY EXPERIMENTAL!** 

I'm running it in production, but you should be careful.

**Do not use snapshots with your MooseFS storage, as they are actively being worked on and not ready yet**

## Usage
Adding as storage             |  Viewing a MooseFS storage target
:-------------------------:|:-------------------------:
![image](https://github.com/user-attachments/assets/0a6fc0cb-46c5-4cd6-a2b6-f6930159e2ea) |  ![image](https://github.com/Zorlin/pve-moosefs/assets/1369772/b8218b51-c6df-4524-9f7d-358d59624f9a)

Perform the following steps on your Proxmox host(s):

Easy:
* Upgrade to Proxmox 8.3.5
* Install the attached .deb file in Releases.

Harder:
* Upgrade to Proxmox 8.3.5
* Clone this Git repository and enter it with `cd`
* Make the Debian package: `make`
* Install the Debian package: `dpkg -i *.deb`

### Graphical mounting
Now mount the storage! You can use the Proxmox GUI for this.

* Go to Datacenter -> Storage
* Click Add -> MooseFS and follow the wizard.

### Command line mounting
Now mount the storage via command line:
`pvesm add moosefs moosefs-vm-storage --path /mnt/mfs`

In this example, we create a custom storage called "moosefs-vm-storage" using the moosefs plugin we just installed.

You can apply the following optional settings:
* --mfsmaster mfsmaster.my.hostname - Set the mfsmaster IP or hostname to help MooseFS find the metadata server(s).
* --mfspassword mypasswordhere - If your MooseFS exports require a password to mount MooseFS, set this.
* --mfssubfolder media - If you need to use a folder within MooseFS instead of pointing at the root of the filesystem, set this.
* --mfsport 9421 - If you're running the mfsmaster on a custom port, you can set this. Note: Currently unused 🚧

## Credits
Huge thanks to the following contributors:
* @anwright - Major fixes, snapshots, general cleanup
* @pkonopelko - General advice

Thanks to the following sources for code contributions:
* https://github.com/mityarzn/pve-storage-custom-mpnetapp - Initial plugin skeleton, packaging
* https://forums.servethehome.com/index.php?threads/custom-storage-plugins-for-proxmox.12558/ - Also used building the skeleton
* Proxmox GlusterFS and CephFS plugins - Also used in building the skeleton

## Changelog
v0.1.0 - Initial release
* Major features
* Mount, unmount and setup shared MooseFS storage on your Proxmox cluster
* Snapshots not working in this build

v0.1.1 - Bug fixes
* Add 'container' as an option in the Proxmox GUI to allow containers to be stored on MooseFS
* Allow leading `/` on mfssubfolder

v0.1.2 - Features
* Initial support for the MooseFS block device (mfsbdev)
