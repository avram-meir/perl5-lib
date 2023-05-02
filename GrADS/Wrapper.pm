#!/usr/bin/perl

package GrADS::Wrapper;

=pod

=head1 NAME

GrADS::Wrapper - Execute GrADS scripts from Perl with some basic error checking

=head1 SYNOPSIS

 use GrADS::Wrapper qw(grads set_grads_exec);

=head1 DESCRIPTION

=head1 FUNCTIONS

=head2 grads

=head2 use_grads

=head1 DIAGNOSTICS

=head1 KNOWN BUGS

=head1 SEE ALSO

=head1 AUTHOR

Adam Allgood

=cut

use strict;
use warnings;
use Carp qw(carp cluck confess croak);
use vars qw(@ISA @EXPORT_OK);
use Exporter;

@ISA             = qw(Exporter);
@EXPORT_OK       = qw(grads use_grads);

my $grads_binary = 'grads';

sub grads {
    unless(@_)              { confess "Argument required"; }
    my $grads_command = shift;
    chomp($grads_command);
    my $result        = `$grads_binary -blc \"$grads_command\"`;
    unless(defined $result) { carp "There was no output from GrADS"; }

    # --- Evaluate results ---

    my $r = $result;
    $r    =~ tr/\n/ /;

    # Let certain warnings pass by replacing "warning" with something nicer

    $r    =~ s/Warning:  X axis labels overridden by SET XAXIS/Note: X axis labels overridden by SET XAXIS/g;
    $r    =~ s/Warning:  Y axis labels overridden by SET YAXIS/Note: Y axis labels overridden by SET YAXIS/g;

    if($r =~ /because the chunks are too big to fit in the cache/) {
        $r =~ s/WARNING!/ATTENTION!/g;
    }

    # Return what was printed to STDOUT if these words are included

    if($r =~ /warning/i or $r =~ /undefined/i or $r =~ /constant/i or $r =~ /cannot/i or $r =~ /error/i) {
        return "WARNING: Potential runtime problem detected. Output from GrADS:\n$result\n";
    }
    else {
        return 0;
    }

}

sub use_grads {
        unless(@_)         { confess "Argument required"; }
        my $binary    = shift; chomp $binary;
        unless(-x $binary) { croak "Executable permissions are not set for $binary"; }
        $grads_binary = $binary;
        return 0;
}

1;

