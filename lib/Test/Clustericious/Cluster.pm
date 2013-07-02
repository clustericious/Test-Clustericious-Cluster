package Test::Clustericious::Cluster;

use strict;
use warnings;
use v5.10;

BEGIN {
  unless($INC{'File/HomeDir/Test.pm'})
  {
    eval q{ use File::HomeDir::Test };
    die $@ if $@;
  }
}

use File::HomeDir;
use Mojo::URL;
use Test::Mojo;
use Mojo::Loader;
use base qw( Test::Builder::Module );

# ABSTRACT: Test an imaginary beowulf cluster of Clustericious services
# VERSION

=head1 SYNOPSIS

 use Test::Clustericious::Cluster;

 my $cluster = Test::Clustericious::Cluster->new;
 $cluster->create_cluster_ok('MyApp1', 'MyApp2');

 my @urls = @{ $cluster->urls };
 my $t = $cluster->t; # an instance of Test::Mojo
 
 $t->get_ok("$url[0]/arbitrary_path");  # tests against MyApp1
 $t->get_ok("$url[1]/another_path");    # tests against MyApp2
 

=head1 DESCRIPTION

This module allows you to test an entire cluster of Clustericious services
(or just one or two).  The only prerequisites are L<Mojolicious> and 
L<File::HomeDir>, so you can mix and match Mojolicious and full Clustericious
apps and test how they interact.

If you are testing against Clustericious applications, it is important to
either use this module as early as possible, or use L<File::HomeDir::Test>
as the very first module in your test, as testing Clustericious configurations
depend on the testing home directory being setup by L<File::HomeDir::Test>.

=cut

BEGIN { $ENV{MOJO_LOG_LEVEL} = 'fatal' }

=head1 CONSTRUCTOR

=head2 Test::Clustericious::Cluster->new( [ $t ] )

Optionally takes an instance of Test::Mojo as its argument.
If not provided, then a new one will be created.

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
    index   => -1,
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

=head2 $cluster-E<gt>create_cluster_ok @services

Adds the given services to the test cluster.
Each element in the services array may be either

=over 4

=item string

The string is taken to be the L<Mojolicious> or L<Clustericious>
application name.  No configuration is created or passed into
the App.

=item list reference in the form: [ string, hashref ]

The string is taken to be the L<Mojolicious> application name.
The hashref is the configuration passed into the constructor
of the app.  This form should NOT be used for L<Clustericious>
apps (see the third form).

=item list reference in the form: [ string, string ]

The first string is taken to be the L<Clustericious> application
name.  The second string is the configuration in either YAML
or JSON format (may include L<Mojo::Template> templating in it,
see L<Clustericious::Config> for details).  This form requires
that you have L<Clustericous> installed, and of course should
not be used for non-L<Clustericious> L<Mojolicious> applications.

=back

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
  
  my $has_clustericious_config = 0;
  
  my $loader = Mojo::Loader->new;
  my $caller = caller;
  $loader->load($caller);
  
  foreach my $i (0..$#_)
  {
    $self->{index}++;
    $self->{url} = shift @urls;
    my $server = Mojo::Server::Daemon->new(
      ioloop => $self->t->ua->ioloop,
      silent => 1,
    );
    
    my $app_name;
    my $config = {};
    my $item = $_[$i];
    if(ref($item) eq '' && $loader->data($caller, "$item.conf"))
    {
      $item = [ $item, $loader->data($caller, "$item.conf") ];
    }

    if(ref $item eq 'ARRAY')
    {
      ($app_name, $config) = @{ $item };
      unless(ref $config)
      {
        my $home = File::HomeDir->my_home;
        mkdir "$home/etc" unless -d "$home/etc";
        open my $fh, '>', "$home/etc/$app_name.conf";
        print $fh $config;
        close $fh;
        $config = {};
        
        unless($has_clustericious_config)
        {
          $has_clustericious_config = 1;
          my $helper = sub { return $self };
        
          require Clustericious::Config::Plugin;
          do {
            no warnings 'redefine';
            *Clustericious::Config::Plugin::cluster = $helper;
          };
          push @Clustericious::Config::Plugin::EXPORT, 'cluster'
            unless grep { $_ eq 'cluster' } @Clustericious::Config::Plugin::EXPORT;
        }
      }
    }
    else
    {
      $app_name = $item;
    }
    
    my $app = eval qq{ use $app_name; $app_name->new(\$config) };
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
