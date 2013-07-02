#!/bin/bash

# setup script for raspicomm
# written by mdk

# variables
revision=2

confirmationtext="[Question]" # used by confirm
confirmed=0 # set by confirm

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

	# Update the list of available packages
	apt-get update

	# Install the RasPiComm Rs-485 Device Driver package (use the kernel verison to retrieve the correct package)
	apt-get install raspicommrs485-$(uname -r)
}

function remove_rs485_driver() {
	apt-get remove raspicommrs485-$(uname  -r)
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

	# truncate/create the empty autostart file
	> ${autostart_file}

	echo "#!/bin/bash" >> ${autostart_file}

	echo >> ${autostart_file}
	echo >> ${autostart_file}
	
	echo "### BEGIN INIT INFO"  >> ${autostart_file}
	echo "# Provides: rpc"  >> ${autostart_file}
	echo "# Required-Start:    $remote_fs $syslog" >> ${autostart_file}
	echo "# Required-Stop:     $local_fs" >> ${autostart_file}
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
	echo "hwclock --hctosys" >> ${autostart_file}

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
	rm ${autostart_file}
}

function install_all() {
	install_rs485_driver;
	export_joystick_gpio;
	export_outputs;
	configure_i2c_support;
	configure_rtc;
	configure_rs232;
	create_autostart;
}

function remove_all() {
	remove_rs485_driver;
	unexport_joystick_gpio;
	unexport_outputs;
	remove_autostart;
}

function configure_rtc() {	

	local i2c_device
	if [ $revision == 1 ] ; then
		i2c_device="/sys/class/i2c-adapter/i2c-0/new_device"
	else
		i2c_device="/sys/class/i2c-adapter/i2c-1/new_device"
	fi

	if [ ! -e $i2c_device ]; then
		echo "i2c support not configured!"
	else

		echo "configuring real time clock..."
		# enable rtc clock
		echo ds1307 0x68 > ${i2c_device}

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
		if [ ${linenumber_patched} == 72 ]; then
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
	echo "[r]remove"
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
  	"configure-rs232"|"rs232") # configure rs232
			configure_rs232;
  	;;
  esac
}

function main() {

	# print some general info about the script
  print_info;

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
}

main $*; # entrypoint
