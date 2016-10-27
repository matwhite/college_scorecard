#!/usr/bin/perl

# Mathew White <mwhite@xmission.com>

# Inspired By Ben Hamner's SQLite Importer at https://www.kaggle.com/benhamner/d/kaggle/college-scorecard/exploring-the-us-college-scorecard-data

use strict;
use Data::Dumper;

use Text::CSV_XS;
use Spreadsheet::XLSX;
use DBI;
use Config::File;
use Date::Parse;
use POSIX qw(strftime);

my $working_dir = '.';
my $dictfile = 'CollegeScorecardDataDictionary-09-26-2016.xlsx';
my $conffile = 'config';
chdir($working_dir);
my $conf = Config::File::read_config_file($conffile);
my $prefix = $conf->{prefix}; # Enable Testing With Table Name Prefix
my $csv = Text::CSV_XS->new({qw(
	binary 1 auto_diag 0 allow_loose_quotes 0
)});

# Define Column Placements
my $name_col=4;
my $type_col=3;
my $value_col=5;
my $label_col=6;
my $i = 0;  # Keep Track Of Row Numbers

# Define Column Type Overrides For MySQL
my %override = map { $_ => 'double' } qw(
    IND_INC_AVG
    DEP_INC_AVG
    fsend_count
    age_entry_sq
    age_entry
    faminc
    lnfaminc
    lnfaminc_ind
    faminc_ind
    ln_median_hh_inc
    median_hh_inc
    md_faminc
    CUML_DEBT_P75
    CUML_DEBT_P25
    CUML_DEBT_P90
    CUML_DEBT_P10
    FAMINC
    AGE_ENTRY
    FAMINC_IND
    MD_FAMINC
    REPAY_DT_MDN
    SEPAR_DT_MDN
    LN_MEDIAN_HH_INC
    MEDIAN_HH_INC
);
$override{ZIP}          = 'string';
$override{REPAY_DT_MDN} = 'date';
$override{SEPAR_DT_MDN} = 'date';
$override{OPEID6}       = 'string';
$override{OPEID}        = 'string';

# Initialize Program

# Get And Parse Dictionary Data
my %terms;  # To Create Schema

# Get Header Row To Determine Field Order
open(my $fh, "<MERGED1996_97_PP.csv") or die "Error: $!";
my $head = $fh->getline();
chomp($head);
close($fh);
my @head = map { $_ =~ s/\W//g; $_; } split(/,/, $head);
my %head = map { $_ => 1 } @head;

my $excel = Spreadsheet::XLSX->new($dictfile);
my $dict = [];
foreach my $sheet (@{$excel -> {Worksheet}}) {
    next if $sheet->{Name} ne 'data_dictionary';
    $sheet->{MaxRow} ||= $sheet->{MinRow};
    foreach my $row ($sheet->{MinRow} .. $sheet->{MaxRow}) {
        $sheet->{MaxCol} ||= $sheet->{MinCol};
        my $rs = [];
        foreach my $col ($sheet->{MinCol} ..  $sheet->{MaxCol}) {
            push(@$rs, $sheet->{Cells}[$row][$col]{Val});
            #printf("( %s , %s ) => %s\n", $row, $col, $cell->{Val});
        }
        push(@$dict, $rs);
    }
}
#print Dumper($dict);
for my $row (@$dict) {
	my $name = $row->[$name_col];
	my $type = $row->[$type_col];
	my $val = $row->[$value_col];
	my $label = $row->[$label_col];
	if ($i == 0) {
		die "Bad name_col" if $name ne 'VARIABLE NAME';
		die "Bad type_col" if $type ne 'API data type';
		die "Bad value_col" if $val ne 'VALUE';
		die "Bad label_col" if $label ne 'LABEL';
		$i++;
		next;
	}
	if ($name) {
        $type = $override{$name} if exists $override{$name};
		$type = 'string' if $type eq 'autocomplete';
	}
	$type = 'text' if $type eq 'string';	# Convert To MySQL Data Type
	$type = 'double' if $type eq 'float';	# Convert To MySQL Data Type

	$terms{$name} = $type if $name;
	$i++;
}

# Define Certain Items Outside The Dictionary
$terms{POOLYRS200}      = 'integer';
$terms{D200_L4_POOLED}  = 'integer';
$terms{D200_L4}         = 'integer';
$terms{D200_4_POOLED}   = 'integer';
$terms{D200_4}          = 'integer';
$terms{C200_L4_POOLED}  = 'double';
$terms{C200_L4}         = 'double';
$terms{C200_4_POOLED}   = 'double';
$terms{C200_4}          = 'double';

# Look For Items Not Defined In Data Dictionary
for my $h (@head) {
    die "Undefined Dictionary Field $h\n" if not exists $terms{$h};
}
for my $d (keys %terms) {
    die "Undefined Table Field $d\n" if not exists $head{$d};
}

# Split Schema Into Two Tables So They Fit Within MySQL's Row-Size Constraints
my $split = int(scalar(@head)/2);

print("SET NAMES 'utf8';\n");
print(
	"CREATE TABLE $prefix"."ScorecardA (Id INT4 NOT NULL PRIMARY KEY, "
	. join(', ', map { sprintf("%s %s", $_, $terms{$_}) } @head[0..$split])
    . ", KEY uo (UNITID, OPEID(40))) DEFAULT CHARSET=utf8;\n"
);
print(
	"CREATE TABLE $prefix"."ScorecardB (Id INT4 NOT NULL PRIMARY KEY, "
	. join(
        ', ',
        map { sprintf("%s %s", $_, $terms{$_}) } @head[$split + 1..$#head]
    )
    . ", Year int2 NOT NULL, KEY (Year)) "
    . "DEFAULT CHARSET=utf8;\n"
);

# Create View To Join Tables For Easy Querying
print(
	"CREATE VIEW $prefix"."sc AS SELECT * "
	. "FROM $prefix"."ScorecardA JOIN $prefix"."ScorecardB USING(Id);\n"
);

# Now Create Records

my $gloid = 0; # Create Key To Join Data
opendir(DIR, '.');
# For Each Data File...
for my $fn (sort grep { $_ =~ /MERGED\d+_\d+_PP\.csv/ } readdir(DIR)) {
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
        #last if $i > 3; # Short Data Test
        my @ta = ($gloid);
        my @tb = ($gloid);
        for my $fnum (0..$#{ $row }) {
            # Convert To MySQL Date Type
            if ($terms{$head[$fnum]} eq 'date'
            and $row->[$fnum] !~ /^(NULL|PrivacySuppressed)$/) {
                my $prior = $row->[$fnum];
                my ($m, $d, $y) = split(/\//, $row->[$fnum]);
                $row->[$fnum] = sprintf('%.4d-%.2d-%.2d', $y, $m, $d);
                #warn(sprintf("DTECONV: F %s T %s\n", $prior, $row->[$fnum]));
                #$row->[$fnum] = strftime(
                #    '%Y-%m-%d', localtime(str2time($row->[$fnum]))
                #);
            }
            if ($fnum <= $split) {
                    push(@ta, $row->[$fnum]);
            }
            else {
                    push(@tb, $row->[$fnum]);
            }
        }
        printf("INSERT INTO $prefix"."ScorecardA VALUES(%s);\n", make_list(@ta));
        printf("INSERT INTO $prefix"."ScorecardB VALUES(%s);\n", make_list(@tb, $year));
    }
}
        
closedir(DIR);

sub make_list {
    my @data = @_;
    return join(
        ',',
        map {
            $_ =~ /^(NULL|PrivacySuppressed)$/ ? 'NULL' : DBD::_::db->quote($_)
        } @data
    );
}
