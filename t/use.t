use strict;
use warnings;
BEGIN { eval q{ use EV } } # supress CHECK block warning, if EV is installed
use Test::More tests => 1;

use_ok 'Test::Clustericious::Cluster';
