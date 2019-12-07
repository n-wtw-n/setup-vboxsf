#!/usr/bin/bash

# make sure script is being run as root
if (( $(id -u) != 0 )); then
	printf '%s: This script must be run as root!\n' "$0"
	exit 100
fi

# check if VirtualBox Guest Additions has been installed
if [[ $(systemctl list-units --all --full | grep -qF vboxadd-service.service; echo $?) -ne 0 || ! -x /usr/sbin/mount.vboxsf ]]; then
	printf '%s: %s (%s) %s!\n' \
	"$0" 'Mount and\or install VirtualBox Guest Additions ISO and create a Shared Folder' \
	'Settings>Shared Folder' 'before running this script'; exit 200
else
	vboxsf_gid=$(awk -F: '/vboxsf/{print $3}' /etc/group)
fi

# print usage statement if '-h' option is provided
if [[ $(echo -n "$*" | grep -qFe -h; echo $?) -eq 0 ]]; then
	printf ' %s:  %s [%s] %s %s\n%s: \t./%s %s %s\n   OR\n%s: \t./%s %s %s\n' \
	"USAGE" "$0" "-h" "/path/to/shared_folder/mountpoint" "share" \
	"EXAMPLE A" "$(basename "$0")" "/mnt/shared" "shared.d" \
	"EXAMPLE B" "$(basename "$0")" "shared.d" "/mnt/shared"; exit 0
fi

# gather positional parameters
if [[ "$#" -eq 2 ]]; then
	while (( $# )); do
		if [[ "$1" =~ ^/.*$ ]]; then
			mntpoint="${1%/}"
		else
			share="$1"
		fi
		shift
	done
else
	printf '%s: %s - (%s)\n%s: %s - (%s)\n%s: %s - (%d)\n' \
	"$0" "Arguments provided" "$*" \
	"$0" "Arguments required" "mountpoint sharename" \
	"$0" "Exiting with failure" "50"; exit 50
fi

# define systemd unit files
systemd_mnt_file="${mntpoint:1}"
systemd_mnt_file="/etc/systemd/system/${systemd_mnt_file//\//-}.mount"
systemd_svc_file="${systemd_mnt_file//.mount/-remount.service}"

# check if systemd unit files already exist
if ! [[ -f $systemd_mnt_file ]] && ! [[ -f $systemd_svc_file ]]; then
	u1=$(basename "$systemd_mnt_file")
	u2=$(basename "$systemd_svc_file")
else
	printf "%s: '%s' and\\or '%s' exist(s).\n%s: %s.\n%s: %s - (%d)\n" \
	"$0" "$systemd_mnt_file" "$systemd_svc_file" \
	"$0" "Delete existing file(s) or use a different mountpoint" \
 	"$0" "Exiting" "1"; exit 1
fi

cat <<EOF > "$systemd_mnt_file"
[Unit]
Description=VirtualBox Shared Folder
Requires=vboxadd-service.service
After=vboxadd-service.service

[Mount]
What=$share
Where=$mntpoint
Type=vboxsf

[Install]
WantedBy=multi-user.target
EOF
cat <<EOF > "$systemd_svc_file"
[Unit]
Description=Remounts $mntpoint with proper permissions
Requires=${u1}
After=${u1}

[Service]
Type=oneshot
ExecStart=/sbin/mount.vboxsf -o rw,uid=0,gid=${vboxsf_gid:-0},dmask=002 ${share} ${mntpoint}

[Install]
WantedBy=multi-user.target
EOF

for i in $u1 $u2; do 
	if ! systemctl -q is-enabled "$i"; then
		systemctl enable "$i"
	else
		systemctl daemon-reload
	fi
done

{ systemctl start "$u1" && systemctl start "$u2"; } && systemctl status -l "$u1" "$u2"

if mountpoint -q "$mntpoint"; then
	df -Ph "$mntpoint"
	exit 0
else
	exit 150	
fi