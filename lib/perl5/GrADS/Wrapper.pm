#!/usr/bin/perl

package GrADS::Wrapper;

=pod

=head1 NAME

GrADS::Wrapper - Execute GrADS scripts from Perl and perform basic evaluations

=head1 SYNOPSIS

 use GrADS::Wrapper qw(grads set_grads_exec);

=head1 DESCRIPTION

=head1 FUNCTIONS

=head2 grads

=head2 set_grads_exec

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

@ISA           = qw(Exporter);
@EXPORT_OK     = qw(grads set_grads_exec);

my $grads_exec = 'grads';

sub grads {
	unless(@_) { croak "GrADS::Wrapper::grads() - ERROR: Argument required"; }
	my $grads_command = shift;
	chomp($grads_command);
	my $result        = `$grads_exec -blc \"$grads_command\"`;
	unless(defined $result) { carp "Grads::Wrapper::grads() - WARNING: Nothing was sent to STDOUT so no evaluations are possible"; }

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
		return "GrADS::Wrapper::grads() -  WARNING: Potential runtime problem detected. Output from GrADS:\n$result\n";
	}
	else {
		return 0;
	}

}

sub set_grads_exec {
	unless(@_)       { croak "GrADS::Wrapper::set_grads_exec() - ERROR: Argument required"; }
	my $exec    = shift; chomp $exec;
	unless(-x $exec) { croak "GrADS::Wrapper::set_grads_exec() - ERROR: You do not have executable permissions for $exec"; }
	$grads_exec = $exec;
	return 0;
}

1;
