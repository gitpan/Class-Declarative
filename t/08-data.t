#!perl -T

use Test::More tests => 2;
use Data::Dumper;

# --------------------------------------------------------------------------------------
# Class::Declarative::Data objects know how to iterate lists.
# --------------------------------------------------------------------------------------
use Class::Declarative qw(-nofilter Class::Declarative::Semantics);

$tree = Class::Declarative->new();

$code = <<'EOF';

data my_data (this, that)
   1    "this is the value of this"
   2    "that is the value of that"
   3    third
   
value count "0"

do {
   ^foreach this, that in my_data {
      print STDERR "$this - $that\n";
      $^count ++;
   }
   
   ^foreach my_data {   # I'm sorry, I just find this incredibly cool.
      print STDERR "$that - $this\n";
      $^count ++;
   }
}

EOF

$tree->load($code);

#diag Dumper($tree->sketch_c());

$data = $tree->find ('data');

$i1 = $data->iterate;

$count = 0;
while (<$i1>) {
   #diag "$_ - $$_[0] $$_[1]\n";
   $count++;
}
is ($count, 3);

# Now let's run that 'do'.
$tree->start;

is ($tree->value('count'), 6);

