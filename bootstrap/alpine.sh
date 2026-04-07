#!/bin/sh
add_alpine_repos() {
	alpine_release=$(cat /etc/alpine-release | cut -d "." -f 1,2)
	main_repo="https://dl-cdn.alpinelinux.org/alpine/v$alpine_release/main"
	community_repo="https://dl-cdn.alpinelinux.org/alpine/v$alpine_release/community"
	if ! grep -q $main_repo /etc/apk/repositories; then
		echo $main_repo | tee -a /etc/apk/repositories
	fi
	if ! grep -q $community_repo /etc/apk/repositories; then
		echo $community_repo | tee -a /etc/apk/repositories
	fi
}

start_openssh() {
	apk add openssh util-linux
	sed -i "1i Include /etc/ssh/sshd_config.d/*.conf" /etc/ssh/sshd_config
	mkdir /etc/ssh/sshd_config.d
	tee /etc/ssh/sshd_config.d/60-hardend.conf <<-EOF
		Port 12345

		PermitRootLogin prohibit-password
		PasswordAuthentication no
		KbdInteractiveAuthentication no
	EOF
	mkdir ~/.ssh/
	chmod 700 ~/.ssh/
	tee ~/.ssh/authorized_keys <<-EOF
		        ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO0pibvDHlrQ2kXoIKhHsoQie8njFFLD2cxv379YU/ZI
	EOF
	chmod 600 ~/.ssh/authorized_keys
	rc-service sshd start
}

enable_dhcp_network() {
	for file in /sys/class/net/*; do
		interface_name=$(basename $file)
		if [ $(basename $file) != "lo" ]; then
			break
		fi
	done
	tee /etc/network/interfaces <<-EOF
		auto $interface_name
		iface $interface_name inet dhcp
	EOF
	rc-service networking start
}

umount_root() {
	echo "=> Copying .modloop to RAM..."
	cp -a /.modloop /root/
	cp -a /media/cdrom/apks /root/

	echo "=> Re-linking kernel modules..."
	rm -rf /lib/modules
	ln -sf /root/.modloop/modules /lib/modules

	echo "=> Unmounting locked disk..."
	umount /.modloop
	umount /media/cdrom 2>/dev/null
	umount /media/* 2>/dev/null

	losetup -D
	echo "=> Done! Validating device locks..."
	# Optional check: ensure no loop devices remain holding onto your sda
	if lsblk | grep -q loop; then
		echo "WARNING: Loop devices are still active! Your dd might fail."
	else
		echo "Disk fully unlocked and ready to receive dd stream."
	fi
}
