#!/bin/bash
clear

# Initia script by @glewarne big thanks!
# Huge modded by @dorimanx, big thanks to him too!

# What you need installed to compile
# gcc, gpp, cpp, c++, g++, lzma, lzop, ia32-libs

# What you need to make configuration easier by using xconfig
# qt4-dev, qmake-qt4, pkg-config

# Structure for building and using this script

# location
KERNELDIR=$(readlink -f .);
export PATH=$PATH:tools/lz4demo

# begin by ensuring the required directory structure is complete, and empty
echo "Initialising................."
rm -rf "$KERNELDIR"/READY-KERNEL/boot
rm -f "$KERNELDIR"/READY-KERNEL/*.zip
rm -f "$KERNELDIR"/READY-KERNEL/*.img
mkdir -p "$KERNELDIR"/READY-KERNEL/boot

# force regeneration of .dtb and zImage files for every compile
rm -f arch/arm/boot/*.dtb
rm -f arch/arm/boot/*.cmd
rm -f arch/arm/boot/zImage
rm -f arch/arm/boot/Image


BUILD_NOW()
{
	if [ -e /usr/bin/python3 ]; then
		rm /usr/bin/python
		ln -s /usr/bin/python2.7 /usr/bin/python
	fi;

	# move into the kernel directory and compile the main image
	echo "Compiling Kernel.............";
	make temiz_kernel_d802_defconfig

	# remove all old modules before compile
	for i in $(find "$KERNELDIR"/ -name "*.ko"); do
		rm -f "$i";
	done;

	# Copy needed dtc binary to system to finish the build.
	if [ ! -e /bin/dtc ]; then
		cp -a tools/dtc-binary/dtc /bin/;
	fi;

	# Idea by savoca
	NR_CPUS=$(grep -c ^processor /proc/cpuinfo)

	if [ "$NR_CPUS" -le "2" ]; then
		NR_CPUS=4;
		echo "Building kernel with 4 CPU threads";
	else
		echo "Building kernel with $NR_CPUS CPU threads";
	fi;

	# build zImage
	time make -j ${NR_CPUS}

	stat "$KERNELDIR"/arch/arm/boot/zImage || exit 1;

	# compile the modules, and depmod to create the final zImage
	echo "Compiling Modules............"
	time make modules -j ${NR_CPUS} || exit 1

	# move the compiled zImage and modules into the READY-KERNEL working directory
	echo "Move compiled objects........"

	for i in $(find "$KERNELDIR" -name '*.ko'); do
		cp -av "$i" "$KERNELDIR"/READY-KERNEL/modules/;
	done;

	chmod 755 "$KERNELDIR"/READY-KERNEL/modules/*

	# remove empty directory placeholders from tmp-initramfs
	for i in $(find ../ramdisk/ -name EMPTY_DIRECTORY); do
		rm -f "$i";
	done;

	if [ -e "$KERNELDIR"/arch/arm/boot/zImage ]; then
		cp arch/arm/boot/zImage READY-KERNEL/boot

		# create the ramdisk and move it to the output working directory
		echo "Create ramdisk..............."
		scripts/mkbootfs ../ramdisk | gzip > ramdisk.gz 2>/dev/null
		mv ramdisk.gz READY-KERNEL/boot

		# create the dt.img from the compiled device files, necessary for msm8974 boot images
		echo "Create dt.img................"
		./scripts/dtbTool -v -s 2048 -o READY-KERNEL/boot/dt.img arch/arm/boot/

		# build the final boot.img ready for inclusion in flashable zip
		echo "Build boot.img..............."
		cp scripts/mkbootimg READY-KERNEL/boot
		cd READY-KERNEL/boot
		base=0x00000000
		offset=0x05000000
		tags_addr=0x04800000
		cmd_line="console=ttyHSL0,115200,n8 androidboot.hardware=g2 user_debug=31 msm_rtb.filter=0x0 mdss_mdp.panel=1:dsi:0:qcom,mdss_dsi_g2_lgd_cmd"
		./mkbootimg --kernel zImage --ramdisk ramdisk.gz --cmdline "$cmd_line" --base $base --offset $offset --tags-addr $tags_addr --pagesize 2048 --dt dt.img -o newboot.img
		mv newboot.img ../boot.img

		# cleanup all temporary working files
		echo "Post build cleanup..........."
		cd ..
		rm -rf boot

		# create the flashable zip file from the contents of the output directory
		echo "Make flashable zip..........."
		zip -r Kernel-tests.zip * >/dev/null
		stat boot.img
		rm -f ./*.img
		cd ..
	else
		# with red-color
		echo -e "\e[1;31mKernel STUCK in BUILD! no zImage exist\e[m"
	fi;
}

BUILD_NOW;

CLEAN_KERNEL()
{
	# fix python
	if [ -e /usr/bin/python3 ]; then
		rm /usr/bin/python
		ln -s /usr/bin/python2.7 /usr/bin/python
	fi;

	make ARCH=arm mrproper;
	make clean;

}
