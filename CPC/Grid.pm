#!/usr/bin/env perl

package CPC::Grid;

=pod

=head1 NAME

CPC::Grid - Create, access, and modify data in lists set up to match common grids used at the Climate Prediction Center

=head1 SYNOPSIS

 use CPC::Grid;
 
 my $grid    = CPC::Grid->new('conus0.125deg');
 $grid->set_values($binary_string);
 $grid->set_values(@data_array);
 my @latlons = $grid->get_latlons();
 $grid->set_missing_value(-999.0);
 my $values  = $grid->get_values();
 my @values  = $grid->get_values();

=head1 DESCRIPTION

=head1 METHODS

=head2 new

 my $grid = CPC::Grid->new('conus0.125deg');

Returns a reference blessed into the CPC::Grid class (object). An argument defining the 
CPC grid type (preset definition) must be supplied.

=head2 set_values

 $grid->set_values($binary_string);
 $grid->set_values(@array);

Given either a string of unformatted floating-point binary data or a list of values, stores 
these data in the CPC::Grid object.

=head2 set_missing_value

 $grid->set_missing_value(-999.0);

Sets the argument passed as the missing value in the dataset. Any values set to the previous 
missing value will be reset to the new missing value.

=head2 get_values

 my @values = $grid->get_values();
 my $values = $grid->get_values();

Returns the grid values. Will return all missing values and carp if nothing was passed in via 
set_values(). In scalar context, it will return the values as a floating-point unformatted 
binary string. In list context, it will return the values in an array.

=head2 Operator overloading

Add info here.

=head1 AUTHOR

Adam Allgood

=cut

use strict;
use warnings;
use Carp qw(carp croak cluck confess);
use File::Temp qw(:seekable);
use File::Which qw(which);
use Scalar::Util qw(blessed looks_like_number reftype);
use List::Util qw(first);
use List::MoreUtils qw(pairwise);
use overload
    '+'        => \&_add,
    '-'        => \&_subtract,
    '*'        => \&_multiply,
    '/'        => \&_divide,
    '%'        => \&_mod,
    '**'       => \&_pow,
    'atan2'    => \&_atan,
    'cos'      => \&_cosine,
    'sin'      => \&_sine,
    'exp'      => \&_exp,
    'abs'      => \&_absval,
    'log'      => \&_log_e,
    'sqrt'     => \&_square_root,
    'int'      => \&_int,
    'nomethod' => \&_nomethod;

sub new {
    my $class = shift;
    my $self  = {};
    $self->{latlons}  = [];
    $self->{lats}     = [];
    $self->{lons}     = [];
    $self->{name}     = undef;
    $self->{values}   = [];
    $self->{missing}  = 'NaN';
    $self->{size}     = 0;
    $self->{valset}   = 0;
    unless(@_) { confess "Argument required"; }
    my $gridtype      = shift;
    $self->{gridtype} = $gridtype;

    if($gridtype eq 'conus0.125deg') {
        my $lat = 20.0;
        my $lon = 230.0;

        for(my $y=0; $y<241; $y++) {
            push(@{$self->{lats}},$lat);
            $lat += 0.125;
        }

        for(my $x=0; $x<601; $x++) {
            push(@{$self->{lons}},$lon);
            $lon += 0.125;
        }

        foreach $lat (@{$self->{lats}}) {

            foreach $lon (@{$self->{lons}}) {
                push(@{$self->{latlons}},join(',',$lat,$lon));
                push(@{$self->{values}},$self->{missing});
            }

        }

        $self->{size} = scalar(@{$self->{latlons}});
    }
    elsif($gridtype eq 'global1deg') {
        my $lat = -90.0;
        my $lon = 0.0;

        for(my $y=0; $y<181; $y++) {
            push(@{$self->{lats}},$lat);
            $lat += 1.0;
        }

        for(my $x=0; $x<360; $x++) {
            push(@{$self->{lons}},$lon);
            $lon += 1.0;
        }

        foreach $lat (@{$self->{lats}}) {

            foreach $lon (@{$self->{lons}}) {
                push(@{$self->{latlons}},join(',',$lat,$lon));
                push(@{$self->{values}},$self->{missing});
            }

        }

        $self->{size} = scalar(@{$self->{latlons}});
    }
    elsif($gridtype eq 'global6thdeg') {
        my $lat = -89.917;
        my $lon = 0.083;

        for(my $y=0; $y<1080; $y++) {
            push(@{$self->{lats}},$lat);
            $lat += 0.1666666667;
        }

        for(my $x=0; $x<2160; $x++) {
            push(@{$self->{lons}},$lon);
            $lon += 0.1666666667;
        }

        foreach $lat (@{$self->{lats}}) {

            foreach $lon (@{$self->{lons}}) {
                push(@{$self->{latlons}},join(',',$lat,$lon));
                push(@{$self->{values}},$self->{missing});
            }

        }

        $self->{size} = scalar(@{$self->{latlons}});
    }
    else {
        confess "Gridtype $gridtype is not supported";
    }

    bless($self,$class);
    return $self;
}

