#!/usr/bin/env bash
##
## Script for making rootfs creation easier.
##

set -e -u

if [ "$(uname -o)" = "Android" ]; then
	echo "[!] This script cannot be executed on Android OS."
	exit 1
fi

for i in curl git mmdebstrap sudo tar xz; do
	if [ -z "$(command -v "$i")" ]; then
		echo "[!] '$i' is not installed."
		exit 1
	fi
done

# Where to put generated plug-ins.
PLUGIN_DIR=$(dirname "$(realpath "$0")")/distro-plugins

# Where to put generated rootfs tarballs.
ROOTFS_DIR=$(dirname "$(realpath "$0")")/rootfs

# Working directory where chroots will be created.
WORKDIR=/tmp/proot-distro-bootstrap

# This is used to generate proot-distro plug-ins.
TAB=$'\t'
CURRENT_VERSION=$(git tag | sort -Vr | head -n1)
if [ -z "$CURRENT_VERSION" ]; then
	echo "[!] Cannot detect the latest proot-distro version tag."
	exit 1
fi

# Usually all newly created tarballs are uploaded into GitHub release of
# current proot-distro version.
GIT_RELEASE_URL="https://github.com/termux/proot-distro/releases/download/${CURRENT_VERSION}"

# Normalize architecture names.
# Prefer aarch64,arm,i686,x86_64 architecture names just like used by
# termux-packages.
translate_arch() {
	case "$1" in
		aarch64|arm64) echo "aarch64";;
		arm|armel|armhf|armhfp|armv7|armv7l|armv7a|armv8l) echo "arm";;
		386|i386|i686|x86) echo "i686";;
		amd64|x86_64) echo "x86_64";;
		*)
			echo "translate_arch(): unknown arch '$1'" >&2
			exit 1
			;;
	esac
}

##############################################################################

# Reset workspace. This also deletes any previously made rootfs tarballs.
sudo rm -rf "${ROOTFS_DIR:?}" "${WORKDIR:?}"
mkdir -p "$ROOTFS_DIR" "$WORKDIR"
cd "$WORKDIR"

# Debian (stable).
debian_dist_name="unstable"
printf "\n[*] Building Debian (${debian_dist_name})...\n"
for arch in arm64; do
	sudo mmdebstrap --debug \
                --skip=check/qemu \
                --mode=proot \
		--architectures=${arch} \
		--variant=minbase \
		--components="main,contrib" \
		--include="dbus-user-session,ca-certificates,gvfs-daemons,libsystemd0,systemd-sysv,udisks2" \
		--format=tar \
		"${debian_dist_name}" \
		"${ROOTFS_DIR}/debian-$(translate_arch "$arch")-pd-${CURRENT_VERSION}.tar"
	sudo chown $(id -un):$(id -gn) "${ROOTFS_DIR}/debian-$(translate_arch "$arch")-pd-${CURRENT_VERSION}.tar"
	xz "${ROOTFS_DIR}/debian-$(translate_arch "$arch")-pd-${CURRENT_VERSION}.tar"
done
unset arch

cat <<- EOF > "${PLUGIN_DIR}/debian.sh"
# This is a default distribution plug-in.
# Do not modify this file as your changes will be overwritten on next update.
# If you want customize installation, please make a copy.
DISTRO_NAME="Debian (${debian_dist_name})"

TARBALL_URL['aarch64']="${GIT_RELEASE_URL}/debian-aarch64-pd-${CURRENT_VERSION}.tar.xz"
TARBALL_SHA256['aarch64']="$(sha256sum "${ROOTFS_DIR}/debian-aarch64-pd-${CURRENT_VERSION}.tar.xz" | awk '{ print $1}')"

distro_setup() {
${TAB}# Don't update gvfs-daemons and udisks2
${TAB}run_proot_cmd apt-mark hold gvfs-daemons udisks2
}
EOF
unset debian_dist_name
