#!/bin/bash

# setup script for raspicomm
# written by mdk

# variables
revision=2

confirmationtext="[Question]" # used by confirm
confirmed=0 # set by confirm
packagename="" # set by set_package

function set_package() {

	# Get the kernels version number
	local version="$(uname -r)"

	# Get build number
	local buildnum="$(uname -a | sed 's/^Linux raspberrypi \([^ ]*\)\s#\([^ ]*\).*/\2/')"

	local package=""
	if [ "$buildnum" -ge 538 ] ; then
		local package="$version$buildnum"
	else
		local package="$version"
	fi

	packagename="raspicommrs485-$package"

	echo Package Version is $packagename
}


# prints general information about the script
function print_info() {
	echo "raspicomm setup script"
	echo "this script helps you setup the raspicomm"
	echo "visit http://www.amescon.com for further information"
	echo
}

# asks the used the [confirmationtext] and sets [confirmed] if he answered yes.
function ask_confirmation() {
	confirmed=0;
	local input=""
	local validinput=0

	while [ $validinput == 0 ]; do
			echo -n "$confirmationtext [y, n] "
			read input

			if [ $input == "y" ] ; then
				confirmed=1
				validinput=1
			elif [[ $input == "n" ]]; then
				confirmed=0
				validinput=1
			fi

	done
}

# asks the user for the rpi revision
function read_revision() {
	local validinput=0;

	while [ $validinput -eq 0 ]; do
			echo -n "Please specify the revision of the raspberry pi you are using [1,2]: "
			read revision

			if [ $revision -eq 1 || $revision -eq 2] ; then
				validinput=1
			fi
	done
}

function gpio_export() {
	echo -n "exporting gpio $1"
	if [ -e "/sys/class/gpio/gpio${1}/" ]; then
		echo "...gpio${1} already exists"
	else
		echo
		echo "${1}" > "/sys/class/gpio/export"
	fi
}

function gpio_unexport() {
	echo -n "unexporting gpio $1"
	if [ -e "/sys/class/gpio/gpio${1}/" ]; then
		echo
		echo "${1}" > "/sys/class/gpio/unexport"
	else		
		echo "...gpio${1} does not exist"
	fi
}
 
function gpio_configure_output() {		
	if [ -e "/sys/class/gpio/gpio${1}/direction" ]; then
		echo "out" > "/sys/class/gpio/gpio${1}/direction"
	fi
}

function gpio_configure_input() {
	if [ -e "/sys/class/gpio/gpio${1}/direction" ]; then
		echo "in" > "/sys/class/gpio/gpio${1}/direction"
	fi
}

function export_joystick_gpio() {
	gpio_export 4
	gpio_configure_input 4

	gpio_export 22
	gpio_configure_input 22

	gpio_export 23
	gpio_configure_input 23

	gpio_export 24
	gpio_configure_input 24

	gpio_export 25
	gpio_configure_input 25
}

function unexport_joystick_gpio() {
	gpio_unexport 4
	gpio_unexport 22
	gpio_unexport 23
	gpio_unexport 24
	gpio_unexport 25
}

function unexport_outputs() {
	gpio_unexport 18

	if [ $revision = 1 ]; then
		gpio_unexport 21
	else
		gpio_unexport 27
	fi
}

# exports both outputs of the raspicomm to userspace
function export_outputs() {

	gpio_export 18
	gpio_configure_output 18

	# export gpio 21 for revision 1 and gpio 27 for revision 2
	if [ $revision = 1 ] ; then
		gpio_export 21
		gpio_configure_output	 21
	else
		gpio_export 27
		gpio_configure_output 27
	fi
	
}


# installs the rs485 device driver
function install_rs485_driver() {

	# Check if http://packages.amescon.com is already added to the list of package servers
	INSTALLED=`cat /etc/apt/sources.list | grep packages.amescon.com -c`

	if [ $INSTALLED = 0 ] ; then
	  echo "Installing http://packages.amescon.com as a package source"

		# Add http://packages.amescon.com to the apt-get package servers
		echo "deb http://packages.amescon.com/ ./" >> /etc/apt/sources.list
	else
		echo "http://packages.amescon.com is already installed as a package source."
	fi

	echo "Updating the list of available apt-get packages..."

	# Update the list of available packages
	apt-get update -qq

	echo "Trying to install the RasPiComm Rs-485 Device Driver package for your kernel..."

	# Install the RasPiComm Rs-485 Device Driver package (use the kernel version to retrieve the correct package)
	apt-get install $packagename

	local apt_get_error=$?

	if [[ $apt_get_error -ne 0 ]]; then
		echo "apt-get returned the error code '$apt_get_error'."
		echo "Failed to install the Rs-485 Device Driver package for your kernel version."
		echo "If apt-get couldn't find a package for your kernel version, you have 3 options:"
		echo "  1) Consider switching to a kernel version for which a rs-485 driver package"
		echo "     has been built (e.g. 3.10.19+ #600)"
		echo "  2) Post your kernel version (uname -a) on our forums"
		echo "     (http://www.amescon.com/forum) and ask for a driver package for your kernel"
		echo "  3) Download the kernel module source and built the module yourself"
		echo "     (https://github.com/amescon/raspicomm-module.git)"
	fi
}

