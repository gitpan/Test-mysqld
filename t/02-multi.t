use strict;
use warnings;

use DBI;
use Test::More;
use Test::mysqld;

{ # look for required progs, or skip all
    local $@;
    eval {
        Test::mysqld::_find_program(qw/mysql_install_db bin scripts/);
    };
    if ($@) {
        plan skip_all => 'could not find mysql_install_db';
    }
    eval {
        Test::mysqld::_find_program(qw/mysqld bin libexec/);
    };
    if ($@) {
        plan skip_all => 'could not find mysqld';
    }
}

plan tests => 3;

my @mysqld = map {
    my $mysqld = Test::mysqld->new(
        my_cnf => {
            'skip-networking' => '',
        },
    );
    ok($mysqld);
    $mysqld;
} 0..1;
is(scalar @mysqld, 2);
