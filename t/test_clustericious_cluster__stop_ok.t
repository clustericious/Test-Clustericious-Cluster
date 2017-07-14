use Test2::V0 -no_srand => 1;
use Test::Clustericious::Cluster;

# test stop_ok start_ok is_stopped isnt_stopped

my $cluster = Test::Clustericious::Cluster->new;
$cluster->create_cluster_ok(qw( Foo Bar ));

is(
  intercept { $cluster->isnt_stopped(0) },
  array {
    event Ok => sub {
      call pass => T();
      call name => 'servers (0) is not stopped';
    };
    end;
  },
  'isnt_stopped (good)',
);

is(
  intercept { $cluster->is_stopped(0) },
  array {
    event Ok => sub {
      call pass => F();
      call name => 'servers (0) is stopped';
    };
    event Diag => sub {
      # generated by TB / T2
    };
    end;
  },
  'is_stopped (bad)',
);

todo "out of bounds testing" => sub {

  is(
    intercept { $cluster->isnt_stopped(4) },
    array {
      event Ok => sub {
        call pass => F();
      };
      # TODO: test diagnostic also
    },
    'isnt_stopped fails with out of bound server',
  );

  is(
    intercept { $cluster->is_stopped(4) },
    array {
      event Ok => sub {
        call pass => F();
      };
      # TODO: test diagnostic also
      etc();
    },
    'is_stopped fails with out of bound server',
  );

};

is(
  intercept { $cluster->stop_ok(0) },
  array {
    event Ok => sub {
      call pass => T();
      call name => 'stop service Foo (0)';
    };
    end;
  },
  'stop_ok(0)',
);

is(
  intercept { $cluster->is_stopped(0) },
  array {
    event Ok => sub {
      call pass => T();
      call name => 'servers (0) is stopped';
    };
    end;
  },
  'is_stopped (good)',
);

is(
  intercept { $cluster->isnt_stopped(0) },
  array {
    event Ok => sub {
      call pass => F();
      call name => 'servers (0) is not stopped';
    };
    event Diag => sub {
      # generated by TB / T2
    };
    end;
  },
  'isnt_stopped (bad)',
);

$cluster->is_stopped(0);
$cluster->isnt_stopped(1);

is(
  intercept { $cluster->stop_ok(0) },
  array {
    event Ok => sub {
      call pass => T();
      call name => 'stop service Foo (0)';
    };
    end;
  },
  'stop again',
);

$cluster->is_stopped(0);
$cluster->isnt_stopped(1);

is(
  intercept { $cluster->start_ok(0) },
  array {
    event Ok => sub {
      call pass => T();
      call name => 'start service Foo (0)';
    };
    end;
  },
  'start_ok(0)',
);

$cluster->isnt_stopped(0);
$cluster->isnt_stopped(1);

is(
  intercept { $cluster->start_ok(0) },
  array {
    event Ok => sub {
      call pass => T();
      call name => 'start service Foo (0)';
    };
    end;
  },
  'start again',
);

$cluster->isnt_stopped(0);
$cluster->isnt_stopped(1);

is(
  intercept { $cluster->start_ok(4) },
  array {
    event Ok => sub {
      call pass => F();
      call name => 'start service (4)';
    };
    event Diag => sub {
        # generated by TB / T2
    };
    event Diag => sub {
      call message => 'no such app for index: 4';
    };
    end;
  },
  'start_ok bad index',
);


is(
  intercept { $cluster->stop_ok(4) },
  array {
    event Ok => sub {
      call pass => F();
      call name => 'stop service (4)';
    };
    event Diag => sub {
        # generated by TB / T2
    };
    event Diag => sub {
      call message => 'no such app for index: 4';
    };
    end;
  },
  'start_ok bad index',
);

done_testing;

__DATA__

@@ lib/Foo.pm
package Foo;

use strict;
use warnings;
use Mojo::Base qw( Mojolicious );

sub startup
{
  my $self = shift;
  $self->routes->get('/' => sub {
    shift->render(text => "Foo");
  });
}

1;

@@ lib/Bar.pm
package Bar;

use strict;
use warnings;
use Mojo::Base qw( Mojolicious );

sub startup
{
  my $self = shift;
  $self->routes->get('/' => sub {
    shift->render(text => "Bar");
  });
}

1;
