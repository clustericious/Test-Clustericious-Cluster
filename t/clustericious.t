use strict;
use warnings;
use Test::Clustericious::Cluster;
use Test::More;
BEGIN {
  plan skip_all => 'test requires Clustericious' unless eval q{ use Clustericious; 1 };
  plan skip_all => 'test requires Clustericious::Config' unless eval q{ use Clustericious::Config; 1 };
  plan skip_all => 'test requires Test::Clustericious::Config 0.22' unless eval q{ use Test::Clustericious::Config; 1 };
}
plan tests => 15;

eval q{
  package
    MyApp;
    
  $INC{'MyApp.pm'} = __FILE__;
  
  our $VERSON = '1.00';
  use Mojo::Base qw( Clustericious::App );
  
  package
    MyApp::Routes;
  
  use Clustericious::RouteBuilder;
  
  get '/' => sub { shift->render(text => 'welcome') };
  get '/number' => sub {
    my $c = shift;
    $c->render(text => $c->config->service_index);
  };
};
die $@ if $@;

my $loader = Mojo::Loader->new;
$loader->load('main');

create_config_ok common => $loader->data('main', 'common.conf');

my $cluster = Test::Clustericious::Cluster->new;
$cluster->create_cluster_ok(qw( MyApp MyApp ));

my $t = $cluster->t;

$t->get_ok($cluster->urls->[0])
  ->status_is(200)
  ->content_is('welcome');

$t->get_ok($cluster->urls->[1])
  ->status_is(200)
  ->content_is('welcome');

is(Clustericious::Config->new('MyApp')->url, $cluster->urls->[1], "config matches last MyApp url");

$t->get_ok($cluster->urls->[0] . "/number")
  ->status_is(200)
  ->content_is(0);

$t->get_ok($cluster->urls->[1] . "/number")
  ->status_is(200)
  ->content_is(1);

__DATA__

@@ common.conf
---
url: <%= cluster->url %>

@@ MyApp.conf
---
% extends_config 'common';
service_index: <%= cluster->index %>
