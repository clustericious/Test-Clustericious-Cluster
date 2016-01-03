# Test::Clustericious::Cluster [![Build Status](https://secure.travis-ci.org/clustericious/Test-Clustericious-Cluster.png)](http://travis-ci.org/clustericious/Test-Clustericious-Cluster)

Test an imaginary beowulf cluster of Clustericious services

# SYNOPSIS

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

# DESCRIPTION

This module allows you to test an entire cluster of Clustericious services
(or just one or two).  The only prerequisites are [Mojolicious](https://metacpan.org/pod/Mojolicious) and 
[File::HomeDir](https://metacpan.org/pod/File::HomeDir), so you can mix and match [Mojolicious](https://metacpan.org/pod/Mojolicious), [Mojolicious::Lite](https://metacpan.org/pod/Mojolicious::Lite)
and full [Clustericious](https://metacpan.org/pod/Clustericious) apps and test how they interact.

If you are testing against Clustericious applications, it is important to
either use this module as early as possible, or use [File::HomeDir::Test](https://metacpan.org/pod/File::HomeDir::Test)
as the very first module in your test, as testing Clustericious configurations
depend on the testing home directory being setup by [File::HomeDir::Test](https://metacpan.org/pod/File::HomeDir::Test).

In addition to passing [Clustericious](https://metacpan.org/pod/Clustericious) configurations into the
`create_cluster_ok` method as describe below, you can include configuration
in the data section of your test script.  The configuration files use 
[Clustericious::Config](https://metacpan.org/pod/Clustericious::Config), so you can use [Mojo::Template](https://metacpan.org/pod/Mojo::Template) directives to 
embed Perl code in the configuration.  You can access the [Test::Clustericious::Cluster](https://metacpan.org/pod/Test::Clustericious::Cluster)
instance from within the configuration using the `cluster` function, which
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
example embeds as [Mojolicious](https://metacpan.org/pod/Mojolicious) app "FooApp" and a [Clustericious::App](https://metacpan.org/pod/Clustericious::App)
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
example that mocks parts of [Net::hostent](https://metacpan.org/pod/Net::hostent):

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

# CONSTRUCTOR

## new

    my $cluster = Test::Clustericious::Cluster->new( %args )

Arguments:

### t

The Test::Mojo object to use.
If not provided, then a new one will be created.

### lite\_path

List reference of paths to search for [Mojolicious::Lite](https://metacpan.org/pod/Mojolicious::Lite)
apps.

# ATTRIBUTES

## t

    my $t = $cluster->t;

The instance of Test::Mojo used in testing.

## urls

    my @urls = @{ $cluster->urls };

The URLs for the various services.
Returned as an array ref.

## apps

    my @apps = @{ $cluster->apps };

The application objects for the various services.
Returned as an array ref.

## index

    my $index = $cluster->index;

The index of the current app (used from within a 
[Clustericious::Config](https://metacpan.org/pod/Clustericious::Config) configuration.

## url

    my $url = $cluster->url;

The url of the current app (used from within a
[Clustericious::Config](https://metacpan.org/pod/Clustericious::Config) configuration.

## auth\_url

    my $url = $cluster->auth_url;

The URL for the PlugAuth::Lite service, if one has been started.

# METHODS

## create\_cluster\_ok

    $cluster->create_cluster_ok( @services )

Adds the given services to the test cluster.
Each element in the services array may be either

- string

    The string is taken to be the [Mojolicious](https://metacpan.org/pod/Mojolicious) or [Clustericious](https://metacpan.org/pod/Clustericious)
    application class name.  No configuration is created or passed into
    the App.

    This can also be the name of a [Mojolicious::Lite](https://metacpan.org/pod/Mojolicious::Lite) application.
    The PATH environment variable will be used to search for the
    lite application.  The script for the lite app must be executable.
    You can specify additional directories to search using the
    `lite_path` argument to the constructor.

    This can also be a PSGI application.  In this case it needs to be
    in the `__DATA__` section of your test and it must have a name
    in the form `script/app.psgi`.  This also requires
    [Mojolicious::Plugin::MountPSGI](https://metacpan.org/pod/Mojolicious::Plugin::MountPSGI) already be installed so if you
    use this feature make sure you declare that as a prereq.

- list reference in the form: \[ string, hashref \]

    The string is taken to be the [Mojolicious](https://metacpan.org/pod/Mojolicious) application name.
    The hashref is the configuration passed into the constructor
    of the app.  This form should NOT be used for [Clustericious](https://metacpan.org/pod/Clustericious)
    apps (see the third form).

- list reference in the form: \[ string, string \]

    The first string is taken to be the [Clustericious](https://metacpan.org/pod/Clustericious) application
    name.  The second string is the configuration in either YAML
    or JSON format (may include [Mojo::Template](https://metacpan.org/pod/Mojo::Template) templating in it,
    see [Clustericious::Config](https://metacpan.org/pod/Clustericious::Config) for details).  This form requires
    that you have [Clustericous](https://metacpan.org/pod/Clustericous) installed, and of course should
    not be used for non-[Clustericious](https://metacpan.org/pod/Clustericious) [Mojolicious](https://metacpan.org/pod/Mojolicious) applications.

## create\_plugauth\_lite\_ok

    $cluster->create_plugauth_lite_ok( %args )

Add a [PlugAuth::Lite](https://metacpan.org/pod/PlugAuth::Lite) service to the test cluster.  The
`%args` are passed directly into the [PlugAuth::Lite](https://metacpan.org/pod/PlugAuth::Lite)
constructor.

You can retrieve the URL for the [PlugAuth::Lite](https://metacpan.org/pod/PlugAuth::Lite) service
using the `auth_url` attribute.

This feature requires [PlugAuth::Lite](https://metacpan.org/pod/PlugAuth::Lite) and [Clustericious](https://metacpan.org/pod/Clustericious) 
0.9925 or better, though neither are a prerequisite of this
module.  If you are using this method you need to either require
[PlugAuth::Lite](https://metacpan.org/pod/PlugAuth::Lite) and [Clustericious](https://metacpan.org/pod/Clustericious) 0.9925 or better, or skip 
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

## stop\_ok

    $cluster->stop_ok( $index );
    $cluster->stop_ok( $index, $test_name);

Stop the given service.  The service is specified by 
an index, the first application when you created the
cluster is 0, the second is 1, and so on.

See [CAVEATS](https://metacpan.org/pod/Test::Clustericious::Cluster#CAVEATS)
below on interactions with IPv6 or TLS/SSL.

## start\_ok

    $cluster->start_ok( $index );
    $cluster->start_ok( $index, $test_name );

Start the given service.  The service is specified by 
an index, the first application when you created the
cluster is 0, the second is 1, and so on.

## is\_stopped

    $cluster->is_stopped( $index );
    $cluster->is_stopped( $index, $test_name );

Passes if the given service is stopped.

## isnt\_stopped

    $cluster->isnt_stopped( $index );
    $cluster->isnt_stopped( $index, $test_name );

Passes if the given service is not stopped.

## create\_ua

    my $ua = $cluster->create_ua;

Create a new instance of Mojo::UserAgent which can be used
to connect to nodes in the test cluster.

## extract\_data\_section

    $cluster->extract_data_section($regex);
    Test::Clustericious::Cluster->extract_data_section($regex);

Extract the files from the data section of the current package
that match the given regex.  `$regex` can also be a plain
string for an exact filename match.

## client

    my $client = $cluster->client($n);

Return a [Clustericious::Client](https://metacpan.org/pod/Clustericious::Client) object for use with the `$n`th
service in the cluster.  If there is a corresponding `YourService::Client`
class then it will be used.  Otherwise you will get a generic
[Clustericious::Client](https://metacpan.org/pod/Clustericious::Client) object with the correct URL configured.

This method only works with [Clustericious](https://metacpan.org/pod/Clustericious) services.

# CAVEATS

Some combination of Mojolicious, FreeBSD, IPv6 and TLS/SSL
seem to react badly to the use of 
[stop\_ok](https://metacpan.org/pod/Test::Clustericious::Cluster#stop_ok).  The work
around is to turn IPv6 and TLS/SSL off in the beginning
of any tests that uses stop\_ok your test like thus:

    use strict;
    use warnings;
    BEGIN { $ENV{MOJO_NO_IPV6} = 1; $ENV{MOJO_NO_TLS} = 1; }
    use Test::Clustericious::Cluster;

A proper fix would be desirable, see 

https://github.com/plicease/Test-Clustericious-Cluster/issues/3

If you want to help.

# AUTHOR

Graham Ollis &lt;plicease@cpan.org>

# COPYRIGHT AND LICENSE

This software is copyright (c) 2013 by Graham Ollis.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
