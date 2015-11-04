#!/bin/bash

input_file=${1:-prof_vmstat.txt}

if [ ! -d vmstat_counters ]; then
    mkdir -p vmstat_counters || exit 1
fi

for i in $(awk '{print $1}' $input_file | sort -u)
do 
#   grep "^$i" $input_file > vmstat_counters/$i
    awk '/^'$i'/ { if ( v0 == "" ) { v0 = $2 }; { print $2 - v0 }}' $input_file > vmstat_counters/$i
    echo -n "."
done
echo "ok usa"
