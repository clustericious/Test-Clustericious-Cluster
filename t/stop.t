use strict;
use warnings;
BEGIN { $ENV{MOJO_NO_IPV6} = 1; $ENV{MOJO_NO_TLS} = 1; }
#use Carp::Always::Dump;
use Test::Clustericious::Cluster;
use Test::More;
use IO::Socket::INET;

plan skip_all => 'cannot turn off Mojo IPv6'
  if IO::Socket::INET->isa('IO::Socket::IP');

plan tests => 22;

my $cluster = Test::Clustericious::Cluster->new;
$cluster->create_cluster_ok(qw( MyApp MyApp MyApp ));
my $t = $cluster->t;
my @url = @{ $cluster->urls };

#diag '';
#diag '';
#diag '';
#foreach my $module (sort keys %INC)
#{
#  my $path    = $INC{$module};
#  if($module =~ s/\.pm//)
#  {
#    $module     =~ s/\//::/g;
#  }
#  my $version = eval qq{ no warnings; \$$module\::VERSION };
#  $version    = '-' unless defined $version;
#  diag sprintf("%40s %8s %s\n", $module, $version, $path);
#}
#diag '';
#diag '';
#diag '';

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
my $error = $tx->error->{message};
my $code  = $tx->error->{code};
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
