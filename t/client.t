use strict;
use warnings;
eval q{ use Test::Clustericious::Log };
use Test::Clustericious::Cluster;
use Test::More;
BEGIN {
  plan skip_all => 'test requires Clustericious::Client'
    unless eval q{ use Clustericious::Client; 1};
  plan skip_all => 'test requires Test::Clustericious::Config 0.22'
    unless eval q{ use Test::Clustericious::Config; 1 };
}

plan tests => 6;

my $cluster = Test::Clustericious::Cluster->new;
$cluster->create_cluster_ok('MyApp');

create_config_ok MyApp => {
  url => $cluster->url,
};

use_ok 'MyApp::Client';

my $client = eval { MyApp::Client->new };
diag $@ if $@;
isa_ok $client, 'MyApp::Client';
$client->client($cluster->t->ua);

is $client->welcome, 'welcome', 'welcome returns welcome';
is $client->version->[0], '1.00', 'version = 1.00';

__DATA__

@@ lib/MyApp.pm
package MyApp;

use Mojo::JSON;
use Mojo::Base qw( Mojolicious );

sub startup
{
  my($self, $config) = @_;
  $self->routes->get('/' => sub { shift->render(text => 'welcome') });
  $self->routes->get('/version' => sub {
    my $c = shift;
    $c->tx->res->headers->content_type('application/json');
    $c->render(text => Mojo::JSON->new->encode([ '1.00' ]));
  });
}

1;

@@ lib/MyApp/Client.pm
package MyApp::Client;
use Clustericious::Client;
route welcome => 'GET', '/';
1;
