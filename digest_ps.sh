#!/bin/bash
awk '{ if ( $1 == "PROF_BEGIN" ) { print timestamp, sum1, sum2, sum3, sum4; timestamp = $2; sum1 = 0; sum2=0;sum3=0;sum4=0 } else if ( $1 != "PID" ) { sum1 += $6; sum2+=$7;sum3+=$8;sum4+=$9; } }' $1
