package Test::mysqld;

use strict;
use warnings;

use Class::Accessor::Lite;
use Cwd;
use File::Temp qw(tempdir);
use POSIX qw(SIGTERM WNOHANG);
use Time::HiRes qw(sleep);

our $VERSION = 0.02;

my %Defaults = (
    auto_start       => 2,
    base_dir         => undef,
    my_cnf           => {},
    mysql_install_db => undef,
    mysqld           => undef,
    pid              => undef,
);

Class::Accessor::Lite->mk_accessors(keys %Defaults);

sub new {
    my $klass = shift;
    my $self = bless {
        %Defaults,
        @_ == 1 ? %{$_[0]} : @_
    }, $klass;
    $self->my_cnf({
        %{$self->my_cnf},
    });
    if (defined $self->base_dir) {
        $self->base_dir(cwd . '/' . $self->base_dir)
            if $self->base_dir !~ m|^/|;
    } else {
        $self->base_dir(
            tempdir(
                CLEANUP => $ENV{TEST_MYSQLD_PRESERVE} ? undef : 1,
            ),
        );
    }
    $self->my_cnf->{socket} ||= $self->base_dir . "/tmp/mysql.sock";
    $self->my_cnf->{datadir} ||= $self->base_dir . "/var";
    $self->my_cnf->{'pid-file'} ||= $self->base_dir . "/tmp/mysqld.pid";
    $self->mysql_install_db(_find_program(qw/mysql_install_db bin scripts/))
        unless $self->mysql_install_db;
    $self->mysqld(_find_program(qw/mysqld bin libexec/))
        unless $self->mysqld;
    die 'mysqld is already running (' . $self->my_cnf->{'pid-file'} . ')'
        if -e $self->my_cnf->{'pid-file'};
    if ($self->auto_start) {
        $self->setup
            if $self->auto_start >= 2;
        $self->start;
    }
    $self;
}

sub DESTROY {
    my $self = shift;
    $self->stop
        if defined $self->pid;
}

sub start {
    my $self = shift;
    return
        if defined $self->pid;
    open my $logfh, '>>', $self->base_dir . '/tmp/mysqld.log'
        or die 'failed to create log file:' . $self->base_dir
            . "/tmp/mysqld.log:$!";
    my $pid = fork;
    die "fork(2) failed:$!"
        unless defined $pid;
    if ($pid == 0) {
        open STDOUT, '>&', $logfh
            or die "dup(2) failed:$!";
        open STDERR, '>&', $logfh
            or die "dup(2) failed:$!";
        exec(
            $self->mysqld,
            '--defaults-file=' . $self->base_dir . '/etc/my.cnf',
            '--user=root',
        );
        die "failed to launch mysqld:$?";
    }
    close $logfh;
    while (! -e $self->my_cnf->{'pid-file'}) {
        if (waitpid($pid, WNOHANG) > 0) {
            die "*** failed to launch mysqld ***\n" . do {
                my $log = '';
                if (open $logfh, '<', $self->base_dir . '/tmp/mysqld.log') {
                    $log = do { local $/; <$logfh> };
                    close $logfh;
                }
                $log;
            };
        }
        sleep 0.1;
    }
    $self->pid($pid);
}

sub stop {
    my ($self, $sig) = @_;
    return
        unless defined $self->pid;
    $sig ||= SIGTERM;
    kill $sig, $self->pid;
    while (waitpid($self->pid, 0) <= 0) {
    }
    $self->pid(undef);
    # might remain for example when sending SIGKILL
    unlink $self->my_cnf->{'pid-file'};
}

sub setup {
    my $self = shift;
    # (re)create directory structure
    mkdir $self->base_dir;
    for my $subdir (qw/etc var tmp/) {
        mkdir $self->base_dir . "/$subdir";
    }
    # my.cnf
    open my $fh, '>', $self->base_dir . '/etc/my.cnf'
        or die "failed to create file:" . $self->base_dir . "/etc/my.cnf:$!";
    print $fh "[mysqld]\n";
    print $fh map {
        my $v = $self->my_cnf->{$_};
        defined $v && length $v
            ? "$_=$v" . "\n"
                : "$_\n";
    } sort keys %{$self->my_cnf};
    close $fh;
    # mysql_install_db
    if (! -d $self->base_dir . '/var/mysql') {
        open(
            $fh,
            '-|',
            $self->mysql_install_db . " --defaults-file='" . $self->base_dir
                . "/etc/my.cnf' 2>&1",
        ) or die "failed to spawn mysql_install_db:$!";
        my $output = do { undef $/; join "", join "\n", <$fh> };
        close $fh
            or die "*** mysql_install_db failed ***\n$output\n";
    }
}

sub _find_program {
    my ($prog, @subdirs) = @_;
    my $path = _get_path_of($prog);
    return $path
        if $path;
    for my $mysql (_get_path_of('mysql'), qw(/usr/local/mysql/bin/mysql)) {
        if (-x $mysql) {
            for my $subdir (@subdirs) {
                $path = $mysql;
                if ($path =~ s|/bin/mysql$|/$subdir/$prog|
                        and -x $path) {
                    return $path;
                }
            }
        }
    }
    die "could not find $prog";
}

sub _get_path_of {
    my $prog = shift;
    my $path = `which $prog 2> /dev/null`;
    chomp $path
        if $path;
    $path;
}

1;
__END__

=head1 NAME

Test::mysqld - mysqld runner for tests

=head1 SYNOPSIS

  use DBI;
  use Test::mysqld;
  
  my $mysqld = Test::mysqld->new(
    my_cnf => {
      'skip-networking' => '', # no TCP socket
    }
  );
  my $dbh = DBI->connect(
    "DBI:mysql:...;mysql_socket=" . $mysqld->base_dir . "/tmp/mysql.sock",
    ...
  );

=head1 DESCRIPTION

C<Test::mysqld> automatically setups a mysqld instance in a temporary directory, and destroys it when the perl script exits.

=head1 FUNCTIONS

=head2 new

Create and run a mysqld instance.  The instance is terminated when the returned object is being DESTROYed.

=head2 base_dir

Returns directory under which the mysqld instance is being created.  The property can be set as a parameter of the C<new> function, in which case the directory will not be removed at exit.

=head2 my_cnf

A hash containing the list of name=value pairs to be written into my.cnf.  The property can be set as a parameter of the C<new> function.

=head2 mysql_install_db

=head2 mysqld

Path to C<mysql_install_db> script or C<mysqld> program bundled to the mysqld distribution.  If not set, the program is automatically search by looking up $PATH and other prefixed directories.

=head2 pid

Returns process id of mysqld (or undef if not running).

=head2 start

Starts mysqld.

=head2 stop

Stops mysqld.

=head2 setup

Setups the mysqld instance.

=head1 COPYRIGHT

Copyright (C) 2009 Cybozu Labs, Inc.  Written by Kazuho Oku.

=head1 LICENSE

This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
