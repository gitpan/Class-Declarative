package Class::Declarative::Semantics;

use warnings;
use strict;

#use base qw(XML::xmlapi);  # Our structure is based on XML::xmlapi, with some useful embellishments.

=head1 NAME

Class::Declarative::Semantics - provides the framework for a set of semantic classes in a declarative framework.

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';


=head1 SYNOPSIS

C<Class::Declarative> can't really do anything on its own; it depends on a set of semantic classes, one for each type of node in the declarative tree.
Setting up a set of semantic classes needs a little glue code, because the top-level class has to search its own set of modules to tell C<Class::Declarative>
what kind of tags it can handle.  C<Class::Declarative::Semantics> does that work for us.  It also provides a very minimal core set of semantics
so we can test the declarative mechanism itself.

=head2 new(), tag()

A semantic class is just a collection of utilities for its plugins.  The core Semantics class doesn't really have anything at all - but as other
semantic classes will subclass this, your mileage will vary.  The one thing we know is that we'll want to keep track of the root.

The tag used to identify a semantic class will differ for each semantic class.  It's used to register the class in the root object.

=cut

sub new {
   my ($class, $root) = @_;

   bless { root => $root }, $class;
}
sub tag { 'core' }

=head2 import

The C<import> function is called when the package is imported.  It checks for submodules (i.e. plugins) and calls their "defines" methods
to ask them what tag they claim to implement.  Then it gives that back to C<Class::Declarative>.

=cut

sub import
{
   my($type, $caller) = @_;
   
   my $directory = File::Spec->rel2abs(__FILE__);
   $directory =~ s/\.pm$//;
   opendir D, $directory;
   foreach my $d (grep /\.pm$/, readdir D) {
      $d =~ s/\.pm$//;
	  my $mod = $type . "::" . $d;
      $mod =~ /(.*)/;
      $mod = $1;
      my @list = ();
	  eval " use $mod; \@list = $mod->defines; ";
	  warn $@ if $@;
	  unless ($@) {
   	     foreach (@list) {
		    eval ' $caller->build_handler ($_, sub { ' . $mod . '->new(@_); }); ';  # Did you get that?
			warn $@ if $@;
		 }
      }
   }
}

=head2 start()

The C<start> function is called by the framework to start the application if this semantic class is the controlling class.  This won't happen
too often with the core semantics (except in the unit tests) but the default behavior here is to execute each callable child of the top-level
application in turn.

=cut

sub start {
   my ($self) = @_;
   
   foreach ($self->{root}->elements) {
      next unless $_->{callable};
      next if $_->{event};
      $_->go;
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

1; # End of Class::Declarative::Semantics
