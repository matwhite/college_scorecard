#!/usr/bin/perl

use strict;
use Data::Dumper;
use Text::CSV_XS;
use DBI;
use Config::File;

$|++;

my $working_dir = '.';
chdir($working_dir);
my $conffile = 'config';
my $conf = Config::File::read_config_file($conffile);
my $prefix = $conf->{prefix};

my $dbh = DBI->connect(
  "DBI:mysql:database=$conf->{db};host=$conf->{host}",
  $conf->{user}, $conf->{pass}
);
my $sth = $dbh->prepare("SET NAMES 'utf8'");
$sth->execute();

my $fldmap;
my $schema = $dbh->selectall_arrayref("EXPLAIN $prefix"."sc");
my @smap;
for my $fn (0..$#{ $schema }) {
    next if $fn == 0;
    push(@smap, $schema->[$fn][0]);
}

# Initialize Program
my $csv = Text::CSV_XS->new({qw(
	binary 1 auto_diag 0 allow_loose_quotes 0
)});

# For Each Data File...
my $gloid = 0;
opendir(DIR, '.');
for my $fn (sort grep { $_ =~ /MERGED\d+_\d+_PP/ } readdir(DIR)) {
	my ($year) = $fn =~ /MERGED(\d+)_/;
	warn("$fn $year\n");

	# Parse The Data And Build SQL
	
	open(my $fh, "<", $fn) or die "Error: $!";
	my $i = 0;
	while (my $row = $csv->getline($fh)) {
		$gloid++;
		if ($i == 0) {
			$i++;
			next;
		}
		$i++;
        print"GOT ROW $gloid Y $year UNITID $row->[0] OPEID $row->[1]\n";
        # Assume Year + UNITID + OPEID = Unique Row ID
        my $res = $dbh->selectrow_arrayref(sprintf(
            "SELECT * FROM $prefix"."sc "
            . "WHERE Year = %s AND UNITID = %s AND OPEID = %s",
            map { $dbh->quote($_); } $year, $row->[0], $row->[1]
        ));
        for my $idx (1..$#{ $res } - 1) {
            # Massage Dates Into ISO8601 Format
            if ($smap[$idx-1] =~ /^(REPAY_DT_MDN|SEPAR_DT_MDN)$/
            and $row->[$idx-1] =~ /^\d+/) {
               my ($m, $d, $y) = split(/\//, $row->[$idx-1]);
               $row->[$idx-1] = sprintf('%.4d-%.2d-%.2d', $y, $m, $d);
            }
            # Fields Are Only A Mismatch If They Are Not Null or Suppressed
            if ($res->[$idx] ne $row->[$idx-1]) {
                if ((not defined $res->[$idx]
                or $res->[$idx] eq ''
                or $res->[$idx] == 0)
                and ($row->[$idx-1] eq 'NULL'
                or $row->[$idx-1] eq 'PrivacySuppressed')) {
                    # Ignore 0 != NULL
                }
                else {
                    printf(
                        "ROW %d FLD %s  %s != %s\n",
                        $gloid, $smap[$idx-1], $res->[$idx], $row->[$idx-1]
                    );
                }
            }
        }
	}
}

closedir(DIR);

sub make_list {
	my @data = @_;
	return join(
		',',
		map { DBD::_::db->quote($_) } @data
	);
}
