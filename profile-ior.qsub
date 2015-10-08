#!/bin/bash
#SBATCH --job-name="bbbblast"
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=24
#SBATCH --time=4:00:00
#SBATCH --partition=ccm_queue
#SBATCH --output=jobscript-sbatch.out
#SBATCH --error=jobscript-sbatch.err
#SBATCH --mail-type=ALL
#SBATCH --mail-user=glock@lbl.gov
#PBS -N bbbblast
#PBS -l mppwidth=24
#PBS -l walltime=06:00:00
#PBS -q ccm_queue
#PBS -o jobscript-pbs.out
#PBS -e jobscript-pbs.err
#
#  Environment variables for configuring behavior:
#     NO_STAGE=1 to run BLAST against the location specified by DB_DIR variable
#     NO_BONNIE=1 to skip bonnie++ prelude (designed to flush disk cache)
#     NO_PROFILE=1 to skip profiling altogether
#     NO_DF=1 to skip profiling file system capacities
#     NO_FILEHANDLES=1 to skip profiling file handle counts
#     
NO_BONNIE=1
NO_STAGE=1
NO_DF=1
NO_FILEHANDLES=1

IOR_CMDS="/scratch1/scratchdirs/glock/run.ior/test.ior"
PROFILE_OUTPUT_DIR="/global/u2/g/glock/blast/profile.19"

#
#  Special stuff just for running at NERSC
#    INPUT - path to file containing input queries
#    DB_DIR - path to directory containing BLAST database
#    SCRATCH_DIR - working directory when application is run; also where
#      database/input queries will be copied if NO_STAGE is not set
#    SCRATCH_DEV - the block device underneath SCRATCH_DEV for iostat to query;
#      leave empty ("") to skip iostat
#    LUSTRE_FS - the Lustre fs name (e.g., snx11025) to be used for profiling;
#      look in /proc/fs/lustre/llite to see options
#
PATH_SET="lustre"
if [ "$PATH_SET" == "lustre" ]; then
    INPUT="/scratch1/scratchdirs/glock/run.ior/blast.db.nsq"
    SCRATCH_DIR="/scratch1/scratchdirs/glock/scratch"
    SCRATCH_DEV=""
    LUSTRE_FS="snx11025"
elif [ "$PATH_SET" == "gpfs" ]; then
    INPUT=""
    SCRATCH_DIR="/global/scratch2/sd/glock/scratch"
    SCRATCH_DEV=""
    LUSTRE_FS=""
elif [ "$PATH_SET" == "bb" ]; then
    INPUT=""
    SCRATCH_DIR="/flash/scratch2/glock/scratch"
    SCRATCH_DEV=""
    LUSTRE_FS=""
elif [ "$PATH_SET" == "local" ]; then
    INPUT=""
    SCRATCH_DEV="/dev/dm-0"
    SCRATCH_DIR="/local/tmp/$USER"
    LUSTRE_FS=""
else
    echo "Unknown PATH_SET=$PATH_SET; aborting" >&2
    exit 1
fi

### Seconds before dropping profile output
### periodic gstack dumping
PROFILE_INTERVAL=1

#
#  Location of various binaries
#
TIME="/global/u2/g/glock/apps.carver/time/bin/time -v"
BONNIE="/global/u2/g/glock/apps.carver/bonnie++/sbin/bonnie++"
BINARY="/global/u2/g/glock/apps.edison/ior-n8/bin/IOR-ompi"
APP_PGREP="IOR"
IS_FILE_IN_PAGE_CACHE="/global/u2/g/glock/bin/is_file_in_page_cache"
DROP_FILE_FROM_PAGE_CACHE="/global/u2/g/glock/bin/drop_file_from_page_cache"

OUTPUT_FILE="ior.out"
OUTPUT_DIR="${PBS_O_WORKDIR-$PWD}"

