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
use Carp qw( croak );

# ABSTRACT: Test an imaginary beowulf cluster of Clustericious services
# VERSION

=head1 SYNOPSIS

 use Test::Clustericious::Cluster;
 
 # suppose MyApp1 isa Clustericious::App and
 # MyApp2 is a Mojolicious app
 my $cluster = Test::Clustericious::Cluster->new;
 $cluster->create_cluster_ok('MyApp1', 'MyApp2');
 
 my @urls = @{ $cluster->urls };
 my $t = $cluster->t; # an instance of Test::Mojo
 
 $t->get_ok("$url[0]/arbitrary_path");  # tests against MyApp1
 $t->get_ok("$url[1]/another_path");    # tests against MyApp2
 
 __DATA__
 
 @@ etc/MyApp1.conf
 ---
 # Clustericious configuration 
 url <%= cluster->url %>
 url_for_my_app2: <%= cluster->urls->[1] %>

=head1 DESCRIPTION

This module allows you to test an entire cluster of Clustericious services
(or just one or two).  The only prerequisites are L<Mojolicious> and 
L<File::HomeDir>, so you can mix and match L<Mojolicious>, L<Mojolicious::Lite>
and full L<Clustericious> apps and test how they interact.

If you are testing against Clustericious applications, it is important to
either use this module as early as possible, or use L<File::HomeDir::Test>
as the very first module in your test, as testing Clustericious configurations
depend on the testing home directory being setup by L<File::HomeDir::Test>.

In addition to passing L<Clustericious> configurations into the
C<create_cluster_ok> method as describe below, you can include configuration
in the data section of your test script.  The configuration files use 
L<Clustericious::Config>, so you can use L<Mojo::Template> directives to 
embed Perl code in the configuration.  You can access the L<Test::Clustericious::Cluster>
instance from within the configuration using the C<cluster> function, which
can be useful for getting the URL for the your and other service URLs.

 __DATA__
 
 @@ etc/Foo.conf
 ---
 url <%= cluster->url %>
 % # because YAML is (mostly) a super set of JSON you can
 % # convert perl structures into config items using json
 % # function:
 % # (json method requires Clustericious::Config 0.25)
 other_urls: <%= json [ @{ cluster->urls } ] %>

You can also put perl code in the data section of your test file, which
can be useful if there isn't a another good place to put it.  This
example embeds as L<Mojolicious> app "FooApp" and a L<Clustericious::App>
"BarApp" into the test script itself:

 ...
 $cluster->create_cluster_ok('FooApp', 'BarApp');
 ...
 
 __DATA__
 
 @@ lib/FooApp.pm
 package FooApp;
 
 # FooApp is a Mojolicious app
 
 use Mojo::Base qw( Mojolicious );
 
 sub startup
 {
   shift->routes->get('/' => sub { shift->render(text => 'hello there from foo') });
 }
 
 1;
 
 @@ lib/BarApp.pm
 package BarApp;
 
 # BarApp is a Clustericious::App
 
 use strict;
 use warnings;
 use base qw( Clustericious::App );
 
 1;
 
 @@ lib/BarApp/Routes.pm
 package BarApp::Routes;
 
 use strict;
 use warnings;
 use Clustericious::RouteBuilder;
 
 get '/' => sub { shift->render(text => 'hello there from bar') };
 
 1;

These examples are full apps, but you could also use this
feature to implement mocks to test parts of your program
that use resources that aren't easily available during
unit testing, or may change from host to host.  Here is an
example that mocks parts of L<Net::hostent>:

# EXAMPLE: t/mock2.t

=cut

BEGIN { $ENV{MOJO_LOG_LEVEL} = 'fatal' }

=head1 CONSTRUCTOR

=head2 Test::Clustericious::Cluster->new( %args )

Arguments:

=head3 t

The Test::Mojo object to use.
If not provided, then a new one will be created.

=head3 lite_path

List reference of paths to search for L<Mojolicious::Lite>
apps.

=cut

