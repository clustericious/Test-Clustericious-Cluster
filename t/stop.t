use strict;
use warnings;
use Test::Clustericious::Cluster;
use Test::More tests => 22;

my $cluster = Test::Clustericious::Cluster->new;
$cluster->create_cluster_ok(qw( MyApp MyApp MyApp ));
my $t = $cluster->t;
my @url = @{ $cluster->urls };

$t->get_ok("$url[0]/foo")
  ->status_is(200);
$t->get_ok("$url[1]/foo")
  ->status_is(200);
$t->get_ok("$url[2]/foo")
  ->status_is(200);

$cluster->stop_ok(1);

$t->get_ok("$url[0]/foo")
  ->status_is(200);

my $tx = $t->ua->get("$url[1]/foo");

ok !$tx->success, "GET $url[1]/foo [connection refused]";
my($error, $code) = $tx->error;
ok $error, "error = $error";
$code//='';
ok !$code, "code  = $code";

$t->get_ok("$url[2]/foo")
  ->status_is(200);

$cluster->start_ok(1);

$t->get_ok("$url[0]/foo")
  ->status_is(200);
$t->get_ok("$url[1]/foo")
  ->status_is(200);
$t->get_ok("$url[2]/foo")
  ->status_is(200);

__DATA__

@@ lib/MyApp.pm
package MyApp;

use strict;
use warnings;
use v5.10;
use Mojo::Base qw( Mojolicious );

sub startup
{
  my($self) = @_;
  state $index = 0;
  $self->{index} = $index++;
  $self->routes->get('/foo' => sub { shift->render(text => "bar" . $self->{index}) });
}

1;
