#!/usr/bin/env sh
set -e

if [ -z $MOUNTPOINT ]; then
    MOUNTPOINT=/tmp
fi

if [ -z $FIO_FILE_SIZE ]; then
    FIO_FILE_SIZE=2G
fi

if [ -z $FIO_OFFSET_INCREMENT ]; then
    FIO_OFFSET_INCREMENT=500M
fi

if [ -z $FIO_RAMP_TIME ]; then
    FIO_RAMP_TIME=10s
fi

if [ -z $FIO_RUN_TIME ]; then
    FIO_RUN_TIME=30s
fi

echo Current Working dir: $MOUNTPOINT
echo

echo Taking Read IOPS performance values
READ_IOPS_OUTPUT=$(fio --randrepeat=0 --verify=0 --ioengine=libaio --direct=1 --gtod_reduce=1 --name=read_iops --filename=$MOUNTPOINT/fiofile --bs=4K --iodepth=64 --size=$FIO_FILE_SIZE --readwrite=randread --time_based --ramp_time=$FIO_RAMP_TIME --runtime=$FIO_RUN_TIME)
echo "$READ_IOPS_OUTPUT"
READ_IOPS_VALUE=$(echo "$READ_IOPS_OUTPUT"|grep -E 'read ?:'|grep -Eoi 'IOPS=[0-9k.]+'|cut -d'=' -f2)
echo ---------------------------------------------------------------------------------
echo

echo Taking Write IOPS performance values
WRITE_IOPS_OUTPUT=$(fio --randrepeat=0 --verify=0 --ioengine=libaio --direct=1 --gtod_reduce=1 --name=write_iops --filename=$MOUNTPOINT/fiofile --bs=4K --iodepth=64 --size=$FIO_FILE_SIZE --readwrite=randwrite --time_based --ramp_time=$FIO_RAMP_TIME --runtime=$FIO_RUN_TIME)
echo "$WRITE_IOPS_OUTPUT"
WRITE_IOPS_VALUE=$(echo "$WRITE_IOPS_OUTPUT"|grep -E 'write:'|grep -Eoi 'IOPS=[0-9k.]+'|cut -d'=' -f2)
echo ---------------------------------------------------------------------------------
echo

echo Taking Read Sequential IPOS performance values
READ_SEQ_OUTPUT=$(fio --randrepeat=0 --verify=0 --ioengine=libaio --direct=1 --gtod_reduce=1 --name=read_seq --filename=$MOUNTPOINT/fiofile --bs=1M --iodepth=16 --size=$FIO_FILE_SIZE --readwrite=read --time_based --ramp_time=$FIO_RAMP_TIME --runtime=$FIO_RUN_TIME --thread --numjobs=4 --offset_increment=$FIO_OFFSET_INCREMENT)
echo "$READ_SEQ_OUTPUT"
READ_SEQ_VALUE=$(echo "$READ_SEQ_OUTPUT"|grep -E 'READ:'|grep -Eoi '(aggrb|bw)=[0-9GMKiBs/.]+'|cut -d'=' -f2)
echo ---------------------------------------------------------------------------------
echo

echo Taking Write Sequential IPOS performance values
WRITE_SEQ_OUTPUT=$(fio --randrepeat=0 --verify=0 --ioengine=libaio --direct=1 --gtod_reduce=1 --name=write_seq --filename=$MOUNTPOINT/fiofile --bs=1M --iodepth=16 --size=$FIO_FILE_SIZE --readwrite=write --time_based --ramp_time=$FIO_RAMP_TIME --runtime=$FIO_RUN_TIME --thread --numjobs=4 --offset_increment=$FIO_OFFSET_INCREMENT)
echo "$WRITE_SEQ_OUTPUT"
WRITE_SEQ_VALUE=$(echo "$WRITE_SEQ_OUTPUT"|grep -E 'WRITE:'|grep -Eoi '(aggrb|bw)=[0-9GMKiBs/.]+'|cut -d'=' -f2)
echo ---------------------------------------------------------------------------------
echo

echo Taking Read/Write IPOS performance values
READ_WRITE_MIX=$(fio --randrepeat=0 --verify=0 --ioengine=libaio --direct=1 --gtod_reduce=1 --name=rw_mix --filename=$MOUNTPOINT/fiofile --bs=4k --iodepth=64 --size=$FIO_FILE_SIZE --readwrite=randrw --rwmixread=75 --time_based --ramp_time=$FIO_RAMP_TIME --runtime=$FIO_RUN_TIME)
echo "$READ_WRITE_MIX"
MIX_READ_IOPS_VALUE=$(echo "$READ_WRITE_MIX"|grep -E 'read ?:'|grep -Eoi 'IOPS=[0-9k.]+'|cut -d'=' -f2)
MIX_WRITE_IOPS_VALUE=$(echo "$READ_WRITE_MIX"|grep -E 'write:'|grep -Eoi 'IOPS=[0-9k.]+'|cut -d'=' -f2)
echo ---------------------------------------------------------------------------------
echo

echo All tests complete.
echo
echo ==================
echo = Summary =
echo ==================
echo "Random Read IOPS Value:      $READ_IOPS_VALUE"
echo "Random Write IOPS Value:     $WRITE_IOPS_VALUE"
echo "Mixed Read IOPS Value:       $MIX_READ_IOPS_VALUE"
echo "Mixed Write IOPS Value:      $MIX_WRITE_IOPS_VALUE"
echo "Sequential Read IOPS Value:  $READ_SEQ_VALUE"
echo "Sequential Write IOPS Value: $WRITE_SEQ_VALUE"
rm $MOUNTPOINT/fiofile
exit 0