THREADS="${PBS_NP-24}"
APWRAP="strace -T -ttt -o $OUTPUT_DIR/strace.out"       # when running on cluster
APWRAP="ccmrun -n24"                      # for running on Cray
APWRAP="orterun -np 24 -host localhost"

#
#  Ensure we don't carry over the results from a previous profiling run
#
if [ -d $PROFILE_OUTPUT_DIR ]; then
    echo "$(date) - Need to kill $PROFILE_OUTPUT_DIR"
    if [ -d ${PROFILE_OUTPUT_DIR}.old ]; then
        rm -rf ${PROFILE_OUTPUT_DIR}.old
    fi
    mv -v $PROFILE_OUTPUT_DIR ${PROFILE_OUTPUT_DIR}.old
fi
mkdir -p $PROFILE_OUTPUT_DIR

#
#  Functions to generate profiling data
#
drop_begin() {
    if [ -z "$1" ]; then
        echo "PROF_BEGIN $1"
    else
        echo "PROF_BEGIN $(date +%s)"
    fi
}
startmon() { 
    echo "$(date) - Starting IO profile..."

    if [ ! -z "$SCRATCH_DEV" ]; then
        drop_begin  > $PROFILE_OUTPUT_DIR/prof_iostat.txt
        iostat -dkt $PROFILE_INTERVAL $SCRATCH_DEV >> $PROFILE_OUTPUT_DIR/prof_iostat.txt &
    fi

    for profile_output in prof_df.txt prof_ps.txt prof_filehandles.txt prof_vmstat.txt prof_lustre.txt prof_meminfo.txt prof_gstack.txt
    do
        if [ -e $PROFILE_OUTPUT_DIR/$profile_output ]; then
            rm $PROFILE_OUTPUT_DIR/$profile_output
        fi
    done

    # Try to find the lustre file system stats file
    LUSTRE_PROC_STATS=""
    if [ ! -z "$LUSTRE_FS" ]; then
        LUSTRE_PROC_STATS=$(find /proc/fs/lustre/llite -name stats 2>/dev/null | grep "$LUSTRE_FS")
        if [ -z "$LUSTRE_PROC_STATS" ]; then
            echo "$(date) - Could not find Lustre fs stats file for $LUSTRE_FS"
        else
            echo "$(date) - Found Lustre fs stats file at $LUSTRE_PROC_STATS"
        fi
    fi

    while [ 1 ]
    do 
        # One timestamp for each record to ensure all profile outputs' columns
        # can be pasted together and remain in-phase
        timestamp=$(date +%s)

        # save record of ssd capacity
        if [ -z "$NO_DF" ]; then
            drop_begin $timestamp >> $PROFILE_OUTPUT_DIR/prof_df.txt
            df -k >> $PROFILE_OUTPUT_DIR/prof_df.txt
        fi

        # save record of running processes
        drop_begin $timestamp >> $PROFILE_OUTPUT_DIR/prof_ps.txt
        ps -U $USER -o pid,ppid,lwp,nlwp,etime,pcpu,pmem,rss,vsz,maj_flt,min_flt,state,cmd -www >> $PROFILE_OUTPUT_DIR/prof_ps.txt

        # save record of open file handles
        if [ -z "$NO_FILEHANDLES" ]; then
            drop_begin $timestamp >> $PROFILE_OUTPUT_DIR/prof_filehandles.txt
            cat /proc/sys/fs/file-nr >> $PROFILE_OUTPUT_DIR/prof_filehandles.txt
        fi

        # save record of virtual memory state
        drop_begin $timestamp >> $PROFILE_OUTPUT_DIR/prof_vmstat.txt
        cat /proc/vmstat >> $PROFILE_OUTPUT_DIR/prof_vmstat.txt

        # save record of memory
        drop_begin $timestamp >> $PROFILE_OUTPUT_DIR/prof_meminfo.txt
        cat /proc/meminfo >> $PROFILE_OUTPUT_DIR/prof_meminfo.txt
 
        # only attempt to drop Lustre stats if the fs is mounted
        if [ ! -z "$LUSTRE_PROC_STATS" ]; then
            drop_begin $timestamp >> $PROFILE_OUTPUT_DIR/prof_lustre.txt
            cat $LUSTRE_PROC_STATS ${LUSTRE_PROC_STATS%stats}statahead_stats ${LUSTRE_PROC_STATS%stats}read_ahead_stats >> $PROFILE_OUTPUT_DIR/prof_lustre.txt
        fi

        # only probe the process stack if we are doing coarse-grained profiling
        if [ ${PROFILE_INTERVAL} -ge 5 ]; then
            my_pid=$(pgrep $APP_PGREP | head -n1)
            if [ ! -z "$my_pid" ]; then
                drop_begin $timestamp >> $PROFILE_OUTPUT_DIR/prof_gstack.txt
                gstack $my_pid 2>&1 >> $PROFILE_OUTPUT_DIR/prof_gstack.txt
            fi
        fi

        sleep ${PROFILE_INTERVAL}s

    done
}

