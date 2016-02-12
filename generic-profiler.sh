#!/bin/bash
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

# use Lustre so dvs ipc counters don't get poisoned by the profile
PROFILE_OUTPUT_DIR="/global/cscratch1/sd/glock/profile.47" 

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
PATH_SET="dw"

if [ "$PATH_SET" == "lustre-cori" ]; then
    INPUT="/global/cscratch1/sd/glock/blast/blast.input/contigs.fa"
    DB_DIR="/global/cscratch1/sd/glock/blast/blast.db"
    SCRATCH_DIR="/global/cscratch1/sd/glock/blast/scratch"
    SCRATCH_DEV=""
    LUSTRE_FS="snx11168"  # cori
elif [ "$PATH_SET" == "lustre-edison" ]; then
    INPUT="/scratch1/scratchdirs/glock/blast/blast.input/contigs.fa"
    DB_DIR="/scratch1/scratchdirs/glock/blast/blast.db"
    SCRATCH_DIR="/scratch1/scratchdirs/glock/blast/scratch"
    SCRATCH_DEV=""
    LUSTRE_FS="snx11025"  # edison
elif [ "$PATH_SET" == "gpfs-cori" ]; then
    INPUT="/global/projectb/scratch/glock/blast.input/contigs.fa"
    DB_DIR="/global/projectb/scratch/glock/blast.db"
    SCRATCH_DIR="/global/projectb/scratch/glock/blast.db/scratch"
    DVS_FS="/global/projectb"
elif [ "$PATH_SET" == "dw" ]; then
    INPUT="/global/cscratch1/sd/glock/blast/blast.input/contigs.fa"
    DB_DIR="$DW_JOB_STRIPED/blast.db"
    SCRATCH_DIR="$DW_JOB_STRIPED/scratch"
    SCRATCH_DEV=""
    DVS_FS="/var/opt/cray/dws/mounts/registrations"
elif [ "$PATH_SET" == "local" ]; then
    INPUT="/global/scratch2/sd/glock/blast.input/contigs.fa"
    DB_DIR="/global/scratch2/sd/glock/blast.db"
    SCRATCH_DEV="/dev/dm-0"
    SCRATCH_DIR="/local/tmp/$USER"
else
    echo "Unknown PATH_SET=$PATH_SET; aborting" >&2
    exit 1
fi

### Number of database shards to use
DBS="nt_dustmasked.00 nt_dustmasked.01 nt_dustmasked.02 nt_dustmasked.03 nt_dustmasked.04 nt_dustmasked.05 nt_dustmasked.06 nt_dustmasked.07 nt_dustmasked.08 nt_dustmasked.09 nt_dustmasked.10 nt_dustmasked.11 nt_dustmasked.12 nt_dustmasked.13"

### Seconds before dropping profile output
### periodic gstack dumping
PROFILE_INTERVAL=1

#
#  Location of various binaries
#
TIME="/global/u2/g/glock/apps.carver/time/bin/time -v"
BONNIE="/global/u2/g/glock/apps.carver/bonnie++/sbin/bonnie++"
BINARY="/global/cscratch1/sd/glock/src/blastn.cori"
APP_PGREP="$(basename $BINARY)"
IS_FILE_IN_PAGE_CACHE="/global/u2/g/glock/bin/is_file_in_page_cache"
DROP_FILE_FROM_PAGE_CACHE="/global/u2/g/glock/bin/drop_file_from_page_cache"

OUTPUT_FILE="blastn.out"
OUTPUT_DIR="${PBS_O_WORKDIR-$PWD}"

THREADS="${PBS_NP-24}"
APWRAP=""

