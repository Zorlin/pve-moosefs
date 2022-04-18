package PVE::Storage::Custom::MooseFSPlugin;

use strict;
use warnings;

use IO::File;

use PVE::Storage::Plugin;
use PVE::Tools qw(run_command);

use base qw(PVE::Storage::Plugin);

# MooseFS helper functions

sub moosefs_is_mounted {
    my ($mountpoint, $mountdata) = @_;

    $mountdata = PVE::ProcFSTools::parse_proc_mounts() if !$mountdata;

    die "$mountdata";

    return $mountpoint if grep {
        $_->[2] eq 'fuse.moosefs' &&
        $_->[1] eq $mountpoint
    } @$mountdata;
    return undef;
}

sub moosefs_mount {
    my ($mfsmaster, $mountpoint) = @_;

    my $cmd = ['/usr/bin/mfsmount', $mountpoint];

    if ($mfsmaster) {
        my $cmd = ['/usr/bin/mfsmount', $mfsmaster, $mountpoint];
    }

    run_command($cmd, errmsg => "mount error");
}

# Configuration

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
    };
}

sub properties {
    return {
    mfsmaster => { optional => 1 },
    }
}

sub options {
    return {
    path => { fixed => 1 },
    subdir => { optional => 1 },
    disable => { optional => 1 },
    };
}

# Storage implementation

sub status {
    my ($class, $storeid, $scfg, $cache) = @_;

    $cache->{mountdata} = PVE::ProcFSTools::parse_proc_mounts()
        if !$cache->{mountdata};

    my $path = $scfg->{path};

    return undef if !moosefs_is_mounted($path, $cache->{mountdata});

    return $class->SUPER::status($storeid, $scfg, $cache);
}


sub activate_storage {
    my ($class, $storeid, $scfg, $cache) = @_;

    # Get MooseFS master definition from config, otherwise return mfsmaster
    my $mfsmaster = $scfg->{mfsmaster} ? $scfg->{mfsmaster} : 'mfsmaster';

    $cache->{mountdata} = PVE::ProcFSTools::parse_proc_mounts()
        if !$cache->{mountdata};

    my $path = $scfg->{path};

    if (!moosefs_is_mounted($path, $cache->{mountdata})) {
        
        mkpath $path if !(defined($scfg->{mkdir}) && !$scfg->{mkdir});

        die "unable to activate storage '$storeid' - " .
            "directory '$path' does not exist\n" if ! -d $path;

        moosefs_mount("mfsmaster", $path);
    }

    $class->SUPER::activate_storage($storeid, $scfg, $cache);
}

sub deactivate_storage {
    my ($class, $storeid, $scfg, $cache) = @_;

    $cache->{mountdata} = PVE::ProcFSTools::parse_proc_mounts()
        if !$cache->{mountdata};

    my $path = $scfg->{path};
    my $volume = $scfg->{volume};

    if (moosefs_is_mounted($path, $cache->{mountdata})) {
        my $cmd = ['/bin/umount', $path];
        run_command($cmd, errmsg => 'umount error');
    }
}

1;