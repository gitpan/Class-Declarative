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

Called by Class::Declarative::Semantics during import, to find out what tags this plugin claims to implement and the
parsers used to build its content.

=cut
sub defines { ('on', 'do', 'perl'); }
our %build_handlers = ( perl => { node => sub { Class::Declarative::Semantics::Code->new (@_) }, body => 'none' } );

=head2 build_payload, fixvars, fixcall, fixevent, make_code, make_select

The C<build_payload> function is then called when this object's payload is built (i.e. in the stage when we're adding semantics to our
parsed syntax).  The payload of a code object is its callable code result.

The parent's payload will always have been created by the time this function is called.

The C<make_select> function is by far the most complex of our code generators, as it has to find an iterator source and build a while loop.

=cut

sub fixvars  { '$cx->{v}->{' . $_[0] . '}' }
sub fixcall  { '$cx->' . $_[0] }
sub fixevent { '$cx->do(\'' . $_[0] . '\')' }

our $next_counter = 1;
sub make_select {
   my ($self, $foreach) = @_;
   my $cx = $self->event_context;
   
   my ($target, $source);
   my @vars = ();
   if ($foreach =~ /^\s*(.*?)\s+in\s+(.*?)\s*$/) {
      ($target, $source) = ($1, $2);
      @vars = split /\s*[, ]\s*/, $target;
   } elsif ($foreach !~ /\s/) {
      $target = '';
      $source = $foreach;
   } else {
      $self->error("'^foreach/select $foreach' can't be parsed");
      return 'if (0) {';
   }
   
   my ($datasource, $type) = $self->find_data($source);   # TODO: error handling if source not found.
   
   if (not $target and $datasource->is ('data')) {
      # Take target from definition of data source.
      push @vars, $datasource->parmlist;
   }
   
   my $unique = $next_counter++;
   
   my $ret;
   if ($type eq 'text') {
      my $my = '';
      if (@vars) {
         $target = 'my $' . shift @vars;
         $my = 'my ($' . join (', $', @vars) . '); ' if @vars;
      } else {
         $target = '$_';
      }
      $ret .= 'my @text_node_' . $unique . ' = $self->find_data(\'' . $source . '\'); ';
      $ret .= 'my $it_' . $unique . ' = $text_node_' . $unique . '[0]->iterate; ';
      $ret .= 'while (' . $target . ' = $it_' . $unique . '->next) { ';
      $ret .= $my;
   } elsif ($type eq 'data') {
      $ret .= 'my @data_node_' . $unique . ' = $self->find_data(\'' . $source . '\'); ';
      $ret .= 'my $it_' . $unique . ' = $data_node_' . $unique . '[0]->iterate; ';
      $ret .= 'while (my $line_' . $unique . ' = $it_' . $unique . '->next) { ';
      $ret .= 'my ($' . join (', $', @vars) . ') = @$line_' . $unique . ';';
   } else {
      $self->error ("node foreach not implemented yet");
      $ret = 'if (0) {';
   }
   
   $ret;
}

sub make_code {
   my $self = shift;
   my $code = shift;
   
   my $cx = $self->event_context;
   
   my $preamble = '';
   if (@_) {
      $preamble = 'my ($' . join (', $', @_) . ') = @_;' . "\n\n";  # I love generating code.
   }
   $code = $preamble . $code;
   $code =~ s/\$\^(\w+)/fixvars($1)/ge;
   $code =~ s/\^!(\w+)/fixevent($1)/ge;
   $code =~ s/\^foreach (.*) {/$self->make_select($1)/ge;
   $code =~ s/\^select (.*) {/$self->make_select($1)/ge;
   $code =~ s/\^(\w+)/fixcall($1)/ge;
      
   my $sub = eval "sub {" . $code . "\n}";
   $self->error ($@) if $@;

   if (wantarray) {
      return ($sub, $code);
   } else {
      return $sub;
   }
}

sub build_payload {
   my $self = shift;
   my $is_event = shift;   # @_ is now the list of 'my' variables the code expects, by name.

   my $cx = $self->event_context;

   return $self if $self->{built};
   $self->{built} = 1;
   
   if (!@_) {   # Didn't get any 'my' variables explicitly defined.
      @_ = $self->optionlist;
   }     
   
   # Here's the tricky part.  We have to build some code and evaluate it when asked.  This could get arbitrarily complex.
   # If we have a code body, that's our code. If we have both a body and a "code" (i.e. a one-line bracketed body), then
   # the "code" takes precedence (e.g. Wx toolbars).
   if ($self->code) {  # TODO: this wasn't covered by the unit tests!
      my $code = $self->code;
      $code =~ s/^{//;
      $code =~ s/}$//;
      #print "code is $code\n";
      ($self->{sub}, $self->{gencode}) = make_code ($self, $code, @_);
      #print "gencode is " . $self->{gencode} . "\n";
      $self->{callable} = 1;
      $self->{owncode} = 1;
   } elsif ($self->body) {
      ($self->{sub}, $self->{gencode}) = make_code ($self, $self->body, @_);

      $self->{callable} = 1;
      $self->{owncode} = 1;
   } else {
      # No body means we're just going to build each of our children, and try to execute each of them in sequence when called.
      # No body and no callable children means we're not callable either.
      #print "making child-based caller:" . $self->myline . "\n";
      my $child_code = 0;
      foreach ($self->nodes) {
         $_->build;
         $child_code = $child_code || $_->{callable};
      }
   
      $self->{callable} = $child_code ? 1 : 0;
      $self->{sub} = sub { $self->go(); };
      $self->{owncode} = 0;
   }

   $self->{event} = $self->is ('on') ? 1 : 0;
   if ($self->{callable} && ($is_event || ($self->is ('on') and $self->name))) {
      $cx->register_event ($self->name, $self->{sub});
   }

   $self->{payload} = $self->{sub} unless $self->{payload};  # TODO: this seems fishy.
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
