#!perl -T

use Test::More tests => 6;

# --------------------------------------------------------------------------------------
# Semantic::Value takes advantage of the active-variable feature of declarative
# contexts to make variables that have active content.  Cool, huh?
# --------------------------------------------------------------------------------------
use Class::Declarative qw(-nofilter Class::Declarative::Semantics);

$tree = Class::Declarative->new();

$tree->load (<<'EOF');

value basevar "0" {
   if (defined $value) {
      $^variable = -$value;
      $this->{$key} = $value;
   }
   $this->{$key}
}
 
EOF

# All right, that should be easy!

$tree->start();

is ($tree->value('basevar'), 0);    # Basevar is initialized.
is ($tree->value('variable'), 0);   # So far, so good.

$tree->setvalue('variable', 1);
is ($tree->value('variable'), 1);
is ($tree->value('basevar'), 0);

$tree->setvalue('basevar', 2);
is ($tree->value('basevar'), 2);
is ($tree->value('variable'), -2);