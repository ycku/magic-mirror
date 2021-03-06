#!/usr/bin/env perl
use v5.14;
use strict;
use warnings;
use autodie;
use File::Path qw<make_path>;
use List::MoreUtils qw<apply>;
use Getopt::Long;

my %opts;
GetOptions(\%opts, 'year=n');

use Parallel::ForkManager;

my ($mirror_repo, $flat_mirror_repo) = apply { s</$><>; } @ARGV[0,1];
my $dataset = $ARGV[2] || "*/*";

my @dataset = map {
    my ($name, $format) = m<\A(.+)\.([a-z]{3,4})\z>;
    +{
        filename => $_,
        name     => $name,
        format   => $format,
    };
} apply {
    s<\A${mirror_repo}><>;
    s<^/><>;                    #// wtfemacs
} sort glob("${mirror_repo}/${dataset}");

chdir $mirror_repo;

my $forkman = Parallel::ForkManager->new(2);

for my $dataset (@dataset) {
    say ">> $dataset->{filename}";
    $forkman->start and next;

    my $cmd = "git log --format='%H %at' $dataset->{filename}";
    open my $fh, "-|", $cmd;
    while (<$fh>) {
        chomp;
        my ($sha1, $author_timestamp) = split / /, $_, 2;
        my @t = (gmtime($author_timestamp))[5,4,3,2,1];
        $t[0] += 1900;
        $t[1] += 1;

        if ($opts{year}) {
            last if $t[0] < $opts{year};
            next if $t[0] > $opts{year};
        }

        my $p_dir = sprintf('%04d-%02d-%02d', @t[0,1,2]);
        my $p = sprintf('%02d-%02d', @t[3,4]);

        my $flat_dir = $flat_mirror_repo . "/" . $dataset->{name} . "/" . $p_dir;
        my $flat_file_name =  $flat_dir . "/" . $p . "." . $dataset->{format};

        last if !$opts{year} && -f $flat_file_name;

        say ">> $flat_file_name";
        make_path($flat_dir) unless -d $flat_dir;
        system("git show ${sha1}:$dataset->{filename} > $flat_file_name");
    }
    $forkman->finish;
}
$forkman->wait_all_children;

