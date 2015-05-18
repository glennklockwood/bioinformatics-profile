#!/bin/bash

awk '{if ( $1 == "PROF_BEGIN" ) { timestamp = $2 }; if ( $1 == "/dev/md0" ) { print timestamp, $3 } }' $1
