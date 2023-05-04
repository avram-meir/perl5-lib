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
use Scalar::Util qw(blessed looks_like_number reftype);
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
    $self->{values}   = [];
    $self->{missing}  = 'NaN';
    $self->{size}     = 0;
    $self->{valset}   = 0;
    unless(@_) { confess "Argument required"; }
    my $gridtype      = shift;
    $self->{gridtype} = $gridtype;

    if($gridtype eq 'conus0.125deg') {
        my $lat = 20.0;

        for(my $y=0; $y<241; $y++) {
            my $lon = 230.0;

            for(my $x=0; $x<601; $x++) {
                push(@{$self->{latlons}},join(',',$lat,$lon));
                push(@{$self->{values}},$self->{missing});
                $lon += 0.125;
            }

            $lat += 0.125;
        }

        $self->{size} = scalar(@{$self->{latlons}});
    }
    elsif($gridtype eq 'global1deg') {
        my $lat = -90.0;

        for(my $y=0; $y<181; $y++) {
            my $lon = 0.0;

            for(my $x=0; $x<360; $x++) {
                push(@{$self->{latlons}},join(',',$lat,$lon));
                push(@{$self->{values}},$self->{missing});
                $lon += 1.0;
            }

            $lat += 1.0;
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

sub get_missing_value {
    my $self = shift;
    return $self->{missing};
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
    my $self = shift;
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
    unless(@_) { carp "Argument required - missing value was not updated"; return 1; }
    my $missing_val  = shift;
    my @values = @{$self->{values}};
    unless(looks_like_number($missing_val)) { confess "Non-numeric missing value is not allowed"; }
    my $tolerance = 0.001*$missing_val;
    foreach my $val (@values) { if(abs($missing_val - $val) <= $tolerance) { $val = 'NaN'; } }
    @{$self->{values}} = @values;
    $self->{missing}   = $missing_val;
    return $self;
}

sub set_values {
    my $self = shift;
    unless(@_)  { carp "Argument required - no values were set"; return 1; }
    my @values;
    if(@_ == 1) { @values = unpack('f*',shift); }
    else        { @values = @_;                 }
    unless(scalar(@values) == $self->{size}) { carp "Values do not match grid size - no values were set"; return 1; }
    @{$self->{values}} = @values;
    $self->{valset}    = 1;
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

