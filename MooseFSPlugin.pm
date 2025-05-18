package PVE::Storage::Custom::MooseFSPlugin;

use strict;
use warnings;

use IO::File;
use IO::Socket::UNIX;
use File::Path;
use POSIX qw(strftime);

use PVE::Storage::Plugin;
use PVE::Tools qw(run_command);
use PVE::ProcFSTools;

use base qw(PVE::Storage::Plugin);

# Logging function, called only when needed explicitly
sub log_debug {
    my ($msg) = @_;
    my $logfile = '/var/log/mfsplugindebug.log';
    my $timestamp = POSIX::strftime('%Y-%m-%d %H:%M:%S', localtime);

    my $cmd = ['/usr/bin/logger', '-t', 'MooseFSPlugin', '-p', 'daemon.debug', $msg];
    run_command($cmd);

    $cmd = ['/bin/sh', '-c', "echo '$timestamp: $msg' >> $logfile"];
    run_command($cmd, errmsg => "Failed to write to log file");
}

# MooseFS helper functions
sub moosefs_is_mounted {
    my ($mfsmaster, $mfsport, $mountpoint, $mountdata, $mfssubfolder) = @_;
    $mountdata = PVE::ProcFSTools::parse_proc_mounts() if !$mountdata;

    # Strip leading slashes from mfssubfolder
    $mfssubfolder =~ s|^/+||;
    my $subfolder_pattern = defined($mfssubfolder) ? "\Q/$mfssubfolder\E" : "";

    # Check that we return something like mfs#mfsmaster:9421 or mfs#mfsmaster:9421/subfolder
    # on a fuse filesystem with the correct mountpoint
    return $mountpoint if grep {
        $_->[2] eq 'fuse' &&
        $_->[0] =~ /^mfs(#|\\043)\Q$mfsmaster\E\Q:\E\Q$mfsport\E$subfolder_pattern$/ &&
        $_->[1] eq $mountpoint
    } @$mountdata;
    return undef;
}

# Returns true only if /dev/mfs/nbdsock exists _and_ we can open() it as a UNIX stream.
sub moosefs_bdev_is_active {
    log_debug "Checking if bdev is active";

    my ($scfg) = @_;

    my $sockpath = '/dev/mfs/nbdsock';

    # Quick check: does the file exist and is it a socket?
    return unless -e $sockpath && -S $sockpath;

    # Now try to connect
    my $sock = IO::Socket::UNIX->new(
        Peer    => $sockpath,
        Timeout => 0.1,                # 100ms timeout
    );

    # If we got a socket object, the daemon is listening
    return defined($sock) ? 1 : 0;
}

sub moosefs_start_bdev {
    my ($scfg) = @_;

    my $mfsmaster = $scfg->{mfsmaster} // 'mfsmaster';

    my $mfspassword = $scfg->{mfspassword};

    my $mfsport = $scfg->{mfsport};

    my $mfssubfolder = $scfg->{mfssubfolder};

    my $cmd = ['/usr/sbin/mfsbdev', 'start', '-H', $mfsmaster, '-S', 'proxmox', '-p', $mfspassword];

    run_command($cmd, errmsg => 'mfsbdev start failed');
}

sub moosefs_stop_bdev {
    my ($scfg) = @_;

    my $cmd = ['/usr/sbin/mfsbdev', 'stop'];

    run_command($cmd, errmsg => 'mfsbdev stop failed');
}

# Mounting functions

sub moosefs_mount {
    my ($scfg) = @_;

    my $mfsmaster = $scfg->{mfsmaster} // 'mfsmaster';

    my $mfspassword = $scfg->{mfspassword};

    my $mfsport = $scfg->{mfsport};

    my $mfssubfolder = $scfg->{mfssubfolder};

    my $cmd = ['/usr/bin/mfsmount'];

    if (defined $mfsmaster) {
        push @$cmd, '-o', "mfsmaster=$mfsmaster";
    }

    if (defined $mfsport) {
        push @$cmd, '-o', "mfsport=$mfsport";
    }

    if (defined $mfspassword) {
        push @$cmd, '-o', "mfspassword=$mfspassword";
    }

    if (defined $mfssubfolder) {
        push @$cmd, '-o', "mfssubfolder=$mfssubfolder";
    }

    push @$cmd, $scfg->{path};

    run_command($cmd, errmsg => "mount error");
}

sub moosefs_unmount {
    my ($scfg) = @_;

    my $mountdata = PVE::ProcFSTools::parse_proc_mounts();

    my $path = $scfg->{path};

    my $mfsmaster = $scfg->{mfsmaster} // 'mfsmaster';

    my $mfsport = $scfg->{mfsport} // '9421';

    #if (moosefs_is_mounted($mfsmaster, $mfsport, $path, $mountdata)) {
    my $cmd = ['/bin/umount', $path];
    run_command($cmd, errmsg => 'umount error');
    #}
}

sub api {
    return 10;
}

sub type {
    return 'moosefs';
}

sub plugindata {
    return {
        content => [ { images => 1, vztmpl => 1, iso => 1, backup => 1, rootdir => 1, import => 1, snippets => 1},
                    { images => 1 } ],
        format => [ { raw => 1, qcow2 => 1, vmdk => 1 } , 'raw' ],
        shared => 1,
    };
}

sub properties {
    return {
        mfsmaster => {
            description => "MooseFS master to use for connection (default 'mfsmaster').",
            type => 'string',
        },
        mfsport => {
            description => "Port with which to connect to the MooseFS master (default 9421)",
            type => 'string',
        },
        mfspassword => {
            description => "Password with which to connect to the MooseFS master (default none)",
            type => 'string',
        },
        mfssubfolder => {
            description => "Define subfolder to mount as root (default: /)",
            type => 'string',
        },
        mfsbdev => {
            description => "Use mfsbdev for raw image allocation",
            type => 'boolean',
        }
    };
}

sub options {
    return {
        path => { fixed => 1 },
        'prune-backups' => { optional => 1 },
        'max-protected-backups' => { optional => 1 },
        maxfiles => { optional => 1 },
        mfsmaster => { optional => 1 },
        mfsport => { optional => 1 },
        mfspassword => { optional => 1 },
        mfssubfolder => { optional => 1 },
        mfsbdev => { optional => 1 },
        nodes => { optional => 1 },
        disable => { optional => 1 },
        shared => { optional => 1 },
        content => { optional => 1 },
    };
}

sub volume_has_feature {
    my ($class, $scfg, $feature, $storeid, $volname, $snapname, $running) = @_;
    my $features = {
        snapshot => {
            current => { qcow2 => 1, raw => 1, vmdk => 1, subvol => 1 },
            snap => { qcow2 => 1, raw => 1, vmdk => 1, subvol => 1 }
        },
        clone => {
            base => { qcow2 => 1, raw => 1, vmdk => 1, subvol => 1 },
            current => { raw => 1 },
            snap => { raw => 1 },
        },
        template => {
            current => { qcow2 => 1, raw => 1, vmdk => 1, subvol => 1 },
        },
        copy => {
            base => { qcow2 => 1, raw => 1, vmdk => 1, subvol => 1 },
            current => { qcow2 => 1, raw => 1, vmdk => 1, subvol => 1 },
            snap => { qcow2 => 1, raw => 1 },
        },
        sparseinit => {
            base => { qcow2 => 1, raw => 1, vmdk => 1, subvol => 1 },
            current => { qcow2 => 1, raw => 1, vmdk => 1, subvol => 1 },
        },
    };

    my ($vtype, $name, $vmid, $basename, $basevmid, $isBase, $format) = $class->parse_volname($volname);

    my $key = undef;
    if ($snapname) {
        $key = 'snap';
    } else {
        $key =  $isBase ? 'base' : 'current';
    }

    # TODO: turn off qcow2 and vmdk support while bdev is active
    # if ($scfg->{mfsbdev}) {
    #     # Turn off qcow2 and vmdk support for bdev
    #     $features->{$feature}->{$key}->{qcow2} = 0;
    #     $features->{$feature}->{$key}->{vmdk} = 0;
    # }

    if (defined($features->{$feature}->{$key}->{$format})) {
        return 1;
    }
    return undef;
}

sub parse_name_dir {
    my $name = shift;
    return PVE::Storage::Plugin::parse_name_dir($name);
}

sub parse_volname {
    my ($class, $volname) = @_;

    # 1) Directory-style: "<vmid>/<name>"
    if ($volname =~ m!^(\d+)/(.+)$!) {
        my ($vmid, $name) = ($1, $2);

        # detect format by extension
        my $format = 'raw';
        $format = 'qcow2' if $name =~ /\.qcow2$/;
        $format = 'vmdk'  if $name =~ /\.vmdk$/;

        return ('images', $name, $vmid, undef, undef, undef, $format);
    }

    # 2) Pure-name style: "vm-117-disk-0" or "base-117-…"
    if ($volname =~ m!^((vm|base)-(\d+)-\S+)$!) {
        my ($name, $is_base, $vmid) = ($1, $2 eq 'base', $3);

        return ('images', $name, $vmid, undef, undef, $is_base, 'raw');
    }

    # If the base implementation couldn't parse it, throw our own error
    die "unable to parse volume filename '$volname'\n";
}

sub alloc_image {
    my ($class, $storeid, $scfg, $vmid, $fmt, $name, $size) = @_;

    return $class->SUPER::alloc_image(@_) if !$scfg->{mfsbdev};

    die "mfsbdev only supports raw format" if $fmt ne 'raw';

    $name = $class->find_free_diskname($storeid, $scfg, $vmid, $fmt) if !$name;

    my $imagedir = "images/$vmid";
    File::Path::make_path($scfg->{path}."/$imagedir");

    my $path = "/$imagedir/$name";

    # Write the size of the block device to a file alongside it
    my $write_size_file = "$scfg->{path}/$imagedir/$name.size";

    open(my $write_fh, '>', $write_size_file) or die "Failed to open $write_size_file: $!";
    print $write_fh $size;
    close $write_fh;

    # Size is in kibibytes, but MooseFS expects bytes
    my $size_bytes = $size * 1024;

    my $cmd = ['/usr/sbin/mfsbdev', 'map', '-f', $path, '-s', $size_bytes];
    run_command($cmd, errmsg => 'mfsbdev map failed');

    return "$vmid/$name";
}

sub free_image {
    my ($class, $storeid, $scfg, $volname, $isBase) = @_;

    return $class->SUPER::free_image(@_) if !$scfg->{mfsbdev};

    my ($vtype, $name, $vmid) = $class->parse_volname($volname);
    return $class->SUPER::free_image(@_) if $vtype ne 'images';

    my $path = "/images/$vmid/$name";

    if (-e $path) {
        my $cmd = ['/usr/sbin/mfsbdev', 'unmap', $path];
        run_command($cmd, errmsg => 'mfsbdev unmap failed');
        unlink $path if -e $path;
        unlink "$path.size" if -e "$path.size";
    }

    return undef;
}

sub activate_volume {  
    my ($class, $storeid, $scfg, $volname, $snapname, $cache) = @_;

    return $class->SUPER::activate_volume(@_) if !$scfg->{mfsbdev};

    # Fetch size from the size file alongside the block device
    my $size_file = "$scfg->{path}/images/$volname.size";
    log_debug "Size file $size_file";
    my $size = -e $size_file ? do { open(my $fh, '<', $size_file) or die "Failed to open $size_file: $!"; local $/; <$fh> } : 0;

    my ($vtype, $name, $vmid) = $class->parse_volname($volname);
    log_debug "Vtype $vtype, name $name, vmid $vmid";
    return $class->SUPER::activate_volume(@_) if $vtype ne 'images';

    my $path = "/images/$vmid/$name";

    # Size is in kibibytes, but MooseFS expects bytes
    my ($safe_size) = $size =~ /^(\d+)$/; 
    my $size_bytes = $safe_size * 1024;
    
    log_debug "Activating volume $volname with size $size_bytes";

    my $cmd = ['/usr/sbin/mfsbdev', 'map', '-f', $path, '-s', $size_bytes];

    run_command($cmd, errmsg => 'mfsbdev map failed');

    # Avoid a race condition where Proxmox immediately tries to use the volume
    log_debug "Looping until volume is active";

    return 1;
}

sub deactivate_volume {  
    my ($class, $storeid, $scfg, $volname, $snapname, $cache) = @_;  

    return $class->SUPER::deactivate_volume(@_) if !$scfg->{mfsbdev};  

    my ($vtype, $name, $vmid) = $class->parse_volname($volname);  
    return $class->SUPER::deactivate_volume(@_) if $vtype ne 'images';  

    my $path = "/images/$vmid/$name";  
    
    log_debug "Deactivating volume $volname";  

    my $cmd = ['/usr/sbin/mfsbdev', 'unmap', '-f', $path];

    run_command($cmd, errmsg => "can't unmap MooseFS device '$path'");  

    return 1;
}

sub filesystem_path {
    my ($class, $scfg, $volname, $snapname) = @_;

    # If we're not in mfsbdev mode, return the original path
    return $class->SUPER::filesystem_path(@_) if !$scfg->{mfsbdev};

    my ($vtype, $name, $vmid) = $class->parse_volname($volname);  
    my $path = "/images/$vmid/$name";  

    # Run mfsbdev list to get current mappings  
    my $cmd = ['/usr/sbin/mfsbdev', 'list'];  
    my $output = '';  
    eval {  
        run_command($cmd,  
            outfunc => sub { $output .= shift; },  
            errmsg => 'mfsbdev list failed');  
    };  
    if ($@) {  
        log_debug "Failed to list MooseFS block devices: $@";  
        # Fall back to regular path if we can't get mappings  
        return $class->SUPER::filesystem_path(@_);  
    }  

    # Parse the output to find our file  
    # Format: file: /images/117/vm-117-disk-0 ; device: /dev/nbd0 ; ...  
    if ($output =~ m|file:\s+\Q$path\E\s+;\s+device:\s+(/dev/nbd\d+)|) {  
        my $nbd_path = $1;
        log_debug "Found NBD device $nbd_path for volume $volname";  
        return $nbd_path;
    }  
    else {  
        # No NBD device found, return the original filesystem path  
        log_debug "No NBD device found for volume $volname, using regular path";
        return $vmid."/".$name;
    }
}

sub volume_resize {
    my ($class, $scfg, $storeid, $volname, $size) = @_;

    return $class->SUPER::volume_resize(@_) if !$scfg->{mfsbdev};

    my ($vtype, $name, $vmid) = $class->parse_volname($volname);
    return $class->SUPER::volume_resize(@_) if $vtype ne 'images';

    my $path = "/images/$vmid/$name";

    if (-e $path) {
        my $cmd = ['/usr/sbin/mfsbdev', 'resize', $path, $size];
        run_command($cmd, errmsg => 'mfsbdev resize failed');
    } else {
        die "volume '$volname' does not exist\n";
    }

    return undef;
}

sub volume_snapshot {
    my ($class, $scfg, $storeid, $volname, $snap) = @_;

    my ($storageType, $name, $vmid, $basename, $basedvmid, $isBase, $format) = $class->parse_volname($volname);

    if ($format ne 'raw') {
        return PVE::Storage::Plugin::volume_snapshot(@_);
    }

    die "snapshots not supported for this storage type" if $storageType ne 'images';

    my $mountpoint = $scfg->{path};

    my $snapdir = "$mountpoint/images/$vmid/snaps/$snap";

    File::Path::make_path($snapdir);

    print "running '/usr/bin/mfsmakesnapshot $mountpoint/images/$vmid/$name $snapdir/$name'\n";

    my $cmd = ['/usr/bin/mfsmakesnapshot', "$mountpoint/images/$vmid/$name", "$snapdir/$name"];

    run_command($cmd, errmsg => 'An error occurred while making the snapshot');

    return undef;
}

sub volume_snapshot_delete {
    my ($class, $scfg, $storeid, $volname, $snap, $running) = @_;

    my ($storageType, $name, $vmid, $basename, $basedvmid, $isBase, $format) = $class->parse_volname($volname);

    if ($format ne 'raw') {
        return PVE::Storage::Plugin::volume_snapshot_delete(@_);
    }

    my $mountpoint = $scfg->{path};

    my $cmd = ['/usr/bin/rm', '-rf', "$mountpoint/images/$vmid/snaps/$snap/$basename"];

    run_command($cmd, errmsg => 'An error occurred while deleting the snapshot');

    return undef;
}

sub volume_snapshot_rollback {
    my ($class, $scfg, $storeid, $volname, $snap) = @_;

    my ($storageType, $name, $vmid, $basename, $basedvmid, $isBase, $format) = $class->parse_volname($volname);

    if ($format ne 'raw') {
        return PVE::Storage::Plugin::volume_snapshot_rollback(@_);
    }

    my $mountpoint = $scfg->{path};

    my $snapdir = "$mountpoint/images/$vmid/snaps/$snap";

    my $cmd = ['/usr/bin/mfsmakesnapshot', '-o', "$snapdir/$name", "$mountpoint/images/$vmid/$name"];

    run_command($cmd, errmsg => 'An error occurred while restoring the snapshot');

    return undef;
}

sub status {
    my ($class, $storeid, $scfg, $cache) = @_;

    $cache->{mountdata} = PVE::ProcFSTools::parse_proc_mounts()
        if !$cache->{mountdata};

    my $path = $scfg->{path};

    my $mfsmaster = $scfg->{mfsmaster} // 'mfsmaster';

    my $mfsport = $scfg->{mfsport} // '9421';

    my $mfssubfolder = $scfg->{mfssubfolder};

    return undef if !moosefs_is_mounted($mfsmaster, $mfsport, $path, $cache->{mountdata}, $mfssubfolder);

    return $class->SUPER::status($storeid, $scfg, $cache);
}

sub activate_storage {
    my ($class, $storeid, $scfg, $cache) = @_;

    $cache->{mountdata} = PVE::ProcFSTools::parse_proc_mounts()
        if !$cache->{mountdata};

    my $path = $scfg->{path};

    my $mfsmaster = $scfg->{mfsmaster} // 'mfsmaster';

    my $mfsport = $scfg->{mfsport} // '9421';

    my $mfssubfolder = $scfg->{mfssubfolder};

    if (!moosefs_is_mounted($mfsmaster, $mfsport, $path, $cache->{mountdata}, $mfssubfolder)) {

        mkpath $path if !(defined($scfg->{mkdir}) && !$scfg->{mkdir});

        die "unable to activate storage '$storeid' - " .
            "directory '$path' does not exist\n" if ! -d $path;

        moosefs_mount($scfg);
    }

    if ($scfg->{mfsbdev} && !moosefs_bdev_is_active()) {
        moosefs_start_bdev($scfg);
    }

    $class->SUPER::activate_storage($storeid, $scfg, $cache);
}

sub on_delete_hook {
    my ($class, $storeid, $scfg, $cache) = @_;

    $cache->{mountdata} = PVE::ProcFSTools::parse_proc_mounts()
        if !$cache->{mountdata};

    my $path = $scfg->{path};

    my $mfsmaster = $scfg->{mfsmaster} // 'mfsmaster';

    my $mfsport = $scfg->{mfsport} // '9421';

    my $mfssubfolder = $scfg->{mfssubfolder};

    if (moosefs_is_mounted($mfsmaster, $mfsport, $path, $cache->{mountdata}, $mfssubfolder)) {
        moosefs_unmount($scfg);
    }
}

1;
