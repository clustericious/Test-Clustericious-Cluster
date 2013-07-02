use strict;
use warnings;
use Test::Clustericious::Cluster;
use Test::More;
BEGIN {
  plan skip_all => 'test requires Clustericious'
    unless eval q{ use Clustericious; 1 };
  plan skip_all => 'test requires PlugAuth::Lite'
    unless eval q{ use PlugAuth::Lite; 1 };
};
plan tests => 1;

eval q{
  package
    MyApp;
  $INC{'MyApp.pm'} = __FILE__;
  our $VERSION = '1.00';
  use Mojo::Base qw( Clustericious::App );
  
  package
    MyApp::Routes;
    
  use Clustericious::RouteBuilder;
  
  get '/' => sub { shift->render(text => 'public') };
};
die $@ if $@;

my $cluster = Test::Clustericious::Cluster->new;
$cluster->create_cluster_ok(
  [ MyApp => <<CONFIG ]
---
url: <%= cluster->url %>
CONFIG
);
