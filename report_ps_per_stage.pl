#!/usr/bin/env perl

use strict;
use warnings;
use Data::Dumper;

# METRIC can be pcpu, pmem, rss, or vsz
use constant METRIC => 'pcpu';

# sweep process and all of its children to calculate the total METRIC
# consumed by the whole process tree
sub recurse_sum_key {
    my $record = shift;
    my $key = shift;
    my $depth = shift;
    $depth = 0 if !defined($depth);
    if ( exists($record->{children})
    &&   length(keys(%{$record->{children}})) > 0 ) {
        my $sum = 0;
        $depth++;
        foreach ( keys(%{$record->{children}}) ) {
            $sum += recurse_sum_key( $record->{children}->{$_}, $key, $depth );
        }
        $depth--;
        return $sum;
    }
    else {
        return $record->{$key};
    }
}


my $timestamp = 0;
my %stage_names;
my @stage_names;
my $records;
my $time_records = {};
while ( my $line = <> )  {
    if ( $line =~ m/^PROF_BEGIN (\d+)$/ ) {
        if ( $timestamp == 0 ) {
            $timestamp = $1;
        }
        else {
            my $stage_sums;
            foreach my $pid ( keys(%$records) ) {
                my $record = $records->{$pid};
                next if !exists($record->{cmd}); # this is the case for pids who are parents of our processes but aren't owned by us
                my @args = split( m/\s+/, $record->{cmd});
                if ( $args[0] eq "python"
                &&   $args[1] =~ m{adapters/python/.*.py}
                &&   $args[2] =~ m{mro/stages/.*?([^/]+)\s*$} ) {
                    my $stage_name = $1;
                    if ( $args[1] =~ m{adapters/python/(split|join).py} ) {
                        $stage_name .= "-$1";
                    }
                    my $recursive_sum = recurse_sum_key( $record, METRIC() );
                    my $self_sum = $record->{METRIC()};
                    $stage_sums->{$stage_name} += $recursive_sum + $self_sum;
                    if ( !exists($stage_names{$stage_name}) ) {
                        print "Found a new stage name $stage_name\n";
                        # and also maintain order of appearance
                        push( @stage_names, $stage_name );
                        # build a list of detected stage names
                        $stage_names{$stage_name} = 1;
                        # should probably just use the array and grep it
                    }
                }
            }

            # cycle to a the beginning of a new time record
            $time_records->{$timestamp} = $stage_sums;
            $timestamp = $1;
            $records = {};
        }
    }
    else {
        $line =~ s/(^\s+|\s+$)//g;
        if ( $line =~ m/^\d+\s+\d+\s+\d+\s+/ ) {
            my @args = split(m/\s+/, $line);
            my $cmd_str = join( " ", @args[9 .. $#args] );
            my $pid = $args[0];
            my $ppid = $args[1];

            $records->{$pid}->{pid}  = $pid;
            $records->{$pid}->{ppid} = $ppid;
            $records->{$pid}->{lwp}  = $args[2];
            $records->{$pid}->{pcpu} = $args[5];
            $records->{$pid}->{pmem} = $args[6];
            $records->{$pid}->{rss}  = $args[7];
            $records->{$pid}->{vsz}  = $args[8];
            $records->{$pid}->{cmd}  = $cmd_str;

            # build process graph :/
            if ( $ppid != 1 ) {
                $records->{$ppid}->{children}->{$pid} = $records->{$pid};
            }
        }
    }
}


print "timestamp,";
print "$_," foreach @stage_names;
print "\n";

# loop over timestamps
for my $timestamp ( sort { $a <=> $b } ( keys(%$time_records) ) ) {
    print "$timestamp,";
    # loop over stages
    foreach my $stage_name ( @stage_names ) {
        my $value = 0.0;
        if ( exists($time_records->{$timestamp}->{$stage_name}) ) {
            $value = $time_records->{$timestamp}->{$stage_name};
        }
        printf("%s,", $value/100.0 );
    }
    print "\n";
}
