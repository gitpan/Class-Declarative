#!perl -T

use Test::More tests => 1;
use Data::Dumper;


# --------------------------------------------------------------------------------------
# Now we'll load a structure that can actually run.  We'll build it, then start it.
# --------------------------------------------------------------------------------------
use Class::Declarative qw(-nofilter Class::Declarative::Semantics);

$tree = Class::Declarative->new(<<'EOF');

pod head1 "THIS IS A TEST"
   Here is some POD code.  There is much POD code like it.  This is mine.
   
do "This is some random code" {
   my $something = 2;
   $^variable = $something + 1;
}

EOF

# All right, that should be easy!

$tree->start();

is ($tree->value('variable'), 3);  # How cool is that?