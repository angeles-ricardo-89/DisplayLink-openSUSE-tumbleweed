#!/bin/bash
# Copyright (c) 2015 - 2019 DisplayLink (UK) Ltd.

SELF=$0
COREDIR=/opt/displaylink
LOGSDIR=/var/log/displaylink
PRODUCT="DisplayLink Linux Software"
VERSION=5.1.26
ACTION=default

add_udev_rule()
{
  echo "Adding udev rule for DisplayLink DL-3xxx/4xxx/5xxx/6xxx devices"
  create_udev_rules_file /etc/udev/rules.d/99-displaylink.rules
  udevadm control -R
  udevadm trigger
}

remove_udev_rule()
{
  rm -f /etc/udev/rules.d/99-displaylink.rules
  udevadm control -R
  udevadm trigger
}

print_help_message()
{
  echo ""
  echo "Please read the FAQ"
  echo "http://support.displaylink.com/knowledgebase/topics/103927-troubleshooting-ubuntu"
}

print_install_complete()
{
  echo "Installation complete!"
}

install_module()
{
  TARGZ="$1"
  MODVER="$2"
  ERRORS="$3"

  SRCDIR="/usr/src/evdi-$MODVER"
  mkdir -p "$SRCDIR"
  if ! tar xf $TARGZ -C "$SRCDIR"; then
    echo "Unable to extract $TARGZ" to "$SRCDIR" > $ERRORS
    return 1
  fi

  echo "Registering EVDI kernel module with DKMS"
  dkms add evdi/$MODVER -q
  if [ $? != 0 -a $? != 3 ]; then
    echo "Unable to add evdi/$MODVER to DKMS source tree." > $ERRORS
    return 2
  fi

  echo "Building EVDI kernel module with DKMS"
  dkms build evdi/$MODVER -q
  if [ $? != 0 ]; then
    echo "Failed to build evdi/$MODVER. Consult /var/lib/dkms/evdi/$MODVER/build/make.log for details." > $ERRORS
    return 3
  fi

  echo "Installing EVDI kernel module to kernel tree"
  dkms install evdi/$MODVER -q
  if [ $? != 0 ]; then
    echo "Failed to install evdi/$MODVER to the kernel tree." > $ERRORS
    return 4
  fi

  echo "EVDI kernel module built successfully"
}

remove_module()
{
  MODVER="$1"
  SRCDIR="/usr/src/evdi-$MODVER"
  dkms remove evdi/$MODVER --all -q
  [ -d "$SRCDIR" ] && rm -rf "$SRCDIR"
}

is_32_bit()
{
  [ "$(getconf LONG_BIT)" == "32" ]
}

is_armv7()
{
  grep -qi armv7 /proc/cpuinfo
}

add_upstart_script()
{
  MODVER="$1"

  cat > /etc/init/displaylink-driver.conf <<EOF
description "DisplayLink Driver Service"
# Copyright (c) 2015 - 2019 DisplayLink (UK) Ltd.

start on login-session-start
stop on desktop-shutdown

# Restart if process crashes
respawn

# Only attempt to respawn 10 times in 5 seconds
respawn limit 10 5

chdir /opt/displaylink

pre-start script
    . /opt/displaylink/udev.sh

    if [ "\$(get_displaylink_dev_count)" = "0" ]; then
        stop
        exit 0
    fi
end script

script
    [ -r /etc/default/displaylink ] && . /etc/default/displaylink
    modprobe evdi || (dkms install evdi/$MODVER && modprobe evdi)
    exec /opt/displaylink/DisplayLinkManager
end script
EOF

  chmod 0644 /etc/init/displaylink-driver.conf
}

add_systemd_service()
{
  MODVER="$1"

  cat > /usr/lib/systemd/system/displaylink-driver.service <<EOF
[Unit]
Description=DisplayLink Driver Service
After=display-manager.service
Conflicts=getty@tty7.service

[Service]
ExecStartPre=/bin/sh -c 'modprobe evdi || (dkms install evdi/$MODVER && modprobe evdi)'
ExecStart=/opt/displaylink/DisplayLinkManager
Restart=always
WorkingDirectory=/opt/displaylink
RestartSec=5

EOF

  chmod 0644 /usr/lib/systemd/system/displaylink-driver.service
}

remove_upstart_service()
{
  driver_name="displaylink-driver"
  if grep -sqi displaylink /etc/init/dlm.conf; then
    driver_name="dlm"
  fi
  echo "Stopping displaylink-driver upstart job"
  stop ${driver_name}
  rm -f /etc/init/${driver_name}.conf
}

remove_systemd_service()
{
  driver_name="displaylink-driver"
  if grep -sqi displaylink /usr/lib/systemd/system/dlm.service; then
    driver_name="dlm"
  fi
  echo "Stopping ${driver_name} systemd service"
  systemctl stop ${driver_name}.service
  systemctl disable ${driver_name}.service
  rm -f /usr/lib/systemd/system/${driver_name}.service
}

