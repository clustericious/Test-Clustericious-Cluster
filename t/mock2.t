use strict;
use warnings;
use Test::Clustericious::Cluster;
use Test::More tests => 2;

use_ok('Net::hostent');
is gethost('bar')->name, 'foo.example.com', 'gethost(bar).name = foo.example.com';

__DATA__

@@ lib/Net/hostent.pm
package Net::hostent;

use strict;
use warnings;
use base qw( Exporter );
our @EXPORT = qw( gethost );

sub gethost
{
  my $input_name = shift;
  return unless $input_name =~ /^(foo|bar|baz|foo.example.com)$/;
  bless {}, 'Net::hostent';
}

sub name { 'foo.example.com' }
sub aliases { qw( foo.example.com foo bar baz ) }

1;