#
#  Stage in input data and create database alias file
#
if [ -d "$SCRATCH_DIR" ]; then
    rm -rf $SCRATCH_DIR
fi
mkdir -p $SCRATCH_DIR || exit 1
if [ ! $NO_STAGE ]; then
    echo "$(date) - Staging in $INPUT ($(du -hcs $INPUT | tail -n1 | cut -d\t -f1))"
    cp -v $INPUT $SCRATCH_DIR/
fi

#
#  Run bonnie++ to scramble the disk cache and get rid of the files we just
#  copied to $SCRATCH_DIR
#
if [ ! $NO_BONNIE ]; then
    memtot_mib=$(awk '/MemTotal:/ { print int($2/1024) + 1 }' /proc/meminfo)
    echo "$(date) - Running bonnie++ assuming $memtot_mib MB of RAM"
    set -x
    $TIME $BONNIE -d $SCRATCH_DIR -m $NERSC_HOST -r $memtot_mib 2>&1
    set +x
    echo "$(date) - Finished bonnie++"
fi

#
#  Drop all of the files we just copied from cache
#
if [ ! $NO_STAGE -a -f "$IS_FILE_IN_PAGE_CACHE" -a -f "$DROP_FILE_FROM_PAGE_CACHE" ]; then
    echo "$(date) - Purging staged data from file cache"
    for i in $SCRATCH_DIR/${dbfile}*; do
        echo -n "$(date) - "
        $IS_FILE_IN_PAGE_CACHE $i
        echo "$(date) - Dropping $i from cache"
        $DROP_FILE_FROM_PAGE_CACHE $i
        echo -n "$(date) - "
        $IS_FILE_IN_PAGE_CACHE $i
    done
    ### Let dirty pages and stuff flush out
    sleep 300
fi

#
#  Start profiling
#
if [ ! $NO_PROFILE ]; then
    startmon &
    monpid=$!
    sleep 5
fi

#
#  Launch application
#
echo "$(date) - Running command"
set -x
$APWRAP $BINARY -f "$IOR_CMDS" > $SCRATCH_DIR/$OUTPUT_FILE 2> $SCRATCH_DIR/${OUTPUT_FILE%out}err
set +x
echo "$(date) - Finished running command"

if [ ! $NO_PROFILE ]; then
    ### Let one last ps/df fire before shutting everything down
    sleep 90
    kill $monpid
fi

#
#  Post-run stage-off and cleanup
#
echo "$(date) - Begin moving output data off of local disk"
mv -v $SCRATCH_DIR/$OUTPUT_FILE $OUTPUT_DIR/
mv -v $SCRATCH_DIR/${OUTPUT_FILE%out}err $OUTPUT_DIR/
echo "$(date) - Finished moving output data off of local disk"

echo "$(date) - Removing $SCRATCH_DIR"
rm -rf $SCRATCH_DIR
echo "$(date) - Done cleaning up $SCRATCH_DIR"
