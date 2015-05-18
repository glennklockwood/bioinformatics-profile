#!/bin/bash

INPUT_DIR=$1
OUTPUT_DIR=$2
SCRATCH_DIR="/ssd"
SCRATCH_DEV="/dev/md0"

if [ ! -d "$INPUT_DIR" ]; then
  echo "Input dir $INPUT_DIR not found; aborting" >&2
  exit 1
fi
if [ -d $OUTPUT_DIR ]; then
  echo "Need to kill $OUTPUT_DIR"
  if [ -d ${OUTPUT_DIR}.old ]; then
    rm -rf ${OUTPUT_DIR}.old
  fi
  mv -v $OUTPUT_DIR ${OUTPUT_DIR}.old
fi
mkdir -p $OUTPUT_DIR

PROFILE_OUTPUT_DIR="$OUTPUT_DIR"
### start monitoring
drop_begin() {
    echo "PROF_BEGIN $(date +%s)"
}
startmon() { 
    echo "Starting IO profile..."
    drop_begin  > $PROFILE_OUTPUT_DIR/prof_iostat.txt
    iostat -dkt 30 $SCRATCH_DEV >> $PROFILE_OUTPUT_DIR/prof_iostat.txt &

    if [ -e $PROFILE_OUTPUT_DIR/prof_df.txt ]; then
    rm $PROFILE_OUTPUT_DIR/prof_df.txt
    fi
    if [ -e $PROFILE_OUTPUT_DIR/prof_ps.txt ]; then
    rm $PROFILE_OUTPUT_DIR/prof_ps.txt
    fi
    while [ 1 ]
    do 
        # save record of ssd capacity
        drop_begin >> $PROFILE_OUTPUT_DIR/prof_df.txt
        df -k >> $PROFILE_OUTPUT_DIR/prof_df.txt

        # save record of running processes
        drop_begin >> $PROFILE_OUTPUT_DIR/prof_ps.txt
        ps -U $USER -o pid,ppid,lwp,nlwp,etime,pcpu,pmem,rss,vsz,cmd -www >> $PROFILE_OUTPUT_DIR/prof_ps.txt
        sleep 1m
    done
}

startmon &
monpid=$!
### end monitoring

tag=$(date +%Y%m%d%H%M%S)

cd $SCRATCH_DIR

### We assume that RunLatest is in $PATH
tstart=$(date +%s)
echo "Running pipeline at $(date) ($tstart)"
RunLatest -r $INPUT_DIR -a $OUTPUT_DIR 2>&1 | tee $OUTPUT_DIR/prof_isislog.txt
ecode=$?
tend=$(date +%s)
echo "Done running pipeline at $(date) ($tend)"

### Let one last ps/df fire before shutting everything down
sleep 90
kill $monpid

output_tar=$SCRATCH_DIR/$(basename $OUTPUT_DIR)-${tag}.tar
tar -C $(dirname $OUTPUT_DIR) -cf $output_tar $(basename $OUTPUT_DIR)
aws s3 cp $output_tar s3://10x.armada.results/

if [ $ecode -ne 0 ]; then
    mailx -s "job failed" glock@10xgenomics.com <<EOF
The pipeline being run in $OUTPUT_DIR just failed.  The results are 
available at s3://10x.armada.results/$(basename $output_tar).

The job took $(($tend - $tstart)) seconds.
EOF
else
mailx -s "job done" glock@10xgenomics.com <<EOF
I just finished the pipeline being run in $OUTPUT_DIR.  The results are 
available at s3://10x.armada.results/$(basename $output_tar)

The job took $(($tend - $tstart)) seconds.
EOF
fi
