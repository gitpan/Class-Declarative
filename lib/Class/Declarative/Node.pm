package Class::Declarative::Node;

use warnings;
use strict;

use Iterator::Simple qw(:all);
use Class::Declarative::Semantics::Code;
use Class::Declarative::Util;
use Data::Dumper;
use Carp;

=head1 NAME

Class::Declarative::Node - implements a node in a declarative structure.

=head1 VERSION

Version 0.02

=cut

our $VERSION = '0.03';


=head1 SYNOPSIS

Each node in a C<Class::Declarative> structure is represented by one of these objects.  Specific semantics modules subclass these nodes for each of their
components.

=head2 defines()

Called by C<Class::Declarative> during import, to find out what xmlapi tags this plugin claims to implement.  This is a class method, and by default
we've got nothing.

The C<wantsbody> function governs how C<iterator> works.

=cut
sub defines { (); }

=head2 new()

The constructor for a node takes either one or an arrayref containing two texts.  If one, it is the entire line-and-body of a node;
if the arrayref, the line and the body are already separated.  If they're delivered together, they're split before proceeding.

The line and body are retained, although they may be further parsed later.  If the body is parsed, its text is discarded and is reconstructed if it's
needed for self-description.  (This can be suppressed if a non-standard parser is used that has no self-description facility.)

The node's I<tag> is the first word in the line.  The tag determines everything pertaining to this entire section of the
application, including how its contents are parsed.

=cut

sub new {
   my $class = shift;
   #print STDERR "Adding $class\n";
   my $self = bless {
      state       => 'unparsed', # Fresh.
      payload     => undef,      # Not built.
      sub         => sub {},     # Null action.
      callable    => 0,          # Default is not callable.
      owncode     => 0,          # Default doesn't have own callable code.
      macroresult => 0,          # Default is explicit text.
      name        => '',
      namelist    => [],
      parameters  => {},
      parmlist    => [],
      options     => {},
      optionlist  => [],
      label       => '',
      parser      => undef,
      code        => undef,
      finalcode   => undef,
      errors      => [],
      elements    => [],
      parent      => undef,
      comment     => '',
      bracket     => 0,
   }, $class;
   
   # Now prepare the body as needed.
   my ($line, $body);
   $body = shift;
   #print STDERR "new: body is " . Dumper ($body);
   $body = '' unless defined $body;
   if (ref $body eq 'ARRAY') {
      #print STDERR "new: body is arrayref\n";
      {
         my @bodyrest;
         ($line, @bodyrest) = @$body;
         #print STDERR "new: first line is $line\n";
         $body = \@bodyrest;
      }
   } else {
      ($line, $body) = split /\n/, $body, 2;
   }
   
   $line = 'node' unless defined $line;
   my ($tag, $rest) = split /\s+/, $line, 2;
   $self->{tag} = $tag;
   $self->{line} = $rest || '';
   $self->{body} = $body;

   return $self;
}

=head2 tag(), is($tag), name(), line(), hasbody(), body(), elements(), nodes(), payload()

Accessor functions.

=cut

sub tag      { $_[0]->{tag} }
sub is       { $_[0]->{tag} eq $_[1] }
sub name     { $_[0]->{name} }
sub line     { $_[0]->{line} }
sub hasbody  { defined $_[0]->{body} ? ($_[0]->{body} ? 1 : 0) : 0 }
sub body     { $_[0]->{body} }
sub elements { @{$_[0]->{elements}} }
sub nodes    { grep { ref $_ && (defined $_[1] ? $_->is($_[1]) : 1) } @{$_[0]->{elements}} }
sub payload  { $_[0]->{payload} }

=head2 parent(), ancestry()

A list of all the tags of nodes above this one, culminating in this one's tag, returned as an arrayref.

=cut

sub parent { $_[0]->{parent} }
sub ancestry {
   my ($self) = @_;
   my $parent = $self->parent();
   (defined $parent and $parent != $self->root()) ? [@{$parent->ancestry()}, $self->tag()] : [$self->tag()];
}

