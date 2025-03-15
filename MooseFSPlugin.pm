package PVE::Storage::Custom::MooseFSPlugin;

use strict;
use warnings;

use IO::File;
use File::Path;

use PVE::Storage::Plugin;
use PVE::Tools qw(run_command);
use PVE::ProcFSTools;

use base qw(PVE::Storage::Plugin);

# MooseFS helper functions
sub moosefs_is_mounted {
    my ($mfsmaster, $mfsport, $mountpoint, $mountdata) = @_;
    $mountdata = PVE::ProcFSTools::parse_proc_mounts() if !$mountdata;

    # Check that we return something like mfs#10.1.1.201:9421
    # on a fuse filesystem with the correct mountpoint
    return $mountpoint if grep {
        $_->[2] eq 'fuse' &&
        $_->[0] =~ /^mfs(#|\\043)\Q$mfsmaster\E\Q:\E\Q$mfsport\E$/ &&
        $_->[1] eq $mountpoint
    } @$mountdata;
    return undef;
}

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

    if (moosefs_is_mounted($mfsmaster, $mfsport, $path, $mountdata)) {
        my $cmd = ['/bin/umount', $path];
        run_command($cmd, errmsg => 'umount error');
    }
}

sub api {
    return 10;
}

sub type {
    return 'moosefs';
}

sub plugindata {
    return {
        content => [ { images => 1, vztmpl => 1, iso => 1, backup => 1, snippets => 1},
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
    return PVE::Storage::Plugin::parse_volname(@_);
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

    return undef if !moosefs_is_mounted($mfsmaster, $mfsport, $path, $cache->{mountdata});

    return $class->SUPER::status($storeid, $scfg, $cache);
}

sub activate_storage {
    my ($class, $storeid, $scfg, $cache) = @_;

    $cache->{mountdata} = PVE::ProcFSTools::parse_proc_mounts()
        if !$cache->{mountdata};

    my $path = $scfg->{path};

    my $mfsmaster = $scfg->{mfsmaster} // 'mfsmaster';

    my $mfsport = $scfg->{mfsport} // '9421';

    if (!moosefs_is_mounted($mfsmaster, $mfsport, $path, $cache->{mountdata})) {
        
        mkpath $path if !(defined($scfg->{mkdir}) && !$scfg->{mkdir});

        die "unable to activate storage '$storeid' - " .
            "directory '$path' does not exist\n" if ! -d $path;

        moosefs_mount($scfg);
    }

    $class->SUPER::activate_storage($storeid, $scfg, $cache);
}

sub deactivate_storage {
    my ($class, $storeid, $scfg, $cache) = @_;
    moosefs_unmount($scfg);
}

1;
