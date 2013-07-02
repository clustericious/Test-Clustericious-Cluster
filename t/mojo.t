use strict;
use warnings;
use v5.10;
use Test::Clustericious::Cluster;
use Test::More tests => 7;

my $cluster = Test::Clustericious::Cluster->new;
$cluster->create_cluster_ok(
  'Foo',
  'Bar',
);

my $t = $cluster->t;
$t->get_ok($cluster->urls->[0])
  ->status_is(200)
  ->content_is('Foo');

$t->get_ok($cluster->urls->[1])
  ->status_is(200)
  ->content_is('Bar');

package
  Foo;

BEGIN { $INC{'Foo.pm'} = __FILE__ }

use Mojo::Base qw( Mojolicious );

sub startup
{
  my $self = shift;
  $self->routes->get('/' => sub {
    shift->render(text => "Foo");
  });
}

package
  Bar;

BEGIN { $INC{'Bar.pm'} = __FILE__ }

use Mojo::Base qw( Mojolicious );

sub startup
{
  my $self = shift;
  $self->routes->get('/' => sub {
    shift->render(text => "Bar");
  });
}

