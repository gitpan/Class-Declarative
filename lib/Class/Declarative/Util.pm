package Class::Declarative::Util;

use warnings;
use strict;
use base qw(Exporter);
use vars qw(@EXPORT);

@EXPORT = qw(car cdr popcar splitcar lazyiter escapequote);

=head1 NAME

Class::Declarative::Util - some utility functions for the declarative framework - automatically included for generated code.

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';


=head1 SYNOPSIS

This class is a lightweight set of utilities to make things easier throughout C<Class::Declarative>.  I'm not yet sure what will end up here, but my
rule of thumb is that it's extensions I'd like to be able to use in code generators as well.

=head2 car(), cdr(), popcar(), splitcar()

I like Higher-Order Perl, really I do - but his head/tail streams are really just car and cdr, so I'm hereby defining car and cdr as lazy-evaluated streams
throughout the language.  Nodes are arrayrefs.  Clean and simple, no object orientation required.

=cut

sub car ($) { return undef unless ref $_[0] eq 'ARRAY'; $_[0]->[0] }
sub cdr ($) {
   my ($s) = @_;
   return undef unless ref $s eq 'ARRAY';
   $s->[1] = $s->[1]->() if ref $s->[1] eq 'CODE';
   $s->[1];
}
sub popcar ($) {
   my $p = car($_[0]);
   $_[0] = cdr($_[0]);
   return $p;
}
sub splitcar ($) { @{$_[0]}; }

=head2 lazyiter($iterator)

Takes any coderef (but especially an L<Iterator::Simple>) and builds a stream out of it.

=cut

sub lazyiter {
   my $i = shift;
   my $value = $i->();
   return unless defined $value;
   [$value, sub { lazyiter ($i); }]
}

=head2 escapequote($string, $quote)

Returns a new string with C<$quote> escaped (by default, '"' is escaped) by means of a backslash.

=cut

sub escapequote {
   my ($string, $quote);
   $quote = '"' unless $quote;
   $string =~ s/($quote)/\\$1/g;
   $string
}

=head1 AUTHOR

Michael Roberts, C<< <michael at vivtek.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-class-declarative at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Class-Declarative>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 LICENSE AND COPYRIGHT

Copyright 2010 Michael Roberts.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

=cut

1; # End of Class::Declarative::Util