clean_profile_dir() {
    #
    #  Ensure we don't carry over the results from a previous profiling run
    #
    PROFILE_OUTPUT_DIR=$1
    if [ -d $PROFILE_OUTPUT_DIR ]; then
        echo "$(date) - Need to kill $PROFILE_OUTPUT_DIR"
        if [ -d ${PROFILE_OUTPUT_DIR}.old ]; then
            rm -rf ${PROFILE_OUTPUT_DIR}.old
        fi
        mv -v $PROFILE_OUTPUT_DIR ${PROFILE_OUTPUT_DIR}.old
    fi
    mkdir -p $PROFILE_OUTPUT_DIR
}

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

    for profile_output in prof_df.txt prof_ps.txt prof_filehandles.txt prof_vmstat.txt prof_lustre.txt prof_meminfo.txt prof_gstack.txt prof_lcache.txt prof_dvs.txt prof_dvs_ipc.txt
    do
        if [ -e $PROFILE_OUTPUT_DIR/$profile_output ]; then
            rm $PROFILE_OUTPUT_DIR/$profile_output
        fi
    done

    # Try to find the DataWarp file system stats file
    DVS_PROC_STATS=""
    if [ ! -z "$DVS_FS" ]; then
        DVS_PROC_STATS=$(mount | grep -m1 "$DVS_FS" | grep -o 'nodefile=[^,]*,' | cut -d= -f2 | sed -e's/,$//' -e's/nodenames/stats/')
        if [ -z "$DVS_PROC_STATS" ]; then
            echo "$(date) - Could not find DataWarp/DVS fs stats file for $DVS_FS"
        else
            echo "$(date) - Found DataWarp/DVS fs stats file at $DVS_PROC_STATS"
        fi
    fi

    # Try to find the Lustre file system stats file
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
            drop_begin $timestamp >> $PROFILE_OUTPUT_DIR/prof_lcache.txt
            cat ${LUSTRE_PROC_STATS%stats}max_cached_mb >> $PROFILE_OUTPUT_DIR/prof_lcache.txt
        fi

        # only attempt to drop DataWarp/DVS stats if the fs is mounted
        if [ ! -z "$DVS_PROC_STATS" ]; then
            # per-filesystem counters
            drop_begin $timestamp >> $PROFILE_OUTPUT_DIR/prof_dvs.txt
            cat $DVS_PROC_STATS >> $PROFILE_OUTPUT_DIR/prof_dvs.txt

            # ipc counters
            drop_begin $timestamp >> $PROFILE_OUTPUT_DIR/prof_dvs_ipc.txt
            cat /proc/fs/dvs/ipc/stats >> $PROFILE_OUTPUT_DIR/prof_dvs_ipc.txt
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

stage_in() {
    #
    #  Stage in input data and create database alias file
    #
    for dbfile in $*
    do
        echo "$(date) - Staging in $DB_DIR/${dbfile}* ($(du -hcs $DB_DIR/${dbfile}* | tail -n1 | cut -d\t -f1))"
        cp -v $DB_DIR/${dbfile}* $SCRATCH_DIR/
    done
    echo $SCRATCH_DIR
}

generate_nal() {
    #
    #  Create the deck that defines database shard file names
    #
    target_nal=$1
    shift
    echo "$(date) - Creating $target_nal"
    cat << EOF > $target_nal
TITLE nt
DBLIST $*
EOF
}

run_bonnie() {
    #
    #  Run bonnie++ to scramble the disk cache and get rid of the files we just
    #  copied to $SCRATCH_DIR
    #
    SCRATCH_DIR=$1
    memtot_mib=$(awk '/MemTotal:/ { print int($2/1024) + 1 }' /proc/meminfo)
    echo "$(date) - Running bonnie++ assuming $memtot_mib MB of RAM"
    set -x
    $TIME $BONNIE -d $SCRATCH_DIR -m $NERSC_HOST -r $memtot_mib 2>&1
    set +x
    echo "$(date) - Finished bonnie++"
}

purge_files_from_cache() {
    #
    #  Drop all of the files we just copied from cache
    #
    for i in $*
    do
        echo -n "$(date) - "
        $IS_FILE_IN_PAGE_CACHE $i
        echo "$(date) - Dropping $i from cache"
        $DROP_FILE_FROM_PAGE_CACHE $i
        echo -n "$(date) - "
        $IS_FILE_IN_PAGE_CACHE $i
    done
    ### Let dirty pages and stuff flush out
    sleep 10
}

################################################################################
### End of function definitions ################################################
################################################################################

################################################################################
### Begin profiled workflow ####################################################
################################################################################

clean_profile_dir $PROFILE_OUTPUT_DIR

test -d "$SCRATCH_DIR" && rm -r "$SCRATCH_DIR"
mkdir -p $SCRATCH_DIR || exit 1

if [ ! $NO_STAGE ]; then
    DB_DIR=$(stage_in $DBS)
fi

generate_nal $DB_DIR/testdb.nal $DBS

if [ ! $NO_BONNIE ]; then
    run_bonnie $SCRATCH_DIR
fi

if [ ! $NO_STAGE -a -f "$IS_FILE_IN_PAGE_CACHE" -a -f "$DROP_FILE_FROM_PAGE_CACHE" ]; then
    echo "$(date) - Purging staged data from file cache"
    purge_files_from_cache $SCRATCH_DIR/${dbfile}*
elif [ -f "$IS_FILE_IN_PAGE_CACHE" -a -f "$DROP_FILE_FROM_PAGE_CACHE" ]; then
    purge_files_from_cache ${DB_DIR}/*
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
echo "$(date) - Running command (check stderr for invocation)"
set -x
export BATCH_SIZE=4999000
$APWRAP $BINARY \
    -num_threads $THREADS \
    -evalue 1e-30 \
    -perc_identity 90 \
    -word_size 45 \
    -task megablast \
    -outfmt 0 \
    -query $INPUT \
    -db ${DB_DIR}/testdb > $SCRATCH_DIR/${OUTPUT_FILE} 2> $SCRATCH_DIR/${OUTPUT_FILE%out}err
set +x
echo "$(date) - Finished running command"

if [ ! $NO_PROFILE ]; then
    ### Let one last ps/df fire before shutting everything down
    sleep 30
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
