#!perl -T

use Test::More tests => 7;

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

$with = $tree->first('with');
isa_ok ($with, 'Class::Declarative::Node');
$with->macroinsert (<<EOF);
 ! macro_expansion
 ! macro_expansion2
 !   with a child
 ! macro_expansion3
EOF

# Check that it all got added.
$me = $tree->first('macro_expansion');
isa_ok ($me, 'Class::Declarative::Node');
$me2 = $tree->first('macro_expansion2');
isa_ok ($me2, 'Class::Declarative::Node');
$child = $me2->find('with');
isa_ok ($child, 'Class::Declarative::Node');
$me3 = $tree->first('macro_expansion2');
isa_ok ($me3, 'Class::Declarative::Node');

$dump = $tree->describe;

ok ($dump !~ /with a child/);
ok ($dump !~ /macro_expansion3/);
