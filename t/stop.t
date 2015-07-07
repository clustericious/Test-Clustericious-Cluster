use strict;
use warnings;
BEGIN { $ENV{MOJO_NO_IPV6} = 1; $ENV{MOJO_NO_TLS} = 1; }
#use Carp::Always::Dump;
use Test::Clustericious::Cluster;
use Test::More;
use IO::Socket::INET;

plan skip_all => 'cannot turn off Mojo IPv6'
  if IO::Socket::INET->isa('IO::Socket::IP');

plan tests => 4;

my $cluster = Test::Clustericious::Cluster->new;
$cluster->create_cluster_ok(qw( MyApp MyApp MyApp ));
my $t = $cluster->t;
my @url = @{ $cluster->urls };

subtest 'servers start as up' => sub {
  plan tests => 6;
  $t->get_ok("$url[0]/foo")
    ->status_is(200);
  $t->get_ok("$url[1]/foo")
    ->status_is(200);
  $t->get_ok("$url[2]/foo")
    ->status_is(200);
};

subtest 'stop middle server' => sub {
  plan tests => 6;

  $cluster->stop_ok(1);

  subtest 'left' => sub {
    plan tests => 2;
    $t->get_ok("$url[0]/foo")
      ->status_is(200);
  };

  subtest 'middle' => sub {
    plan tests => 3;
    my $tx = $t->ua->get("$url[1]/foo");
    ok !$tx->success, "GET $url[1]/foo [connection refused]";
    my $error = $tx->error->{message};
    my $code  = $tx->error->{code};
    ok $error, "error = $error";
    $code//='';
    ok !$code, "code  = $code";
  };
  
  subtest 'right' => sub {
    plan tests => 2;
    $t->get_ok("$url[2]/foo")
      ->status_is(200);
  };
  
  subtest 'middle with new ua' => sub {
    plan tests => 3;
    
    my $ua = $cluster->create_ua;
    
    my $tx = $ua->get("$url[1]/foo");
    ok(!$tx->success, "GET $url[1]/foo [connection refused]") || diag $tx->res->to_string;
    
    my $error = eval { $tx->error->{message} };
    my $code  = eval { $tx->error->{code} };
    $error//='';
    ok $error, "error = $error";
    $code//='';
    ok !$code, "code  = $code";
  };
  
  subtest 'is_stopped / isnt_stopped' => sub {
    plan tests => 3;
    $cluster->isnt_stopped(0);
    $cluster->is_stopped(1);
    $cluster->isnt_stopped(2);
  };
};

subtest 'restart middle server' => sub {
  plan tests => 8;
  $cluster->start_ok(1);

  $t->get_ok("$url[0]/foo")
    ->status_is(200);
  $t->get_ok("$url[1]/foo")
    ->status_is(200);
  $t->get_ok("$url[2]/foo")
    ->status_is(200);
    
  subtest 'with create_ua' => sub {
    plan tests => 3;
    my $ua = $cluster->create_ua;
    
    my $tx = $ua->get("$url[1]/foo");
    
    ok $tx->success, "GET $url[1]/foo SUCCESS";
    #note $tx->res->to_string;
    is $tx->res->code, 200, 'code == 200';
    is $tx->res->body, 'bar1', 'body = bar1';
  };
};

__DATA__

@@ lib/MyApp.pm
package MyApp;

use strict;
use warnings;
use 5.010001;
use Mojo::Base qw( Mojolicious );

sub startup
{
  my($self) = @_;
  state $index = 0;
  $self->{index} = $index++;
  $self->routes->get('/foo' => sub { shift->render(text => "bar" . $self->{index}) });
}

1;
