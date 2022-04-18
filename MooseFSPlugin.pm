package PVE::Storage::Custom::MooseFSPlugin;

use strict;
use warnings;

use IO::File;

use PVE::Storage::Plugin;
use PVE::Tools qw(run_command);

use base qw(PVE::Storage::Plugin);

# MooseFS helper functions

sub moosefs_is_mounted {
    die "Nope"
}

# Configuration

sub api {
    return 9;
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
    }
}

sub options {
    return {
    path => { fixed => 1 },
    subdir => { optional => 1 },
    disable => { optional => 1 },
    };
}

1;