sub get_gridtype {
    my $self = shift;
    return $self->{gridtype};
}

sub get_latlons {
    my $self = shift;
    if(wantarray()) { return @{$self->{latlons}}; }
    else            { return $self->{latlons};   }
}

sub get_lats {
    my $self = shift;
    if(wantarray()) { return @{$self->{lats}}; }
    else            { return $self->{lats};   }
}

sub get_lons {
    my $self = shift;
    if(wantarray()) { return @{$self->{lons}}; }
    else            { return $self->{lons};   }
}

sub get_missing_value {
    my $self = shift;
    return $self->{missing};
}

sub get_name {
    my $self = shift;
    if(not defined($self->{name})) { carp "Name is undefined"; return undef; }
    else                           { return $self->{name};                   }
}

sub get_size {
    my $self = shift;
    return scalar(@{$self->{values}});
}

sub get_values {
    my $self   = shift;
    unless($self->{valset}) { carp "Values were never set by set_values()"; }
    my @values = @{$self->{values}};
    foreach my $val (@values) { if($val =~ /nan/i) { $val = $self->{missing}; } }
    if(wantarray()) { return @values; }
    else { return pack('f*',@values); }
}

sub get_values_missing_nans {
    my $self   = shift;
    unless($self->{valset}) { carp "Values were never set by set_values()"; }
    my @values = @{$self->{values}};
    if(wantarray()) { return @values; }
    else { return pack('f*',@values); }
}

sub init_values {
    my $self        = shift;
    unless(@_) { carp "Argument required - no values were set"; return $self; }
    my $value       = shift;
    for(my $i=0; $i<$self->{size}; $i++) { ${$self->{values}}[$i] = $value; }
    $self->{valset} = 1;
    return $self;
}

sub set_missing_value {
    my $self         = shift;
    unless(@_) { carp "Argument required - missing value was not updated"; return $self; }
    my $missing_val  = shift;
    my @values = @{$self->{values}};
    unless(looks_like_number($missing_val)) { confess "Non-numeric missing value is not allowed"; }
    my $tolerance = abs(0.001*$missing_val);
    foreach my $val (@values) { if(abs($missing_val - $val) <= $tolerance) { $val = 'NaN'; } }
    @{$self->{values}} = @values;
    $self->{missing}   = $missing_val;
    return $self;
}

sub set_name {
    my $self = shift;
    unless(@_) { carp "Argument required - name was not set"; return $self; }
    $self->{name} = shift;
    return $self;
}

sub set_values {
    my $self = shift;
    unless(@_)  { carp "Argument required - no values were set"; return $self; }
    my @values;
    if(@_ == 1) { @values = unpack('f*',shift); }
    else        { @values = @_;                 }
    unless(scalar(@values) == $self->{size}) { carp "Values do not match grid size - no values were set"; return 1; }
    my $missing_val = $self->{missing};
    my $tolerance = abs(0.001*$missing_val);
    foreach my $val (@values) { if(abs($missing_val - $val) <= $tolerance) { $val = 'NaN'; } }
    @{$self->{values}} = @values;
    $self->{valset}    = 1;
    return $self;
}

sub set_values_from_file {
    my $self       = shift;
    unless(@_) { carp "Argument required - no values were set"; return $self; }
    my $input_file = shift;
    unless(-s $input_file) { carp "File $input_file not found - no values were set"; return $self; }
    my $format     = 'binary';
    if(@_) { $format = shift; }

    if($format =~ /binary/i) {
        unless(open(INPUT,'<',$input_file)) { carp "Cannot open $input_file for reading - $! - no values were set"; return $self; }
        binmode(INPUT);
        my $input_str = join('',<INPUT>);
        close(INPUT);
        return $self->set_values($input_str);
    }
    elsif($format =~ /netcdf/i) {
        my $field     = 'grid';
        if(@_) { $field = shift; }
        my $cdl_fh    = File::Temp->new();
        my $cdl_fn    = $cdl_fh->filename();
        my $err       = system("ncdump -v $field $input_file | sed -e '1,/data:/d' -e '\$d' > $cdl_fn");
        if($err) { carp "An error occurred using ncdump to parse $input_file - no values were set"; return $self; }
        unless(open(CDL,'<',$cdl_fn)) { carp "Cannot open cdl dump for reading - $! - no values were set"; return $self; }
        my $cdl_str   = do { local $/; <CDL> };
        close(CDL);
        $cdl_str      =~ s/\R//g;
        my @vals      = split(',',$cdl_str);
        my @dump      = split('=',$vals[0]);
        $vals[0]      = pop(@dump);
        $vals[-1]     =~ s/;//g;

        for(my $i=0; $i<scalar(@vals); $i++) {
            my $val    = $vals[$i];
            $val       =~ s/^\s+//;
            $val       =~ s/\s+$//;
            if($val =~ '_' or $val =~ '-')  { $val = 'NaN'; }
            unless(looks_like_number($val)) { $val = 'NaN'; }
            $vals[$i] = $val;
        }

        return $self->set_values(@vals);
    }
    else {
        carp "Format $format is not supported - no values were set"; return $self;
    }

}

