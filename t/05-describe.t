#!perl -T

use Test::More tests => 2;
use Data::Dumper;

# --------------------------------------------------------------------------------------
# Class::Declarative::Node objects can describe themselves.  The overall
# Class::Declarative object can, too.  The result is that any Class::Declarative
# framework object should be able to dump its own source code when necessary.
# --------------------------------------------------------------------------------------
use Class::Declarative qw(-nofilter Class::Declarative::Semantics);

$tree = Class::Declarative->new();

$code = <<'EOF';

pod head1 "HEADING"
  This is a POD element.
  
Another {   # commented
  bracketed body
}

value basevar "0" {
   if (defined $value) {
      $^variable = -$value;
      $this->{$key} = $value;
   }
   $this->{$key}
}

thing nolabel { single-line body }

something (with=parameters, borders, numeric=0, boing=boing) [with_options, something here] "and a label"
   with children
      and grandchildren
      multiple ones
   and yet "more kids"
   a "plethora of'em"
 
EOF

$tree->load($code);

$code2 = <<'EOF';

# Comments are preserved.
extra stuff "gets loaded right along"

EOF

$tree->load ($code2);
#diag Dumper($tree->sketch);
isa_ok ($tree->find('value'), 'Class::Declarative::Node');  # Make sure it didn't get clobbered.

#diag $tree->describe;

$tree2 = Class::Declarative->new();
$tree2->load ($tree->describe);

is_deeply ($tree->sketch, $tree2->sketch);   # We can't compare directly because the coderefs will differ!  (This wasn't true in the old version.)
