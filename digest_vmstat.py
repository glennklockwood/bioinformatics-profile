#!/usr/bin/env python

import os
import sys

_OUTPUT_DIR = 'vmstat_counters'

if __name__ == '__main__':
    if len(sys.argv) < 2:
        filename = 'prof_vmstat.txt'
    else:
        filename = sys.argv[2]

    fp = open( filename, 'r' )

    fps = {}

    if os.path.exists( _OUTPUT_DIR ):
        sys.exit( "Output directory %s already exists" % _OUTPUT_DIR )
    else:
        os.mkdir( _OUTPUT_DIR )

    ts = ""
    for line in fp.readlines():
        k, v = line.split()

        if k == 'PROF_BEGIN':
            ts = v
        else:
            if k not in fps:
                fps[k] = open( os.path.join( _OUTPUT_DIR, k ), 'w' )
            fps[k].write( "%s %s\n" % (ts, v) )