function remove_rs485_driver() {
	# apt-get remove raspicommrs485-$(uname  -r)
	apt-get remove $packagename
}

function configure_i2c_support() {

	# first check if the i2c already exists
	local i2c_device

	if [ $revision == 1 ] ; then
		i2c_device="/sys/class/i2c-adapter/i2c-0/new_device"
	else
		i2c_device="/sys/class/i2c-adapter/i2c-1/new_device"
	fi

	if [ -e $i2c_device ]; then
		echo "i2c already configured"
	else
		echo "configuring i2c"

		# install the i2c-tools
		apt-get install i2c-tools

		# check if i2c_bcm2708 is already added to /etc/modules
		installed=`cat /etc/modules | grep i2c_bcm2708 -c`
		if [ $installed = 0 ] ; then
			# if not, add i2c_bcm2708 to /etc/modules
			echo "adding i2c_bcm2708 module to startup"	
			echo "i2c_bcm2708" >> /etc/modules
		else
			echo "i2c_bcm2708 already added to /etc/modules"
		fi

		# load the module
		modprobe i2c-bcm2708
	
	fi

}


autostart_file="/etc/init.d/rpc.sh"

function create_autostart() {

	echo "creating autostart file ${autostart_file}"

	# truncate/create the empty autostart file
	> ${autostart_file}

	echo "#!/bin/bash" >> ${autostart_file}

	echo >> ${autostart_file}
	echo >> ${autostart_file}
	
	echo "### BEGIN INIT INFO"  >> ${autostart_file}
	echo "# Provides: rpc"  >> ${autostart_file}
	echo '# Required-Start:    $remote_fs $syslog' >> ${autostart_file}
	echo '# Required-Stop:     $local_fs' >> ${autostart_file}
	echo "# Default-Start:     2 3 4 5" >> ${autostart_file}
	echo "# Default-Stop:" >> ${autostart_file}
	echo "# Short-Description: Creates the real time clock i2c device and configures the rpc gpios" >> ${autostart_file}
	echo "### END INIT INFO" >> ${autostart_file}

	# add real time clock configuration to autostart file
	if [ ${revision} == 1 ]; then
		echo "echo ds1307 0x68 > /sys/class/i2c-adapter/i2c-0/new_device" >> ${autostart_file}
	else
		echo "echo ds1307 0x68 > /sys/class/i2c-adapter/i2c-1/new_device" >> ${autostart_file}
	fi

	# add rtc time -> sys time to autostart file
	echo "sudo hwclock --hctosys" >> ${autostart_file}

	# add joystick gpio configuration to autostart file
	echo "echo  4 > /sys/class/gpio/export" >> ${autostart_file}
	echo "echo 22 > /sys/class/gpio/export" >> ${autostart_file}
	echo "echo 23 > /sys/class/gpio/export" >> ${autostart_file}
	echo "echo 24 > /sys/class/gpio/export" >> ${autostart_file}
	echo "echo 25 > /sys/class/gpio/export" >> ${autostart_file}
	echo "echo in > /sys/class/gpio/gpio4/direction" >> ${autostart_file}
	echo "echo in > /sys/class/gpio/gpio22/direction" >> ${autostart_file}
	echo "echo in > /sys/class/gpio/gpio23/direction" >> ${autostart_file}
	echo "echo in > /sys/class/gpio/gpio24/direction" >> ${autostart_file}
	echo "echo in > /sys/class/gpio/gpio25/direction" >> ${autostart_file}

	# add output gpio configuration to autostart file
	echo "echo 18 > /sys/class/gpio/export" >> ${autostart_file}
	echo "echo out > /sys/class/gpio/gpio18/direction" >> ${autostart_file}
	if [ ${revision} == 1 ]; then
		echo "echo 21 > /sys/class/gpio/export" >> ${autostart_file}
		echo "echo out > /sys/class/gpio/gpio21/direction" >> ${autostart_file}
	else
		echo "echo 27 > /sys/class/gpio/export" >> ${autostart_file}
		echo "echo out > /sys/class/gpio/gpio27/direction" >> ${autostart_file}
	fi

	# make the file executable
	chmod +x ${autostart_file}

	# set the script to autostart
	update-rc.d rpc.sh start 80 2 3 4 5
}