add_pm_script()
{
  cat > $COREDIR/suspend.sh <<EOF
#!/bin/bash
# Copyright (c) 2015 - 2019 DisplayLink (UK) Ltd.

suspend_displaylink-driver()
{
  #flush any bytes in pipe
  while read -n 1 -t 1 SUSPEND_RESULT < /tmp/PmMessagesPort_out; do : ; done;

  #suspend DisplayLinkManager
  echo "S" > /tmp/PmMessagesPort_in

  if [ -p /tmp/PmMessagesPort_out ]; then
    #wait until suspend of DisplayLinkManager finish
    read -n 1 -t 10 SUSPEND_RESULT < /tmp/PmMessagesPort_out
  fi
}

resume_displaylink-driver()
{
  #resume DisplayLinkManager
  echo "R" > /tmp/PmMessagesPort_in
}

EOF

  if [ "$1" = "upstart" ]
  then
    cat >> $COREDIR/suspend.sh <<EOF
case "\$1" in
  thaw)
    resume_displaylink-driver
    ;;
  hibernate)
    suspend_displaylink-driver
    ;;
  suspend)
    suspend_displaylink-driver
    ;;
  resume)
    resume_displaylink-driver
    ;;
esac

EOF
  elif [ "$1" = "systemd" ]
  then
    cat >> $COREDIR/suspend.sh <<EOF
