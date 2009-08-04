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

plan tests => 2;

my $base_dir;
{
    my $mysqld = Test::mysqld->new(
        my_cnf => {
            'skip-networking' => '',
        },
    );
    $base_dir = $mysqld->base_dir;
    my $dbh = DBI->connect(
        "DBI:mysql:test;mysql_socket=$base_dir/tmp/mysql.sock;user=root",
    );
    ok($dbh, 'connect to mysqld');
}
sleep 1; # just in case
ok(! -e "$base_dir/tmp/mysql.sock", "mysqld is down");
