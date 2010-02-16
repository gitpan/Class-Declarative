#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'Class::Declarative' ) || print "Bail out!
";
}

diag( "Testing Class::Declarative $Class::Declarative::VERSION, Perl $], $^X" );
