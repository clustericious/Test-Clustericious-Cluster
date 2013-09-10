# Test::Clustericious::Cluster [![Build Status](https://secure.travis-ci.org/plicease/Test-Clustericious-Cluster.png)](http://travis-ci.org/plicease/Test-Clustericious-Cluster)

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
    url <%= cluster->url %>
    url_for_my_app2: <%= cluster->urls->[1] %>

# DESCRIPTION

This module allows you to test an entire cluster of Clustericious services
(or just one or two).  The only prerequisites are [Mojolicious](http://search.cpan.org/perldoc?Mojolicious) and 
[File::HomeDir](http://search.cpan.org/perldoc?File::HomeDir), so you can mix and match [Mojolicious](http://search.cpan.org/perldoc?Mojolicious), [Mojolicious::Lite](http://search.cpan.org/perldoc?Mojolicious::Lite)
and full [Clustericious](http://search.cpan.org/perldoc?Clustericious) apps and test how they interact.

If you are testing against Clustericious applications, it is important to
either use this module as early as possible, or use [File::HomeDir::Test](http://search.cpan.org/perldoc?File::HomeDir::Test)
as the very first module in your test, as testing Clustericious configurations
depend on the testing home directory being setup by [File::HomeDir::Test](http://search.cpan.org/perldoc?File::HomeDir::Test).

In addition to passing [Clustericious](http://search.cpan.org/perldoc?Clustericious) configurations into the
`create_cluster_ok` method as describe below, you can include configuration
in the data section of your test script.  The configuration files use 
[Clustericious::Config](http://search.cpan.org/perldoc?Clustericious::Config), so you can use [Mojo::Template](http://search.cpan.org/perldoc?Mojo::Template) directives to 
embed Perl code in the configuration.  You can access the [Test::Clustericious::Cluster](http://search.cpan.org/perldoc?Test::Clustericious::Cluster)
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
example embeds as [Mojolicious](http://search.cpan.org/perldoc?Mojolicious) app "FooApp" and a [Clustericious::App](http://search.cpan.org/perldoc?Clustericious::App)
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
example that mocks parts of [Net::hostent](http://search.cpan.org/perldoc?Net::hostent):

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

## Test::Clustericious::Cluster->new( %args )

Arguments:

### t

The Test::Mojo object to use.
If not provided, then a new one will be created.

### lite\_path

List reference of paths to search for [Mojolicious::Lite](http://search.cpan.org/perldoc?Mojolicious::Lite)
apps.

# ATTRIBUTES

## t

The instance of Test::Mojo used in testing.

## urls

The URLs for the various services.
Returned as an array ref.

## apps

The application objects for the various services.
Returned as an array ref.

## index

The index of the current app (used from within a 
[Clustericious::Config](http://search.cpan.org/perldoc?Clustericious::Config) configuration.

## url

The url of the current app (used from within a
[Clustericious::Config](http://search.cpan.org/perldoc?Clustericious::Config) configuration.

## auth\_url

The URL for the PlugAuth::Lite service, if one has been started.

# METHODS

## $cluster->create\_cluster\_ok( @services )

Adds the given services to the test cluster.
Each element in the services array may be either

- string

    The string is taken to be the [Mojolicious](http://search.cpan.org/perldoc?Mojolicious) or [Clustericious](http://search.cpan.org/perldoc?Clustericious)
    application class name.  No configuration is created or passed into
    the App.

    This can also be the name of a [Mojolicious::Lite](http://search.cpan.org/perldoc?Mojolicious::Lite) application.
    The PATH environment variable will be used to search for the
    lite application.  The script for the lite app must be executable.
    You can specify additional directories to search using the
    `lite_path` argument to the constructor.

- list reference in the form: \[ string, hashref \]

    The string is taken to be the [Mojolicious](http://search.cpan.org/perldoc?Mojolicious) application name.
    The hashref is the configuration passed into the constructor
    of the app.  This form should NOT be used for [Clustericious](http://search.cpan.org/perldoc?Clustericious)
    apps (see the third form).

- list reference in the form: \[ string, string \]

    The first string is taken to be the [Clustericious](http://search.cpan.org/perldoc?Clustericious) application
    name.  The second string is the configuration in either YAML
    or JSON format (may include [Mojo::Template](http://search.cpan.org/perldoc?Mojo::Template) templating in it,
    see [Clustericious::Config](http://search.cpan.org/perldoc?Clustericious::Config) for details).  This form requires
    that you have [Clustericous](http://search.cpan.org/perldoc?Clustericous) installed, and of course should
    not be used for non-[Clustericious](http://search.cpan.org/perldoc?Clustericious) [Mojolicious](http://search.cpan.org/perldoc?Mojolicious) applications.

## $cluster->create\_plugauth\_lite\_ok( %args )

Add a [PlugAuth::Lite](http://search.cpan.org/perldoc?PlugAuth::Lite) service to the test cluster.  The
`%args` are passed directly into the [PlugAuth::Lite](http://search.cpan.org/perldoc?PlugAuth::Lite)
constructor.

You can retrieve the URL for the [PlugAuth::Lite](http://search.cpan.org/perldoc?PlugAuth::Lite) service
using the `auth_url` attribute.

This feature requires [PlugAuth::Lite](http://search.cpan.org/perldoc?PlugAuth::Lite) and [Clustericious](http://search.cpan.org/perldoc?Clustericious) 
0.9925 or better, though neither are a prerequisite of this
module.  If you are using this method you need to either require
[PlugAuth::Lite](http://search.cpan.org/perldoc?PlugAuth::Lite) and [Clustericious](http://search.cpan.org/perldoc?Clustericious) 0.9925 or better, or skip 
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

## $cluster->stop\_ok( $index, \[ $test\_name \])

Stop the given service.  The service is specified by 
an index, the first application when you created the
cluster is 0, the second is 1, and so on.

## $cluster->start\_ok( $index, \[ $test\_name \] )

Start the given service.  The service is specified by 
an index, the first application when you created the
cluster is 0, the second is 1, and so on.

## $cluster->create\_ua

Create a new instance of Mojo::UserAgent which can be used
to connect to nodes in the test cluster.

# AUTHOR

Graham Ollis <plicease@cpan.org>

# COPYRIGHT AND LICENSE

This software is copyright (c) 2013 by Graham Ollis.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
