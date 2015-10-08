#!/usr/bin/env python
#
#  Pull a gstack from a prof_gstack.txt given a specific timestamp
#

import os
import sys

__t0 = 1443487132

def print_first_timestamp( fp, timestamp, thread=-1 ):
    state = 0
    print_lines = []
    if timestamp < __t0:
        timestamp = timestamp + __t0 

    for line in fp.readlines():
        if line.startswith('PROF_BEGIN'):
            ### state > 0 means we already found the right timestamp
            if state > 0:
                break
            ### state = 0 means we are looking for the right timestamp
            else:
                this_timestamp = int(line.split()[1])
                if this_timestamp >= timestamp:
                    # we found the right timestamp
                    state = 1

        ### state 0 means we are looking for the right timestamp
        if state > 0:
            ### negative thread specifier = print all threads
            if thread < 0: state = 2
            ### state 1 means we found the right timestamp, now look for thread
            if ( state == 1
                and line.startswith('Thread')
                and int(line.split()[1]) == thread ):
                    state = 2
            ### state 2 means we are printing lines
            if state == 2 or line.startswith('PROF_BEGIN'):
                print_lines.append( line.strip() )

    if state > 0:
        print_lines.reverse()
        print "Timestamp %d" % this_timestamp
        for line in print_lines:
            if line.startswith('#'):
                print "  " + line.split()[3].split('(')[0]
    else:
        sys.stderr.write('timestamp never found :(\n')
    
if __name__ == '__main__':
    if len(sys.argv) < 3:
        sys.stderr.write('Syntax: %s <prof_gstack.txt> <epoch timestamp>\n' % sys.argv[0] )
        sys.exit(1)

    filename = sys.argv[1]
    timestamp = int(sys.argv[2])
    if not os.path.isfile( filename ):
        sys.stderr.write('Error: file %s not found\n' % filename )
        sys.exit(1)

    with open( filename, 'r' ) as fp:
        print_first_timestamp( fp, timestamp )
