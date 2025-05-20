# pve-moosefs
MooseFS on Proxmox.

Adds MooseFS as a storage option in Proxmox VE.

## DISCLAIMER
This is **HIGHLY EXPERIMENTAL!**

**Do not use snapshots in MooseFS bdev mode - they will eat your data. They are not safe until this notice is removed, we're still improving them.**

[@Zorlin](https://github.com/Zorlin) is running it in production on multiple clusters, but it should be considered unstable for now.

# Preview
<img width="597" alt="image" src="https://github.com/user-attachments/assets/a3d13281-344e-4ec4-9ed8-7556582e5d5b" />

# Features
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/Zorlin/pve-moosefs)

* Natively use MooseFS storage on Proxmox.
* Support for MooseFS clusters with passwords and subfolders
* Live migrate VMs between Proxmox hosts with the VMs living on MooseFS storage
* Cleanly unmounts MooseFS when removed
* MooseFS block device (`mfsbdev`) support for high performance

## Future features
* Instant snapshots and rollbacks
* Instant clones

## Usage
Perform the following steps on your Proxmox host(s):

Easy:
* Upgrade to Proxmox 8.4.1
* Install the attached .deb file in Releases.

Harder:
* Upgrade to Proxmox 8.4.1
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
* --mfsport 9421 - Coming soon 🚧

## Credits
Huge thanks to the following contributors:

* [@anwright](https://github.com/anwright) - Major fixes, snapshots, general cleanup
* [@pkonopelko](https://github.com/pkonopelko) - General advice

Thanks to the following sources for code contributions:

* https://github.com/mityarzn/pve-storage-custom-mpnetapp - Initial plugin skeleton, packaging
* https://forums.servethehome.com/index.php?threads/custom-storage-plugins-for-proxmox.12558/ - Also used building the skeleton
* Proxmox GlusterFS and CephFS plugins - Also used in building the skeleton

## Changelog
v0.1.4 - Bug fixes
* Lots of small fixes
* Defensive fixes for various edge cases
* Proper support for LXC
* Live migration fixes
* Unmapping fixes
* Clone fixes

v0.1.3 - Features
* Full support for MooseFS block device (mfsbdev)

v0.1.2 - Features
* Initial support for the MooseFS block device (mfsbdev)

v0.1.1 - Bug fixes
* Add 'container' as an option in the Proxmox GUI to allow containers to be stored on MooseFS
* Allow leading `/` on mfssubfolder

v0.1.0 - Initial release
* Major features
* Mount, unmount and setup shared MooseFS storage on your Proxmox cluster
* Snapshots not working in this build
