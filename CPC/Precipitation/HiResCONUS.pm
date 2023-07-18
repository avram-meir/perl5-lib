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
    my $date     = undef;
    my $gridtype = undef;
    if(@_) { $date     = shift; }
    if(@_) { $gridtype = shift; }
    else   { $gridtype = 'conus0.125deg'; }

    # --- Validate arguments ---

    my $precip   = undef;
    eval                                    { $precip = CPC::Grid->new($gridtype); };
    if($@)                                  { return(CPC::Grid->new('conus0.125deg')->set_missing_value($self->{missing}),"$method: An invalid GRIDTYPE argument was supplied"); }
    $precip->set_missing_value($self->{missing});
    if(not defined $date)                   { return($precip,"$method: DATE argument was not supplied"); }
    if(not $date->isa("Date::Manip::Date")) { return($precip,"$method: The supplied DATE argument was not a blessed Date::Manip::Date reference"); }

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

    if(not defined $input_file) { return($precip,"$method: No file for $date was found in the archives"); }

    # --- Load precip data ---

    my $input_fh = File::Temp->new();
    my $input_fn;

    if($input_file =~ '.gz') {
        $input_fn    = $input_fh->filename();
        unless(gunzip $input_file => $input_fn) { return($precip,"$method: Could not unzip archive file $input_file - $GunzipError"); }
    }
    else {
        $input_fn = $input_file;
    }

    unless(open(INPUT,'<',$input_fn)) { return($precip,"$method: Could not open unzipped file $input_fn for reading (system permissions problem?)"); }
    binmode(INPUT);
    my $input_str  = join('',<INPUT>);
    close(INPUT);
    my @input_vals = unpack('f*',$input_str);
    my @vals       = splice(@input_vals,0,scalar(@input_vals)/2);

    # --- Regrid if needed ---

    if($gridtype ne 'conus0.125deg') {
        my $grib2template    = "$pkg_path../grib2templates/conus0.125deg.grb";
        my $temp_fh          = File::Temp->new();
        my $temp_fn          = $temp_fh->filename();
        my $output_fh        = File::Temp->new();
        my $output_fn        = $output_fh->filename();
        unless(open(TEMP,'>',$temp_fn)) { return($precip,"$method: Could not open $temp_fn for writing (system permissions problem?)"); }
        binmode(TEMP);
        my $temp_str         = pack('f*',@vals);
        print TEMP $temp_str;
        close(TEMP);
        my $params           = {};
        $params->{'input.template'}  = $grib2template;
        $params->{'input.byteorder'} = 'little_endian';
        $params->{'input.missing'}   = -999.0;
        $params->{'input.headers'}   = 'no_header';
        $params->{'output.gridtype'} = $gridtype;
        my $rg                       = Wgrib2::Regrid->new($params);
        $rg->regrid($temp_fn,$output_fn);
        unless(open(OUTPUT,'<',$output_fn)) { return($precip,"$method: Could not open temporary regridded data file $output_fn for reading (system permissions problem?)"); }
        binmode(OUTPUT);
        my $rg_string                = join('',<OUTPUT>);
        @vals                        = unpack('f*',$rg_string);
        $precip->set_values(@vals)->set_missing_value(9.999e+20);  # Default missing value from wgrib2
        $precip->set_missing_value($self->{missing});
    }
    else {
        $precip->set_values(@vals);
    }
    return($precip/10.0,'');
}

1;

