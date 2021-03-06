#!/bin/sh
# Copyright (c) 2016 - 2019 DisplayLink (UK) Ltd.

create_udev_rules_file()
{
  displaylink_rules_file="$1"
cat > $displaylink_rules_file  <<'EOF'
# Copyright (c) 2016 - 2019 DisplayLink (UK) Ltd.
# File autogenerated by udev-installer.sh script

ACTION=="add", SUBSYSTEM=="usb", DRIVERS=="usb", ATTR{idVendor}=="17e9", IMPORT{builtin}="usb_id", ENV{DISPLAYLINK_DEVNAME}="$env{DEVNAME}", ENV{DISPLAYLINK_DEVICE_ID}="$env{ID_BUS}-$env{BUSNUM}-$env{DEVNUM}-$env{ID_SERIAL}", ENV{REMOVE_CMD}="/opt/displaylink/udev.sh $root $env{DISPLAYLINK_DEVICE_ID} $env{DISPLAYLINK_DEVNAME}"

ACTION=="add", SUBSYSTEM=="usb", DRIVERS=="usb", ATTRS{idVendor}=="17e9", ATTR{bInterfaceClass}=="ff", ATTR{bInterfaceProtocol}=="03", IMPORT{parent}="DISPLAYLINK*", RUN+="/opt/displaylink/udev.sh $root $env{DISPLAYLINK_DEVICE_ID} $env{DISPLAYLINK_DEVNAME}"

ACTION=="remove", ENV{PRODUCT}=="17e9/*", RUN+="/opt/displaylink/udev.sh $root $env{DEVNAME}"

EOF

  chmod 0644 $displaylink_rules_file
}

systemd_start_stop_functions()
{
  cat <<'EOF'
start_service()
{
  systemctl start displaylink-driver
}

stop_service()
{
  systemctl stop displaylink-driver
}

EOF

}

upstart_start_stop_functions()
{
  cat <<'EOF'
start_service()
{
  start displaylink-driver
}

stop_service()
{
  stop displaylink-driver
}

EOF

}

displaylink_bootstrapper_code()
{
  cat <<'EOF'
#!/bin/sh
# Copyright (c) 2016 - 2019 DisplayLink (UK) Ltd.
# File autogenerated by udev-installer.sh script

get_displaylink_dev_count()
{
   cat /sys/bus/usb/devices/*/idVendor | grep 17e9 | wc -l
}

get_displaylink_symlink_count()
{
  root=$1

  if [ ! -d "$root/displaylink/by-id" ]; then
    echo "0"
    return
  fi

  for f in $(find $root/displaylink/by-id -type l -exec realpath {} \; 2> /dev/null); do
    test -c $f && echo $f;
  done | wc -l
}

start_displaylink()
{
  if [ "$(get_displaylink_dev_count)" != "0" ]; then
    start_service
  fi
}

stop_displaylink()
{
  root=$1

  if [ "$(get_displaylink_symlink_count $root)" = "0" ]; then
    stop_service
  fi
}

remove_dldir_if_empty()
{
  root=$1
  (cd $root; rmdir -p --ignore-fail-on-non-empty displaylink/by-id)
}

create_displaylink_symlink()
{
  root=$1
  device_id=$2
  devnode=$3

  mkdir -p $root/displaylink/by-id
  ln -sf $devnode $root/displaylink/by-id/$device_id
}

unlink_displaylink_symlink()
{
   root=$1
   devname=$2

   for f in $root/displaylink/by-id/*; do
     if [ ! -e "$f" ] || ([ -L "$f" ] && [ "$f" -ef "$devname" ]); then
       unlink "$f"
     fi
   done
   (cd $root; rmdir -p --ignore-fail-on-non-empty displaylink/by-id)
}

prune_broken_links()
{
  root=$1

  dir="$root/displaylink/by-id"
  find -L "$dir" -name "$dir" -o type d -prune -o -type -l -exec rm {} +
  remove_dldir_if_empty $root
}

main()
{
  action=$1
  root=$2
  devnode=$4

  if [ "$action" = "add" ]; then
    device_id=$3
    create_displaylink_symlink $root $device_id $devnode
    start_displaylink
  elif [ "$action" = "remove" ]; then
      devname=$3
      unlink_displaylink_symlink "$root" "$devname"
      stop_displaylink "$root"
  elif [ "$action" = "START" ]; then
    start_displaylink
  fi
}

EOF
}

create_main_function()
{
  cat <<'EOF'

if [ "$ACTION" = "add" ] && [ "$#" -ge 3 ]; then
  main $ACTION $1 $2 $3
  return 0
fi

if  [ "$ACTION" = "remove" ]; then
  if [ "$#" -ge 2 ]; then
    main $ACTION $1 $2 $3
    return 0
  else
    prune_broken_links $root
    return 0
  fi
fi

EOF
}

create_bootstrap_file()
{
  init_daemon=$1
  filename=$2

  if [ "$init_daemon" = "upstart" ]; then
    start_stop_functions="$(upstart_start_stop_functions)"
  elif [ "$init_daemon" = "systemd" ]; then
    start_stop_functions="$(systemd_start_stop_functions)"
  else
    (>&2 echo "Unknown init daemon: $init_daemon")
    exit 1
  fi

  displaylink_bootstrapper_code > $filename
  echo "$start_stop_functions" >> $filename
  create_main_function >> $filename
  chmod 0744 $filename
}

main()
{
  init_daemon=$1
  rules_path=$2
  udev_script_path=$3
  create_bootstrap_file $init_daemon $udev_script_path
  create_udev_rules_file $rules_path
}

if [ "$#" = "3" ]; then
  main $1 $2 $3
fi
