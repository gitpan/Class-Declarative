package Class::Declarative::Node;

use warnings;
use strict;

use base qw(XML::xmlapi);  # Our structure is based on XML::xmlapi, with some useful embellishments.
use Data::Dumper;

=head1 NAME

Class::Declarative::Node - implements a node in a declarative structure.

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';


=head1 SYNOPSIS

Each node in a C<Class::Declarative> structure is represented by one of these objects.  Specific semantics subclass these nodes for each of their
components.

=head2 defines()

Called by Wx::DefinedUI during import, to find out what xmlapi tags this plugin claims to implement.  This is a class method, and by default
we've got nothing.

=cut
sub defines { (); }

=head2 new()

After creating the XML::xmlapi node, our local C<new> has to create a null payload.

=cut

sub new {
   my $class = shift;
   my $self = $class->SUPER::new (@_);
   $self->{payload} = undef;
   $self->{sub} = sub {};   # Null action.
   $self->{callable} = 0;   # Default is not callable.
   return $self;
}

=head2 payload()

Returns our payload (the underlying object in whatever system we're providing a framework for).

=cut

sub payload { $_[0]->{payload}; }

=head2 build(), build_payload(), add_to_parent()

The C<build> function builds the payload we define, then builds all its children, then adds itself to its parent.  It provides two hooks,
C<build_payload> and C<add_to_parent>, that can be overridden by semantic classes.  The defaults do nothing.

=cut

sub build {
   my $self = shift;
   
   $self->build_payload;
   
   foreach ($self->elements) {
      $_->build;
   }
   
   $self->add_to_parent;
   
   return $self->payload;
}

sub build_payload {}
sub add_to_parent {}

=head2 describe

The C<describe> function is used to get our code back out so we can reparse it later if we want to.

=cut

sub describe {
   my ($self) = @_;
   
   $self->name . "\"" . $self->get('name') . "\"";
}

=head2 go($item)

For callable nodes, this is one way to call them.  The default is to call the go methods of all the children of the node, in sequence.

=cut

sub go {
   my $self = shift;

   return unless $self->{callable};
   foreach ($self->elements) {
      $_->go (@_);
   }
}

=head2 closure(...)

For callable nodes, this is the other way to call them; it returns the closure created during initialization.  Note that the
default closure is really boring.

=cut

sub closure { $_[0]->{sub} }

=head2 body()

Extracts the body text of this node, if any.

=cut

sub body {
   my $self = shift;
   
   my $body = $self->first('body');
   return '' unless $body;
   return $body->content;
}


our $ACCEPT_EVENTS = 0;

=head2 event_context

If the node is an event context (e.g. a window or frame or dialog), this should return the payload of the node.
Otherwise, it returns the event_context of the parent node.

=cut

sub event_context {
   return $_[0] if $ACCEPT_EVENTS;
   return $_[0]->parent()->event_context() if $_[0]->parent;
   $_[0]->root;
}

=head2 root

Returns the parent - all nodes do this.  The top node at C<Class::Declarative> returns itself.

=cut

sub root {$_[0]->parent}


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

1; # End of Class::Declarative::Node
