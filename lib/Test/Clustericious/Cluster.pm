package Test::Clustericious::Cluster;

use strict;
use warnings;
use 5.010001;

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
use Carp qw( croak carp );
use File::Basename ();
use File::Path ();

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
 url: <%= cluster->url %>
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

=head2 new

 my $cluster = Test::Clustericious::Cluster->new( %args )

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
  
  my $sep = $^O eq 'MSWin32' ? ';' : ':';
  my $lite_path = [ split $sep, $ENV{PATH} ];

  $args->{lite_path} //= [];
  unshift @$lite_path, ref($args->{lite_path}) ? @{ $args->{lite_path} } : ($args->{lite_path});
  
  bless { 
    t           => $t, 
    urls        => [], 
    apps        => [], 
    stopped     => [],
    index       => -1,
    url         => '', 
    servers     => [],
    app_servers => [],
    auth_url    => '',
    extra_ua    => [$t->ua],
    lite_path   => $lite_path,
  }, $class;
}

=head1 ATTRIBUTES

=head2 t

 my $t = $cluster->t;

The instance of Test::Mojo used in testing.

=cut

sub t { shift->{t} }

=head2 urls

 my @urls = @{ $cluster->urls };

The URLs for the various services.
Returned as an array ref.

=cut

sub urls { shift->{urls} }

=head2 apps

 my @apps = @{ $cluster->apps };

The application objects for the various services.
Returned as an array ref.

=cut

sub apps { shift->{apps} }

=head2 index

 my $index = $cluster->index;

