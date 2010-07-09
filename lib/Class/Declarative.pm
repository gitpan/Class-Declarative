package Class::Declarative;

use warnings;
use strict;
use base qw(Class::Declarative::EventContext Class::Declarative::Node);
use Filter::Util::Call;
#use Parse::Indented;
#use Parse::RecDescent::Simple;
use Class::Declarative::Parser;
use Class::Declarative::Util;
use File::Spec;
use Data::Dumper;

=head1 NAME

Class::Declarative - Provides a declarative framework for Perl

=head1 VERSION

Version 0.04

=cut

our $VERSION = '0.04';

$SIG{__WARN__} = sub {
   return if $_[0] =~ /Deep recursion.*Parser/;  # TODO: Jezus, Maria es minden szentek.
   #require Carp; Carp::cluck
   warn $_[0];
};


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

A declarative object can report its own source code, and that source code can compile into an equivalent declarative object.  This means that dynamically
constructed objects or applications can be written out as executable code, and code has introspective capability while in the loaded state.  C<Class::Declarative>
also has a macro system that allows the construction of code during the build phase; a macro always dumps as its source, not the result of the expansion, so
you can capture dynamic behavior that runs dynamically every time.

C<Class::Declarative> runs as a filter by default.  That means that you can do this, giving it one or more semantic classes:

   use Class::Declarative qw(Wx::Declarative);   # Wx::Declarative is a set of semantic classes for wxPerl.
   
   frame (xsize=450, ysize=400, x=50, y=50) "Caret Wx::Declarative sample"
      menubar:
         menu "&File":
            item blinktime "&Blink time...\tCtrl-B"
            separator
            item about     "&About...\tCtrl-A"
            separator
            item quit      "E&xit\tAlt-X"
         
      status (segments=2) "Welcome to Wx::Declarative!"
   
      on quit {
         ^Close(1);
      }
   
      on about:
         message:
            title "Caret Wx::Declarative Sample"
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
doesn't show much Perl code, but the basic rule of thumb is that anything in curly brackets {} is Perl.  C<Class::Declarative> gives you a little syntactic
sugar to make things easy ("^word" expands to "$self->word", "$^word" expands to "$self->{word}", and "my $self = shift;" is appended to all functions).
I don't know about you, but without that kind of help, I'd never get the structural references right, so I've done it once, right.

In addition to being declarative, a C<Class::Declarative> program is event-based.  That means that things happen when events fire.  There are many other
Perl-y event frameworks, such as POE and Wx itself.  C<Class::Declarative> organizes its object framework to work around Wx because that's the
framework I know.  I don't see why it couldn't build a POE application just as well, and that would be an excellent exercise after I've done
Wx.  Tell me if you're interested in this.

At any rate, all code snippets can function as event handlers.  Events take place in the context of some node in the tree - and that node may not be
the node where the code was defined.  For instance, under Wx, you might define a code handler in the button that triggers it, but when that code actually
runs, "$self" won't point to the button, it'll point to the frame or dialog the button is placed on.

=head1 TUTORIAL

For more information about how to use C<Class::Declarative>, you'll probably want to see L<Class::Declarative::Tutorial> instead of this file;
the rest of this presentation is devoted to the internal workings of C<Class::Declarative>.  (Old literate programming habits, I guess.)

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

=head2 class_build_handler ($string, $hash), app_build_handler ($string, $hash), build_handler ($string)

Given a tag name, C<class_build_handler> returns a hashref of information about how the tag expects to be treated:

* The class its objects should be blessed into, as a coderef to generate the object ('Class::Declarative::Node' is the default)
* Its line parser, by name ('default-line' is the default)
* Its body parser, by name ('default-body' is the default)
* A second-level hashref of hashrefs providing overriding semantics for descendants of this tag.

If you also provide a hashref, it is assigned to the tag name.

The C<app_build_handler> does the same thing, but specific to the given application - this allows dynamic tag definition.

Finally, C<build_handler> is a read-only lookup for a tag in the context of its ancestry that climbs the tree to find the contextual
semantics for the tag.

=cut

