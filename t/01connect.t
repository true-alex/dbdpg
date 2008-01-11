#!perl -w

# Make sure we can connect and disconnect cleanly
# All tests are stopped if we cannot make the first connect

use Test::More;
use DBI;
use strict;
select((select(STDERR),$|=1)[0]);
$|=1;

## Define this here in case we get to the END block before a connection is made.
my ($pgversion,$pglibversion,$pgvstring,$pgdefport) = ('?','?','?','?');

my $bail = 0;
if (defined $ENV{DBI_DSN}) {
	plan tests => 15;
} else {
	BAIL_OUT "DBI_DSN must be set";
}

# Trapping a connection error can be tricky, but we only have to do it 
# this thoroughly one time. We are trapping two classes of errors:
# the first is when we truly do not connect, usually a bad DBI_DSN;
# the second is an invalid login, usually a bad DBI_USER or DBI_PASS

my ($dbh,$t);
eval {
	$dbh = DBI->connect($ENV{DBI_DSN}, $ENV{DBI_USER}, $ENV{DBI_PASS},
											{RaiseError => 1, PrintError => 0, AutoCommit => 0});
};
if ($@) {
	if (! $DBI::errstr) {
		print STDOUT "Bail out! Could not connect: $@\n";
	}
	else {
		print STDOUT "Bail out! Could not connect: $DBI::errstr\n";
	}
	exit; # Force a hasty exit
}

pass('Established a connection to the database');

$pgversion = $dbh->{pg_server_version};
$pglibversion = $dbh->{pg_lib_version};
$pgdefport = $dbh->{pg_default_port};
$pgvstring = $dbh->selectall_arrayref("SELECT VERSION();")->[0][0];

ok( $dbh->disconnect(), 'Disconnect from the database');

# Connect two times. From this point onward, do a simpler connection check
ok( $dbh = DBI->connect($ENV{DBI_DSN}, $ENV{DBI_USER}, $ENV{DBI_PASS},
												{RaiseError => 1, PrintError => 0, AutoCommit => 0}),
		'Connected with first database handle');

my $dbh2;
ok( $dbh2 = DBI->connect($ENV{DBI_DSN}, $ENV{DBI_USER}, $ENV{DBI_PASS},
												 {RaiseError => 1, PrintError => 0, AutoCommit => 0}),
		'Connected with second database handle');

my $sth = $dbh->prepare('SELECT 123');
ok ( $dbh->disconnect(), 'Disconnect with first database handle');
ok ( $dbh2->disconnect(), 'Disconnect with second database handle');
ok ( $dbh2->disconnect(), 'Disconnect again with second database handle');

eval {
 $sth->execute();
};
ok( $@, 'Execute fails on a disconnected statement');

# Try out various connection options
SKIP: {
	my $alias = qr{(database|db|dbname)};
	if ($ENV{DBI_DSN} !~ /$alias\s*=\s*\S+/) {
		skip "DBI_DSN contains no database option, so skipping connection tests", 4;
	}

	$t=q{Connect with invalid option fails};
	my $oldname = $1;
	(my $dbi = $ENV{DBI_DSN}) =~ s/$alias\s*=/dbbarf=/;
	eval {
		$dbh = DBI->connect($dbi, $ENV{DBI_USER}, $ENV{DBI_PASS}, {RaiseError=>1});
	};
	like ($@, qr{invalid connection option}, $t);
	for my $opt (qw/db dbname database/) {
		$t=qq{Connect using string '$opt' works};
		($dbi = $ENV{DBI_DSN}) =~ s/$alias\s*=/$opt=/;
		eval {
			$dbh = DBI->connect($dbi, $ENV{DBI_USER}, $ENV{DBI_PASS}, {RaiseError=>1});
		};
		is($@, q{}, $t);
	}

	if ($ENV{DBI_DSN} =~ /$alias\s*=\s*"/) {
		skip "DBI_DSN already contains quoted database, no need for explicit test", 1;
	}
	$t=q{Connect using a quoted database argument};
	($dbi = $ENV{DBI_DSN}) =~ s/$alias\s*=(\w+)/'db="'.lc $2.'"'/e;
	eval {
		$dbh = DBI->connect($dbi, $ENV{DBI_USER}, $ENV{DBI_PASS}, {RaiseError=>1});
	};
	is($@, q{}, $t);
}

$t=q{Connect with an undefined user picks up $ENV{DBI_USER}};
eval {
	$dbh = DBI->connect($ENV{DBI_DSN}, undef, $ENV{DBI_PASS}, {RaiseError=>1});
};
is($@, q{}, $t);

$t=q{Connect with an undefined password picks up $ENV{DBI_PASS}};
eval {
	$dbh = DBI->connect($ENV{DBI_DSN}, $ENV{DBI_USER}, undef, {RaiseError=>1});
};
is($@, q{}, $t);

END {
	my $pv = sprintf("%vd", $^V);
	my $schema = exists $ENV{DBD_SCHEMA} ? 
		"\nDBD_SCHEMA        $ENV{DBD_SCHEMA}" : '';
	my $dsn = exists $ENV{DBI_DSN} ? $ENV{DBI_DSN} : '?';
	my $ver = defined $DBD::Pg::VERSION ? $DBD::Pg::VERSION : '?';
	diag 
		"\nProgram               Version\n".
		"Perl                  $pv ($^O)\n".
		"DBD::Pg               $ver\n".
		"PostgreSQL (compiled) $pglibversion\n".
		"PostgreSQL (target)   $pgversion\n".
		"PostgreSQL (reported) $pgvstring\n".
		"Default port          $pgdefport\n".
		"DBI                   $DBI::VERSION\n".
		"DBI_DSN               $dsn$schema\n";
}