=head2 parameter($p), option($o), parmlist(), optionlist(), parameter_n(), option_n(), label(), parser(), code(), gencode(), errors(), bracket(), comment()

More accessor functions.

=cut

sub parameter   { $_[0]->{parameters}->{$_[1]} || $_[2] || '' }
sub option      { $_[0]->{options}->{$_[1]} || $_[2] || '' }
sub option_n    { ($_[0]->optionlist)[$_[1]-1] }
sub parameter_n { ($_[0]->parmlist)[$_[1]-1] }
sub parmlist    { @{$_[0]->{parmlist}} }
sub optionlist  { @{$_[0]->{optionlist}} }
sub label       { $_[0]->{label} }
sub parser      { $_[0]->{parser} }
sub code        { $_[0]->{code} }
sub gencode     { $_[0]->{gencode} }
sub bracket     { $_[0]->{bracket} }
sub comment     { $_[0]->{comment} }

sub errors  { @{$_[0]->{errors}} }

=head2 plist(@parameters)

Given a list of parameters, returns a hash (not a hashref) of their values, first looking in the parameters, then looking for children
of the same name and returning their labels if necessary.  This allows us to specify a parameter for a given object either like this:

   object (parm1=value1, parm2 = value2)
   
or like this:

   object
      parm1 "value1"
      parm2 "value2"
      
It just depends on what you find more readable at the time.  For this to work during payload build, though, the children have to be built
first, which isn't the default - so you have to call $self->build_children before using this in the payload build.

This is really useful if you're wrapping a module that uses a hash to initialize its object.  Like, say, L<LWP::UserAgent>.

=cut

sub plist {
   my $self = shift;
   my %p;
   foreach my $p (@_) {
      if ($self->parameter($p)) {
         $p{$p} = $self->parameter($p);
      } elsif (my $pnode = $self->find($p)) {
         $p{$p} = $pnode->label;
      }
   }

   %p;
}

=head2 parm_css (parameter), set_css_values (hashref, parameter_string), prepare_css_value (hashref, name), get_css_value (hashref, name)

CSS is characterized by a sort of "parameter tree", where many parameters can be seen as nested in a hierarchy.  Take fonts, for example.
A font has a size, a name, a bolded flag, and so on.  To specify a font, then, we end up with things like font-name, font-size, font-bold, etc.
In CSS, we can also group those things together and get something like font="name: Times; size: 20", and that is equivalent to
font-name="Times", font-size="20".  See?

This function does the same thing with the parameters of a node.  If you give it a name "font" it will find /font-*/ as well, and munge
the values into the "font" value.  It returns a hashref containing the entire hierarchy of these things, and it will also interpret any
string-type parameters in the higher levels, e.g. font="size: 20; name: Times" will go into {size=>20, name=>'Times'}.  Honestly, I love
this way of handling parameters in CSS.

If you give a name "font-size" it will also find any font="size: 20" specification and retrieve the appropriate value.

It I<won't> decompose multiple hierarchical levels starting from a string (e.g. something like font="size: {type: 3}" will not be parsed for
font-size-type, because you'd need curly brackets or something anyway, and this ain't JSON, it's just simple CSS-like parameter addressing.

=cut

sub parm_css {
   my ($self, $parameter) = @_;
   my $return = {};
   my $top = $parameter;
   $top =~ s/[.\-\/].*$//;
   hh_set ($return, $top, $self->parameter ($top)) if $self->parameter($top);
   foreach ($self->parmlist()) {
      if ($_ =~ /^$top[.\-\/]/) {
         hh_set ($return, $_, $self->parameter ($_));
      }
   }
   return hh_get ($return, $parameter);
}


=head2 flags({flag=>numeric value, ...}), oflags({flag=>numeric value, ...})

A quick utility to produce an OR'd flag set from a list of parameter words.  Pass it a hashref containing numeric values for a set of words, and
you'll get back the OR'd sum of the flags found in the parameters.  The C<flags> function does this for the parameters (round parens) and the C<oflags>
function does the same for the options [square brackets].

