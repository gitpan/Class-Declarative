#!perl -T

use Test::More tests => 3;
use Data::Dumper;


# --------------------------------------------------------------------------------------
# Nodes have some structure access and building functionality that we'll test here.
# --------------------------------------------------------------------------------------
use Class::Declarative qw(-nofilter Class::Declarative::Semantics);

$tree = Class::Declarative->new(<<'EOF');

pod head1 "THIS IS A TEST"
   Here is some POD code.  There is much POD code like it.  This is mine.
   
regular tree "This is a regular tree."
   node node1 "This is node 1"
      node node1a "This is node 1a"
   node node2 "This is node 2"
      node node2a "This is node 2a"
      node node2b "Yeah, node 2b"
         node node2b1 "This is node 2b1"
         node node2b2 "Node 2b2"
   node node3 "Here is node three"

EOF

$node = $tree->find("regular.node[node2]");
is ($node->label, "This is node 2");
$node = $tree->find("regular.node[node2].node[node2b].node[node2b2]");
is ($node->label, "Node 2b2");

$node = $tree->first("node[node3]");
is ($node->label, "Here is node three");