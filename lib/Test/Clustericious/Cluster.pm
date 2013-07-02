package Test::Clustericious::Cluster;

use strict;
use warnings;
use v5.10;
use File::HomeDir::Test;
use File::HomeDir;
use Mojo::URL;
use Test::Mojo;
use base qw( Test::Builder::Module );

=head1 NAME

Test::Clustericious::Cluster - test an imaginary beowulf cluster of clustericious services

=head1 SYNOPSIS

 use Test::Clustericious::Config;
 use Test::Clustericious::Cluster;

 create_cluster_ok;

=cut

our $VERSION = '0.9927';

BEGIN { $ENV{MOJO_LOG_LEVEL} = 'fatal' }

=head1 CONSTRUCTOR

=head2 Test::Clustericious::Cluster->new

=cut

sub new
{
  my $class = shift;

  my $t;
  if(defined $_[0] && ref $_[0] && eval { $_[0]->isa('Test::Mojo') })
  { $t = shift }
  else
  { $t = Test::Mojo->new }
  
  my $builder = __PACKAGE__->builder;
  
  bless { 
    t       => $t, 
    builder => $builder, 
    urls    => [], 
    apps    => [], 
    index   => 0,
    url     => '', 
    servers => [],
  }, $class;
}

sub _builder { shift->{builder} }

=head1 ATTRIBUTES

=head2 t

The instance of Test::Mojo used in testing.

=cut

sub t { shift->{t} }

=head2 urls

The URLs for the various services.
Returned as an array ref.

=cut

sub urls { shift->{urls} }

=head2 apps

The application objects for the various services.
Returned as an array ref.

=cut

sub apps { shift->{apps} }

=head2 index

The index of the current app (used from within a 
L<Clustericious::Config> configuration.

=cut

sub index { shift->{index} }

=head2 url

The url of the current app (used from within a
L<Clustericious::Config> configuration.

=cut

sub url { shift->{url} }

=head1 METHODS

=head2 create_cluster_ok 

=cut

sub create_cluster_ok
{
  my $self = shift;
  
  my $total = scalar @_;
  my @urls = map { 
    my $url = Mojo::URL->new("http://127.0.0.1");
    $url->port($self->t->ua->ioloop->generate_port);
    $url } (0..$total);

  push @{ $self->{urls} }, @urls;
  
  my @errors;
  
  foreach my $i (0..$#_)
  {
    $self->{url} = shift @urls;
    my $server = Mojo::Server::Daemon->new(
      ioloop => $self->t->ua->ioloop,
      silent => 1,
    );
    
    my $app_name = $_[$i];
    my $app = eval qq{ use $app_name; $app_name->new };
    if(my $error = $@)
    {
      push @errors, [ $app_name, $error ];
      push @{ $self->apps }, undef;
    }
    else
    {
      push @{ $self->apps }, $app;
      $server->app($app);
    }
    
    $server->listen([$self->url.'']);
    $server->start;
    push @{ $self->{servers} }, $server;
  }

  my $tb = __PACKAGE__->builder;
  $tb->ok(@errors == 0, "created cluster");
  $tb->diag("exception: " . $_->[0] . ': ' . $_->[1]) for @errors;
  
  return $self;
}

1;
