#!/bin/bash

### Options
INPUT_DIR=$1
OUTPUT_DIR=$2
# define PRECALLED_VCF to the path of a precalled vcf to enable wgs mode
# PRECALLED_VCF=/ssd/NA12878_v3.vcf
NO_BCLPROCESSOR=1
### define EXOME_TARGETS to the path of a targets bed to enable exome mode
# EXOME_TARGETS=/ssd/agilent_exome_v5_targs.bed
# NO_PROFILE=1
MRP_PORT_FLAG='--uiport=3600'
SCRATCH_DIR="/ssd"
SCRATCH_DEV="/dev/md0"

if [ "$PRECALLED_VCF" -a ! -f "$PRECALLED_VCF" ]; then
    echo "Precalled VCF $PRECALLED_VCF not found" >&2
    exit 1
fi

if [ "$EXOME_TARGETS" -a ! -f "$EXOME_TARGETS" ]; then
    echo "Exome targets file $EXOME_TARGETS not found" >&2
    exit 1
fi

if [ -z "$INPUT_DIR" -o -z "$OUTPUT_DIR" ]; then
    echo "Syntax: $0 INPUT_DIR OUTPUT_DIR"
    echo ""
    echo "INPUT_DIR is a flowcell directory which gets renamed to INPUT_DIR.in"
    echo "for bclprocessor, which then outputs to INPUT_DIR.  longranger then"
    echo "takes the fastqs generated to INPUT_DIR/outs/fastq_path as input and"
    echo "outputs to OUTPUT_DIR-output.  The profiling data is output to"
    echo "OUTPUT_DIR."
    exit 1
fi

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

if [ ! $NO_PROFILE ]; then
    startmon &
    monpid=$!
    ### end monitoring
fi

tag=$(date +%Y%m%d%H%M%S)

cd $SCRATCH_DIR

### We assume 
###  1. TENX_REFDATA is already set
###  2. sourceme.bash has already been sourced
###  3. bcl2fastq is in $PATH
tstart=$(date +%s)
echo "Running pipeline at $(date) ($tstart)"

### Option to exclude bclprocessor
if [ ! $NO_BCLPROCESSOR ]; then
    mv -v $INPUT_DIR ${INPUT_DIR}.in
    bclprocessor --run=${INPUT_DIR}.in $MRP_PORT_FLAG 2>&1
    ecode=$?
    tend=$(date +%s)
fi
#### TODO TODO TODO TODO!
### need to check for errors in bclprocessor here in case it fails!  if it 
### fails, do NOT run longranger!
#### TODO TODO TODO TODO!
if [ $PRECALLED_VCF ]; then
    longranger --sample=$(basename ${OUTPUT_DIR})-pipestance \
               --sex=female \
               --fastqs=${INPUT_DIR}/outs/fastq_path \
               --indices=any \
               --vc_mode=precalled:$PRECALLED_VCF $MRP_PORT_FLAG 2>&1
    ecode=$?
    tend=$(date +%s)
elif [ $EXOME_TARGETS ]; then
    longranger --sample=$(basename ${OUTPUT_DIR})-pipestance \
               --sex=female \
               --fastqs=${INPUT_DIR}/outs/fastq_path \
               --indices=any \
               --targets=$EXOME_TARGETS $MRP_PORT_FLAG 2>&1
    ecode=$?
    tend=$(date +%s)
else
    longranger --sample=$(basename ${OUTPUT_DIR})-pipestance \
               --sex=female \
               --fastqs=${INPUT_DIR}/outs/fastq_path \
               --indices=any \
               --vc_mode=freebayes $MRP_PORT_FLAG 2>&1
    ecode=$?
    tend=$(date +%s)
fi
echo "Done running pipeline at $(date) ($tend)"

if [ ! $NO_PROFILE ]; then
    ### Let one last ps/df fire before shutting everything down
    sleep 90
    kill $monpid
fi

### Preserve output data:
###  $(basename $OUTPUT_DIR) contains the prof_*.txt files
###  $(basename $OUTPUT_DIR)-pipestance contains the phaser_svcaller output
###  $(basename $INPUT_DIR) contains the bclprocessor output
output_tar=$SCRATCH_DIR/$(basename $OUTPUT_DIR)-${tag}.tar
tar -C $(dirname $OUTPUT_DIR) -cf $output_tar \
    $(basename $OUTPUT_DIR) \
    $(basename $OUTPUT_DIR)-pipestance \
    $(basename $INPUT_DIR)
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