sub class_build_handler {
   my ($class, $tag, $handler) = @_;
   if ($handler) {
      # # print STDERR "defining $tag with " . Dumper ($handler);
      $build_handlers{$tag} = $handler;
   }
   $build_handlers{$tag} || { node => sub { Class::Declarative::Node->new (@_) }, not_found => 1 };
}
sub app_build_handler {
   my ($self, $tag, $handler) = @_;
   if ($handler) {
      $self->{build_handlers}->{$tag} = $handler;
   }
   $self->{build_handlers}->{$tag} || class_build_handler ('', $tag);
}
sub build_handler {
   my ($self, $ancestry) = @_;
   my @a = @$ancestry;
   my $own_tag = pop @a;
   while (@a) {
      my $parent = $self->build_handler(\@a);
      if (not ($parent->{not_found})) {
         my $possible = $parent->{tags}->{$own_tag};
         return $possible if $possible;
      }
      pop @a;
   }
   $self->app_build_handler($own_tag)
}

=head2 makenode($ancestry, $code)

Finds the right build handler for the tag in question, then builds the right class of node with the code given.

=cut

sub makenode {
   my ($self, $ancestry, $body) = @_;
   my $bh = $self->build_handler($ancestry);
   $bh->{node}->($body);
}

=head2 known_tags()

Returns the keys of the build handler hash.  This is probably a fossil.

=cut

sub known_tags { keys %build_handlers }


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


=head1 PARSERS

The parsing process in C<Class::Declarative> is recursive.  The basic form is a tagged line followed by indented text, followed by another tagged line
with indented text, and so on.  Alternatively, the indented part can be surrounded by brackets.

   tag [rest of line]
      indented text
      indented text
      indented text
   tag [rest of line] {
      bracketed text
      bracketed text
   }
   
By default, each tag parses its indented text in the same way, and it's turtles all the way down.  Bracketed text, however, is normally I<not> parsed as 
declarative (or "nodal") structure, but is left untouched for special handling, typically being parsed by Perl and wrapped as a closure.

However, all this is merely the default.  Any tag may also specify a different parser for its own indented text, or may carry out some transformation on the
text before invoking the parser.  It's up to the tag.  The C<data> tag, for instance, treats each indented line as a row in a table.

Once the body is handled, the "rest of line" is also parsed into data useful for the node.  Again, there is a default parser, which takes a line of the
following form:

   tag name (parameter, parameter=value) [option, option=value] "label or other string text" parser < { bracketed text }
   
Any element of that line may be omitted, except for the tag.

=head2 init_parsers(), including locally defined is_blank, is_blank_or_comment, and line_indentation

Sets up the registry and builds our default line and body parsers.

=cut

sub init_parsers {
   my ($self) = @_;
   $self->{parsers} = {};
   
   $self->{parsers}->{"default-line"} = $self->init_default_line_parser();
   $self->{parsers}->{"default-body"} = $self->init_default_body_parser();
   $self->{parsers}->{"locator"} = $self->init_locator_parser();
}


=head2 init_default_line_parser(), init_default_body_parser(), init_locator_parser()

These are called by C<init_parsers> to initialize our various sublanguage parsers.  You don't need to call them.

=cut

