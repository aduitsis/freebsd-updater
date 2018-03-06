#!/bin/sh -

DATE=$(date +%Y%m%dZ%H%M%S)
BASENAME=$(basename $0)
DIRNAME=$(dirname $0)
STATE=$DIRNAME/state.txt
SYSRC="sysrc -f $STATE"
touch $STATE
$SYSRC last_run=$DATE
. $STATE
UNAME=$(uname -r)
TMP=/tmp/var.out

NEW="11.1-RELEASE"

DIALOG="dialog --ascii-lines --yesno "

if [ ! "$previous_version" ]; then
	$SYSRC previous_version=$UNAME
	previous_version=$UNAME
fi

if [ ! "$phase_pkg_upgrade" ]; then
	$DIALOG "pkg upgrade this system?" 0 0
	if [ $? -eq 0 ]; then
		pkg update
		pkg upgrade
	fi
	clear
	$SYSRC phase_pkg_upgrade=1
fi

if [ ! "$phase_puppet4" ]; then
	$DIALOG "install puppet4?" 0 0
	if [ $? -eq 0 ]; then
		pkg install -y puppet4
	fi
	clear
	$SYSRC phase_puppet4=1
fi

if [ ! "$phase_puppetrun" ]; then
	$DIALOG "do a test puppet run?" 0 0
	if [ $? -eq 0 ]; then
		puppet agent -t
	fi
	clear
	$SYSRC phase_puppetrun=1
fi


if [ ! "$phase_fetchinstall" ]; then
	$DIALOG "run a freebsd-update fetch install?" 0 0
	if [ $? -eq 0 ]; then
		freebsd-update --not-running-from-cron fetch install
	fi
	clear
	$SYSRC phase_fetchinstall=1
fi

if [ ! "$new_version" ]; then
	dialog --ascii-lines --inputbox "version to upgrade to?" 0 0 $NEW 2> $TMP
	NEW=$(cat $TMP)
	clear
	$SYSRC new_version=$NEW
fi

if [ ! "$phase_upgrade" ]; then
	$DIALOG "run a freebsd-update -r $NEW upgrade?" 0 0
	if [ $? -eq 0 ]; then
		freebsd-update --not-running-from-cron -r $new_version upgrade
		$SYSRC phase_upgrade=1
	fi
fi

if [ ! "$phase_install" ]; then
	$DIALOG "run a freebsd-update install?" 0 0
	if [ $? -eq 0 ]; then
		freebsd-update --not-running-from-cron install
		$SYSRC phase_install=1
	fi
fi

if [ ! "$phase_deactivate_jails" ]; then
	$DIALOG "deactivate jails before reboot?" 0 0
	if [ $? -eq 0 ]; then
		sysrc ezjail_enable=NO
	fi
	$SYSRC phase_deactivate_jails=1
fi

if [ ! "$phase_reboot" ]; then
	$DIALOG "reboot now?" 0 0
	if [ $? -eq 0 ]; then
		$SYSRC phase_reboot=1
		reboot
	fi
fi


if [ ! "$phase_reboot2" ]; then
	dialog --ascii-lines --msgbox "reboot has been done!" 0 0
	$SYSRC phase_reboot2=1
fi


if [ ! "$phase_install_after1" ]; then
	$DIALOG "run a freebsd-update install?" 0 0
	if [ $? -eq 0 ]; then
		freebsd-update --not-running-from-cron install
		$SYSRC phase_install_after1=1
	fi
fi

if [ ! "$phase_pkg_upgrade_after_reboot" ]; then
	$DIALOG "pkg upgrade this system?" 0 0
	if [ $? -eq 0 ]; then
		pkg-static install -f pkg
		pkg update
		pkg upgrade
	fi
	clear
	$SYSRC phase_pkg_upgrade_after_reboot=1
fi

if [ ! "$phase_install_after2" ]; then
	$DIALOG "run a freebsd-update install again?" 0 0
	if [ $? -eq 0 ]; then
		freebsd-update --not-running-from-cron install
		$SYSRC phase_install_after2=1
	fi
fi

if [ ! "$phase_reboot3" ]; then
	dialog --ascii-lines --msgbox "$(hostname) is now a $(uname -r)!" 0 0
	$SYSRC phase_reboot3=1
fi

prv_str=$(echo $previous_version | cut -d'-' -f1 | tr '.' '_')
if [ ! "$phase_reactivate_jails" ]; then
	$DIALOG "reactivate jails with old basejail from $previous_version ?" 0 0
	if [ $? -eq 0 ]; then
		echo $prv_str
		for j in $(ls /usr/local/etc/ezjail | egrep -v '_norun$'); do
			sed -i -E "s/^\/var\/jails\/basejail/\/var\/jails\/old_basejail_$prv_str/" /etc/fstab.$j
		done
		test -d /var/jails/basejail && mv /var/jails/basejail /var/jails/old_basejail_$prv_str
		test -d /var/jails/newjail && mv /var/jails/newjail /var/jails/old_newjail_$prv_str
		sysrc ezjail_enable=YES
		service ezjail start
		$SYSRC phase_reactivate_jails=1
	fi
fi

if [ ! "$phase_create_basejail" ]; then
	$DIALOG "create ($(uname -r)) basejail?" 0 0
	if [ $? -eq 0 ]; then
		ezjail-admin install -s -p
		$SYSRC phase_create_basejail=1
	fi
fi


JAILS=$(ezjail-admin list | tail +3 | awk '{print $4}')

for j in $JAILS; do
	jail_ver=$(ezjail-admin console -e 'freebsd-version' $j)
	if [ "$jail_ver" != "$UNAME" ]; then
		phase_var=$(echo phase_update_jail_$j | tr '.' '_')
		#echo $phase_var
		phase_var_name="\$$phase_var"
		#echo $phase_var_name
		phase_var_value=$(eval echo $phase_var_name)
		#echo $phase_var_value
		if [ ! "$phase_var_value" ]; then
			$DIALOG "update jail $j ?" 0 0
			if [ $? -eq 0 ]; then
				jname=$(echo $j | tr '.' '_')
				ezjail-admin stop $j
				sed -i -E "s/^\/var\/jails\/old_basejail_$prv_str/\/var\/jails\/basejail/" /etc/fstab.$jname
				ezjail-admin start $j
				ezjail-admin console -e 'freebsd-version' $j
				ezjail-admin console -e "sed -i -E s/^IGNORE/IIGNORE/ /etc/mergemaster.rc" $j
				ezjail-admin console -e 'mergemaster -p' $j
				ezjail-admin console -e "sed -i -E s/^IIGNORE/IGNORE/ /etc/mergemaster.rc" $j
				ezjail-admin console -e 'mergemaster -iU --run-updates=always' $j
				ezjail-admin console -e 'pkg-static install -f pkg' $j
				ezjail-admin console -e 'pkg upgrade' $j
				$SYSRC $phase_var=1
			fi
		fi
	fi
done
