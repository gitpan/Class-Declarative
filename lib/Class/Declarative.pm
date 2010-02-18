package Class::Declarative;

use warnings;
use strict;
use base qw(Class::Declarative::EventContext XML::xmlapi);
use Filter::Util::Call;
use Parse::Indented;
use Parse::RecDescent::Simple;
use File::Spec;

=head1 NAME

Class::Declarative - Provides a declarative framework for Perl

=head1 VERSION

Version 0.03

=cut

our $VERSION = '0.03';

our $NODE_TYPE = "Class::Declarative::Node";  # Could be smarter here.


=head1 SYNOPSIS

Perl's dominant paradigm, like most languages, is imperative.  That is, when told to run a program, the computer does first one thing, then the next,
until it terminates.  Where this paradigm breaks down is when we are better off conceiving of our task not as programming a single agent (the computer)
but a collection of objects, say, a GUI.  In a GUI program, we talk about events that fire based on user actions.  The events themselves lend themselves
well to modeling by imperative code, but the I<overall organization> of the program as a whole is much easier when we look at the system as a set of 
data structures.

Traditionally, when writing a GUI based on, say, L<Wx>, these data structures have been built in an imperative initialization function.

That approach sucks.

Instead, I find it a lot easier to write a full description of the GUI, then hang code on it.  So at some point, I thought, well, why not just write
a class to interpret that pseudocode description directly?

That is this module.