sub write_binary {
    my $self        = shift;
    unless(@_) { confess "Argument required"; }
    my $binary_file = shift;
    my $missing     = $self->{missing};
    my @values      = @{$self->{values}};
    foreach my $val (@values) { if($val =~ /nan/i) { $val = $missing; } }
    open(BINARY,'>',$binary_file) or confess "Could not open $binary_file for writing - $!";
    binmode(BINARY);
    my $binary_str  = pack('f*',@values);
    print BINARY $binary_str;
    close(BINARY);
    return $self;
}

sub write_netcdf {
    my $self  = shift;
    my $ncgen = which('ncgen');
    unless(defined $ncgen) { confess "Executable ncgen was not found on your system"; }
    unless(@_) { carp "Argument required"; }
    my $netcdf_file = shift;
    my $format      = undef;
    if(@_) { $format = shift;    }
    else   { $format = 'double'; }
    if(not defined(first { $format eq $_ } qw(char byte short int float double))) { carp "Invalid format arg - using default 'double'"; $format = 'double'; }
    my $cdl_fh      = File::Temp->new();
    my $cdl_file    = $cdl_fh->filename();
    $self->write_cdl($cdl_file,$format);
    unless(-s $cdl_file) { confess "There was a problem creating the CDL input data for netCDF generation"; }
    my $err         = system("$ncgen -o $netcdf_file $cdl_file");

    if($err)             {
        if(-s $netcdf_file) { unlink($netcdf_file); }
        confess "There was a problem creating the netCDF file";
    }

    return $self;
}

