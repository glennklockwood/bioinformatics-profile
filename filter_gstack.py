#!/usr/bin/env python
#
#  Discard all traces of child threads in prof_gstack.txt
#

import sys

state = 0
fp = open( sys.argv[1], 'r' )
for line in fp.readlines():
    yes_print = False

    if state == 0:
        if line.startswith('Thread 1 '):
            state = 1
            yes_print = True
    elif state == 1:
        if line.startswith('#'):
            yes_print = True
        else:
            state = 0
            yes_print = False

    if yes_print or line.startswith('PROF_BEGIN'):
        print line.strip()
    
fp.close()
