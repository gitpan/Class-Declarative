package Class::Declarative::EventContext;

use warnings;
use strict;


=head1 NAME

Class::Declarative::EventContext - base class implementing an event context in a declarative structure.

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';


=head1 SYNOPSIS

Each node in a C<Class::Declarative> structure that can respond to events can inherit from this class to get the proper machinery in place.

=head2 event_context_init()

Called during object creation to set up fields and such.

=cut

sub event_context_init {
   my $self = shift;
   $self->{v} = {};
   $self->{e} = {};
}

=head2 value($var)

Returns the global application value named.

=cut

sub value { $_[0]->{v}->{$_[1]} }

=head2 event_context()

Returns $self, the event context of last resort.

=cut

sub event_context { $_[0] }

=head2 register_event($event, $closure), fire ($event)

Registers and fires closures by name.  This is the mechanism used by the 'on' tag in the core semantics.

=cut

sub register_event {
   my ($self, $event, $closure) = @_;

   $self->{e}->{$event} = $closure;
}

sub fire {
   my ($self, $event) = @_;
   
   my $e = $self->{e}->{$event};
   &$e if $e;
}


=head1 AUTHOR

Michael Roberts, C<< <michael at vivtek.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-wx-definedui at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Wx-DefinedUI>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 LICENSE AND COPYRIGHT

Copyright 2010 Michael Roberts.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

=cut

1; # End of Class::Declarative::EventContext
