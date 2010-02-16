package Class::Declarative::Semantics::Code;

use warnings;
use strict;

use base qw(Class::Declarative::Node);

=head1 NAME

Class::Declarative::Semantics::Code - implements some code (perl or otherwise) in a declarative framework.

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';


=head1 SYNOPSIS

This class serves two purposes: first, it's an example of what a semantic node class should look like, and second, it
will probably end up being the class that builds most of the code references in a declarative program.

=head2 defines()

Called by Class::Declarative::Semantics during import, to find out what xmlapi tags this plugin claims to implement.

=cut
sub defines { ('on', 'do'); }

=head2 build, fixvars, fixcall, fixevent

The C<build> function is then called when this object's payload is built (i.e. in the stage when we're adding semantics to our
parsed syntax).

The parent's payload will always have been created by the time this function is called.

=cut

sub fixvars  { '$cx->{v}->{' . $_[0] . '}' }
sub fixcall  { '$cx->' . $_[0] }
sub fixevent { '$cx->fire(\'' . $_[0] . '\')' }

sub build {
   my ($self) = @_;
   my $cx = $self->event_context;

   # Here's the tricky part.  We have to build some code and evaluate it when asked.  This could get arbitrarily complex.
   # If we have a code body, that's our code.  (Note: the parser will happily allow a code body *and* children; we're going to
   # ignore that for now because I can't think of logical semantics for it.)
   if (my $body = $self->first('body')) {
      my $code = $body->content; #'my ($self, $event) = @_;' . "\n\n" . $body->content . "\n";
      
      $code =~ s/\$\^(\w+)/fixvars($1)/ge;
      $code =~ s/\^!(\w+)/fixevent($1)/ge;
      $code =~ s/\^(\w+)/fixcall($1)/ge;
      
      $self->{code} = $code;   # Kept for diagnostics.
      #print STDERR $code;
      
      $self->{sub} = eval "sub {" . $code . "\n}";
      $self->{owncode} = 1;
   } else {
      # No body means we're just going to build each of our children, and try to execute each of them in sequence when called.
      foreach ($self->elements) { $self->root->build($_) }
      my $goref = $self->can('go');
      $self->{sub} = sub { &$goref(); };
      $self->{owncode} = 0;
   }
   
   $self->{callable} = 1;
   $self->{event} = $self->is ('on') ? 1 : 0;
   if ($self->is ('on') and $self->get('name')) {
      $cx->register_event ($self->get('name'), $self->{sub});
   }

   return $self;
}

=head2 go()

This is called to execute callable stuff.  We override Node's default because we know how to build our own code in closures, so
we'll call that if we've got it.

=cut

sub go {
   my $self = shift;
   
   if ($self->{owncode}) {
      &{$self->{sub}} (@_);
   } else {
      foreach ($self->elements) {
         $_->go(@_);
      }
   }
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

1; # End of Class::Declarative::Semantics::Code
