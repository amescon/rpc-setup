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
	echo "[1]...install rs-485 device driver (/dev/ttyRPC0)"
	echo "[2]...configure the joystick gpios"
	echo "[3]...configure the outputs"
	echo "[4]...configure the i2c support"
	echo "---------------------------------"	
	echo "[5]...remove the rs-485 device driver"
	echo "[6]...free the joystick gpios"
	echo "[7]...free the outputs"
	echo "---------------------------------"		
	echo "[q]uit setup"
	echo "[c]hange revision"
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

			"1") # install rs-485 device driver
			install_rs485_driver;
			enter_to_continue;
			;;
	
			"2") # joystick
			export_joystick_gpio;
			enter_to_continue;
			;;

			"3") # outputs
			export_outputs;
			enter_to_continue;
			;;

			"4") # configure i2c support
			configure_i2c_support;
			enter_to_continue;
			;;

			"5") # remove rs485 device driver
			remove_rs485_driver;
			enter_to_continue;
			;;

			"6") # remove joystick
			unexport_joystick_gpio;
			enter_to_continue;
			;;

			"7") # remove outputs
			unexport_outputs;
			enter_to_continue;
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

function main() {

	# print some general info about the script
  print_info;

  main_repl;

	# # ask the user if we should install the raspicomm device driver
 #  confirmationtext="Do you want to install the raspicomm rs485 driver?"
 #  ask_confirmation;
 #  if [ $confirmed == 1 ]; then		 
	# 	install_rs485_driver; # install the driver
 #  fi

 #  # ask the user for the revision of the raspberry pi
 #  read_revision;

	# # ask the user if we should install and enable the i2c support

	# # ask the user if we should export the joystick gpios
	# confirmationtext="Do you want to export the joystick gpios?"
	# ask_confirmation;
	# if [ $confirmed == 1]; then
	# 	export_joystick_gpio; #export the gpios
	# fi

	# # ask the user if we should export the gpios 

	echo "setup finished...";
}

main; # entrypoint
