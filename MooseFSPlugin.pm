package PVE::Storage::Custom::MooseFSPlugin;

use strict;
use warnings;
use IO::File;
use File::Path;
use PVE::Storage::Plugin;
use PVE::Tools qw(run_command);
use PVE::ProcFSTools;

use base qw(PVE::Storage::Plugin);

# Configuration constants
use constant {
    DEFAULT_MASTER => 'mfsmaster',
    DEFAULT_PORT => '9421',
    MOUNT_RETRIES => 3,
    MOUNT_TIMEOUT => 30,
};

# MooseFS helper functions
sub moosefs_is_mounted {
    my ($scfg, $mountdata) = @_;
    $mountdata = PVE::ProcFSTools::parse_proc_mounts() if !$mountdata;

    my $mfsmaster = $scfg->{mfsmaster} // DEFAULT_MASTER;
    my $mfsport = $scfg->{mfsport} // DEFAULT_PORT;
    my $mountpoint = $scfg->{path};

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
    my $retry_count = 0;

    while ($retry_count < MOUNT_RETRIES) {
        eval {
            my $cmd = ['/usr/bin/mfsmount'];

            # Build mount options
            my %mount_opts = (
                mfsmaster => $scfg->{mfsmaster} // DEFAULT_MASTER,
                mfsport => $scfg->{mfsport} // DEFAULT_PORT,
            );

            # Optional parameters
            $mount_opts{mfspassword} = $scfg->{mfspassword} if defined $scfg->{mfspassword};
            $mount_opts{mfssubfolder} = $scfg->{mfssubfolder} if defined $scfg->{mfssubfolder};

            # Add all options to command
            for my $key (keys %mount_opts) {
                push @$cmd, '-o', "$key=$mount_opts{$key}";
            }

            push @$cmd, $scfg->{path};

            run_command($cmd, timeout => MOUNT_TIMEOUT, errmsg => "mount error");

            # Verify mount
            die "Mount verification failed - path not mounted"
                unless moosefs_is_mounted($scfg);

            return 1;
        };
        if ($@) {
            my $error = $@;
            $retry_count++;

            if ($retry_count >= MOUNT_RETRIES) {
                die "Failed to mount after $retry_count attempts: $error";
            }

            sleep(2 ** $retry_count); # Exponential backoff
        }
    }
}

sub moosefs_unmount {
    my ($scfg) = @_;

    if (moosefs_is_mounted($scfg)) {
        my $cmd = ['/bin/umount', $scfg->{path}];
        eval {
            run_command($cmd, timeout => MOUNT_TIMEOUT, errmsg => 'umount error');
        };
        if ($@) {
            die "Failed to unmount $scfg->{path}: $@";
        }
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
            type => 'integer',
            minimum => 1,
            maximum => 65535,
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
        mfsmaster => { optional => 1 },
        mfsport => { optional => 1 },
        mfspassword => { optional => 1 },
        mfssubfolder => { optional => 1 },
        disable => { optional => 1 },
        shared => { optional => 1 },
        content => { optional => 1 },
    };
}

# Helper function for snapshot paths
sub get_snapshot_path {
    my ($scfg, $vmid, $snap, $name) = @_;
    my $base_path = "$scfg->{path}/images/$vmid";
    return defined $snap ? "$base_path/snaps/$snap/$name" : "$base_path/$name";
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

    my ($vtype, $name, $vmid, $basename, $basevmid, $isBase, $format) =
        $class->parse_volname($volname);

    my $key = $snapname ? 'snap' : ($isBase ? 'base' : 'current');

    return defined($features->{$feature}->{$key}->{$format});
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

    my ($storageType, $name, $vmid, $basename, $basedvmid, $isBase, $format) =
        $class->parse_volname($volname);

    if ($format ne 'raw') {
        return PVE::Storage::Plugin::volume_snapshot(@_);
    }

    die "snapshots not supported for this storage type" if $storageType ne 'images';

    my $snapdir = get_snapshot_path($scfg, $vmid, $snap, '');
    my $source = get_snapshot_path($scfg, $vmid, undef, $name);
    my $target = get_snapshot_path($scfg, $vmid, $snap, $name);

    eval {
        File::Path::make_path($snapdir);
        my $cmd = ['/usr/bin/mfsmakesnapshot', $source, $target];
        run_command($cmd, timeout => MOUNT_TIMEOUT, errmsg => 'Failed to create snapshot');
    };
    if ($@) {
        die "Error creating snapshot: $@";
    }

    return undef;
}

sub volume_snapshot_delete {
    my ($class, $scfg, $storeid, $volname, $snap, $running) = @_;

    my ($storageType, $name, $vmid, $basename, $basedvmid, $isBase, $format) =
        $class->parse_volname($volname);

    if ($format ne 'raw') {
        return PVE::Storage::Plugin::volume_snapshot_delete(@_);
    }

    my $snapshot_path = get_snapshot_path($scfg, $vmid, $snap, $basename);

    eval {
        my $cmd = ['/usr/bin/rm', '-rf', $snapshot_path];
        run_command($cmd, timeout => MOUNT_TIMEOUT, errmsg => 'Failed to delete snapshot');
    };
    if ($@) {
        die "Error deleting snapshot: $@";
    }

    return undef;
}

sub volume_snapshot_rollback {
    my ($class, $scfg, $storeid, $volname, $snap) = @_;

    my ($storageType, $name, $vmid, $basename, $basedvmid, $isBase, $format) =
        $class->parse_volname($volname);

    if ($format ne 'raw') {
        return PVE::Storage::Plugin::volume_snapshot_rollback(@_);
    }

    my $source = get_snapshot_path($scfg, $vmid, $snap, $name);
    my $target = get_snapshot_path($scfg, $vmid, undef, $name);

    eval {
        my $cmd = ['/usr/bin/mfsmakesnapshot', '-o', $source, $target];
        run_command($cmd, timeout => MOUNT_TIMEOUT, errmsg => 'Failed to rollback snapshot');
    };
    if ($@) {
        die "Error rolling back snapshot: $@";
    }

    return undef;
}

sub status {
    my ($class, $storeid, $scfg, $cache) = @_;

    $cache->{mountdata} = PVE::ProcFSTools::parse_proc_mounts()
        if !$cache->{mountdata};

    return undef if !moosefs_is_mounted($scfg, $cache->{mountdata});
    return $class->SUPER::status($storeid, $scfg, $cache);
}

sub activate_storage {
    my ($class, $storeid, $scfg, $cache) = @_;

    $cache->{mountdata} = PVE::ProcFSTools::parse_proc_mounts()
        if !$cache->{mountdata};

    if (!moosefs_is_mounted($scfg, $cache->{mountdata})) {
        mkpath $scfg->{path} if !(defined($scfg->{mkdir}) && !$scfg->{mkdir});

        die "unable to activate storage '$storeid' - " .
            "directory '$scfg->{path}' does not exist\n" if ! -d $scfg->{path};

        moosefs_mount($scfg);
    }

    $class->SUPER::activate_storage($storeid, $scfg, $cache);
}

sub deactivate_storage {
    my ($class, $storeid, $scfg, $cache) = @_;
    moosefs_unmount($scfg);
}

1;
