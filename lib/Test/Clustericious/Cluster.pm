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
use Mojo::UserAgent;
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
    t           => $t, 
    builder     => $builder, 
    urls        => [], 
    apps        => [], 
    index       => -1,
    url         => '', 
    servers     => [],
    app_servers => [],
    auth_url    => '',
    extra_ua    => [$t->ua],
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

=head2 auth_url

The URL for the PlugAuth::Lite service, if one has been started.

=cut

sub auth_url { shift->{auth_url} }

=head1 METHODS

=head2 $cluster-E<gt>create_cluster_ok( @services )

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

sub _add_app_to_ua
{
  use Carp qw( confess );
  my($self, $ua, $url, $app, $index) = @_;
  #confess "usage: \$cluster->_add_app_to_ua($ua, $url, $app)" unless $url;
  my $server = Mojo::Server::Daemon->new(
    ioloop => $ua->ioloop,
    silent => 1,
  );
  $server->app($app);
  $server->listen(["$url"]);
  $server->start;
  if(defined $index)
  {
    push @{ $self->{app_servers}->[$index] }, $server;
  }
  else
  {
    push @{ $self->{servers} }, $server;
  }
  return;
}

sub _add_app
{
  my($self, $url, $app, $index) = @_;
  $self->_add_app_to_ua($_, $url, $app, $index) for @{ $self->{extra_ua} };
  return;
}

sub _add_ua
{
  my($self) = @_;
  
  my $max = $#{ $self->{apps} };
  
  my $ua = Mojo::UserAgent->new;
  
  $self->_add_app_to_ua($ua, $self->{auth_url}, $self->{auth_url})
    if $self->{auth_url} && $self->{auth_url};
  
  for(my $i=0; $i<=$max; $i++)
  {
    next unless defined $self->{apps}->[$i];
    $self->_add_app_to_ua($ua, $self->{urls}->[$i], $self->{apps}->[$i], $i);
  }
  push @{ $self->{extra_ua} }, $ua;
  return $ua;
}

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

  push @INC, sub {
    my($self, $file) = @_;
    my $data = $loader->data($caller, "lib/$file");
    return unless defined $data;
    open my $fh, '<', \$data;
    return $fh;
  };
  
  foreach my $i (0..$#_)
  {
    $self->{index}++;
    $self->{url} = shift @urls;
    
    my $app_name;
    my $cb;
    my $config = {};
    my $item = $_[$i];
    if(ref($item) eq '' && $loader->data($caller, "etc/$item.conf"))
    {
      $item = [ $item, $loader->data($caller, "etc/$item.conf") ];
    }

    if(ref $item eq 'ARRAY')
    {
      ($app_name, $config, $cb) = @{ $item };
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
            no warnings 'once';
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
    
    my $app;
    
    if(my $script = $loader->data($caller, "script/$app_name"))
    {
      state $index = 0;
      my $home = File::HomeDir->my_home;
      $app = eval '# line '. __LINE__ . ' "' . __FILE__ . qq("\n) . sprintf(q{
        mkdir "$home/script" unless -d "$home/script";
        open my $fh, '>', "$home/script/$app_name";
        print $fh $script;
        close $fh;
        package
          Test::Clustericious::Cluster::LiteApp%s;
        my $app = do "$home/script/$app_name";
        if(!$app && (my $e = $@ || $!)) { die $e }
        $app;
      }, $index++);
    }
    else
    {
      $app = eval qq{ use $app_name; $app_name->new(\$config) };
    }
    if(my $error = $@)
    {
      push @errors, [ $app_name, $error ];
      push @{ $self->apps }, undef;
    }
    else
    {
      push @{ $self->apps }, $app;
      $self->_add_app($self->url, $app, $#{ $self->apps });
    }
    
    if(eval { $app->isa('Clustericious::App') })
    {
      $app->helper(auth_ua => sub { 
        die "no plug auth service configured for test cluster, either turn off authentication or use Test::Clustericious::Cluster#create_plugauth_lite_ok"
          unless defined $self->{auth_ua};
        $self->{auth_ua};
      });
    }

    $cb->() if defined $cb;
  }

  my $tb = __PACKAGE__->builder;
  $tb->ok(@errors == 0, "created cluster");
  $tb->diag("exception: " . $_->[0] . ': ' . $_->[1]) for @errors;
  
  return $self;
}

=head2 $cluster-E<gt>create_plugauth_lite_ok( %args )

Add a L<PlugAuth::Lite> service to the test cluster.  The
C<%args> are passed directly into the L<PlugAuth::Lite>
constructor.

You can retrieve the URL for the L<PlugAuth::Lite> service
using the C<auth_url> attribute.

=cut

sub create_plugauth_lite_ok
{
  my($self, %args) = @_;
  my $ok = 1;
  my $tb = __PACKAGE__->builder;
  
  if($self->{auth_ua} || $self->{auth_url})
  {
    $ok = 0;
    $tb->diag("only use create_plugauth_lite_ok once");
  }
  else
  {
    my $ua = $self->{auth_ua} = $self->_add_ua;
    my $url = Mojo::URL->new("http://127.0.0.1");
    $url->port($self->t->ua->ioloop->generate_port);
  
    eval {
      require PlugAuth::Lite;
      
      my $app = $self->{auth_app} = PlugAuth::Lite->new(\%args);
      $self->{auth_url} = $url;
      $self->_add_app($url, $app);
    };
    if(my $error = $@)
    {
      $tb->diag("error: $error");
      $ok = 0;
    }
  }
  
  $tb->ok($ok, "PlugAuth::Lite instance on " . $self->{auth_url});
  
  return $self;
}

=head2 $cluster-E<gt>stop_ok( $index, [ $test_name ])

Stop the given service.  The service is specified by 
an index, the first application when you created the
cluster is 0, the second is 1, and so on.

=cut

sub stop_ok
{
  my($self, $index, $test_name) = @_;
  my $ok = 1;
  my $tb = __PACKAGE__->builder;
  
  my $app = $self->apps->[$index];
  if(defined $app)
  {
    my $app_name = ref $app;
    $test_name //= "stop service $app_name ($index)";
    @{ $self->{app_servers}->[$index] } = ();
  }
  else
  {
    $tb->diag("no such app for index: $index");
    $ok = 0;
  }
  
  $test_name //= "stop service ($index)";
  
  $tb->ok($ok, $test_name);
}

=head2 $cluster-E<gt>start_ok( $index, [ $test_name ] )

Start the given service.  The service is specified by 
an index, the first application when you created the
cluster is 0, the second is 1, and so on.

=cut

sub start_ok
{
  my($self, $index, $test_name) = @_;
  my $ok = 1;
  my $tb = __PACKAGE__->builder;
  
  my $app = $self->apps->[$index];
  if(defined $app)
  {
    my $app_name = ref $app;
    $test_name //= "start service $app_name ($index)";
    eval {
      $self->_add_app($self->urls->[$index], $app, $index);
    };
    if(my $error = $@)
    {
      $tb->diag("error in start: $error");
      $ok = 0;
    }
  }
  else
  {
    $tb->diag("no such app for index: $index");
    $ok = 0;
  }
  
  $test_name //= "start service ($index)";
  
  $tb->ok($ok, $test_name);
}

1;