case "\$1/\$2" in
  pre/*)
    suspend_displaylink-driver
    ;;
  post/*)
    resume_displaylink-driver
    ;;
esac

EOF
  fi

  chmod 0755 $COREDIR/suspend.sh
  if [ "$1" = "upstart" ]
  then
    ln -sf $COREDIR/suspend.sh /etc/pm/sleep.d/displaylink.sh
  elif [ "$1" = "systemd" ]
  then
    ln -sf $COREDIR/suspend.sh /usr/lib/systemd/system-sleep/displaylink.sh
  fi
}

remove_pm_scripts()
{
  rm -f /etc/pm/sleep.d/displaylink.sh
  rm -f /usr/lib/systemd/system-sleep/displaylink.sh
}

cleanup()
{
  rm -rf $COREDIR
  rm -rf $LOGSDIR
  rm -f /usr/bin/displaylink-installer
  rm -f ~/.dl.xml
  rm -f /root/.dl.xml
}

binary_location()
{
  if is_armv7; then
    echo "arm-linux-gnueabihf"
  else
    local PREFIX="x64"
    local POSTFIX="ubuntu-1604"

    is_32_bit && PREFIX="x86"
    echo "$PREFIX-$POSTFIX"
  fi
}

install()
{
  echo "Installing"
  mkdir -p $COREDIR
  mkdir -p $LOGSDIR
  chmod 0755 $COREDIR
  chmod 0755 $LOGSDIR

  cp -f $SELF $COREDIR
  ln -sf "$COREDIR/$(basename $SELF)" /usr/bin/displaylink-installer
  chmod 0755 /usr/bin/displaylink-installer

  local ERRORS=$(mktemp)
  echo "Configuring EVDI DKMS module"
  install_module "evdi-$VERSION-src.tar.gz" "$VERSION" "$ERRORS"
  local success=$?

  local error="$(< $ERRORS)"
  rm -f $ERRORS
  if [ 0 -ne $success ]; then
    echo "ERROR (code $success): $error." >&2
    cleanup
    exit 1
  fi

  local BINS=$(binary_location)
  local DLM="$BINS/DisplayLinkManager"
  local LIBEVDI="$BINS/libevdi.so"
  local LIBUSB="$BINS/libusb-1.0.so.0.1.0"

  echo "Installing $DLM"
  [ -x $DLM ] && mv -f $DLM $COREDIR

  echo "Installing libraries"
  [ -f $LIBEVDI ] && mv -f $LIBEVDI $COREDIR
  [ -f $LIBUSB ] && mv -f $LIBUSB $COREDIR
  ln -sf $COREDIR/libusb-1.0.so.0.1.0 $COREDIR/libusb-1.0.so.0
  ln -sf $COREDIR/libusb-1.0.so.0.1.0 $COREDIR/libusb-1.0.so

  chmod 0755 $COREDIR/DisplayLinkManager
  chmod 0755 $COREDIR/libevdi.so
  chmod 0755 $COREDIR/libusb*.so*

  echo "Installing firmware packages"
  mv -f *.spkg $COREDIR
  chmod 0644 $COREDIR/*.spkg

  echo "Installing licence file"
  cp -f LICENSE $COREDIR
  chmod 0644 $COREDIR/LICENSE
  if [ -f 3rd_party_licences.txt ]; then
    cp -f 3rd_party_licences.txt $COREDIR
    chmod 0644 $COREDIR/3rd_party_licences.txt
  fi

  source udev-installer.sh
  displaylink_bootstrap_script=$COREDIR/udev.sh
  create_bootstrap_file $SYSTEMINITDAEMON $displaylink_bootstrap_script
  add_udev_rule

  if [ "upstart" == "$SYSTEMINITDAEMON" ]; then
    add_upstart_script "$VERSION"
    add_pm_script "upstart"
  elif [ "systemd" == "$SYSTEMINITDAEMON" ]; then
    add_systemd_service "$VERSION"
    add_pm_script "systemd"
  fi

  print_help_message

  $displaylink_bootstrap_script START

  print_install_complete
}

uninstall()
{
  echo "Uninstalling"

  echo "Removing EVDI from kernel tree, DKMS, and removing sources."
  remove_module $VERSION

  if [ "upstart" == "$SYSTEMINITDAEMON" ]; then
    remove_upstart_service
  elif [ "systemd" == "$SYSTEMINITDAEMON" ]; then
    remove_systemd_service
  fi

  echo "Removing suspend-resume hooks"
  remove_pm_scripts

  echo "Removing udev rule"
  remove_udev_rule

  echo "Removing Core folder"
  cleanup

  echo -e "\nUninstallation steps complete."
  if [ -f /sys/devices/evdi/version ]; then
    echo "Please note that the evdi kernel module is still in the memory."
    echo "A reboot is required to fully complete the uninstallation process."
  fi
}

missing_requirement()
{
  echo "Unsatisfied dependencies. Missing component: $1." >&2
  echo "This is a fatal error, cannot install $PRODUCT." >&2
  exit 1
}

version_lt()
{
  local left=$(echo $1 | cut -d. -f-2)
  local right=$(echo $2 | cut -d. -f-2)
  local greater=$(echo -e "$left\n$right" | sort -Vr | head -1)
  [ "$greater" != "$left" ] && return $true
  return $false
}

check_requirements()
{
  # DKMS
  which dkms >/dev/null || missing_requirement "DKMS"

  # Required kernel version
  KVER=$(uname -r)
  KVER_MIN="3.14"
  version_lt "$KVER" "$KVER_MIN" && missing_requirement "Kernel version $KVER is too old. At least $KVER_MIN is required"

  # Linux headers
  [ ! -f "/lib/modules/$KVER/source/Kconfig" ] && missing_requirement "Linux headers for running kernel, $KVER"
}

usage()
{
  echo
  echo "Installs $PRODUCT, version $VERSION."
  echo "Usage: $SELF [ install | uninstall ]"
  echo
  echo "If no argument is given, a quick compatibility check is performed but nothing is installed."
  exit 1
}

detect_init_daemon()
{
    INIT=$(readlink /proc/1/exe)
    if [ "$INIT" == "/sbin/init" ]; then
        INIT=$(/sbin/init --version)
    fi

    [ -z "${INIT##*upstart*}" ] && SYSTEMINITDAEMON="upstart"
    [ -z "${INIT##*systemd*}" ] && SYSTEMINITDAEMON="systemd"

    if [ -z "$SYSTEMINITDAEMON" ]; then
        echo "ERROR: the installer script is unable to find out how to start DisplayLinkManager service automatically on your system." >&2
        echo "Please set an environment variable SYSTEMINITDAEMON to 'upstart' or 'systemd' before running the installation script to force one of the options." >&2
        echo "Installation terminated." >&2
        exit 1
    fi
}

detect_distro()
{
  if which lsb_release >/dev/null; then
    local R=$(lsb_release -d -s)
    echo "Distribution discovered: $R"
    [ -z "${R##Ubuntu 14.*}" ] && return
    [ -z "${R##Ubuntu 15.*}" ] && return
    [ -z "${R##Ubuntu 16.04*}" ] && return
    [ -z "${R##openSUSE *}" ] && return
  else
    echo "WARNING: This is not an officially supported distribution." >&2
    echo "Please use DisplayLink Forum for getting help if you find issues." >&2
  fi
}

ensure_not_running()
{
  if [ -f /sys/devices/evdi/version ]; then
    local V=$(< /sys/devices/evdi/version)
    echo "WARNING: Version $V of EVDI kernel module is already running." >&2
    if [ -d $COREDIR ]; then
      echo "Please uninstall all other versions of $PRODUCT before attempting to install." >&2
    else
      echo "Please reboot before attempting to re-install $PRODUCT." >&2
    fi
    echo "Installation terminated." >&2
    exit 1
  fi
}

if [ $(id -u) != 0 ]; then
  echo "You need to be root to use this script." >&2
  exit 1
fi

echo "$PRODUCT $VERSION install script called: $*"
[ -z "$SYSTEMINITDAEMON" ] && detect_init_daemon || echo "Trying to use the forced init system: $SYSTEMINITDAEMON"
detect_distro
check_requirements

while [ -n "$1" ]; do
  case "$1" in
    install)
      ACTION="install"
      ;;

    uninstall)
      ACTION="uninstall"
      ;;
    *)
      usage
      ;;
  esac
  shift
done

if [ "$ACTION" == "install" ]; then
  ensure_not_running
  install
elif [ "$ACTION" == "uninstall" ]; then
  uninstall
fi
