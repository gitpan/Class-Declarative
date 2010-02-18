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
sub defines { ('on', 'do', 'perl*'); }

=head2 build, fixvars, fixcall, fixevent

The C<build> function is then called when this object's payload is built (i.e. in the stage when we're adding semantics to our
parsed syntax).

The parent's payload will always have been created by the time this function is called.

=cut

sub fixvars  { '$cx->{v}->{' . $_[0] . '}' }
sub fixcall  { '$cx->' . $_[0] }
sub fixevent { '$cx->fire(\'' . $_[0] . '\')' }

sub build {
   my $self = shift;
   my $is_event = shift;

   return $self if $self->{built};
   $self->{built} = 1;
   my $cx = $self->event_context;
   
   # Here's the tricky part.  We have to build some code and evaluate it when asked.  This could get arbitrarily complex.
   # If we have a code body, that's our code.  (Note: the parser will happily allow a code body *and* children; we're going to
   # ignore that for now because I can't think of logical semantics for it.)
   if (my $body = $self->first('body')) {
      my $code = '';
      if (@_) {
         $code = 'my ($' . join (', $', @_) . ') = @_;' . "\n\n";  # I love generating code.
      }
      $code .= $body->content;
      $code =~ s/\$\^(\w+)/fixvars($1)/ge;
      $code =~ s/\^!(\w+)/fixevent($1)/ge;
      $code =~ s/\^(\w+)/fixcall($1)/ge;
      
      $self->{code} = $code;   # Kept for diagnostics.
      
      $self->{sub} = eval "sub {" . $code . "\n}";
      $self->{callable} = 1;
      $self->{owncode} = 1;
   } else {
      # No body means we're just going to build each of our children, and try to execute each of them in sequence when called.
      # No body and no callable children means we're not callable either.
      my $child_code = undef;
      foreach ($self->elements) { $child_code = $_->build if $_->can('build') }
   
      $self->{callable} = defined $child_code ? 1 : 0;
      $self->{sub} = sub { $self->go(); };
      $self->{owncode} = 0;
   }

   $self->{event} = $self->is ('on') ? 1 : 0;
   if ($self->{callable} && ($is_event || ($self->is ('on') and $self->get('name')))) {
      $cx->register_event ($self->get('name'), $self->{sub});
   }

   return $self;
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

1; # End of Class::Declarative::Semantics::Code
