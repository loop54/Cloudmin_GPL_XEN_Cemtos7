#!/bin/sh
# cloudmin-gpl-redhat-install.sh
# Copyright 2005-2009 Virtualmin, Inc.
#
# Installs Cloudmin GPL for Xen and all dependencies on a CentOS, RHEL or
# Fedora system.

VER=1.1

# Define functions
yesno () {
	while read line; do
		case $line in
			y|Y|Yes|YES|yes|yES|yEs|YeS|yeS) return 0
			;;
			n|N|No|NO|no|nO) return 1
			;;
			*)
			printf "\nPlease enter y or n: "
			;;
		esac
	done
}

# Ask the user first
cat <<EOF
*******************************************************************************
*       Welcome to the Cloudmin GPL for Xen installer, version $VER           *
*******************************************************************************

 Operating systems supported by this installer are:

 Fedora Core 3-12 on i386 and x86_64
 CentOS and RHEL 3-7 on i386 and x86_64

 If your OS is not listed above, this script will fail (and attempting
 to run it on an unsupported OS is not recommended, or...supported).
EOF
printf " Continue? (y/n) "
if ! yesno
then exit
fi
echo ""

# Cleanup old repo files
rm -f /etc/yum.repos.d/vm2* /etc/yum.repos.d/cloudmin*

# Check for yum
echo Checking for yum ..
if [ ! -x /usr/bin/yum ]; then
	echo .. not installed. The Cloudmin installer requires YUM to download packages
	echo ""
	exit 1
fi
echo .. found OK
echo ""

# Enable extra repos
if [ -x /usr/bin/dnf ]; then
	echo Enabling additional repositories ..
	dnf config-manager --set-enabled PowerTools
	dnf config-manager --set-enabled extras
	dnf install epel-release
	echo .. done
	echo ""
fi

# Make sure we have wget
echo "Installing wget .."
yum install -y wget
echo ".. done"
echo ""

# Check for wget or curl
echo "Checking for curl or wget..."
if [ -x "/usr/bin/curl" ]; then
	download="/usr/bin/curl -s "
elif [ -x "/usr/bin/wget" ]; then
	download="/usr/bin/wget -nv -O -"
else
	echo "No web download program available: Please install curl or wget"
	echo "and try again."
	exit 1
fi
echo "found $download"
echo ""

# Create Cloudmin licence file
echo Creating Cloudmin licence file
cat >/etc/server-manager-license <<EOF
SerialNumber=GPL
LicenseKey=GPL
EOF
chmod 600 /etc/server-manager-license

# Download GPG keys
echo Downloading GPG keys for packages ..
$download "http://software.virtualmin.com/lib/RPM-GPG-KEY-virtualmin" >/etc/pki/rpm-gpg/RPM-GPG-KEY-virtualmin
if [ "$?" != 0 ]; then
	echo .. download failed
	exit 1
fi
$download "http://software.virtualmin.com/lib/RPM-GPG-KEY-webmin" >/etc/pki/rpm-gpg/RPM-GPG-KEY-webmin
if [ "$?" != 0 ]; then
	echo .. download failed
	exit 1
fi
echo .. done
echo ""

# Import keys
echo Importing GPG keys ..
rpm -q gpg-pubkey-a0bdbcf9-42d1d837 || rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-virtualmin
rpm -q gpg-pubkey-11f63c51-3c7dc11d || rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-webmin
echo .. done
echo ""

# Setup the YUM repo file
echo Creating YUM repository for Cloudmin packages ..
cat >/etc/yum.repos.d/cloudmin.repo <<EOF
[cloudmin-universal]
name=Cloudmin Distribution Neutral
baseurl=http://cloudmin.virtualmin.com/gpl/universal/
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-virtualmin
gpgcheck=1
EOF
echo .. done
echo ""

# Enable Xen kernels repo, if on CentOS 7
yum info kernel-xen >/dev/null 2>&1
if [ "$?" != 0 ]; then
	echo Enabling Xen kernel repo for CentOS 7 ..
	yum install wget
	yum install http://mirror.centos.org/centos/7/extras/x86_64/Packages/centos-release-xen-412-8-7.el7.centos.x86_64.rpm
	if [ "$?" != 0 ]; then
		echo .. repo install failed
		exit 1
	fi
	echo .. done
	echo ""
