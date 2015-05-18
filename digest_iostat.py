#!/usr/bin/env python

import sys
from datetime import datetime, timedelta

def digest_iostat():
    with open( sys.argv[1], 'r' ) as fp:
        lines = fp.readlines();

    processing = False
    line_no = 0
    prev_timestamp_str = None
    while True:
        line = lines[line_no]
        if line.startswith('PROF_BEGIN'):
            processing = True
            line_no += 7
        elif processing:
            timestamp_str = line.strip()
            timestamp = datetime.strptime(timestamp_str, "%m/%d/%Y %I:%M:%S %p")
            if prev_timestamp_str is not None:
                prev_timestamp = datetime.strptime(prev_timestamp_str, "%m/%d/%Y %I:%M:%S %p")
                if (timestamp - prev_timestamp).total_seconds() > 600:
                    print "WARNING: %s (%s) <-> %s (%s) > 600 sec" % ( 
                        prev_timestamp.strftime("%c"), 
                        prev_timestamp_str,
                        timestamp.strftime("%c"),
                        timestamp_str )
                    raise Exception("time gap detected")
        
            md0_line = lines[line_no+2].strip().split()
            print "%s %s %s %s" % (
                timestamp.strftime("%s"),
                md0_line[1],
                md0_line[2],
                md0_line[3]
            )
            prev_timestamp_str = timestamp_str
            line_no += 4
        else:
            line_no += 1
        if line_no >= len(lines):
            break

_NFSIOSTAT_TIMESTEP = 30
def digest_nfsiostat():
    with open( sys.argv[1], 'r' ) as fp:
        lines = fp.readlines();

    processing = False
    line_no = 0
    prev_timestamp_str = None
    while True:
        line = lines[line_no]
        if line.startswith('PROF_BEGIN'):
            timestamp = datetime.fromtimestamp( int(line.split()[1]) )
            processing = True
            line_no += 11
        elif processing:
            timestamp += timedelta(seconds=_NFSIOSTAT_TIMESTEP)
            timestamp_str = timestamp.strftime("%s")
            if prev_timestamp_str is not None:
                prev_timestamp = datetime.fromtimestamp( int( prev_timestamp_str ) )
                if (timestamp - prev_timestamp).total_seconds() > 600:
                    print "WARNING: %s (%s) <-> %s (%s) > 600 sec" % ( 
                        prev_timestamp.strftime("%c"), 
                        prev_timestamp_str,
                        timestamp.strftime("%c"),
                        timestamp_str )
                    raise Exception("time gap detected")
        
            iops = lines[line_no+3].split()[0]
            read_rate = lines[line_no+5].split()[1]
            write_rate = lines[line_no+7].split()[1]
#           md0_line = lines[line_no+2].strip().split()
            print "%s %s %s %s" % (
                timestamp.strftime("%s"),
                iops,
                read_rate,
                write_rate,
            )
            prev_timestamp_str = timestamp_str
            line_no += 9
        else:
            line_no += 1
        if line_no >= len(lines):
            break

if __name__ == '__main__':
    digest_iostat()