=cut

sub flags {
   my ($self, $f) = @_;
      
   my $r = 0;
   
   while (my ($k, $v) = each %$f) {
      $r |= $v if $self->parameter ($k);
   }
   return $r;
}
sub oflags {
   my ($self, $f) = @_;
   
   my $r = 0;
   
   for (my ($k, $v) = each %$f) {
      $r |= $v if $self->option ($k);
   }
   return $r;
}

=head2 list_parameter ($name)

Sometimes, instead of having e.g. position-x and position-y parameters, it's easier to have something like p=40 20 or dim=20x20.  We can use
the C<list_parameter> function to obtain a list of any numbers separated by non-number characters. (Note that due to the line parser using
commas to separate the parameters themselves, the separator can't be a comma.  Unless you want to write a different line parser, in which
case, go you!)

So the separator characters can be: !@#$%^&*|:;~x and space.

=cut

sub list_parameter { split /[!@\#\$%\^\&\*\|:;~xX ]/, parameter(@_); }

=head1 BUILDING STRUCTURE

=head2 load ($string)

The C<load> method loads declarative specification text into a node by calling the parser appropriate to the node.  Multiple loads can be carried out,
and will simply add to text already there.

The return value is the list of objects added to the target, if any.

=cut

sub load {
   my ($self, $string) = @_;
   
   my @added;
   
   if (ref $string) {
      #print STDERR "load: Adding from arrayref!\n" . Dumper($string);
      my $root = $self->root;
      $string = [$string] unless ref $$string[0];
      foreach my $addition (@$string) {
         #print STDERR "addition is $addition\n";
         #print STDERR "line is " . ref($addition) ? $$addition[0] : $addition;
         my $tag = ref($addition) ? $$addition[0] : $addition;
         $tag =~ s/ .*//;
         #print STDERR ", tag is $tag\n";
         
         # Make and add the tag by hand (for a text body, this is done by the parser in the 'else' block below).
         my $newtag = $root->makenode([@{$self->ancestry}, $tag], $addition);
         $newtag->{parent} = $self;
         $self->{elements} = [$self->elements, $newtag];
         
         push @added, $newtag;
      }
   } else {
      # Taken from the Perl recipes:
      my ($white, $leader);  # common whitespace and common leading string
      if ($string =~ /^\s*(?:([^\w\s]+)(\s*).*\n)(?:\s*\1\2?.*\n)+$/) {
          ($white, $leader) = ($2, quotemeta($1));
      } else {
          ($white, $leader) = ($string =~ /^(\s+)/, '');
      }
      $leader = '' unless $leader;
      $white = '' unless $white;
      $white =~ s/^\n*//;
      $string =~ s/^\s*?$leader(?:$white)?//gm if $leader or $white;
   
      my $root = $self->root();
      @added = $root->parse ($self, $string);
   }
   
   foreach (@added) {
      $_->build if $_->can('build');
   }
   #print Dumper($self->sketch);
   @added;
}

=head2 macroinsert ($spec)

This function adds structure to a given node at runtime that won't show up in the node's C<describe> results.  It is used by the macro system (hence
the name) but can be used by other runtime structure modifiers that act more or less like macros.  The idea is that this structure is meaningful at runtime
but is semantically already accounted for in the existing definition, and should I<always> be generated only at runtime.

=cut

sub macroinsert {
   my ($self, $string) = @_;
   my @objects = $self->load($string);
   foreach (@objects) {
      $_->{macroresult} = 1;
   }
   @objects;   
}


=head2 build(), preprocess(), preprocess_line(), decode_line(), parse_body(), build_payload(), build_children(), add_to_parent(), post_build()

The C<build> function parses the body of the tag, then builds the payload it defines, then calls build on each child if appropriate, then adds itself
to its parent.  It provides the hooks C<preprocess> (checks for macro nature and expresses if so), C<parse_body> (asks the application to call the appropriate
parser for the tag), C<build_payload> (does nothing by default), C<build_children> (calls C<build> on each element), and C<add_to_parent> 
(does nothing by default).

If this tag corresponds to a macro, then substitution takes place before parsing, in the preprocess step.

=cut

sub build {
   my $self = shift;
   
   if ($self->{state} ne 'built') {
      $self->preprocess_line;
      $self->decode_line;
      $self->preprocess;
      $self->parse_body;
      $self->build_payload;
      $self->build_children;
      $self->add_to_parent;
      $self->post_build;

      $self->{state} = 'built';
   }
   return $self->payload;
}

sub preprocess_line {}

sub decode_line {   # Was called parse_line, but there was an unfortunate and brain-bending collision with Text::ParseWords.   Oy.
   my $self = shift;
   my $root = $self->root;
   $root->parse_line ($self);
}

sub preprocess {}

sub parse_body {
   my $self = shift;
   if ($self->tag =~ /^!/) {
      $self->{tag} =~ s/^!//;
      #print "!'d tag " . $self->{tag} . " found; not parsing body\n";
   } else {
      my $root = $self->root;
      if (ref $self->body eq 'ARRAY') {
         # If we have an arrayref input, we don't need to parse it!  (2010-12-05)
         #print "parse_body: body is an arrayref\n";
         my $list = $self->{body};
         $self->{body} = '';
         foreach (@$list) {
            $self->load ($_);
         }
      } else {
         my @results = $root->parse ($self, $self->body) if $self->body and not $self->{bracket};
         $self->{body} = '' if @results;
      }
   }
}

sub build_payload {}

sub build_children {
   my $self = shift;
   
   foreach ($self->nodes) {
      $_->build if $_->can('build');
   }
}

sub add_to_parent {}

sub post_build {}

=head1 STRUCTURE ACCESS

=head2 find($nodename)

Given a node, finds a descendant using a simple XPath-like language.  Once you build a recursive-descent parser facility into your language, this sort
of thing gets a whole lot easier.

Generation separators are '.', '/', or ':' depending on how you like it.  Offsets by number are in round brackets (), while finding children by name is
done with square brackets [].  Square brackets [name] find tags named "name".  Square brackets [name name2] find name lists (which nodes can have, yes),
and square brackets with an = or =~ can also search for nodes by other values.

You can also pass the results of a parse (the arrayref tree) in as the path; this allows you to build the parse tree using other tools instead of forcing
you to build a string (it also allows a single parse result to be used recursively without having to parse it again).

=cut

sub find {
   my ($self, $path) = @_;
   
   $path = $self->root->parse_using ($path, 'locator') unless ref $path;
   return $self if @$path == 0;

   my $first = shift @$path;
   foreach ($self->nodes) {
      return $_->find($path) if $_->match($first);
   }
   return undef;
}

=head2 match($pathelement)

Returns a true value if the node matches the path element specified; otherwise, returns a false value.

=cut

sub match {
   my ($self, $pathelement) = @_;
   return ($self->tag eq $pathelement) unless ref $pathelement;
   my ($tag, $name) = @$pathelement;
   return 1 if $self->tag eq $tag and $self->name eq $name;
   return 0;
}

=head2 first($nodename)

Given a node, finds a descendant with the given tag anywhere in its descent.  Uses the same path notation as C<find>.

=cut

sub first {
   my ($self, $path) = @_;

   $path = $self->root->parse_using ($path, 'locator') unless ref $path;
   return $self if @$path == 0;

   my ($first, @rest) = @$path;
   foreach ($self->nodes) {
      if ($_->match($first)) {
         my $possible = $_->find(\@rest);
         return $possible if $possible;
      }
      my $child = $_->first($path);
      return $child if $child;
   }
   return undef;
}

=head2 search($nodename)

Given a node, finds all descendants with the given tag.

=cut

sub search {
   my ($self, $path) = @_;
   my @returns = ();
   foreach ($self->nodes) {
      push @returns, $_ if $_->tag eq $path;
      push @returns, $_->search($path);
   }
   @returns
}

=head2 describe, myline

The C<describe> function is used to get our code back out so we can reparse it later if we want to.  It includes the body and any children.
The C<myline> function just does that without the body and children (just the actual line).
We could also use this to check the output of the parser, which notoriously just stops on a line if it encounters something it's not
expecting.

=cut

sub myline {
   my ($self) = @_;

   my $description = $self->tag;
   foreach (@{$self->{namelist}}) {
      $description .= " " . $_;
   }
   
   if ($self->parmlist) {
      $description .= " (" .
         join (', ', map {
            $self->parameter($_) eq 'yes' ?
               $_ :
               ($self->parameter($_) =~ / |"/ ?
                   $_ . '="' . escapequote ($self->parameter($_)) . '"' :
                   $_ . '=' . $self->parameter($_))
            } $self->parmlist) .
         ")";
   }

   if ($self->optionlist) {
      $description .= " [" .
         join (', ', map {
            $self->option($_) eq 'yes' ?
               $_ :
               ($self->option($_) =~ / |"/ ?
                   $_ . '="' . escapequote ($self->option($_)) . '"' :
                   $_ . '=' . $self->option($_))
            } $self->optionlist) .
         "]";
   }
   
   $description .= ' "' . $self->label . '"' if $self->label ne '';
   $description .= ' ' . $self->parser . ' <' if $self->parser;
   $description .= ' ' . $self->code if $self->code;
   $description .= ' ' . $self->bracket if $self->bracket;
   $description .= ' ' . $self->comment if $self->comment;
   
   $description;
}   
   
sub describe {
   my ($self) = @_;
   
   my $description = $self->myline . "\n";
   
   if ($self->body) {
      foreach (split /\n/, $self->body) {
         $description .= "   $_\n";
      }
      $description .= "}\n" if $self->bracket;
   } else {
      foreach ($self->elements) {
         if (not ref $_) {
            $description .= $_;
         } elsif ($_->{macroresult}) {
            next;
         } else {
            foreach (split /\n/, $_->describe) {
               $description .= "   $_\n";
            }
         }
      }
   }
   
   $description;
}

=head2 sketch (), sketch_c()

Returns a thin structure reflecting the nodal structure of the node in question:

   ['tag',
     [['child1', []],
      ['child2', []]]]
      
Like that.  I'm building it for testing purposes, but it might be useful for something else, too.

=cut

sub sketch {
   my ($self) = @_;
   
   [$self->tag, [map { $_->sketch() } $self->nodes()]];
}
sub sketch_c {
   my ($self) = @_;
   
   [$self->tag, ref($self), [map { $_->sketch_c() } $self->nodes()]];
}

=head2 go($item)

For callable nodes, this is one way to call them.  The default is to call the go methods of all the children of the node, in sequence.
The last result is returned as our result (this means that the overall tree may have a return value if you set things up right).

=cut

sub go {
   my $self = shift;
   my $return;

   return unless $self->{callable};
   if ($self->{owncode} && $self->{sub}) {
      $return = &{$self->{sub}}(@_);
   } else {
      foreach ($self->nodes) {
         $return = $_->go (@_);
      }
   }
   return $return;
}

=head2 closure(...)

For callable nodes, this is the other way to call them; it returns the closure created during initialization.  Note that the
default closure is really boring.

=cut

sub closure { $_[0]->{sub} }


=head2 iterate()

Returns an L<Iterator::Simple> iterator over the body of the node.  If the body is a text body, each call returns a line.  If the body is a bracketed
code body, it is executed to return an iterable object.  Yes, this is neat.

If we're a parser macro, we'll run our special parser over the body instead of the normal parser.

=cut

sub iterate {
   my $self = shift;
   return iter([]) unless $self->code or $self->body;
   if ($self->code or $self->bracket) {
      # This is code to be executed, that should return an iterable object.
      my $code;
      if ($self->code) { 
         $code = $self->code;
      } else {
         $code = $self->bracket . "\n";
         $code =~ s/^{//;
         $code .= $self->body;
      }
      my $sub = Class::Declarative::Semantics::Code::make_code ($self, $code);
      my $result = &$sub();
      if (ref $result) {
         return iter ($result);
      } else {
         my @lines = split /\n/, $result;
         return iter (\@lines);
      }
   } else {
      # This is text to be iterated over.
      my @lines = split /\n/, $self->body;
      return iter (\@lines);
   }
}

=head2 text()

This returns a tokenstream on the node's body permitting a consumer to read a series of words interspersed with formatting commands.
The formatting commands are pretty loose - essentially, "blankline" is the only one.  Punctuation is treated as letters in words; that is, 
only whitespace is elided in the tokenization process.

If the node has been parsed, it probably doesn't have a body any more, so this will return a blank tokenstream.  On the other hand, if the node
is callable, it will be called, and the result will be used as input to the tokenstream - same rules as C<iterate> above.

=cut


=head2 content()

This returns the iterated content from iterate(), assembled into lines with as few newlines as possible.

=cut

sub content {
   my ($self, $linebreak) = @_;
   $linebreak = "\n" unless $linebreak;
   my $i = $self->iterate;
   my $result = '';
   my $line;
   
   my $linestart = 1;
   do {
      $line = $i->();
      if (defined $line) {
         if ($self->parameter('raw')) {
            $result .= $line . "\n";
         } else {
            $line =~ s/\s+$//;
            if ($line ne '') {
               $result .= ($linestart ? '' : ' ') . $line;
               $linestart = 0;
            } else {
               $result .= $linebreak;
               $linestart = 1;
            }
         }
      }
   } while (defined $line);
   return $result;
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

sub root {$_[0]->parent->root}

=head2 error

Error handling is the part of programming I'm worst at.  But you just have to bite the bullet and address your weaknesses,
so here is an error marker function.  If there's a problem with a node specification, this marks it.  Later we'll do something
sensible with it.  TODO: something sensible.

=cut

sub error {
   my ($self, $error) = @_;
   $self->{errors} = [] unless $self->{errors};
   push @{$self->{errors}}, $error;
   #print STDERR "$error\n";  # TODO: bad long-term...
}

=head2 find_data

The C<find_data> function finds a data node starting at a given point in the tree.  Right now, it's just going to look for nodes
by name, but more mature locators should follow eventually.

=cut

sub find_data {
   my ($self, $data) = @_;
   foreach ($self->nodes) { return ($_, $_->tag) if $_->name eq $data; }
   foreach ($self->nodes) { return ($_, $_->tag) if $_->is($data); }
   return $self->parent->find_data ($data) if $self->parent;
   return (undef, undef);
}


=head2 set(), get(), get_pair()

These provide a place for object constructors to stash useful information.  The C<get> function gets a parameter if the named user variable
hasn't been set.  It also allows the specification of a default value.

C<get_pair> gets a pair of named values as an arrayref, with a single arrayref default if neither is found.  The individual defaults are assumed
to be 0.

=cut

sub set {
   my ($self, $var, $value) = @_;
   $self->{user}->{$var} = $value;
}
sub get {
   my ($self, $var, $default) = @_;
   return $self->{user}->{$var} if defined $self->{user}->{$var};
   return $self->{parameters}->{$var} if defined $self->{parameters}->{$var};
   return $default if defined $default;
   ''
}
sub get_pair {
   my ($self, $x, $y, $default) = @_;
   
   if ($self->get($x) ne '' || $self->get($y) ne '') {
      return [($self->get($x, 0)), ($self->get($y, 0))];
   }
   return $default;
}

=head2 subs()

Returns all our direct children named 'sub', plus the same thing from our parent.  Our answers mask our parent's.

=cut

sub subs {
   my $self = shift;
   my $subs = $self->parent ? $self->parent()->subs() : {};
   foreach ($self->nodes()) {
      next unless $_->tag() eq 'sub';
      $_->build();
      $subs->{$_->name} = $_;
   }
   return $subs;
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

1; # End of Class::Declarative::Node
