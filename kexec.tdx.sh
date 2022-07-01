#!/usr/bin/bash

# a template to prepare for kexec test from scratch

# variables
#KERNEL_IMAGE=/home/tdx/git_tdx_github/tdx/arch/x86/boot/bzImage.tdx-guest-v5.17-2
QEMU_IMAGE=/home/tdx/git_qemu_github/qemu-tdx/build/qemu-system-x86_64.tdx-upstream-wip-20220601-0c841693eb
#BIOS_IMAGE=/usr/share/qemu/OVMF.fd
BIOS_IMAGE=/home/tdx/git_edk2_github/edk2/Build/OvmfX64/DEBUG_GCC5/FV/OVMF.9c733f0b90.fd
GUEST_IMAGE=/home/tdx/guest_image/td-guest-cs8.syzkaller.qcow2
DISK_TARGET=target.qcow2
#KERNEL_TARGET=$1
#INITRD_TARGET=$2
#KEXEC_SCRIPT_TARGET=$3

# do the work
# common functions
usage() {
  cat <<-EOF
  usage: ./${0##*/}
  -o ORIGINAL_KERNEL to run
  -k TARGET_KERNEL to run
  -i TARGET_INITRD to run
  -s TARGET_KEXEC_SCRIPT to tun
  -h print this usage
EOF
}

while getopts :o:k:i:s:h arg; do
  case $arg in
  o)
    KERNEL_IMAGE=$OPTARG
    ;;
  k)
    KERNEL_TARGET=$OPTARG
    ;;
  i)
    INITRD_TARGET=$OPTARG
    ;;
  s)
    KEXEC_SCRIPT_TARGET=$OPTARG
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

if [ $# -lt 4 ]; then
	echo "arguments provided unexpected"
	usage && exit 1
fi

# list all arguments passed through
echo "kexec test arguments:"
echo "orginal kernel: $KERNEL_IMAGE"
echo "target kernel: $KERNEL_TARGET"
echo "target initrd: $INITRD_TARGET"
echo "target kexec script: $KEXEC_SCRIPT_TARGET"
echo "#########################################"


# create new $DISK_TARGET for target kernel and initramfs
echo "remove existing $DISK_TARGET file"
if [ -f "$DISK_TARGET" ]; then
	rm $DISK_TARGET
fi

lsblk | grep nbd0 && umount /dev/nbd0p1 && qemu-nbd -d /dev/nbd0

echo "create new $DISK_TARGET file with 5GB size"
qemu-img create -f qcow2 $DISK_TARGET 5G

echo "modprobe nbd for file $KERNEL_TARGET and $INITRD_TARGET transfer" 
lsmod | grep nbd || modprobe nbd || echo "Failed to probe nbd module"

echo "create filesystem for new $DISK_TARGET file"
qemu-nbd -c /dev/nbd0 $DISK_TARGET
echo -e "o\nn\np\n1\n\n\nw" | fdisk /dev/nbd0
mkfs.ext4 -F /dev/nbd0p1 || echo "Failed to create filesystem for new $DISK_TARGET file"

echo "transfer target kernel/initrd images and kexec test script to $DISK_TARGET"
mkdir -p temp
mount /dev/nbd0p1 $PWD/temp
cp $KERNEL_TARGET $PWD/temp/ || exit 1
cp $INITRD_TARGET $PWD/temp/ || exit 1
cp $KEXEC_SCRIPT_TARGET $PWD/temp/ || exit 1
umount /dev/nbd0p1 || exit 1
qemu-nbd -d /dev/nbd0 || exit 1
rm -rf temp

# launch VM with $DISK_TARGET for kexec test
$QEMU_IMAGE \
	-accel kvm \
	-no-reboot \
	-name process=tdx-kexec,debug-threads=on \
	-cpu host,host-phys-bits,pmu=off \
	-m 8G \
	-smp 2 \
	-object tdx-guest,id=tdx,debug=off,sept-ve-disable=off,quote-generation-service=vsock:2:4050 \
	-machine q35,kernel_irqchip=split,confidential-guest-support=tdx \
	-bios $BIOS_IMAGE \
	-nographic \
	-vga none \
        -device virtio-net-pci,netdev=mynet0,mac=00:16:3E:68:08:FF,romfile= \
        -netdev user,id=mynet0,hostfwd=tcp::10030-:22,hostfwd=tcp::12030-:2375 \
        -device vhost-vsock-pci,guest-cid=30 \
        -chardev stdio,id=mux,mux=on \
        -device virtio-serial,romfile= \
        -device virtconsole,chardev=mux \
        -serial chardev:mux \
        -monitor chardev:mux \
	-drive format=qcow2,if=virtio,file=$GUEST_IMAGE \
	-drive format=qcow2,file=$DISK_TARGET \
	-kernel ${KERNEL_IMAGE} \
	-append "root=/dev/vda3 ro console=hvc0 earlyprintk=ttyS0 keep ignore_loglevel debug earlyprintk initcall_debug l1tf=off log_buf_len=200M" \
