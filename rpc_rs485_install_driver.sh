#
# This script installs the RasPiComm Rs-485 Device Driver that is packaged as a debian package from http://packages.amescon.com
#

# Check if http://packages.amescon.com is already added to the list of package servers
INSTALLED=`cat /etc/apt/sources.list | grep packages.amescon.com -c`
if [ $INSTALLED = 0 ] ; then
  echo Installing http://packages.amescon.com as a package source
	# Add http://packages.amescon.com to the apt-get package servers
	echo "deb http://packages.amescon.com/ ./" >> /etc/apt/sources.list
else
	echo http://packages.amescon.com is already installed as a package source.
fi

# Update the list of available packages
apt-get update

# Install the RasPiComm Rs-485 Device Driver package (use the kernel verison to retrieve the correct package)
apt-get install raspicommrs485-$(uname -r)