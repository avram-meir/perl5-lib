#!/usr/bin/env perl

package CPC::Precipitation::Conus8thDegree;

=pod

=head1 NAME

CPC::Precipitation::Conus8thDegree - Read CPC's CONUS 8th degree Cartesian precipitation dataset and return data in CPC::Grid objects

=head1 SYNOPSIS

 use CPC::Grid;
 use CPC::Precipitation::Conus8thDegree;

=head1 DESCRIPTION

=head1 METHODS

=head1 AUTHOR

Adam Allgood

=cut

use strict;
use warnings;
use Carp qw(carp cluck confess croak);
use Config::Simple;
use Date::Manip;
use File::Basename qw(fileparse);
use File::Temp qw(:seekable);
use Scalar::Util qw(blessed looks_like_number reftype);
my($pkg_name,$pkg_path,$pkg_suffix);
BEGIN { ($pkg_name,$pkg_path,$pkg_suffix) = fileparse(__FILE__, qr/\.[^.]*/); }
use lib "$pkg_path/../..";  # Top dir for this library
use CPC::Grid;
use Wgrib2::Regrid;

sub new {
    my $class         = shift;
    my $self          = {};
    my $method        = "$class\::new";
    $self->{class}    = $class;
    $self->{archive}  = undef;
    $self->{gridtype} = 'conus0.125deg';
    $self->{missing}  = -999.0;
    my $arg           = undef;

    if(@_) {
        $arg = shift;
        confess "$method: Invalid argument" unless(reftype($arg) eq 'HASH');

        if(exists $arg->{GRIDTYPE})     {
            eval   { my $test          = CPC::Grid->new($arg->{GRIDTYPE}); };
            if($@) { confess $@ }
            else   { $self->{gridtype} = $arg->{GRIDTYPE}; }
        }

        if(exists $arg->{MISSING})      {
            confess "Non-numeric missing value" unless(looks_like_number($arg->{MISSING}));
            $self->{missing} = $arg->{MISSING};
        }

        if(exists $arg->{ARCHIVE})      { $self->{archive} = $arg->{ARCHIVE}; }
    }

    bless($self,$class);
    return $self;
}

sub set_params {
    my $self   = shift;
    my $class  = $self->{class};
    my $method = "$class\::set_params";
    unless(@_) { confess "$method: No params to set"; }
    my $arg    = shift;
    confess "$method: Invalid argument" unless(reftype($arg) eq 'HASH');

    if(exists $arg->{GRIDTYPE})     {
        eval   { my $test          = CPC::Grid->new($arg->{GRIDTYPE}); };
        if($@) { confess $@ }
        else   { $self->{gridtype} = $arg->{GRIDTYPE}; }
    }

    if(exists $arg->{MISSING})      {
        confess "Non-numeric missing value" unless(looks_like_number($arg->{MISSING}));
        $self->{missing} = $arg->{MISSING};
    }

    if(exists $arg->{ARCHIVE})      { $self->{archive} = $arg->{ARCHIVE}; }
    return $self;
}

sub get_precip {
    my $self   = shift;
    my $class  = $self->{class};
    my $method = "$class\::get_precip";
    confess "Two arguments required" unless(@_ >= 2);
    my $ndays  = shift;
    my $date   = shift;
    confess "$ndays is an invalid argument" unless($ndays =~ /^[+-]?\d+$/ and $ndays > 0);
    confess "Second arg must be a Date::Manip::Date object" unless($date->isa("Date::Manip::Date"));
    my $delta  = $date->new_delta();
    $delta->parse("1 day ago");
    my $count  = 0;
    my $day    = $date;
    my $precip = CPC::Grid->new($self->{gridtype})->init_values(0.0);

    while($count < $ndays) {
        my $src_file = $day->printf($self->{archive});
        croak "$method: $src_file not found" unless(-s $src_file);
        open(SRC,'<',$src_file) or croak "$method: Could not open $src_file for reading - $!";
        binmode(SRC);
        my $src_str  = join('',<SRC>);
        close(SRC);

        # Precip is the first of two records

        my @precip = unpack('f*',$src_str);
        @precip    = splice(@precip,scalar(@precip)/2);

        # Basic validation

        foreach my $p (@precip) { if($p < 0) { $p = 0.0; } }

        # Add daily precip to sum

        $precip    = $precip + CPC::Grid->new($self->{gridtype})->set_values(@precip);
        $day       = $day->calc($delta);
        $count++;
    }

    # Precip is in units of mm*10. Return as mm

    return $precip/10.0;
}

1;