function remove_autostart() {
	update-rc.d rpc.sh remove
	echo "removing autostart file ${autostart_file}"
	rm ${autostart_file}
}

function install_all() {
	install_rs485_driver;
	export_joystick_gpio;
	export_outputs;
	configure_i2c_support;
	configure_rtc;
	configure_rs232;
	disable_devicetree;
	create_autostart;
}

function remove_all() {
	remove_rs485_driver;
	unexport_joystick_gpio;
	unexport_outputs;
	remove_autostart;
}

function disable_devicetree() {
	# device tree's implementation of irq handling is broken in 3.18.7-v7+ #755 - the kernel deactivates the irq 49 on the raspberry pi 2 if device tree is not disabled
	# disable devicetree by adding the line 'device_tree=' to the beginning of /boot/config.txt
	local line=`grep "^device_tree=$" /boot/config.txt`
	echo -n "checking /boot/config.txt..."
	if [[ ${line} == "" ]]; then
		echo "PATCHING FILE"
		echo "device_tree=" >> /boot/config.txt
	else
		echo "ALREADY PATCHED."
	fi
}

function configure_rtc() {	

	local i2c_base

	if [ $revision == 1 ] ; then
		i2c_base="/sys/class/i2c-adapter/i2c-0/"
	else
		i2c_base="/sys/class/i2c-adapter/i2c-1/"
	fi

	local i2c_device="${i2c_base}new_device"

	if [ ! -e $i2c_device ]; then
		echo "i2c support not configured!"
	else

		echo "configuring real time clock..."

		# check if the real time clock is already configured
		if [[ -d "${i2c_base}1-0068" ]]; then
			echo "i2c device with address 0x68 already configured"
		else
			# enable rtc clock
			echo ds1307 0x68 > ${i2c_device}
		fi

	fi
	
}

# configures the raspberry pi to not use the rs232 for startup logging
function configure_rs232() {

	local reboot_required=0

	# we need to remove all references of /dev/ttyAMA0 from /boot/cmdline.txt and /etc/inittab so that the rs232 device becomes usable

	local file1="/boot/cmdline.txt"
	local file1_content="dwc_otg.lpm_enable=0 console=ttyAMA0,115200 kgdboc=ttyAMA0,115200 console=tty1 root=/dev/mmcblk0p2 rootfstype=ext4 elevator=deadline rootwait"
	local file1_replacement="dwc_otg.lpm_enable=0 console=tty1 root=/dev/mmcblk0p2 rootfstype=ext4 elevator=deadline rootwait"

	echo -n "checking ${file1}..."

	# load the file
	local file1_content_live=$(<${file1})

	# if the contents match, backup and replace the file
	if [ "${file1_content_live}" == "${file1_content}" ]; then 
		echo "OK."
		echo "creating backup ${file1}.bak..."
		mv ${file1} ${file1}.bak
		if [ $? == 0 ]; then			
			echo -n "updating file..."
			echo "${file1_replacement}" > ${file1}
			if [ $? == 0 ]; then
				echo "OK."
				reboot_required=1
			else
				echo "ERROR."
				echo "restoring backup"
				mv ${file1}.bak ${file1}
			fi		
		fi
	elif [ "${file1_content_live}" == "${file1_replacement}" ]; then
		echo "ALREADY PATCHED."
	else
		echo "UNKNOWN."
		echo "aborted patching file"
	fi

	local file2="/etc/inittab"
	local line2="T0:23:respawn:/sbin/getty -L ttyAMA0 115200 vt100"
	local line2_replacement="# T0:23:respawn:/sbin/getty -L ttyAMA0 115200 vt100"

	# get the linenumber
	echo -n "checking ${file2}..."
	local linenumber=`cat "${file2}" | grep -nx "T0:23:respawn:/sbin/getty -L ttyAMA0 115200 vt100" | sed -n 's/^\([0-9]*\)[:].*/\1/p'`
	if [ "${linenumber}" == "72" ]; then
		echo "OK."
		echo "creating backup ${file2}.bak..."
		cp ${file2} ${file2}.bak
		if [ $? == 0 ]; then
			echo -n "updating file..."
			sed -i '72s/.*/# T0:23:respawn:\/sbin\/getty -L ttyAMA0 115200 vt100/' /etc/inittab

			if [ $? == 0 ]; then
				echo "OK.";
				reboot_required=1
			else
				echo "ERROR."
				echo "restoring backup"
				mv ${file2}.bak ${file2}
			fi
		fi
	else
		local linenumber_patched=`cat "${file2}" | grep -nx "# T0:23:respawn:/sbin/getty -L ttyAMA0 115200 vt100" | sed -n 's/^\([0-9]*\)[:].*/\1/p'`
		if [[ ${linenumber_patched} == 72 ]]; then
			echo "ALREADY PATCHED."
		else
			echo "UNKNOWN."
			echo "aborted patching file"		
		fi
	fi

	# inform the use that a reboot is required
	if [ $reboot_required == 1 ]; then
		echo "startup files patched -> reboot required to use rs-232 port"
	fi

}

