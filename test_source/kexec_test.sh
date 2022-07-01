#!/usr/bin/bash

#KERNEL_TARGET=$1
#INITRD_TARGET=$2
#CMDLINE_TARGET=$3
usage() {
  cat <<-EOF
  usage: ./${0##*/}
  -k TARGET_KERNEL to run
  -i TARGET_INITRD to run
  -c TARGET_CMDLINE to tun
  -h print this usage
EOF
}

while getopts :k:i:c:h arg; do
  case $arg in
  k)
    KERNEL_TARGET=$OPTARG
    ;;
  i)
    INITRD_TARGET=$OPTARG
    ;;
  c)
    CMDLINE_TARGET=$OPTARG
    ;;
  h)
    usage && exit 0
    ;;
  :)
    echo "Must supply all arguments to -$OPTARG."
    usage && exit 1
    ;;
  \?)
    echo "Invalid Option -$OPTARG ignored."
    usage && exit 1
    ;;
  esac
done

echo "run kexec test with kernel: $KERNEL_TARGET, \
	initrd: $INITRD_TARGET, \
	cmdline: $CMDLINE_TARGET"

kexec -l $KERNEL_TARGET \
	--append=$CMDLINE_TARGET \
	--initrd=$INITRD_TARGET \
	&& kexec -e
exit 0
