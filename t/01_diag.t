use strict;
use warnings;
use v5.10;
use Test::More tests => 1;

pass 'okay';

diag '';
diag "$_=$ENV{$_}" for grep /MOJO/, sort keys %ENV;