sub init_default_line_parser {
   my ($self) = @_;
   
   # Default line parser.
   my $p = Class::Declarative::Parser->new();
   
   $p->add_tokenizer ('CODEBLOCK'); # TODO: parameterizable, perhaps.
   $p->add_tokenizer ('STRING', "'(?:\\.|[^'])*'|\"(?:\\.|[^\"])*\"",
                      sub {
                         my $s = shift;
                         $s =~ s/.//;
                         $s =~ s/.$//;
                         $s =~ s/\\(['"])/$1/g;
                         $s =~ s/\\\\/\\/g;
                         $s =~ s/\\n/\n/g;
                         $s =~ s/\\t/\t/g;
                         ['STRING', $s]
                      }); # TODO: this should be globally available.
   $p->add_tokenizer ('BRACKET', '{.*');
   $p->add_tokenizer ('COMMENT', '#.*');
   $p->add_tokenizer ('WHITESPACE*', '\s+');
   $p->add_tokenizer ('EQUALS',  '=');
   $p->add_tokenizer ('COMMA',   ',');
   $p->add_tokenizer ('LPAREN',  '\(');
   $p->add_tokenizer ('RPAREN',  '\)');
   $p->add_tokenizer ('LBRACK',  '\[');
   $p->add_tokenizer ('RBRACK',  '\]');
   $p->add_tokenizer ('LT',      '<');
   
   $p->add_rule ('line',       'p_and(optional(<name>), optional(<parmlist>), optional(<optionlist>), optional (<label>), optional(<parser>), optional(<code>), optional(<bracket>), optional(<comment>), \&end_of_input)');
   $p->add_rule ('name',       'one_or_more(\&word)');
   $p->add_rule ('parmlist',   'p_and(token_silent(["LPAREN"]), list_of(<parm>, "COMMA*"), token_silent(["RPAREN"]))');
   $p->add_rule ('parm',       'p_or(<parmval>, one_or_more(\&word))');
   $p->add_rule ('parmval',    'p_and(\&word, token_silent(["EQUALS"]), <value>)');
   $p->add_rule ('value',      'p_or(\&word, token(["STRING"]))');
   $p->add_rule ('optionlist', 'p_and(token_silent(["LBRACK"]), list_of(<parm>, "COMMA*"), token_silent(["RBRACK"]))');
   $p->add_rule ('label',      'token(["STRING"])');
   $p->add_rule ('parser',     'p_and(\&word, token_silent(["LT"]))');
   $p->add_rule ('code',       'token(["CODEBLOCK"])');
   $p->add_rule ('bracket',    'token(["BRACKET"])');
   $p->add_rule ('comment',    'token(["COMMENT"])');
   
   $p->action ('input', sub {
      my ($parser, $node, $input) = @_;
      if (not ref $node) {
         $node = 'tag' unless defined $node;
         $node = Class::Declarative::Node->new($node);
      }
      $parser->{user}->{node} = $node;
      $input = $node->line() unless $input;
   });
   $p->action ('output', sub {
      my ($parse_result, $parser) = @_;
      my $node = $parser->{user}->{node};
      if (defined $parse_result and car($parse_result) eq 'line') {
         foreach my $piece (@{$parse_result->[1]}) {
            if      (car($piece) eq 'name') {
               my @names = map { cdr $_ } @{cdr($piece)};
               $node->{name} = $names[0];
               $node->{namelist} = \@names;
            } elsif (car($piece) eq 'parmlist') {
               my @parmlist = ();
               foreach my $parm (@{cdr($piece)}) {
                  my $value = cdr($parm);
                  if (car($value) eq 'parmval') {
                     my $parameter = cdr(car(cdr($value)));
                     my $val = cdr(cdr(cdr(cdr($value))));
                     push @parmlist, $parameter;
                     $node->{parameters}->{$parameter} = $val;
                  } else {
                     my @words = map { cdr $_ } @$value;
                     my $parameter = join ' ', @words;
                     push @parmlist, $parameter;
                     $node->{parameters}->{$parameter} = 'yes';
                  }
               }
               $node->{parmlist} = \@parmlist;
            } elsif (car($piece) eq 'optionlist') {
               my @parmlist = ();
               foreach my $parm (@{cdr($piece)}) {
                  my $value = cdr($parm);
                  if (car($value) eq 'parmval') {
                     my $parameter = cdr(car(cdr($value)));
                     my $val = cdr(cdr(cdr(cdr($value))));
                     push @parmlist, $parameter;
                     $node->{options}->{$parameter} = $val;
                  } else {
                     my @words = map { cdr $_ } @$value;
                     my $parameter = join ' ', @words;
                     push @parmlist, $parameter;
                     $node->{options}->{$parameter} = 'yes';
                  }
               }
               $node->{optionlist} = \@parmlist;
            } elsif (car($piece) eq 'parser') {
               $node->{parser} = cdr car cdr $piece;
            } else {
               $node->{car($piece)} = cdr(cdr($piece));  # Elegance!  We likes it, precioussss.
            }
         }
      }
      return $node;
   });
   
   $p->build();
   return $p;
}

sub init_default_body_parser {
   my ($self) = @_;
   
   # Default body parser.
   my $p = Class::Declarative::Parser->new();
   
   $p->add_tokenizer ('BLANKLINE', '\n\n+');
   $p->add_tokenizer ('NEWLINE*', '\n');
   $p->add_rule ('body', 'series(p_or(\&word, token("BLANKLINE")))');
   $p->action ('input', sub {
      my ($parser, $parent, $input) = @_;
      $input
   });
   $p->action ('output', sub {
      my ($parse_result, $parser, $parent, $input) = @_;
      my @results = ();
      my @nodes_made = ();
      my $root = $parent->root();
      return () unless popcar($parse_result) eq 'body';
      my $indent = 0;
      my $lineindent = 0;
      my $thisindent = 0;
      my $curtext = '';
      my $tag = '';
      my $blanks = '';
      my $firstcode = '';
      my $rest;
      my $spaces = '';
      my $bracket = '';
      
      my $starttag = sub {
         my ($line) = @_;
         if ($line =~ /^(\s+)/) {
            $lineindent = length ($1);
            $line =~ s/^\s*//; # Discard any indentation before the tag line
         } else {
            $lineindent = 0;
         }
         if ($curtext) {
            push @results, $curtext;
         }
         $curtext = $line . "\n";
         ($tag, $rest) = split /\s+/, $line, 2;
         $indent = 0;
      };
      
      my $concludetag = sub {
         # print STDERR "---- concludetag: $tag\n";
         my $newnode = $self->makenode([@{$parent->ancestry}, $tag], $curtext);
         $newnode->{parent} = $parent;
         push @results, $newnode;
         push @nodes_made, $newnode;
         $tag = '';
         $curtext = '';
         $indent = 0;
      };
      sub is_blank { $_[0] =~ /^(\s|\n)*$/ };
      sub is_blank_or_comment {
         $_ = shift;
         /^\s*#/ || is_blank ($_)
      };
      sub line_indentation {
         if ($_[0] =~ /^(\s+)/) {
            length($1)
         } else {
            0
         }
      }
      
      # print STDERR "\n\n----- Starting " . $parent->tag . " with:\n$input-----------------------\n";
      foreach (@$parse_result) {
         my ($type, $line) = splitcar ($_);
         my $testline = $line;
         $testline =~ s/\n/\\n/g;
         # print STDERR "$testline : ";
         $line =~ s/\n*// if $type;  # If we have a BLANKLINE token, there are one too many \n's in there.
         if (not $tag) {   # We're in a blank-and-comment stretch
            if (is_blank_or_comment($line)) {
               # print STDERR "blank-or-comment\n";
               $curtext .= $line . "\n";
            } else {
               # print STDERR "start tag\n";
               $starttag->($line);
            }
         } else {   # We're in a tag
            if (not $indent) {    # We just started it, though.
               $indent = line_indentation($line);
               if ($indent <= $lineindent) {   # And the first line after the starting line is already back-indented!
                  if (is_blank($line)) {  # This is a blank line, though, so it may not count as indented.
                     # print STDERR "blank line at start of tag\n";
                     $blanks .= $line;    # We'll stash it and try again.
                     $indent = 0;
                  } else {  # It's not a blank; it's either a new tag, or a comment.
                     $concludetag->();
                     if (is_blank_or_comment($line)) {
                        # print STDERR "blank-or-comment\n";
                        $curtext = $blanks . $line . "\n";
                        $blanks = '';
                     } else {
                        if ($blanks) {
                           # print STDERR "(had some leftover blanks) ";
                           push @results, $blanks;
                           $blanks = '';
                        }
                        # print STDERR ("starting new tag\n");
                        $starttag->($line);
                     }
                  }
               } elsif (is_blank ($line)) {
                  # print STDERR "blank line at start of tag with longer indent\n";
                  $blanks .= $line; # Stash it and keep going.
               } else {   # This is the first line of the body, because it's indented further than the opening line.
                  $spaces = ' ' x $indent;
                  $line =~ s/^$spaces//;
                  if ($blanks) {
                     # print STDERR "(had blanks) ";
                     $curtext .= $blanks;
                     $blanks = '';
                  }
                  # print STDERR "first line of body\n";
                  $curtext .= $line . "\n";
               }
            } else {
               if (line_indentation ($line) < $indent) { # A new back-indentation!
                  if (is_blank($line)) { # If this is blank, we don't add it to the body until there's more to add.
                     # print STDERR ("stash blank line\n");
                     $blanks .= $line . "\n";
                  } elsif ($line =~ /^\s*}/) { # Closing bracket; we don't check for matching brackets; the closing bracket is really just a sort of comment.
                     # print STDERR ("closing bracket\n");
                     $concludetag->();
                  } elsif (is_blank_or_comment($line)) { # Comment; this by definition belongs to the parent.
                     # print STDERR ("back-indented comment, denoting end of last tag\n");
                     $concludetag->();
                     $curtext = $blanks . $line . "\n";
                     $blanks = '';
                  } else {  # Next tag line.
                     $concludetag->();
                     if ($blanks) {
                        # print STDERR "(had some blanks) ";
                        push @results, $blanks;
                        $blanks = '';
                     }
                     # print STDERR "starting tag!\n";
                     $starttag->($line);
                  }
               } elsif (is_blank ($line)) { # This blank line may fall between nodes, or be part of the current one.
                  # print STDERR "stash blank line within body\n";
                  $blanks .= $line . "\n";
               } else { # Normal body line; toss it into the mix.
                  $line =~ s/^$spaces//;
                  if ($blanks) {   # If we've stashed some blanks, add them back.
                     # print STDERR "(had some blanks) ";
                     $curtext .= $blanks;
                     $blanks = '';
                  }
                  # print STDERR "body line\n";
                  $curtext .= $line . "\n";
               }
            }
         }
      }
      if ($curtext) {
         if ($tag) {
            # print STDERR "FINAL: had a tag\n";
            $concludetag->();
         } else {
            # print STDERR "FINAL: extra text\n";
            push @results, $curtext;
         }
      }
      if ($blanks) {
         # print STDERR "FINAL: extra blanks\n";
         push @results, $blanks;
      }
      $parent->{elements} = [$parent->elements, @results];
      @nodes_made
   });
   
   $p->build();   # Forgetting this cost me several hours of debugging...
   return $p;
}

sub init_locator_parser {
   my ($self) = @_;
   
   my $p = Class::Declarative::Parser->new();
   
   $p->add_tokenizer ('STRING', "'(?:\\.|[^'])*'|\"(?:\\.|[^\"])*\"",
                      sub {
                         my $s = shift;
                         $s =~ s/.//;
                         $s =~ s/.$//;
                         $s =~ s/\\(['"])/$1/g;
                         $s =~ s/\\\\/\\/g;
                         $s =~ s/\\n/\\n/g;
                         $s =~ s/\\t/\\t/g;
                         ['STRING', $s]
                      });
   $p->add_tokenizer ('WHITESPACE*', '\s+');
   $p->add_tokenizer ('MATCHES',   '=~');
   $p->add_tokenizer ('EQUALS',    '=');
   $p->add_tokenizer ('SEPARATOR', '[.:/]');
   $p->add_tokenizer ('LPAREN',    '\(');
   $p->add_tokenizer ('RPAREN',    '\)');
   $p->add_tokenizer ('LBRACK',    '\[');
   $p->add_tokenizer ('RBRACK',    '\]');
   
   $p->add_rule ('locator',    'list_of(<tag>, "SEPARATOR*")');
   $p->add_rule ('tag',        'p_and(\&word, p_or (<attribute>, <match>, <offset>, <name>, \&nothing))');
   $p->add_rule ('name',       'p_and(token_silent(["LBRACK"]), one_or_more(\&word), token_silent(["RBRACK"]))');
   $p->add_rule ('attribute',  'p_and(token_silent(["LBRACK"]), \&word, token_silent(["EQUALS"]), p_or(\&word, token (["STRING"])), token_silent(["RBRACK"]))');
   $p->add_rule ('match',      'p_and(token_silent(["LBRACK"]), \&word, token_silent(["MATCHES"]), p_or(\&word, token (["STRING"])), token_silent(["RBRACK"]))');
   $p->add_rule ('offset',     'p_and(token_silent(["LPAREN"]), \&word, token_silent(["RPAREN"]))');
   
   $p->action ('output', sub {
      my ($parse_result, $parser) = @_;
      my $list = cdr $parse_result;
      my @pieces = ();
      foreach (@$list) {
         my $t = cdr $_;
         my $tag = cdr car $t;
         my $rest = cdr $t;
         if (defined $rest) {
            my ($type, $spec) = @$rest;
            if ($type eq 'name') {
               my @names = map { cdr $_ } @$spec;
               push @pieces, [$tag, @names];
            } elsif ($type eq 'attribute') {
               push @pieces, [$tag, ['a', cdr car $spec, cdr cdr $spec]];
            } elsif ($type eq 'match') {
               push @pieces, [$tag, ['m', cdr car $spec, cdr cdr $spec]];
            } elsif ($type eq 'offset') {
               push @pieces, [$tag, ['o', cdr car $spec]];
            }
         } else {
            push @pieces, $tag;
         }
      }
      return \@pieces;
   });
   
   $p->build();
   return $p;
}

=head2 parser($name)

Retrieves a parser from the registry.

=cut

sub parser { $_[0]->{parsers}->{$_[1]} }

=head2 parse_line ($node)

Given a node, finds the line parser for it, and runs it on the node's line.

=cut

sub parse_line {
   my ($self, $node, $line) = @_;
   
   my $bh = $self->build_handler($node->ancestry());
   return if defined $bh->{line} and $bh->{line} eq 'none';
   my $p = $self->parser($bh->{line} || 'default-line');
   $p->execute($node, $line);    # TODO: error handler for incorrect parser specification.
}

=head2 parse($node, $body)

Given a node and body text for it, finds the body parser appropriate to the node's tag and runs it on the node and the body text specified.

=cut

sub parse {
   my ($self, $node, $body) = @_;
   
   my $bh = $self->build_handler($node->ancestry());
   return if defined $bh->{body} and $bh->{body} eq 'none';
   my $p = $self->parser($bh->{body} || 'default-body');
   $p->execute($node, $body);
}

=head2 parse_using($string, $parser)

Given a string and the name of a parser, calls the parser on the string and returns the result.

=cut

sub parse_using {
   my ($self, $string, $parser) = @_;
   my $p = $self->parser($parser);
   return undef unless $p;
   return $p->execute($string);
}


=head1 BUILDING AND MANAGING THE APPLICATION

You'd think this would be up at the top, but we had to do a lot of work just to be ready to instantiate a C<Class::Declarative> object.

=head2 new

The C<new> function is of course called to create a new C<Class::Declarative> object.  If you pass it some code, it will load that code
immediately.

=cut

sub new {
   my $class = shift;
   my $self = $class->SUPER::new('*root');
   $self->{id_list} = {};
   $self->{next_id} = 1;
   $self->{root} = $self;
   
   $self->init_parsers;
   
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
   
   if (defined $_[0]) {
      $self->load($_[0]);
   }
   return $self;
}

=head2 semantic_handler ($tag)

Returns the instance of a semantic module, such as 'core' or 'wx'.

=cut

sub semantic_handler { $_[0]->{semantics}->{$_[1]} }


=head2 start

This is called from outside to kick off the process defined in this application.  The way we handle this is just to ask the first semantic class to start
itself.  The idea there being that it's probably going to be Wx or something that provides the interface.  (It could also be a Web server or something.)

The core semantics just execute all the top-level items that are flagged callable.

=cut

sub start {
   my ($self, $tag) = @_;
   
   $tag = $self->{controller} unless $tag;
   $self->{semantics}->{$tag}->start;
}


=head2 id($idstring)

Wx works with numeric IDs for events, and I presume the other event-based systems do, too.  I don't like numbers; they're hard to read and tell apart.
So C<Class::Declarative> registers event names for you, assigning application-wide unique numeric IDs you can use in your payload objects.

=cut

sub id {
   my ($self, $str) = @_;
   
   if (not defined $str or not $str) {
      my $retval = $self->{next_id} ++;
      return $retval;
   }
   if (not defined $self->{id_list}->{$str}) {
      $self->{id_list}->{$str} = $self->{next_id} ++;
   }
   return $self->{id_list}->{$str};
}


=head2 root()

Returns $self; for nodes, returns the parent.  The upshot is that by calling C<root> we can get the root of the tree, fast.

=cut

sub root { $_[0] }

=head2 describe([$use])

Returns a reconstructed set of source code used to compile this present C<Class::Declarative> object.  If it was assembled
in parts, you still get the whole thing back.  Macro results are not included in this dump (they're presumed to be the result
of macros in the tree itself, so they should be regenerated the next time anyway).

If you specify a true value for $use, the dump will include a "use" statement at the start in order to make the result an
executable Perl script.
The dump is always in filter format (if you built it with -nofilter) and contains C<Class::Declarative>'s best guess of the
semantic modules used.  If you're using a "use lib" to affect your %INC, the result won't work right unless you modify it,
but if it's all standard modules, the dump result, after loading, should work the same as the original entry.

=cut

sub describe {
   my ($self, $use) = @_;
   
   my $description = '';
   $description = "use Class::Declarative qw(" . join (", ", @semantic_classes) . ");\n\n" if $use;
   
   foreach ($self->elements) {
      if (not ref $_) {
         $description .= $_;
      } elsif ($_->{macroresult}) {
         next;
      } else {
         $description .= $_->describe;
      }
   }
   
   return $description;
}

=head2 find_data

The C<find_data> function finds a top-level data node.

=cut

sub find_data {
   my ($self, $data) = @_;
   foreach ($self->nodes) { return ($_, $_->tag) if $_->name eq $data; }
   foreach ($self->nodes) { return ($_, $_->tag) if $_->is($data); }
   return (undef, undef);
}





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
