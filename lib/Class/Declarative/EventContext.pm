package hashtie;
use warnings;
use strict;
require Tie::Hash;
our @ISA = qw(Tie::ExtraHash);

sub STORE {
   my ($this, $key, $value) = @_;
   if ($this->[1]{$key}) { return &{$this->[1]{$key}}($this->[0], $key, $value); }
   $this->[0]{$key} = $value;
}

sub FETCH {
   my ($this, $key, $value) = @_;
   if ($this->[1]{$key}) { return &{$this->[1]{$key}}($this->[0], $key); }
   $this->[0]{$key};
}

package Class::Declarative::EventContext;

use warnings;
use strict;
use Class::Declarative::Semantics::Code;


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
   
   my %values = ();
   my %handlers = ();
   tie %values, 'hashtie', \%handlers;
   $self->{v} = \%values;
   $self->{h} = \%handlers;
   $self->{e} = {};
}

=head2 value($var), setvalue($var, $value)

Accesses the global application value named.

=cut

sub value { $_[0]->{v}->{$_[1]} }
sub setvalue { $_[0]->{v}->{$_[1]} = $_[2]; }

=head2 register_varhandler ($event, $handler)

Registers a variable handler in the event context.  If there is a handler registered for a name, it will be called instead of the normal
hash read and write.  This means you can attach active content to a variable, then treat it just like any other variable in your code.

=cut

sub register_varhandler {
   my ($self, $key, $handler) = @_;
   $self->{h}->{$key} = $handler;
}


=head2 event_context()

Returns $self.

=cut

sub event_context { $_[0] }

=head2 register_event($event, $closure), fire ($event)

Registers and fires closures by name.  This is the mechanism used by the 'on' tag in the core semantics.

=cut

sub register_event {
   my ($self, $event, $closure) = @_;

   $self->{e}->{$event} = $closure;
}

=head2 make_event

Given the name of a C<Class::Declarative> event, finds the code referred to in its callable closure.

=cut

sub make_event {
   my ($self, $item) = @_;
   
   # Does the item have a body or children?  Then use Class::Declarative::Semantics::Code to build code for it.
   # Note: the flag $is_event registers the item as a named event, if it has a name.
   Class::Declarative::Semantics::Code::build ($item, 1);
   return $item->{sub} if $item->{callable};

   # Does the item have an appropriately named 'on' handler?  Then build that and use it.
   # Search up the tree to inherit parents' 'on' handlers.
   for (my $cursor = $item; $cursor; $cursor = $cursor->parent()) {
      foreach ($cursor->elements) {
         if ($_->is('on') and $_->get('name') eq $item->get('name') and $item->can('build') and my $handler = $_->build) {
            my $closure = $handler->closure();
            $self->register_event($_->get('name'), $closure);
            return $closure;
         }
      }
   }
   
   # If all else fails, build a stub.
   my $closure = sub { print "event " . $item->get('name') . "\n"; };
   $self->register_event($_->get('name'), $closure);
   return $closure;
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
