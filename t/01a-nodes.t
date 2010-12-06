#!perl -T

use Test::More tests => 15;
use Data::Dumper;


#goto ARRAYREF;

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

# --------------------
# Test parmlist.
# --------------------

$tree = Class::Declarative->new(<<'EOF');

object (file="myfile.txt", other=stuff)
   file2 "myfile2.txt"

EOF

$node = $tree->find("object");
%p = $node->plist ('file', 'file2', 'other');
is_deeply (\%p, {file=>'myfile.txt', file2=>'myfile2.txt', other=>'stuff'});

# -----------------------
# Test parm_css.
# -----------------------

$tree = Class::Declarative->new(<<'EOF');

object1 (border="simple")
object2 (border-left="simple", border-right="simple", border-middle="simple", border-middle-left="not simple")
object2a (border-left="simple", border-right="simple", border-middle-left="not simple", border-middle="simple")
object3 (border="left: simple; right: simple; middle: simple; middle.left: not simple")
object4 (border="left: simple; right/top: simple", border-middle=something)

EOF

$node1 = $tree->find("object1");
is ($node1->parm_css("border"), 'simple');

$node2 = $tree->find("object2");
is_deeply ($node2->parm_css("border"),
           {'left'   => 'simple',
            'right'  => 'simple',
            'middle' => {'*' => 'simple', 'left' => 'not simple'}});

$node2a = $tree->find("object2a");
is_deeply ($node2a->parm_css("border"),
           {'left'   => 'simple',
            'right'  => 'simple',
            'middle' => {'*' => 'simple', 'left' => 'not simple'}});

$node3 = $tree->find("object3");
is ($node3->parm_css("border-left"), 'simple');
is ($node3->parm_css("border-middle-left"), 'not simple');

$node4 = $tree->find("object4");
is ($node4->parm_css("border-middle"), 'something');
is ($node4->parm_css("border.right.top"), 'simple');

# ------------------------------------------------
# Test arrayref node creation.
# ------------------------------------------------

ARRAYREF:
$tree = Class::Declarative->new([['pod head1 "THIS IS A TEST"', "Here is some POD code.\nThere is much POD code like it.\nThis is mine.\n"],
                                 ['regular tree "This is a regular tree."',
                                   ['node node1 "This is node 1"', ['node node1a "This is node 1a"']],
                                   ['node node2 "This is node 2"',
                                      ['node node2a "This is node 2a"'],
                                      ['node node2b "Yeah, node 2b"', ['node node2b1 "This is node 2b1"'], ['node node2b2 "Node 2b2"']]],
                                   ['node node3 "Here is node three"']]]);

$node = $tree->find("regular.node[node2]");
isa_ok ($tree, 'Class::Declarative');
#diag Dumper ($tree->sketch);
is ($node->label, "This is node 2");
$node = $tree->find("regular.node[node2].node[node2b].node[node2b2]");
is ($node->label, "Node 2b2");

$node = $tree->first("node[node3]");
is ($node->label, "Here is node three");