sub write_cdl {
    my $self     = shift;
    unless(@_) { carp "Argument required"; }
    my $cdl_file = shift;
    my $name     = undef;
    if(defined $self->{name}) { $name = $self->{name}; }
    else                      { carp 'Grid name is undefined - using "grid" as name'; $name = 'grid'; }
    my $format   = undef;
    if(@_) { $format = shift;    }
    else   { $format = 'double'; }
    if(not defined(first { $format eq $_ } qw(char byte short int float double))) { carp "Invalid format arg - using default 'double'"; $format = 'double'; }
    my $lonsz    = scalar(@{$self->{lons}});
    my $latsz    = scalar(@{$self->{lats}});
    my $missing  = $self->{missing};
    my @values = @{$self->{values}};
    foreach my $val (@values) { if($val =~ /nan/i) { $val = '_'; } }
    open(CDLFILE,'>',$cdl_file) or confess "Could not open $cdl_file for writing - $!";

    print CDLFILE <<"END_HEADER";
netcdf $name {
dimensions:
	lon = $lonsz ;
	lat = $latsz ;
variables:
	float lon(lon) ;
		lon:units = "degrees_east" ;
		lon:long_name = "Longitude" ;
	float lat(lat) ;
		lat:units = "degrees_north" ;
		lat:long_name = "Latitude" ;
	$format $name(lat, lon) ;
		$name:_FillValue = $missing ;
data:

END_HEADER

    my $lonstr  = " lon = ".join(', ',@{$self->{lons}})." ;";
    my $latstr  = " lat = ".join(', ',@{$self->{lats}})." ;";
    my $datastr = " $name = ".join(', ',@values)." ;";
    print CDLFILE "$lonstr\n\n";
    print CDLFILE "$latstr\n\n";
    print CDLFILE "$datastr\n}\n";
    close(CDLFILE);
    return $self;
}

# --- Operator overloading methods ---

sub _get_operand_vals {
    my($self,$thing) = @_;
    my(@operand1,@operand2);
    @operand1 = $self->get_values_missing_nans();
    if(ref($thing) and blessed($thing) eq 'CPC::Grid')    { @operand2 = $thing->get_values_missing_nans(); }
    elsif(looks_like_number($thing))                      { @operand2 = ($thing) x scalar(@operand1); }
    else                                                  { confess "Invalid operand used in operation with CPC::Grid object";   }
    if(scalar(@operand1) != scalar(@operand2))            { confess "CPC::Grid objects have mismatched grid sizes in operation"; }
    return(\@operand1,\@operand2);
}

sub _add { # Overloads + operator
    my($self,$thing,$switched) = @_;
    my $gridtype               = $self->get_gridtype();
    my($operand1,$operand2)    = _get_operand_vals($self,$thing);
    my @result = pairwise { $a + $b } @{$operand1}, @{$operand2};
    return CPC::Grid->new($gridtype)->set_values(@result);
}

sub _multiply { # Overloads * operator
    my($self,$thing,$switched) = @_;
    my $gridtype               = $self->get_gridtype();
    my($operand1,$operand2)    = _get_operand_vals($self,$thing); 
    my @result = pairwise { $a * $b } @{$operand1}, @{$operand2};
    return CPC::Grid->new($gridtype)->set_values(@result);
}

sub _subtract { # Overloads - operator
    my($self,$thing,$switched) = @_;
    my $gridtype               = $self->get_gridtype();
    my($operand1,$operand2)    = _get_operand_vals($self,$thing); 
    my @result;
    if($switched) { @result    = pairwise { $b - $a } @{$operand1}, @{$operand2}; }
    else          { @result    = pairwise { $a - $b } @{$operand1}, @{$operand2}; }
    return CPC::Grid->new($gridtype)->set_values(@result);
}

sub _divide { # Overloads / operator
    my($self,$thing,$switched) = @_;
    my $gridtype               = $self->get_gridtype();
    my($operand1,$operand2)    = _get_operand_vals($self,$thing);
    my @result;
    if($switched) { @result    = pairwise { $b / $a } @{$operand1}, @{$operand2}; }
    else          { @result    = pairwise { $a / $b } @{$operand1}, @{$operand2}; }
    return CPC::Grid->new($gridtype)->set_values(@result);
}

sub _mod { # Overloads % operator
    my($self,$thing,$switched) = @_;
    my $gridtype               = $self->get_gridtype();
    my($operand1,$operand2)    = _get_operand_vals($self,$thing);
    my @result;
    if($switched) { @result    = pairwise { $b % $a } @{$operand1}, @{$operand2}; }
    else          { @result    = pairwise { $a % $b } @{$operand1}, @{$operand2}; }
    return CPC::Grid->new($gridtype)->set_values(@result);
}

sub _pow { # Overloads ** operator
    my($self,$thing,$switched) = @_;
    my $gridtype               = $self->get_gridtype();
    my($operand1,$operand2)    = _get_operand_vals($self,$thing);
    my @result;
    if($switched) { @result    = pairwise { $b ** $a } @{$operand1}, @{$operand2}; }
    else          { @result    = pairwise { $a ** $b } @{$operand1}, @{$operand2}; }
    return CPC::Grid->new($gridtype)->set_values(@result);
}

sub _cosine { # Overloads cos()
    my $self       = shift;
    my $gridtype   = $self->get_gridtype();
    my @operand    = $self->get_values_missing_nans();
    my @result;
    foreach my $g (@operand) { push(@result,cos($g)); }
    return CPC::Grid->new($gridtype)->set_values(@result);
}

sub _sine { # Overloads sin()
    my $self       = shift;
    my $gridtype   = $self->get_gridtype();
    my @operand    = $self->get_values_missing_nans();
    my @result;
    foreach my $g (@operand) { push(@result,sin($g)); }
    return CPC::Grid->new($gridtype)->set_values(@result);
}

sub _absval { # Overloads abs()
    my $self       = shift;
    my $gridtype   = $self->get_gridtype();
    my @operand    = $self->get_values_missing_nans();
    my @result;
    foreach my $g (@operand) { push(@result,abs($g)); }
    return CPC::Grid->new($gridtype)->set_values(@result);
}

sub _log_e { # Overloads log()
    my $self       = shift;
    my $gridtype   = $self->get_gridtype();
    my @operand    = $self->get_values_missing_nans();
    my @result;
    foreach my $g (@operand) { push(@result,log($g)); }
    return CPC::Grid->new($gridtype)->set_values(@result);
}

sub _square_root { # Overloads sqrt()
    my $self       = shift;
    my $gridtype   = $self->get_gridtype();
    my @operand    = $self->get_values_missing_nans();
    my @result;
    foreach my $g (@operand) { push(@result,sqrt($g)); }
    return CPC::Grid->new($gridtype)->set_values(@result);
}

sub _int { # Overloads int()
    my $self       = shift;
    my $gridtype   = $self->get_gridtype();
    my @operand    = $self->get_values_missing_nans();
    my @result;
    foreach my $g (@operand) { push(@result,int($g)); }
    return CPC::Grid->new($gridtype)->set_values(@result);
}

sub _nomethod { # ???
    my $operator = pop;
    confess "Cannot use $operator operator with a CPC::Grid object";
}

1;

