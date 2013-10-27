use strict;
use warnings;
eval q{ use Test::Clustericious::Log };
use Test::Clustericious::Cluster;
use Test::More;
BEGIN {
  plan skip_all => 'test requires Clustericious 0.9931' unless eval q{ use Clustericious 0.9931; 1 };
}
plan tests => 7;

my $cluster = Test::Clustericious::Cluster->new;
$cluster->create_cluster_ok(qw( MyApp1 MyApp2 ));

my $t = $cluster->t;

$t->get_ok($cluster->urls->[0])
  ->status_is(200)
  ->content_is('myapp1');

$t->get_ok($cluster->urls->[1])
  ->status_is(200)
  ->content_is('myapp2');

__DATA__

@@ etc/MyApp1.conf
---
url: <%= cluster->url %>

@@ etc/MyApp2.conf
---
url: <%= cluster->url %>

@@ lib/MyApp1.pm
package MyApp1;

use strict;
use warnings;
use Mojo::Base qw( Clustericious::App );
use MyApp1::Routes;
our $VERSON = '1.00';

1;

@@ lib/MyApp1/Routes.pm
package MyApp1::Routes;

use strict;
use warnings;
use Clustericious::RouteBuilder;

get '/' => sub { shift->render(text => 'myapp1') };

1;

@@ lib/MyApp2.pm
package MyApp2;

use strict;
use warnings;
use Mojo::Base qw( Clustericious::App );
use MyApp2::Routes;
our $VERSON = '1.00';

1;

@@ lib/MyApp2/Routes.pm
package MyApp2::Routes;

use strict;
use warnings;
use Clustericious::RouteBuilder;

get '/' => sub { shift->render(text => 'myapp2') };

1;
