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
# snapshot_time             1441417734.605685 secs.usecs
# read_bytes                632846 samples [bytes] 0 4194304 2446905945284
# write_bytes               575477 samples [bytes] 4 4194304 1805014315717
# osc_read                  1857468 samples [bytes] 34 1048576 1453712666209
# osc_write                 1731183 samples [bytes] 35 1048576 1805005089875
# ioctl                     8143 samples [regs]
# open                      8275 samples [regs]
# close                     8272 samples [regs]
# seek                      109822 samples [regs]
# setattr                   5 samples [regs]
# truncate                  2887 samples [regs]
# getattr                   20417 samples [regs]
# create                    1133 samples [regs]
# unlink                    812 samples [regs]
# mkdir                     5 samples [regs]
# rename                    5 samples [regs]
# statfs                    17 samples [regs]
# alloc_inode               1889 samples [regs]
# getxattr                  2186201 samples [regs]
# inode_permission          249369 samples [regs]
# statahead total: 0
# statahead wrong: 0
# agl total: 0
# snapshot_time             1441417734.605818 secs.usecs
# hits                      353601375 samples [pages]
# misses                    413852 samples [pages]
# readpage not consecutive  151712 samples [pages]
# miss inside window        1041 samples [pages]
# failed grab_cache_page    2476744 samples [pages]
# failed lock match         296 samples [pages]
# read but discarded        514811 samples [pages]
# zero size window          67316269 samples [pages]
# read-ahead to EOF         249 samples [pages]
# hit max r-a issue         286338857 samples [pages]
# failed to reach end       286360117 samples [pages]
# 

import sys
import re

_BYTES_TO_MEBIBYTES = 1.0 / 1024.0 / 1024.0
_COLS_TO_PRINT = [
#       ( key,              fmt,        rate?, conversion factor )
        ('osc_read_ops',    "%10d",     False, 1 ),
        ('osc_write_ops',   "%10d",     False, 1 ),
#       ('osc_read',        "%10.1f",   False, _BYTES_TO_MEBIBYTES ),
#       ('osc_write',       "%10.1f",   False, _BYTES_TO_MEBIBYTES ),
        ('osc_read',        "%10d",     False, 1 ),
        ('osc_write',       "%10d",     False, 1 ),
        ('osc_read',        "%10.1f",    True, _BYTES_TO_MEBIBYTES ),
        ('osc_write',       "%10.1f",    True, _BYTES_TO_MEBIBYTES ),
        ('hits',            "%10.1f",    True, 1 ),
        ('misses',          "%10.1f",    True, 1 ),
        ('readpage not consecutive', "%10.1f",    True, 1 ),
#       ('miss inside window', "%10.1f",    True, 1 ),
        ('failed grab_cache_page', "%10.1f",    True, 1 ),
#       ('read but discarded', "%10.1f",    True, 1 ),
        ('zero size window', "%10.1f",    True, 1 ),
#       ('read-ahead to EOF', "%10.1f",    True, 1 ),
#       ('hit max r-a issue', "%10.1f",    True, 1 ),
#       ('failed to reach end', "%10.1f",    True, 1 ),


    ]


def print_delta( data, last_data, t0 ):

    line = ""
    if data is None:
#       line += "%12s," % "time(sec)"
        line += "%s," % "time(sec)"
        for col in _COLS_TO_PRINT:
            key, fmt, is_rate, xfac  = col
#           rex_match = re.match( '(%\d+)', fmt )
#           if rex_match is not None:
#               if is_rate:
#                   fmt = ("%ss/sec," % rex_match.group(1))
#               else:
#                   fmt = ("%ss," % rex_match.group(1))
#               line += (fmt % key)
            if is_rate:
                fmt = "%s/sec,"
            else:
                fmt = "%s,"
            line += (fmt % key)
    else:
        line += "%12.3f," % (data['snapshot_time'] - t0)
        for col in _COLS_TO_PRINT:
            key, fmt, is_rate, xfac  = col
            data_to_print = data[ key ] - last_data[ key ]
            if is_rate:
                data_to_print /= ( data['snapshot_time'] - last_data['snapshot_time'] )
            line += (fmt + ",") % (data_to_print * xfac)

    print line.rstrip(' ,')

def main( input_file ):
    last_data = None
    data = None
    t0 = None

    _SPECIAL_PARSE_KEYS = [ 'read_bytes', 'write_bytes', 'osc_read', 'osc_write' ]

    print_delta( None, None, None )

    fp = open(input_file, 'r')
    for line in fp.readlines():
        if line.startswith('PROF_BEGIN'):
            ### flush everything to this point
            if last_data is not None:
                print_delta( data, last_data, t0 )
            if data is not None:
                last_data = data
            data = {}

            continue

        ### stats and readahead_stats use spaces to separate key/value pairs;
        ### statahead_stats uses a colon.  Mildly annoying.
        if ':' in line:
            key, val = [ x.strip() for x in line.strip().split(':', 1 ) ]
        else:
            key, val = [ x.strip() for x in line.strip().split('  ', 1 ) ]
        
        ### there are two snapshot_times: one from stats and from 
        ### readahead_stats.  they should be within microseconds of each other.
        if key == 'snapshot_time':
            val = float( val.split()[0] )
            if t0 is None:
                t0 = val
        elif key in _SPECIAL_PARSE_KEYS:
            special_key = key + '_ops'
            special_val = int( val.split()[0] )
            data[special_key] = special_val

            val = int( val.split()[-1] )
        else:
            val = int( val.split()[0] )
    
        data[key] = val
    
    fp.close()
    
if __name__ == '__main__':
    main( sys.argv[1] )
