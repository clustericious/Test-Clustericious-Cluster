use strict;
use warnings;
BEGIN { eval q{ use EV } } # avoid warning
use Test::More tests => 1;

my @mods = sort qw(
  Mojolicious
  Clustericious
  Clustericious::Config
  Clustericious::Log
  Clustericious::Client
  File::HomeDir
);

diag "";

foreach my $mod (@mods)
{
  my $version = eval qq{ use $mod; \$${mod}::VERSION };
  if($@)
  { diag sprintf("%-22s : not installed", $mod) }
  else
  { diag sprintf("%-22s : $version", $mod) }
}

pass 'okay';
