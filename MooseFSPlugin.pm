package PVE::Storage::Custom::MooseFSPlugin;

use strict;
use warnings;

use IO::File;

use PVE::Storage::Plugin;
use PVE::Tools qw(run_command);

use base qw(PVE::Storage::Plugin);

# MooseFS helper functions

sub moosefs_is_mounted {
    my ($mfsmaster, $mfsport, $mountpoint, $mountdata) = @_;

    $mountdata = PVE::ProcFSTools::parse_proc_mounts() if !$mountdata;

    # Check that we return something like mfs#10.1.1.201:9421
    # on a fuse filesystem with the correct mountpoint
    return $mountpoint if grep {
        $_->[2] eq 'fuse' &&
        $_->[0] =~ /^mfs#\Q$mfsmaster\E\Q:\E\Q$mfsport\E$/ &&
        $_->[1] eq $mountpoint
    } @$mountdata;
    return undef;
}

sub moosefs_mount {
    my ($mfsmaster, $mountpoint) = @_;

    my $cmd = ['/usr/bin/mfsmount', $mfsmaster, $mountpoint];

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
    mfsmaster => { fixed => 1 },
    mfsport => { optional => 1 },
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

    return undef if !moosefs_is_mounted($mfsmaster, $mfsport, $path, $cache->{mountdata});

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

    if (moosefs_is_mounted($mfsmaster, $mfsport, $path, $cache->{mountdata})) {
        my $cmd = ['/bin/umount', $path];
        run_command($cmd, errmsg => 'umount error');
    }
}

1;