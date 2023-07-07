#!/usr/bin/env perl

package CPC::Precipitation::HiResCONUS;

=pod

=cut

use strict;
use warnings;
use Carp qw(carp cluck confess croak);
use Date::Manip;
use File::Basename qw(fileparse);
use File::Temp qw(:seekable);
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
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
    $self->{archive}  = [];
    $self->{class}    = $class;
    $self->{missing}  = -999.0;
    while(@_) { push(@{$self->{archive}}, shift); }
    bless($self,$class);
    return $self;
}

sub add_archive {
    my $self   = shift;
    my $class  = $self->{class};
    my $method = "$class\::new";
    while(@_) { push(@{$self->{archive}}, shift); }
    return $self;
}

sub get_precip {
    my $self     = shift;
    my $class    = $self->{class};
    my $method   = "$class\::get_precip";
    my $err      = '';
    my $date     = undef;
    my $gridtype = undef;
    if(@_) { $date     = shift; }
    if(@_) { $gridtype = shift; }
    else   { $gridtype = 'conus0.125deg'; }

    # --- Validate arguments ---

    my $precip   = undef;
    eval   { $precip = CPC::Grid->new($gridtype); };

    if($@) {
        $err    = "$method: An invalid GRIDTYPE argument was supplied";
        $precip = CPC::Grid->new('conus0.125deg');
        return($precip,$err);
    }

    if(not defined $date) {
        $err = "$method: DATE argument was not supplied";
        return($precip,$err);
    }

    if(not $date->isa("Date::Manip::Date")) {
        $err = "$method: The supplied DATE argument was not blessed in the Date::Manip::Date package";
        return($precip,$err);
    }

    # --- Find precip file in the archives ---

    my $basename  = "PRCP_CU_GAUGE_V1.0CONUS_0.125deg.lnx.%Y%m%d";

    my @filenames = (
        $basename,
        $basename.".RT",
        $basename.".gz",
        $basename.".RT.gz",
    );

    my $input_file = undef;

    ARCHIVE: foreach my $archive (@{$self->{archive}}) {
        if(defined $input_file) { last ARCHIVE; }

        FILENAME: foreach my $filename (@filenames) {
            if(defined $input_file) { last FILENAME; }
            my $archive_file = $date->printf("$archive/$filename");
            if(-s $archive_file) { $input_file = $archive_file; }
        }  # :FILENAME

    }  # :ARCHIVE

    if(not defined $input_file) {
        $err = "$method: No file for $date was found in the archives";
        return($precip,$err);
    }

    # --- Load precip data ---

    if($input_file =~ '.gz') {
        my $fh    = File::Temp->new();
        my $fname = $fh->filename();

        unless(gunzip $input_file => $fname) {
            $err = "$method: Could not unzip archive file $input_file - $GunzipError";
            return($precip,$err);
        }

        unless(open(INPUT,'<',$fname)) {
            $err = "$method: Could not open unzipped data file for reading (system permissions problem?)";
            return($precip,$err);
        }

        binmode(INPUT);
        my $input_str  = join('',<INPUT>);
        close(INPUT);
        my @input_vals = unpack('f*',$input_str);
        my @vals       = splice(@input_vals,scalar(@input_vals)/2);
        my $gridsize   = $precip->get_size();

        if(scalar(@vals) != $gridsize) {
            $err       = "$method: Invalid input grid size, got ".scalar(@vals)." expected $gridsize";
            return($precip,$err);
        }
        else {
            $precip->set_values(@vals);
            $precip->set_missing_value(-999.0);
        }

    }
    else {

        unless(open(INPUT,'<',$input_file)) {
            $err = "$method: Could not open $input_file for reading (system permissions problem?)";
            return($precip,$err);
        }
    
        binmode(INPUT);
        my $input_str  = join('',<INPUT>);
        close(INPUT);
        my @input_vals = unpack('f*',$input_str);
        my @vals       = splice(@input_vals,scalar(@input_vals)/2);
        my $gridsize   = $precip->get_size();

        if(scalar(@vals) != $gridsize) {
            $err       = "$method: Invalid input grid size, got ".scalar(@vals)." expected $gr
idsize";
            return($precip,$err);
        }
        else {
            $precip->set_values(@vals);
            $precip->set_missing_value(-999.0);
        }

    }

    # --- Regrid if needed ---

    

    return($precip,'');
}

1;

