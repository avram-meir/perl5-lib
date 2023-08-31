#!/usr/bin/env perl

package CPC::Temperature::HiRes;

=pod

=head1 NAME

CPC::Temperatures::HiRes - Read CPC's global hi-res (6th degree cartesian) temperature dataset and return data in CPC::Grid objects

=head1 SYNOPSIS

 use CPC::Grid;
 use CPC::Temperatures::HiRes;

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
    my $class             = shift;
    my $self              = {};
    my $method            = "$class\::new";
    $self->{archive}      = undef;
    $self->{class}        = $class;
    $self->{missing}      = -999.0;
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

sub _get_field {
    my $self      = shift;
    my $method    = shift;
    my $field     = shift;
    my $date      = shift;
    my $gridtype  = shift;

    # --- Build CPC::Grid object ---

    my $temp = undef;
    eval   { $temp = CPC::Grid->new($gridtype); };
    if($@) { return(CPC::Grid->new('global6thdegree')->set_missing_value($self->{missing}), "$method: GRIDTYPE argument is invalid"); }

    # --- Validate date ---

    if(not $date->isa("Date::Manip::Date")) { return($temp,"$method: DATE argument is invalid"); }

    # --- Find temperature file in the archives ---

    my $basename = "CPC_GLOBAL_T_V0.x_10min.lnx.%Y%m%d";

    my @filenames = (
        $basename,
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

    if(not defined $input_file) { return($temp,$date->printf("$method: No file for %b %d, %Y was found in the archives")); }

    # --- Load temperature data ---

    my $fn = undef;
    if($field =~ /tmax/i)                         { $fn = 0; }
    elsif($field =~ /tmin/i)                      { $fn = 2; }
    elsif($field =~ /tave/i or $field =~ /tavg/i) { $fn = 4; }
    else { return($temp,"$method: $field is an invalid field"); }

    my $split_dir = File::Temp->newdir();
    unless(open(SPLIT,"split -n 6 --verbose $input_file $split_dir/input 2<&1 |")) { return($temp,"$method: Could not split $input_file into 6 pieces for processing"); }
    my @input_files;

    while(<SPLIT>) {

        if ( /^creating file (.*)$/ ) {
            my $split_file = $1;
            $split_file    =~ s/[\p{Pi}\p{Pf}'"]//g;  # Remove every type of quotation mark
            $split_file    =~ s/[^[:ascii:]]//g;      # Remove non-ascii characters
            push(@input_files, $split_file);
        }
        else {
            carp "Warning: this output line from splitting the temperature dataset was not parsed: $_";
        }

    }

    close(SPLIT);
    my $input_fn = $input_files[$fn];

    # --- Regrid if needed ---

    if($gridtype ne 'global6thdeg') {
        my $grib2template = "$pkg_path../grib2templates/global6thdegree.grb";
        my $output_fh     = File::Temp->new();
        my $output_fn     = $output_fh->filename();
        my $params        = {};
        $params->{'input.grib2template'} = $grib2template;
        $params->{'input.byteorder'}     = 'little_endian';
        $params->{'input.missing'}       = -999.0;
        $params->{'input.headers'}       = 'no_header';
        $params->{'output.gridtype'}     = $gridtype;
        my $rg                           = Wgrib2::Regrid->new($params);
        $rg->regrid($input_fn,$output_fn);
        unless(open(TEMP,'<',$output_fn)) { return($temp,"$method: Could not open file holding regridded temperature data $output_fn for reading (system permissions problem?)"); }
        binmode(TEMP);
        my $temp_data = join('',<TEMP>);
        close(TEMP);
        $temp->set_values($temp_data)->set_missing_value(9.999e+20); # Default missing value from wgrib2
        $temp->set_missing_value($self->{missing});
    }
    else {
        unless(open(TEMP,'<',$input_fn)) { return($temp,"$method: Could not open file holding temperature data $input_fn for reading (system permissions problem?)"); }
        binmode(TEMP);
        my $temp_data = join('',<TEMP>);
        close(TEMP);
        $temp->set_values($temp_data);
    }

    return($temp,'');
}

sub get_tavg {
    my $self     = shift;
    my $class    = $self->{class};
    my $method   = "$class\::get_tavg";
    my $field    = "tavg";
    my $date     = '';
    my $gridtype = undef;
    if(@_) { $date     = shift; }
    if(@_) { $gridtype = shift; }
    else   { $gridtype = 'global6thdegree'; }
    my($result,$err)   = $self->_get_field($method,$field,$date,$gridtype);
    return($result,$err);
}

sub get_tmax {
    my $self     = shift;
    my $class    = $self->{class};
    my $method   = "$class\::get_tmax";
    my $field    = "tmax";
    my $date     = '';
    my $gridtype = undef;
    if(@_) { $date     = shift; }
    if(@_) { $gridtype = shift; }
    else   { $gridtype = 'global6thdegree'; }
    my($result,$err)   = $self->_get_field($method,$field,$date,$gridtype);
    return($result,$err);
}

sub get_tmin {
    my $self     = shift;
    my $class    = $self->{class};
    my $method   = "$class\::get_tmin";
    my $field    = "tmin";
    my $date     = '';
    my $gridtype = undef;
    if(@_) { $date     = shift; }
    if(@_) { $gridtype = shift; }
    else   { $gridtype = 'global6thdegree'; }
    my($result,$err)   = $self->_get_field($method,$field,$date,$gridtype);
    return($result,$err);
}

1;

