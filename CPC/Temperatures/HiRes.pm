#!/usr/bin/env perl

package CPC::Temperatures::HiRes;

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

# --- Package data ---

my $temp2m_config = "$pkg_path/HiRes/regrid-params.config";
my $hires_params  = Config::Simple->new($temp2m_config)->vars();

# --- Replace allowed vars in the config params ---

foreach my $param (keys %$hires_params) {

    if(ref($hires_params->{$param} eq 'ARRAY')) {

        for(my $i=0; $i<scalar(@{$hires_params->{$param}}); $i++) {
            $hires_params->{$param}[$i] = _parse_param($hires_params->{$param}[$i]);
        }
    }
    else {
        $hires_params->{$param} = _parse_param($hires_params->{$param});
    }

}

sub new {
    my $class             = shift;
    my $self              = {};
    $self->{archive}      = undef;
    $self->{gridtype}     = undef;
    $self->{missing}      = 9.999e+20;  # Default value for grids out of CPC::Regrid
    my $arg               = undef;

    if(@_) {
        $arg = shift;
        confess "Invalid argument to CPC::Temperatures::HiRes constructor" unless(reftype($arg) eq 'HASH');

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
    my $self = shift;
    unless(@_) { confess "No params to set"; }
    my $arg  = shift;
    confess "Invalid argument" unless(reftype($arg) eq 'HASH');

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

sub _get_field {
    my $self      = shift;
    my $src       = shift;
    confess "$src not found" unless(-s $src);
    my $field     = shift;
    my $fn = undef;
    if($field =~ /tmax/i)                         { $fn = 0; }
    elsif($field =~ /tmin/i)                      { $fn = 2; }
    elsif($field =~ /tave/i or $field =~ /tavg/i) { $fn = 4; }
    else { confess "$field is an invalid field";             }
    $hires_params->{'output.gridtype'} = $self->{gridtype};
    my $rg        = Wgrib2::Regrid->new($hires_params);
    my $split_dir = File::Temp->newdir();
    open(SPLIT,"split -n 6 --verbose $src $split_dir/input 2<&1 |") or confess "Could not split $src into 6 pieces for processing";
    my @input_files;

    while(<SPLIT>) {

        if ( /^creating file (.*)$/ ) {
            my $split_file = $1;
            $split_file    =~ s/[\p{Pi}\p{Pf}'"]//g;  # Remove every type of quotation mark
            $split_file    =~ s/[^[:ascii:]]//g;      # Remove non-ascii characters
            push(@input_files, $split_file);
        }
        else {
            warn "Warning: this output line from split was not parsed: $_";
        }

    }

    close(SPLIT);

    my $field_grid = File::Temp->new();
    $rg->regrid($input_files[$fn],$field_grid);
    confess "Unsuccessful regrid of $field in $src" unless(-s $field_grid);
    open(FIELD,'<',$field_grid) or confess "Could not open $field_grid for reading";
    binmode(FIELD);
    my $field_str  = join('',<FIELD>);
    close(FIELD);
    return CPC::Grid->new($self->{gridtype})->set_values($field_str)->set_missing_value($self->{missing});
}

sub get_tavg {
    my $self  = shift;
    confess "Two arguments required" unless(@_ >= 2);
    my $ndays = shift;
    my $date  = shift;
    confess "$ndays is an invalid argument" unless($ndays =~ /^[+-]?\d+$/ and $ndays > 0);
    confess "Second arg must be a Date::Manip::Date object" unless($date->isa("Date::Manip::Date"));
    my $delta = $date->new_delta();
    $delta->parse("1 day ago");
    my $count = 0;
    my $day   = $date;
    my $tavg  = CPC::Grid->new($self->{gridtype})->init_values(0.0);

    while($count < $ndays) {
        my $src_file   = $day->printf($self->{archive});
        my $tavg_daily = $self->_get_field($src_file,'tavg');
        $tavg         += $tavg_daily;
        $day           = $day->calc($delta);
        $count++;
    }

    $tavg = $tavg / $ndays;
    return $tavg;
}

sub _parse_param {
    my $param = shift;

    my($DATA_IN,$DATA_OUT);
    if(exists $ENV{DATA_IN})  { $DATA_IN  = $ENV{DATA_IN};  }
    else                      { $DATA_IN  = '';             }
    if(exists $ENV{DATA_OUT}) { $DATA_OUT = $ENV{DATA_OUT}; }
    else                      { $DATA_OUT = '';             }

    my %allowed_vars = (
        APP_PATH => $pkg_path,
        DATA_IN  => $DATA_IN,
        DATA_OUT => $DATA_OUT,
    );

    my $parsed = $param;
    $parsed    =~ s/\$(\w+)/exists $allowed_vars{$1} ? $allowed_vars{$1} : 'illegal000BLORT000illegal'/eg;
    if($parsed =~ /illegal000BLORT000illegal/) { confess "Illegal variable found in config file argument"; }
    return $parsed;
}

1;