The index of the current app (used from within a 
L<Clustericious::Config> configuration.

=cut

sub index { shift->{index} }

=head2 url

 my $url = $cluster->url;

The url of the current app (used from within a
L<Clustericious::Config> configuration.

=cut

sub url { shift->{url} }

=head2 auth_url

 my $url = $cluster->auth_url;

The URL for the PlugAuth::Lite service, if one has been started.

=cut

sub auth_url { shift->{auth_url} }

=head1 METHODS

=head2 create_cluster_ok

 $cluster->create_cluster_ok( @services )

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

This can also be a PSGI application.  In this case it needs to be
in the C<__DATA__> section of your test and it must have a name
in the form C<script/app.psgi>.  This also requires
L<Mojolicious::Plugin::MountPSGI> already be installed so if you
use this feature make sure you declare that as a prereq.

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

BEGIN {
  # TODO
  # so we muck with this @INC in two places.  Here we do it so
  # that you can use_ok files in your .t file.  Later we do 
  # extract files in create_cluster_ok and add ~/lib to the @INC
  # path so that we can load as regular files.  This is more
  # reliable for anything that expects a real live file, and we'd
  # like to do that for use_ok as well in the future.

  unshift @INC, sub {
    my($self, $file) = @_;

    # avoid deep recursion
    state $first;
    Mojo::Loader::load_class('main') unless $first++;
  
    my $data = Mojo::Loader::data_section('main', "lib/$file");
    return unless defined $data;
    
    # This will make the file really there.
    # Some stuff depends on that
    __PACKAGE__->extract_data_section("lib/$file", 'main');

    open my $fh, '<', \$data;
  
    # fake out %INC because Mojo::Home freeks the heck
    # out when it sees a CODEREF on some platforms
    # in %INC
    my $home = File::HomeDir->my_home;
    mkdir "$home/lib" unless -d "$home/lib";
    $INC{$file} = "$home/lib/$file";
  
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
    my $stopped = $self->{stopped}->[$i];
    next if $stopped;
    $self->_add_app_to_ua($ua, $self->{urls}->[$i], $self->{apps}->[$i], $i);
  }
  push @{ $self->{extra_ua} }, $ua;
  return $ua;
}

sub _load_lite_app
{
  my($app_path, $script) = @_;
  local @ARGV = ( eval => 'app');
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

sub _generate_port
{
  require IO::Socket::INET;
  IO::Socket::INET->new(
    Listen => 5, 
    LocalAddr => '127.0.0.1',
  )->sockport;
}

sub create_cluster_ok
{
  my $self = shift;
  
  my $total = scalar @_;
  my @urls = map { 
    my $url = Mojo::URL->new("http://127.0.0.1");
    $url->port(_generate_port);
    $url } (0..$total);

  push @{ $self->{urls} }, @urls;
  
  my @errors;
  
  my $has_clustericious_config = 0;
  
  my $caller = caller;
  Mojo::Loader::load_class($caller);

  local @INC = @INC;
  $self->extract_data_section(qr{^lib/}, $caller);
  my $home = File::HomeDir->my_home;
  unshift @INC, "$home/lib"
    if -d "$home/lib";

  foreach my $i (0..$#_)
  {
    $self->{index}++;
    $self->{url} = shift @urls;
    
    my $app_name;
    my $cb;
    my $config = {};
    my $item = $_[$i];
    if(ref($item) eq '' && Mojo::Loader::data_section($caller, "etc/$item.conf"))
    {
      $item = [ $item, Mojo::Loader::data_section($caller, "etc/$item.conf") ];
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
    # we want to try to load class first, so that YourApp.pm
    # will be picked over lite app yourapp on MSWin32 
    # (which is case insensative).  So we save the error
    # (from $@) and only push it onto the @errors list
    # if loading as a lite app also fails.
    my $first_try_error;
    
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
      $first_try_error = $@;
    }

    unless(defined $app)
    {
      if(my $script = Mojo::Loader::data_section($caller, "script/$app_name"))
      {
        my $home = File::HomeDir->my_home;
        mkdir "$home/script" unless -d "$home/script";
        $app = _load_lite_app("$home/script/$app_name", $script);
        if(my $error = $@)
        { push @errors, [ $app_name, $error ] }
      }
      
      if(my $script = Mojo::Loader::data_section($caller, "script/$app_name.psgi"))
      {
        my $home = File::HomeDir->my_home;
        require Mojolicious;
        require Mojolicious::Plugin::MountPSGI;
        $app = Mojolicious->new;
        # TODO: check syntax of .psgi file?
        $self->extract_data_section("script/$app_name.psgi", $caller);
        $app->plugin('Mojolicious::Plugin::MountPSGI' => { '/' => "$home/script/$app_name.psgi" });
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
      push @errors, [ $app_name, $first_try_error ]
        if $first_try_error;
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
  
  if($INC{'Clustericious/App.pm'})
  {
    eval { require Clustericious::Client };
    if(!$@ && Clustericious::Client->can('_mojo_user_agent_factory'))
    {
      Clustericious::Client->_mojo_user_agent_factory(sub {
        $self->create_ua;
      });
    }
  }
  
  return $self;
}

=head2 create_plugauth_lite_ok

 $cluster->create_plugauth_lite_ok( %args )

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
     unless eval q{ use Clustericious 1.00; 1 };
   plan skip_all => 'test requires PlugAuth::Lite'
     unless eval q{ use PlugAuth::Lite 0.30; 1 };
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
    $url->port(_generate_port);
  
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

=head2 stop_ok

 $cluster->stop_ok( $index );
 $cluster->stop_ok( $index, $test_name);

Stop the given service.  The service is specified by 
an index, the first application when you created the
cluster is 0, the second is 1, and so on.

See L<CAVEATS|Test::Clustericious::Cluster#CAVEATS>
below on interactions with IPv6 or TLS/SSL.

=cut

sub stop_ok
{
  my($self, $index, $test_name) = @_;
  my $ok = 1;
  my $tb = __PACKAGE__->builder;
  
  my $error;
  
  my $app = $self->apps->[$index];
  if(defined $app)
  {
    my $app_name = ref $app;
    $test_name //= "stop service $app_name ($index)";
    $_->stop for @{ $self->{app_servers}->[$index] };
    eval { @{ $self->{app_servers}->[$index] } = () };
    $error = $@;
    $ok = 0 if $error;
  }
  else
  {
    $tb->diag("no such app for index: $index");
    $ok = 0;
  }
  
  $self->{stopped}->[$index] = 1 if $ok;
  
  $test_name //= "stop service ($index)";
  
  my $ret = $tb->ok($ok, $test_name);
  
  $tb->diag($error) if $error;
  
  $ret;
}

=head2 start_ok

  $cluster->start_ok( $index );
  $cluster->start_ok( $index, $test_name );

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
  
  $self->{stopped}->[$index] = 0 if $ok;

  $test_name //= "start service ($index)";
  
  $tb->ok($ok, $test_name);
}

=head2 is_stopped

 $cluster->is_stopped( $index );
 $cluster->is_stopped( $index, $test_name );

Passes if the given service is stopped.

=cut

sub is_stopped
{
  my($self, $index, $test_name) = @_;
  
  my $ok = !!$self->{stopped}->[$index];
  
  $test_name //= "servers ($index) is stopped";
  
  my $tb = __PACKAGE__->builder;
  $tb->ok($ok, $test_name);
}

=head2 isnt_stopped

 $cluster->isnt_stopped( $index );
 $cluster->isnt_stopped( $index, $test_name );

Passes if the given service is not stopped.

=cut

sub isnt_stopped
{
  my($self, $index, $test_name) = @_;
  
  my $ok = !$self->{stopped}->[$index];
  
  $test_name //= "servers ($index) is not stopped";
  
  my $tb = __PACKAGE__->builder;
  $tb->ok($ok, $test_name);
}

=head2 create_ua

 my $ua = $cluster->create_ua;

Create a new instance of Mojo::UserAgent which can be used
to connect to nodes in the test cluster.

=cut

sub create_ua
{
  shift->_add_ua;
}

=head2 extract_data_section

 $cluster->extract_data_section($regex);
 Test::Clustericious::Cluster->extract_data_section($regex);

Extract the files from the data section of the current package
that match the given regex.  C<$regex> can also be a plain
string for an exact filename match.

=cut

sub extract_data_section
{
  my($class, $regex, $caller) = @_;

  $regex //= qr{};
  
  unless(ref $regex eq 'Regexp')
  {
    $regex = quotemeta $regex;
    $regex = qr{^$regex$};
  }
  
  $caller //= caller;
  my $all = Mojo::Loader::data_section $caller;
  my $home = File::HomeDir->my_home;
  my $tb = __PACKAGE__->builder;

  foreach my $name (keys %$all)
  {
    use autodie;
    next unless $name =~ $regex;
    my $basename = File::Basename::basename $name;
    my $dir      = File::Basename::dirname  $name;

    unless(-d "$home/$dir")
    {
      $tb->note("[extract] DIR  $home/$dir");
      File::Path::mkpath "$home/$dir", 0, 0700;
    }
    unless(-f "$home/$dir/$basename")
    {
      $tb->note("[extract] FILE $home/$dir/$basename");
      open my $fh, '>', "$home/$dir/$basename";
      print $fh $all->{$name};
      close $fh;
    }
  }
  
  $class;
}

1;

=head1 CAVEATS

Some combination of Mojolicious, FreeBSD, IPv6 and TLS/SSL
seem to react badly to the use of 
L<stop_ok|Test::Clustericious::Cluster#stop_ok>.  The work
around is to turn IPv6 and TLS/SSL off in the beginning
of any tests that uses stop_ok your test like thus:

 use strict;
 use warnings;
 BEGIN { $ENV{MOJO_NO_IPV6} = 1; $ENV{MOJO_NO_TLS} = 1; }
 use Test::Clustericious::Cluster;

A proper fix would be desirable, see 

https://github.com/plicease/Test-Clustericious-Cluster/issues/3

If you want to help.

=cut