C<Class::Declarative> provides the framework for building a complete Perl program based on a simple, indented, rather informal language.  The language has
no keywords at all; you have to provide a set of objects to define the semantics of I<everything>.  (Caveat: C<Class::Declarative> knows how to build code,
so there are some things it will interpret on its own.  We'll use those to write the test suites.)

C<Class::Declarative> gives us some other goodies. or will eventually.  Since it is easy to parse, and since it knows how to write its own code back out, at
least some programming constructs will act like LISP, in that we can write macros to handle them.  That will come later.  We will also be able to change the
behavior of a running program by modifying its parsed structure.  That will also come later.  But keep them in mind.  They'll be very powerful.

C<Class::Declarative> runs as a filter by default.  That means that you can do this, giving it one or more semantic classes:

   use Class::Declarative qw(Wx::DefinedUI);   # Wx::DefinedUI is a set of semantic classes for wxPerl.
   
   frame (xsize=450, ysize=400, x=50, y=50) "Caret Wx::DefinedUI sample"
      menubar:
         menu "&File":
            item blinktime "&Blink time...\tCtrl-B"
            separator
            item about     "&About...\tCtrl-A"
            separator
            item quit      "E&xit\tAlt-X"
         
      status (segments=2) "Welcome to Wx::DefinedUI!"
   
      on quit {
         ^Close(1);
      }
   
      on about:
         message:
            title "Caret Wx::DefinedUI Sample"
            body  "About Caret"
            icons "OK INFORMATION"
         
      on blinktime:
         dialog (template=getnumber):
            help   "The caret blink time is the time between two blinks"
            prompt "Time in milliseconds"
            title  "Caret sample"
            get { Wx::Caret::GetBlinkTime }
            min "0"
            max "10000"
            result "blinktime"
            on OK {
               if ($^blinktime != -1) {
                  Wx::Caret::SetBlinkTime( $^blinktime );
                  Wx::LogStatus( $self, 'Blink time set to %d milliseconds', $^blinktime );
               }
            }
            
This structure is almost obvious without any explanation at all.  That's kind of the point of declarative programming.  This particular example
doesn't show much Perl code, but the basic rule is that anything in curly brackets {} is Perl.  C<Class::Declarative> gives you a little syntactic
sugar to make things easy ("^word" expands to "$self->word", "$^word" expands to "$self->{word}", and "my $self = shift;" is appended to all functions).
I don't know about you, but without that kind of help, I'd never get the structural references right, so I've done it once, right.

In addition to being declarative, a C<Class::Declarative> program is event-based.  That means that things happen when events fire.  There are many other
Perl-y event frameworks, such as POE, Moose, and Wx itself.  C<Class::Declarative> organizes its event framework to work around Wx because that's the
framework I know.  I don't see why it couldn't build a POE or Moose application just as well, and that would be an excellent exercise after I've done
Wx.  Tell me if you're interested in this.

At any rate, all code snippets are assumed to be event handlers.  Events take place in the context of some node in the tree - and that node may not be
the node where the code was defined.  For instance, under Wx, you might define a code handler in the button that triggers it, but when that code actually
runs, "$self" won't point to the button, it'll point to the frame or dialog the button is placed on.

=head1 SETTING UP THE CLASS STRUCTURE

=head2 import

The C<import> function is called when the package is imported.  It's used for the filter support; don't call it.

If semantic classes are supplied in the C<use> command, we're going to instantiate and scan them here.  They'll be used to decorate the
parse tree appropriately.

=cut

our %build_handlers = ();
our %build_flags = ();
our @semantic_classes = ();

sub import
{
   my($type, @arguments) = @_;
   
   if (@arguments and $arguments[0] ne '-nofilter') {
      filter_add(bless { start => 1 });  # We won't do filtering if there's no semantics.  This allows us to test parsing easily.
   } else {
      shift @arguments if @arguments;
   }
   push @arguments, "Class::Declarative::Semantics" unless grep { $_ eq "Class::Declarative::Semantics" } @arguments;

   use lib "./lib"; # This allows us to test semantic modules without disturbing their production variants that are installed.
   foreach (@arguments) {   
      eval "use $_ qw(" . __PACKAGE__ . ");";
      if ($@) {
         warn $@;
      } else {
         push @semantic_classes, $_;
      }
   }
}

=head2 build_handler ($string)

Given a tag name, returns the name of the class that claims to handle that node.  If nobody else claims it, it ends up as Class::Declarative::Node
for default behavior.

=cut

sub build_handler {
   my ($class, $string, $handler) = @_;
   if ($handler) {
      if ($string =~ /\*$/) {
         $string =~ s/\*$//;
         $build_flags{$string} = 1;
      } else {
         $build_flags{$string} = 0;
      }
      $build_handlers{$string} = $handler;
   }
   $build_handlers{$string} || sub { $NODE_TYPE->new (@_); };
}

=head2 known_tags()

Returns the keys of the build handler hash.

=cut

sub known_tags { keys %build_handlers }

=head1 PARSING

We parse our input with a three-stage process.  L<Parse::Indented> is called to build the base structure line by line.  It is told to return
C<Class::Declarative::Node> objects, which inherit from L<XML::xmlapi> objects to provide structure manipulation functionality.

Each line in the structure is handed off to C<line_parser> below, which calls L<Parse::RecDescent::Simple> to build an L<XML::xmlapi> structure
from the line.  The C<line_parser> function then takes that structure, which is very similar to the grammar that built it, and builds the
C<Class::Declarative::Node> object it specifies.

Each node object has a type (determining the semantic class that will instantiate it later), an optional name, an optional set of parameters
in round parentheses (), an optional set of options in square brackets [], an optional label in single or double quotes, and an optional body in
curly brackets {}.

Why so many different ways to specify an object?  The parameters are meant to be short and sweet, and are typically used to instantiate the payload (things
like the ID number of a button).
The options are equally short and sweet, and are used by the object when adding itself to its parent (things like where a button is on the form).
The label may be longer and contain punctuation and spaces, so to simplify parsing and also to improve self-documentation, it is placed outside the
parameters where it's easy to see.  Finally, the body is the only part of the object that may span multiple lines, and is typically where Perl code
is defined.

Any object may have children in the parse tree.  What the semantic class does with them - if anything - is the business of the semantic class.

=head2 line_parser ($string)

This function is just a function; it takes a string corresponding to a line, and returns a parsed structure.
It's cool, but you probably don't want to call it.  It uses L<Parse::RecDescent::Simple> to return an L<XML::xmlapi>
structure, which it then munges into a more appropriate structure built of $baseclass objects subclassed from
L<XML::xmlapi>, by default C<Class::Declarative::Node> objects.

=cut

our $line_parser;

BEGIN {
  local $SIG{__WARN__} = sub {0};     # TODO: this is weird - under Linux this warns several times in a row. Windows, it's silent.
                                      #       It's definitely something that should be fixed, but my little head isn't up to it.
  $line_parser = Parse::RecDescent::Simple->new (q{
parse: line
line: word(s) parmlist(?) optionlist(?) label(?) body(?)
parmlist: "(" option(s /,\s*|\s+/) ")"
optionlist: "[" option(s /,\s*|\s+/) "]"
label: <perl_quotelike>
body: <perl_codeblock>
word: /[A-Za-z0-9_\-]+/
option: /[A-Za-z0-9_\- =]+/ | <perl_quotelike>
});
}

sub line_parser {
    my ($line) = @_;
    $line .= '""' unless $line =~ /"/;   # TODO: figure out why the parser gets snippy if there's a second word without a label.
    my $parse = $line_parser->parse($line);

    # TODO: error handling if not $parse;
    my @words = $parse->elements ('word');
    my $word = $words[0]->stringcontent;
    my $ret = &{build_handler('', $word)}($word);
              # You know what's cool about this code above?
              # The fact that I don't have to import the modules;
              # the build handler closure does that magically.
    my $wants_sublines = $build_flags{$word} || 0;
    if ($words[1] && $words[1]->is('word')) {
       $ret->set('name', $words[1]->content());
    }
    
    my $mark;
    if ($mark = $parse->first ('parmlist')) {
       foreach ($mark->elements) {
          my $option = $_->content;
          if ($option =~ /^(.*)=(.*)$/) {
             $ret->set ($1, $2);
          } else {
             $ret->set ($option, "yes");
          }
       }
    }
    if ($mark = $parse->first ('optionlist')) {
       my $o = XML::xmlapi->create ('options');
       my @options = $mark->elements;
       my $i = 0;
       $o->set ("options", scalar @options);
       foreach (@options) {
           $i++;
           $o->set ($i, $_->content);
       }
       $ret->append_pretty ($o);
    }
    if ($mark = $parse->first ('label')) {
       $ret->set ('label', $mark->content);
    }
    if ($mark = $parse->first ('body')) {
       my $copy = XML::xmlapi->create ("body");
       $copy->append (XML::xmlapi->createtext ($mark->content));
       $ret->append_pretty ($copy);
    }

    return ($ret, $wants_sublines);
}

our $parser = Parse::Indented->new (\&line_parser, $NODE_TYPE);

=head1 FILTERING SOURCE CODE

By default, C<Class::Declarative> runs as a filter.  That means it intercepts code coming in and can change it before Perl starts parsing.  Needless to say,
filters act very cautiously, because the only thing that can parse Perl correctly is Perl (and sometimes even Perl has doubts).  So this filter basically just
wraps the entire input source in a call to C<new>, which is then parsed and called after the filter returns.

=head2 filter

The C<filter> function is called by the source code filtering process.  You probably don't want to call it.  But if you've ever wondered
how difficult it is to write a source code filter, read it.  Hint: I<it really isn't difficult>.

=cut

sub filter
{
   my $self = shift;
   my $status;

   if (($status = filter_read()) > 0) {
      if ($$self{start}) {
         $$self{start} = 0;
         $_ = "my \$root = " . __PACKAGE__ . "->new();\n\$root->load(<<'DeclarativeEOF');\n$_";
      }
   } elsif (!$$self{start}) { # Called on EOF if we ever saw any code.
      $_ = "\nDeclarativeEOF\n\n\$root->start();\n\n";
      $$self{start} = 1;    # Otherwise we'll repeat the EOF forever.
      $status = 1;
   }

   $status;
}



=head1 BUILDING AND MANAGING THE APPLICATION

You'd think this would be up at the top.

=head2 new

The C<new> function is of course called to create a new C<Class::Declarative> object.

=cut

sub new {
   my ($class) = @_;
   my $self = $class->SUPER::create('root');
   $self->{id_list} = {};
   $self->{next_id} = 1;
   $self->{root} = $self;
   
   $self->{semantics} = {};
   $self->{semtags} = {};
   $self->{controller} = '';
   foreach (@semantic_classes) {
      my $s = $_->new($self);
      $self->{semtags}->{$_} = $s->tag;
      $self->{controller} = $s->tag unless $self->{controller};
      $self->{semantics}->{$s->tag} = $s;
   }
   
   $self->event_context_init;
   return $self;
}

=head2 semantic_handler ($tag)

Returns the instance of a semantic module, such as 'core' or 'wx'.

=cut

sub semantic_handler { $_[0]->{semantics}->{$_[1]} }

=head2 load

The C<load> method loads a UI specification into the C<Wx::DefinedUI> object by calling C<parse>.  Right now this replaces what's there; really,
you should be able to load multiple things that would then get stashed into a registry of top-level items (frames and dialogs).

=cut

sub load {
   my $self = shift;
   $parser->parse (shift, undef, $self);
}

=head2 start

This is called from outside to kick off the process defined in this application.  The way we handle this is just to ask the first semantic class to start
itself.  The idea there being that it's probably going to be Wx or something that provides the interface.  (It could also be a Web server or something.)

If this isn't the right approach, we can pass in a tag, like 'ui'.

=cut

sub start {
   my ($self, $tag) = @_;
   
   foreach ($self->elements) {
      $_->build;
   }
   
   $tag = $self->{controller} unless $tag;
   $self->{semantics}->{$tag}->start;
}


=head2 id($idstring)

Wx works with numeric IDs for events, and I presume the other event-based systems do, too.  I don't like numbers; they're hard to read and tell apart.
So C<Class::Declarative> registers event names for you, assigning unique numeric IDs you can use in your payload objects.

=cut

sub id {
   my ($self, $str) = @_;
   
   if (not defined $self->{id_list}->{$str}) {
      $self->{id_list}->{$str} = $self->{next_id} ++;
   }
   return $self->{id_list}->{$str};
}


=head2 root()

Returns $self; for nodes, returns the parent.  The upshot is that by calling C<root> we can get the root of the tree, fast.

=cut

sub root { $_[0] }


=head1 AUTHOR

Michael Roberts, C<< <michael at vivtek.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-class-declarative at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Class-Declarative>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Class::Declarative


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Class-Declarative>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Class-Declarative>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Class-Declarative>

=item * Search CPAN

L<http://search.cpan.org/dist/Class-Declarative/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2010 Michael Roberts.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1; # End of Class::Declarative
