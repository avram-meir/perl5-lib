#!/usr/bin/env perl

package Wgrib2::Regrid;

=pod

=head1 NAME

Wgrib2::Regrid - Regrid a binary IEEE file to a specified grid type using wgrib2.

=head1 SYNOPSIS

 use Wgrib2::Regrid;
 
 my $rg = Wgrib2::Regrid->new($config_file,'conus0.125deg');
 $rg->regrid($input_file,$output_file);

=head1 DESCRIPTION

=head1 METHODS

=head2 new

 my $regridder = Wgrib2::Regrid->new($config_file,$gridtype);

The new() method is the constructor for the Wgrib2::Regrid package. It returns a reference 
blessed into the Wgrib2::Regrid class, which can be used as a Wgrib2::Regrid object. Two 
arguments are required:

=over 4

=item * CONFIG_FILE - An INI-formatted configuration file containing parameters describing the input grid

=item * GRIDTYPE - A string identifying the output grid type (must be supported by the package, e.g., conus0.125deg or global1deg)

=back

See the DESCRIPTION section for a list of the required parameters in the configuration file.

=head2 regrid

 $regridder->regrid($input_file,$output_file)

Given an input binary (IEEE) gridded data file and an output filename, regrids the input data 
to match the grid dimensions used in the Wgrib2 production and stores the results as 
unformatted binary in the specified output file. Output data will have the machine native 
byte order. If the output file exists, it will be destroyed, even if the new data are not 
successfully produced.

=head1 AUTHOR

Adam Allgood

=cut

use strict;
use warnings;
use Carp qw(carp croak cluck confess);
use Scalar::Util qw(blessed looks_like_number reftype);
require File::Temp;
use File::Temp ();
use File::Temp qw(:seekable);
use Config::Simple;

my $package     = __FILE__;
my $install_dir = $package =~ s/\/lib\/perl\/Wgrib2\/Regrid.pm//r;
my $wgrib2;

BEGIN {
        $wgrib2 = `which wgrib2`; chomp $wgrib2;
        unless($wgrib2) { confess "Data::BinaryUtils requires wgrib2 to be installed on your system"; }
}

sub new {
    my $class          = shift;
    my $self           = {};
    $self->{template}  = undef;
    $self->{byteorder} = undef;
    $self->{missing}   = undef;
    $self->{header}    = undef;
    $self->{gridtype}  = undef;
    unless(@_) { confess "Argument required"; }
    my $arg            = shift;
    confess "Argument must be a hash reference" unless(reftype($arg) eq 'HASH');
    confess "Missing param input.grib2template" unless(exists $arg->{'input.grib2template'});
    confess "Missing param input.byteorder"     unless(exists $arg->{'input.byteorder'});
    confess "Missing param input.missing"       unless(exists $arg->{'input.missing'});
    confess "Missing param input.headers"       unless(exists $arg->{'input.headers'});
    confess "Missing param output.gridtype"     unless(exists $arg->{'output.gridtype'});
    $self->{template}  = $arg->{'input.grib2template'};
    $self->{byteorder} = $arg->{'input.byteorder'};
    $self->{missing}   = $arg->{'input.missing'};
    $self->{header}    = $arg->{'input.headers'};
    $self->{gridtype}  = $arg->{'output.gridtype'};

    # --- Validate params ---

    confess "Invalid input.grid2template param: Template file ".$self->{template}." not found" unless(-s $self->{template});
    confess "Invalid input.byteorder param" unless($self->{byteorder} eq 'big_endian' or $self->{byteorder} eq 'little_endian');
    confess "Invalid input.headers param" unless($self->{header} eq 'header' or $self->{header} eq 'no_header');

    my %allowed_gridtypes = ( 
        'conus0.125deg' => 1,
        'global1deg'    => 1,
    );

    confess "Invalid output.gridtype param" unless(exists $allowed_gridtype{$self->{gridtype}});

    bless($self,$class);
    return $self;
}

sub regrid {
    my $self = shift;
    confess "Two arguments required" unless(@_ >= 2);
    my $input_fn    = shift;
    my $output_fn   = shift;
    my $template    = $self->{'input.grib2template'};
    my $byteorder   = $self->{'input.byteorder'};
    my $missing     = $self->{'input.missing'};
    my $header      = $self->{'input.headers'};
    my $gridtype    = $self->{'output.gridtype'};
    my $work_dir    = File::Temp->newdir();

    # --- Convert input data to grib2 format ---

    my $input_grib2    = File::Temp->new(DIR => $work_dir);
    my $input_grib2_fn = $input_grib2->filename();
    my $error          = system("$wgrib2 -d 1 $template -import_ieee $input_fn -$header -$byteorder -undefine_val $missing -set_date 19710101 -set_grib_type j -set_scaling -1 0 -grib_out $input_grib2_fn > /dev/null");
    if($error) { confess "Could not convert $input_fn to grib2 format"; }

    # --- Regrid to the specified output grid ---

    my $output_grib2    = File::Temp->new(DIR => $work_dir);
    my $output_grib2_fn = $output_grib2->filename();

    if($gridtype eq 'conus0.125deg') {
        $error = system("$wgrib2 $input_grib2_fn -set_grib_type jpeg -new_grid_winds earth -new_grid latlon 230:601:0.125 20:241:0.125 $output_grib2_fn > /dev/null");
        if($error) { confess "Could not regrid grib2 version of $input_fn"; }
    }
    elsif($gridtype eq 'global1deg') {
        $error = system("$wgrib2 $input_grib2_fn -set_grib_type jpeg -new_grid_winds earth -new_grid latlon 0:360:1.0 -90:181:1.0 $output_grib2_fn > /dev/null");
        if($error) { confess "Could not regrid grib2 version of $input_fn"; }
    }
    else {
        confess "$gridtype is an unknown Wgrib2::Regrid gridtype (Did you update the constructor and not the regrid method for a new gridtype?)";
    }

    # --- Convert the data to unformatted binary with machine native byteorder ---

    $error = system("$wgrib2 $output_grib2_fn -no_header -bin $output_fn > /dev/null");

    if($error) {
        if(-e $output_fn) { unlink($output_fn); }
        confess"Could not create binary file $output_fn";
    }

    return $self;
}

1;

