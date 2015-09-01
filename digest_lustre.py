#!/usr/bin/env python
#
#  Read a text file containing multiple concatenated outputs of 
#  `cat /proc/fs/lustre/llite/*/stats` and print deltas
#
#  The final column of read_bytes, write_bytes, osc_read, and osc_write
#    are byte values.  Not sure what the other columns mean.  In addition,
#    osc_* seems to be a more reliable indicator of file data read/written;
#    see "Lustre llite proc stats.xlsx" for the data showing this.
#

import sys

def print_delta( data, last_data, t0 ):
    print "%-12.3f %10.1f %10.1f" % (
        data['snapshot_time'] - t0,
        (data['osc_read'] - last_data['osc_read']) / 1024.0 / 1024.0,
        (data['osc_write'] - last_data['osc_write']) / 1024.0 / 1024.0 )

def main( input_file ):
    last_data = None
    data = None
    t0 = None

    _SPECIAL_PARSE_KEYS = [ 'read_bytes', 'write_bytes', 'osc_read', 'osc_write' ]

    fp = open(input_file, 'r')
    for line in fp.readlines():
        if line.startswith('PROF_BEGIN'):
            continue

        key, val = [ x.strip() for x in line.strip().split(' ', 1 ) ]
        
        if key == 'snapshot_time':
            if last_data is not None:
                print_delta( data, last_data, t0 )
            if data is not None:
                last_data = data
            data = {}
            val = float( val.split()[0] )
            if t0 is None:
                t0 = val
        elif key in _SPECIAL_PARSE_KEYS:
            val = int(val.split()[-1])
        else:
            val = int(val.split()[0])
    
        data[key] = val
    
    fp.close()
    
if __name__ == '__main__':
    main( sys.argv[1] )
