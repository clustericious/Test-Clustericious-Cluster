use strict;
use warnings;
use v5.10;
use Config;
use Test::More tests => 1;

pass 'okay';

diag '';
diag "$_=$ENV{$_}" for grep /MOJO|PERL/i, sort keys %ENV;

if(defined $ENV{PERL5LIB})
{
  diag '';
  diag $_ for split $Config{path_sep}, $ENV{PERL5LIB};
}