sub new
{
  my $class = shift;
  
  my $args;
  if(ref($_[0]) && eval { $_[0]->isa('Test::Mojo') })
  {
    # undocumented and deprecated
    # you can pass in just an instance of Test::Mojo
    $args = { t => $_[0] };
  }
  else
  {
    $args = ref $_[0] ? { %{ $_[0] } } : {@_};
  }

  my $t = $args->{t} // Test::Mojo->new;
  
  my $builder = __PACKAGE__->builder;
  
  my $sep = $^O eq 'MSWin32' ? ';' : ':';
  my $lite_path = [ split $sep, $ENV{PATH} ];

  $args->{lite_path} //= [];
  unshift @$lite_path, ref($args->{lite_path}) ? @{ $args->{lite_path} } : ($args->{lite_path});
  
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
    lite_path   => $lite_path,
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
application class name.  No configuration is created or passed into
the App.

This can also be the name of a L<Mojolicious::Lite> application.
The PATH environment variable will be used to search for the
lite application.  The script for the lite app must be executable.
You can specify additional directories to search using the
C<lite_path> argument to the constructor.

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

our $inc_hook;

BEGIN {
  unshift @INC, sub {
    my($self, $file) = @_;

    return $inc_hook->($self, $file) if $inc_hook;
   
    state $loader;
    unless(defined $loader)
    {
      $loader = Mojo::Loader->new;
      $loader->load('main');
    }
  
    my $data = $loader->data('main', "lib/$file");
    return unless defined $data;
    open my $fh, '<', \$data;
  
    # fake out %INC because Mojo::Home freeks the heck
    # out when it sees a CODEREF on some platforms
    # in %INC
    my $home = File::HomeDir->my_home;
    mkdir "$home/mojohome" unless -d "$home/mojohome";
    $INC{$file} = "$home/mojohome/$file";
  
    return $fh;
  };
};

sub _add_app_to_ua
{
  my($self, $ua, $url, $app, $index) = @_;
  #use Carp qw( confess );
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

sub _load_lite_app
{
  my($app_path, $script) = @_;
  state $index = 0;
  eval '# line '. __LINE__ . ' "' . __FILE__ . qq("\n) . sprintf(q{
    if(defined $script)
    {
      open my $fh, '>', $app_path;
      print $fh $script;
      close $fh;
    }
    package
      Test::Clustericious::Cluster::LiteApp%s;
    my $app = do $app_path;
    if(!$app && (my $e = $@ || $!)) { die $e }
    $app;
  }, $index++);
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

  local $inc_hook = sub {
    my($self, $file) = @_;
    my $data = $loader->data($caller, "lib/$file");
    return unless defined $data;
    open my $fh, '<', \$data;
    
    # fake out %INC because Mojo::Home freeks the heck
    # out when it sees a CODEREF on some platforms
    # in %INC
    my $home = File::HomeDir->my_home;
    mkdir "$home/mojohome" unless -d "$home/mojohome";
    $INC{$file} = "$home/mojohome/$file";
    
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
        
          state $class;
          
          unless(defined $class)
          {
            if(eval q{ require Clustericious::Config::Helpers; 1})
            {
              $class = 'Clustericious::Config::Helpers';
              push @Clustericious::Config::Helpers::EXPORT, 'cluster';
            }
            else
            {
              require Clustericious::Config::Plugin;
              $class = 'Clustericious::Config::Plugin';
              push @Clustericious::Config::Plugin::EXPORT, 'cluster';
            }
          }
        
          do {
            # there are a multitude of sins here aren't there?
            no warnings 'redefine';
            no warnings 'once';
            no strict 'refs';
            *{join '::', $class, 'cluster'} = $helper;
          };
        }
      }
    }
    else
    {
      $app_name = $item;
    }
    
    my $app;
    
    unless(defined $app)
    {
      if(my $script = $loader->data($caller, "script/$app_name"))
      {
        my $home = File::HomeDir->my_home;
        mkdir "$home/script" unless -d "$home/script";
        $app = _load_lite_app("$home/script/$app_name", $script);
        if(my $error = $@)
        { push @errors, [ $app_name, $error ] }
      }
    }
    
    unless(defined $app)
    {
      foreach my $dir (@{ $self->{lite_path} })
      {
        if(($^O eq 'MSWin32' && -e "$dir/$app_name")
        || (-x "$dir/$app_name"))
        {
          $app = _load_lite_app("$dir/$app_name");
          if(my $error = $@)
          { push @errors, [ $app_name, $error ] }
          last;
        }
      }
    }
    
    unless(defined $app) 
    {
      $app = eval qq{
        use $app_name;
        if($app_name->isa('Clustericious::App'))
        {
          eval { # if they have Clustericious::Log 0.11 or better
            require Test::Clustericious::Log;
            Test::Clustericious::Log->import;
          };
        }
        $app_name->new(\$config);
      };
      if(my $error = $@)
      { push @errors, [ $app_name, $error ] }
    }

    push @{ $self->apps }, $app;
    if(defined $app)
    { $self->_add_app($self->url, $app, $#{ $self->apps }); }
    
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

This feature requires L<PlugAuth::Lite> and L<Clustericious> 
0.9925 or better, though neither are a prerequisite of this
module.  If you are using this method you need to either require
L<PlugAuth::Lite> and L<Clustericious> 0.9925 or better, or skip 
your test in the event that the user has an earlier version. 
For example:

 use strict;
 use warnings;
 use Test::Clustericious::Cluster;
 use Test::More;
 BEGIN {
   plan skip_all => 'test requires Clustericious 0.9925'
     unless eval q{ use Clustericious 0.9925; 1 };
   plan skip_all => 'test requires PlugAuth::Lite'
     unless eval q{ use PlugAuth::Lite; 1 };
 };

=cut

sub create_plugauth_lite_ok
{
  my($self, %args) = @_;
  my $ok = 1;
  my $tb = __PACKAGE__->builder;
  
  if(eval q{ use Clustericious; 1 } && ! eval q{ use Clustericious 0.9925; 1 })
  {
    croak "creat_plugin_lite_ok requires Clustericious 0.9925 or better (see Test::Clustericious::Test for details)";
  }
  
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

=head2 $cluster-E<gt>create_ua

Create a new instance of Mojo::UserAgent which can be used
to connect to nodes in the test cluster.

=cut

sub create_ua
{
  shift->_add_ua;
}

1;
