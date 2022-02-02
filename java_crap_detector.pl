#!/usr/bin/perl

use strict;
use warnings;

use lib "/home/drahflow/bin";
use Data::Dumper;
use Functional qw(all);

my @crap;
my %global_seen_code;
my $filenameFilter = qr(\.java$);

sub lineSignature {
    my ($content) = @_;

    $content =~ s/^\s*(.*)\s*$/$1/;
    $content =~ s/\s//g;
#    $content =~ s/\w[a-z][A-Z0-9a-z]*\w/_/g;

    return $content;
}

sub irrelevantSignature {
    my ($signature, $length) = @_;

    return 1 if $signature =~ /\nimport/s;

    $signature =~ s/}//g;
    $signature =~ s/^\s*$//g;

    return 1 if 4 > @{[grep { $_ } split /\n/, $signature]};

    $signature =~ s/\n//g;

    return 1 if length $signature <= $length * 3;
    return 0;
}

sub detect_crap {
    my ($file) = @_;

    return if ($file !~ $filenameFilter);

    print "$file\n";

    my %local_seen_code;

    open FILE, '<', $file or die "cannot open $file: $!";
    my @lines;
    while (my $line = <FILE>) {
	chomp $line;
	push @lines, [$., $line];
    }

    my %imports;

    foreach my $line (@lines) {
	my ($number, $content) = @$line;

	if (   $content =~ /^\s*else/
	    or $content =~ /\binstanceof\b/
	    or $content =~ /\bTODO\b/) {
	    push @crap, [2, $file, $number, substr($content, 0, $-[0]) . "\e[31m" . substr($content, $-[0], $+[0] - $-[0]) . "\e[0m" . substr($content, $+[0])];
	}

	if (   $content =~ /\s+$/) {
	    push @crap, [2, $file, $number, "\e[31mtrailing whitespace\e[0m"];
	}

	if (   $content =~ /\bFIXME\b/
	    or $content =~ /\bMARK\b/) {
	    push @crap, [7, $file, $number, substr($content, 0, $-[0]) . "\e[31m" . substr($content, $-[0], $+[0] - $-[0]) . "\e[0m" . substr($content, $+[0])];
	}

	if ($content =~ /^\s*import ([^ ]+)\.[a-zA-Z0-9]+\s*;\s*$/) {
	    my $package = $1;
	    ++$imports{$package};

	    if ($imports{$package} == 3 and $package ne 'java.awt') {
		push @crap, [3, $file, $number, "\e[31mtoo many imports\e[0m from the same package $package"];
	    }
	}
    }

    my $check_duplicated_code = sub {
	my ($seen_code, $length, $highlight, $lengthen) = @_;

	for (my $i = 0; $i < @lines - ($length - 1); ++$i) {
	    my $signature = join("\n", map { lineSignature($_->[1]) } @lines[$i .. $i + ($length - 1)]);

	    next if irrelevantSignature($signature, $length);

	    my $matchLen = 0;

	    if (exists $seen_code->{$signature}) {
		if ($lengthen) {
		    my $start = $seen_code->{$signature}->[1];

		    my $cont = 1;
		    do {
			my $normStart = lineSignature($lines[$start]->[1]);
			my $normHere = lineSignature($lines[$i]->[1]);

			$cont = 0 if($normStart ne $normHere);

			++$matchLen;
			++$i;
			++$start;
		    } while($cont);
		    --$matchLen;
		} else {
		    $i = $i + $length;
		    $matchLen = $length;
		}

		push @crap, [5 + 0.01 * $matchLen, $file, $i - $matchLen + ($lengthen? 0: 1), "${highlight}Duplicated code (" . $matchLen. " lines)\e[0m with " .
		    sprintf('%s:%d', $seen_code->{$signature}->[0], $seen_code->{$signature}->[1] + 1)];
	    } else {
		$seen_code->{$signature} = [$file, $i];
	    }
	}
    };

    &$check_duplicated_code(\%local_seen_code,  4, "\e[34;1m", 1);
    &$check_duplicated_code(\%global_seen_code, 6, "\e[34m", 0);
    &$check_duplicated_code(\%global_seen_code, 10, "\e[34m", 0);
    &$check_duplicated_code(\%global_seen_code, 20, "\e[34m", 0);
    &$check_duplicated_code(\%global_seen_code, 30, "\e[34m", 0);
    &$check_duplicated_code(\%global_seen_code, 50, "\e[34m", 0);

    for (my $i = 1; $i < @lines; ++$i) {
	if (    $lines[$i]->[1] =~ /^\s*(private|public|protected|static)/
	    and $lines[$i]->[1] !~ /serialVersionUID/
	    and $lines[$i - 1]->[1] !~ /^\s*\/\//
	    and $lines[$i - 1]->[1] !~ /\*\//
	    and $lines[$i - 1]->[1] !~ /^\s*\@Override/) {
	    push @crap, [1, $file, $lines[$i]->[0], "\e[32mUndocumented and non-overridden\e[0m " . $lines[$i]->[1]];
	}
    }

    close FILE;
} ## end sub detect_crap

sub recurse {
    my ($dir) = @_;

    my @files = glob("$dir/*");
    foreach my $file (@files) {
	next if $file =~ /\/\./;

	if (-d $file) {
	    recurse($file);
	} else {
	    detect_crap($file);
	}
    }
}

if ($ARGV[0] eq '--filter') {
  shift;
  $filenameFilter = shift;
}

if (@ARGV) {
    foreach my $file (@ARGV) {
	detect_crap($file);
    }
} else {
    recurse('.');
}

my %files;

my @problems = sort { $b->[0] <=> $a->[0] } @crap;
foreach my $crap (reverse @problems[0 .. 200]) {
    next unless $crap;

    printf '%06.2f %s:%d  %s' . "\n", @$crap;
}

foreach my $crap (@problems) {
    $files{$crap->[1]} += $crap->[0];
}

print "\nCrappiest files:\n";

my @files = sort { $files{$b} <=> $files{$a} } keys %files;

foreach my $file (@files[0 .. 10]) {
    next unless $file;

    printf '%06.2f %s' . "\n", $files{$file}, $file;
}

print "\nOverall Crappyness: ", (foldl { $a + $b } 0, values %files), "\n";
