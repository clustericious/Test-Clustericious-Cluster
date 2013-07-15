use strict;
use warnings;
use Test::Clustericious::Cluster;
use Test::More;
BEGIN {
  plan skip_all => 'test requires Test::Clustericious::Config' unless eval q{ use Test::Clustericious::Config; 1 };
}

plan tests => 5;

my $bin = create_directory_ok 'bin';

do {
  open my $fh, '>', "$bin/myapp";
  eval { chmod 0755, $fh }; # in case OS does not support chmod
  print $fh "#!/usr/bin/perl\n";
  print $fh "use Mojolicious::Lite;\n";
  print $fh "get '/' => sub { shift->render( text => 'bar' ) };\n";
  print $fh "app;\n";
  close $fh;
};

$ENV{PATH} = $bin . ($^O eq 'MSWin32' ? ';' : ':') . $ENV{PATH};

my $cluster = Test::Clustericious::Cluster->new;

$cluster->create_cluster_ok('myapp');

my $t = $cluster->t;

$t->get_ok($cluster->url)
  ->status_is(200)
  ->content_is('bar');

