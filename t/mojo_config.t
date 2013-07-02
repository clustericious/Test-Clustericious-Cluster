use strict;
use warnings;
use Test::Clustericious::Cluster;
use Test::More tests => 10;

my $cluster = Test::Clustericious::Cluster->new;
$cluster->create_cluster_ok(['Foo' => { arg1 => 'one', arg2 => 'two' }]);

my $t = $cluster->t;
my $url = $cluster->url;

$t->get_ok("$url")
  ->status_is(200)
  ->content_is('welcome');

$t->get_ok("$url/foo")
  ->status_is(200)
  ->content_is('one');

$t->get_ok("$url/bar")
  ->status_is(200)
  ->content_is('two');

package
  Foo;

use Mojo::Base qw( Mojolicious );

BEGIN { $INC{"Foo.pm"} = __FILE__ }

sub startup
{
  my($self, $config) = @_;
  $self->routes->get('/' => sub { shift->render(text => 'welcome') });
  $self->routes->get('/foo' => sub { shift->render(text => $config->{arg1}) });
  $self->routes->get('/bar' => sub { shift->render(text => $config->{arg2}) });
}