function enter_to_continue() {
	echo
	echo -n "press any key to continue";
	read -n 1 
}

function print_menu() {
	clear
	echo "================================="
	echo "Raspberry Pi Revision: $revision"  # show the currently selected rpi revision
	echo "----------------------------------"
	echo "[c]hange revision"
	echo "[i]nstall"
	echo "[r]emove"
	echo "---------------------------------"		
	echo "[q]uit setup"
	echo "================================="
	echo -n "Enter command: ";
}

function main_repl {

	local stop=0
	local input=""
	while [ $stop == 0 ]; do

		print_menu; # print the menu

		read -n 1 input; # read the command
		echo
		echo

		# handle the users command
		case "$input" in
			"q") # quit
			stop=1
			;;

			"r") # remove
			remove_all;
			stop=1
			;;

			"i") # install
			install_all;
			stop=1
			;;

			"c") # toggle the revision
			if [ $revision = 2 ]; then
				revision=1				
			else
				revision=2
			fi
			;;

		esac

	done;

}

function print_help() {
	echo "rpc_setup.sh supports the following parameters:"
	echo
	echo "help|h|?............this output"
	echo "revision1|rev1......consider the raspberry pi to be revision 1"
	echo "                    must be specified before all other arguments"
	echo "configure-rs232.....modifies /etc/inittab and /boot/cmdline.txt"
	echo "                    to not use /dev/ttyAMA0"
	echo "configure-i2c.......installs i2c support"
	echo "configure-rtc.......configures the real time clock"
	echo "install-rs485.......installs the rs485 device driver"
	echo "export-joystick.....exports the gpios used by the joystick"
	echo "export-outputs......exports the gpios used as outputs"
	echo "unexport-joystick...unexports the gpios used by the joystick"
	echo "unexport-outputs....unexports the gpios used as outputs"
	echo "create-autostart....creates and registers an autostart script that"
	echo "                    configures the rtc and gpios on startup"
	echo "remove-autostart....removes the autostart script"
	echo "get-packagename.....shows the package name for kernel module"
	echo
	echo "example: sudo ./rpc_setup.sh --configure-rs232"
	echo
	echo "when no arguments are supplied, starts in interactive mode"
	echo "hint: you need to have root access for most actions"
	echo
}

function parseArgument() {
	local arg=$1

  if [ ${arg:0:1} = '/' ]; then # strip leading '/'
    local arg=${arg:1}
  elif [ ${arg:0:2} = '--' ]; then # strip leading '--'
    local arg=${arg:2}
  fi

  local name=${arg%%=*}  # extract parameter name
  local value=${arg##*=} # extract parameter value

  case $name in

		"revision1"|"rev1"|"r1") # use revision 1
			echo "now considering raspberry pi revision 1"
			revision=1;
		;;

  	"configure-rs232"|"rs232") # configure rs232
			configure_rs232;
  	;;

  	"configure-i2c"|"i2c") # configure i2c
			configure_i2c_support;
		;;

		"configure-rtc"|"rtc") # configure rtc
			configure_rtc;
		;;

		"install-rs485"|"rs485") # install rs-485 driver
			install_rs485_driver;
		;;

		"export-joystick") # export joystick gpios
			export_joystick_gpio;
		;;

		"export-outputs") # export outputs
			export_outputs;
		;;

		"unexport-joystick") # unexport joystick gpios
			unexport_joystick_gpio;
		;;

		"unexport-outputs") # unexport outputs
			unexport_outputs;
		;;

		"create-autostart") # create the autostart script
			create_autostart;
		;;

		"remove-autostart") # remove the autostart script
			remove_autostart;
		;;

		"get-packagename") # get the packagename
			echo packagename: $packagename
		;;

		"help"|"h"|"?") # help
			print_help;
		;;

  esac
}

function main() {

	# print some general info about the script
  print_info;

  # check if this script is run as root
  if [[ $EUID -ne 0 ]]; then
  	echo "This script must be run as root. Try 'sudo rpc-setup.sh'."
  else

    # sets the package name
    set_package;

    # check if arguments were supplied
    if [[ -z $1 ]]; then
      # enter the main loop
      main_repl;
    else

      # execute the supplied arguments
      for arg in "$@"
      do
        parseArgument $arg;
      done

    fi

  fi
}

main $*; # entrypoint
