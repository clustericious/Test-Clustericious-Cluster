use strict;
use warnings;
use Test::More tests => 14;
use Test::Mojo;

use Mojolicious::Lite;

plugin 'plug_auth_lite';

my $t = Test::Mojo->new;

$t->get_ok('/')
  ->status_is(404);

my $port = eval { $t->ua->server->url->port } // $t->ua->app_url->port;

$t->get_ok("http://localhost:$port/auth")
  ->status_is(401)
  ->content_like(qr[authenticate], 'got authenticate header');

$t->get_ok("http://foo:bar\@localhost:$port/auth")
  ->status_is(403)
  ->content_is('not ok', 'auth failed');

$t->get_ok("http://foo:foo\@localhost:$port/auth")
  ->status_is(403)
  ->content_is('not ok', 'auth failed');

$t->get_ok("/authz/user/foo/bar/baz")
  ->status_is(200)
  ->content_is('ok', 'authz succeeded');

