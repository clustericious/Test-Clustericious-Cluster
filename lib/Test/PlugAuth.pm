package Test::PlugAuth;

use strict;
use warnings;
use 5.010001;
use PlugAuth::Lite;
use Mojo::UserAgent;

# ABSTRACT: minimum PlugAuth server to test Clustericious apps against
# VERSION

=head1 SYNOPSIS

assuming you have a Clustericious app MyApp with authentication/authorization
directives that you need to test:

 use Test::Clustericious::Config;
 use Test::Clustericious;
 use Test::PlugAuth;
 
 my $auth = Test::PlugAuth->new(auth => {
   my($user,$pass) = @_;
   return $user eq 'gooduser' && $pass eq 'goodpass';
 });
 
 create_config_ok 'MyApp', { plug_auth => { url => $auth->url } };
 
 $t = Test::Clustericious->new('MyApp');
 $auth->apply_to_client_app($t->app);
 
 my $port = $t->ua->app_url->port;
 
 $t->get_ok("http://baduser:badpass\@localhost:$port/private")
   ->status_is(401);
 $t->get_ok("http://gooduser:goodpass\@localhost:$port/private")
   ->status_is(200);

=head1 DESCRIPTION

Provides a way to test a Clustericious application with a fake PlugAuth server
with reduced boilerplate

=head1 CONSTRUCTOR

=head2 Test::PlugAuth->new( $config )

Creates a new instance of Test::PlugAuth.  The $config is passed
directly into L<PlugAuth::Lite>.  See L<Mojolicious::Plugin::PlugAuthLite>
for details.

=cut

sub new
{
  my $class = shift;
  my $config = ref $_[0] ? $_[0] : {@_};
  my $self = bless {}, $class;
  
  $self->{app} = PlugAuth::Lite->new($config);
  $self->{ua}  = Mojo::UserAgent->new;
  eval { $self->ua->server->app($self->app) } // $self->ua->app($self->app);
  
  $self->{url} = eval { $self->ua->server->url->to_string } // $self->ua->app_url->to_string;
  $self->{url} =~ s{/$}{};
  
  return $self;
}

=head1 ATTRIBUTES

=head2 ua

The L<Mojo::UserAgent> used to connect to the PlugAuth (lite) server.

=cut

sub ua  { shift->{ua}  }

=head2 app

The L<PlugAuth::Lite> instance of the PlugAuth server.

=cut

sub app { shift->{app} }

=head2 url

The (fake) url used to connect to the PlugAuth server with.  You MUST
connect to through the L<Mojo::UserAgent> above.

=cut

sub url { shift->{url} }

=head1 METHODS

=head2 $test_auth->apply_to_client_app( $client_app )

Given a Clustericious application C<$client_app>, this method will 
rewire our L<Mojo::UserAgent> for authentication requests to PlugAuth.

=cut

sub apply_to_client_app 
{
  my($self, $client_app) = @_;
  $client_app->helper(auth_ua => sub { $self->ua });
  return;
}

1;
