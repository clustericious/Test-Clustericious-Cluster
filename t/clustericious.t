use strict;
use warnings;
use Test::Clustericious::Cluster;
use Test::More;
BEGIN {
  plan skip_all => 'test requires Clustericious' unless eval q{ use Clustericious; 1 };
  plan skip_all => 'test requires Clustericious::Config' unless eval q{ use Clustericious::Config; 1 };
  plan skip_all => 'test requires Test::Clustericious::Config 0.22' unless eval q{ use Test::Clustericious::Config; 1 };
}
plan tests => 9;

eval q{
  package
    MyApp;
    
  BEGIN { $INC{'MyApp.pm'} = __FILE__ }
  
  our $VERSON = '1.0';
  use Mojo::Base qw( Clustericious::App );
  
  package
    MyApp::Routes;
  
  use Clustericious::RouteBuilder;
  
  get '/' => sub { shift->render(text => 'welcome') };
};
die $@ if $@;

create_config_ok common => <<COMMON_CONFIG;
---
url: <%= cluster->url %>
COMMON_CONFIG

my $cluster = Test::Clustericious::Cluster->new;
$cluster->create_cluster_ok(
  [ MyApp => <<CONFIG1 ],
---
url: <%= cluster->url %>
CONFIG1
  [ MyApp => <<CONFIG2 ],
---
% extends_config 'common';
CONFIG2
);

my $t = $cluster->t;

$t->get_ok($cluster->urls->[0])
  ->status_is(200)
  ->content_is('welcome');

$t->get_ok($cluster->urls->[1])
  ->status_is(200)
  ->content_is('welcome');

is(Clustericious::Config->new('MyApp')->url, $cluster->urls->[1], "config matches last MyApp url");