fi

# YUM install Perl, modules and other dependencies
echo Installing required Perl modules using YUM ..
yum install -y perl openssl perl-Net-SSLeay bind bind-utils kernel-xen kernel-xen-devel xen413 xen-libs lsof
if [ "$?" != 0 ]; then
	echo .. install failed
	exit 1
fi
yum install -y perl-JSON
yum install -y dhcp
yum install -y openssh-clients
yum install -y vixie-cron || yum install -y cronie
echo .. done
echo ""

# Check for virbrN interfaces
echo "Checking for and disabling virbr interfaces .."
ifaces=`/sbin/ifconfig -a | grep "^virbr" | cut -d " " -f 1`
if [ "$ifaces" != "" ]; then
	echo ".. need to disable $ifaces .."
	for iface in $ifaces; do
		/sbin/ifconfig $iface 0.0.0.0 down
	done
	echo ".. done"
else
	echo ".. none found"
fi
if [ -r /etc/libvirt/qemu/networks/default.xml ]; then
	cp /etc/libvirt/qemu/networks/default.xml /etc/libvirt/qemu/networks/default.xml.disabled
	cat /dev/null >/etc/libvirt/qemu/networks/default.xml
fi
echo ""

# YUM install webmin, theme and Cloudmin
echo Installing Cloudmin packages using YUM ..
yum install -y webmin wbm-server-manager wbt-virtual-server-theme
if [ "$?" != 0 ]; then
	echo .. install failed
	exit 1
fi
mkdir -p /xen
echo .. done
echo ""

# Configure Webmin to use theme
echo Configuring Webmin ..
grep -v "^preroot=" /etc/webmin/miniserv.conf >/tmp/miniserv.conf.$$
echo preroot=authentic-theme >>/tmp/miniserv.conf.$$
cat /tmp/miniserv.conf.$$ >/etc/webmin/miniserv.conf
rm -f /tmp/miniserv.conf.$$
grep -v "^theme=" /etc/webmin/config >/tmp/config.$$
echo theme=authentic-theme >>/tmp/config.$$
cat /tmp/config.$$ >/etc/webmin/config
rm -f /tmp/config.$$
/etc/webmin/restart
echo .. done
echo ""

# Setup BIND zone for virtual systems
basezone=`hostname -d`
if [ "$basezone" = "" ]; then
	basezone=example.com
fi
zone="cloudmin.$basezone"
echo Creating DNS zone $zone ..
/usr/libexec/webmin/server-manager/setup-bind-zone.pl --zone $zone --auto-view
if [ "$?" != 0 ]; then
  echo .. failed
else
  echo xen_zone=$zone >>/etc/webmin/server-manager/config
  echo xen_zone=$zone >>/etc/webmin/server-manager/this
  echo .. done
fi
echo ""

# Open Webmin firewall port
echo Opening port 10000 on IPtables firewall ..
ports="10000 10001 10002 10003 10004 10005 843"
/usr/libexec/webmin/firewall/open-ports.pl $ports
if [ "$?" != 0 ]; then
  echo .. failed
else
  echo .. done
fi
echo ""

# Open firewalld ports
if [ -x /usr/bin/firewall-cmd ]; then
  echo Opening port 10000 on Firewalld firewall ..
  for port in $ports; do
    /usr/bin/firewall-cmd --add-port=$port/tcp >/dev/null
    /usr/bin/firewall-cmd --permanent --add-port=$port/tcp >/dev/null
  done
  echo .. done
  echo ""
fi

# Use Xen kernel
echo Configuring GRUB to boot Xen-capable kernel ..
/usr/libexec/webmin/server-manager/setup-xen-kernel.pl

# Tell user about need to reboot
hostname=`hostname`
echo Cloudmin GPL has been successfully installed. However, you will need to
echo reboot to activate the new Xen-capable kernel before any Xen instances
echo can be created.
echo
echo One this is done, you can login to Cloudmin at :
echo https://$hostname:10000/

# All done!

