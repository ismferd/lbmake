# Makefile
DESTDIR ?= devel
ARCH ?= i386
FLAVOUR ?= 686-pae
IMAGE ?= iso-hybrid
INSTALL ?= cdrom
CPATH ?= /var/lib/lxc/
MACADDR ?= $(shell echo $$(echo $$FQDM|md5sum|sed 's/^\(..\)\(..\)\(..\)\(..\)\(..\).*$$/02:\1:\2:\3:\4:\5/'))

GET_KEY := curl -s 'http://pgp.mit.edu/pks/lookup?op=get&search=0xKEY_ID' | sed -n '/^-----BEGIN/,/^-----END/p'
ARCHDIR := ${DESTDIR}/config/archives
PKGDIR := ${DESTDIR}/config/package-lists
HOOKDIR := ${DESTDIR}/config/hooks
CUSTDIR := ${DESTDIR}/config/custom

NAME := Clommunity distro
SPLASH_TITLE := ${NAME}
SPLASH_SUBTITLE := ${ARCH} ${FLAVOUR}
TIMESTAMP := $(shell date -u '+%d %b %Y %R %Z')
GIT_BRANCH := $(shell git rev-parse --abbrev-ref HEAD)
GIT_HASH := $(shell git rev-parse --short=12 HEAD)

all: build

describe: packages
	@cat packages

build_environment:
	mkdir -p ${DESTDIR}/auto
	cp /usr/share/doc/live-build/examples/auto/* ${DESTDIR}/auto/

prepare_configure: build_environment
	echo 'lb config noauto \
		--binary-images ${IMAGE} \
		--architectures ${ARCH} \
		--linux-flavours ${FLAVOUR} \
		--debian-installer ${INSTALL} \
		--bootappend-live "boot=live config keyboard-layouts=es,es" \
		--apt-indices false \
		"$${@}"' > ${DESTDIR}/auto/config

make_config: prepare_configure
	cd ${DESTDIR} && lb config

add_repos: make_config
	which curl >/dev/null
	mkdir -p ${ARCHDIR}
	echo "deb http://repo.clommunity-project.eu/debian unstable/" > ${ARCHDIR}/gcodis.list.chroot
	$(subst KEY_ID,8AE35B96C3FD5CD9, ${GET_KEY}) > ${ARCHDIR}/gcodis.key.chroot
	echo "deb http://serveis.guifi.net/debian guifi/" > ${ARCHDIR}/serveis.list.chroot
	$(subst KEY_ID,2E484DAB, ${GET_KEY}) > ${ARCHDIR}/serveis.key.chroot

add_packages: add_repos
	mkdir -p ${PKGDIR}
	while IFS=':	' read name pkgs; do \
		echo $$pkgs > ${PKGDIR}/$$name.list.chroot; \
	done < packages

hooks: add_packages
	mkdir -p ${HOOKDIR}
	cp hooks/* ${HOOKDIR}/

custom: hooks res/clommunity.png
	mkdir -p ${CUSTDIR}
	convert res/clommunity.png -gravity NorthWest -background black \
		-bordercolor black -border 80x50 -extent 640x480 \
		-fill white -pointsize 28 -gravity NorthWest -annotate +330+55 \
		"${SPLASH_TITLE}\n${SPLASH_SUBTITLE}" \
		-fill white -pointsize 20 -gravity NorthWest -annotate +330+120 \
		"${TIMESTAMP}\n${GIT_BRANCH}@${GIT_HASH}" \
		${CUSTDIR}/splash.png

build: custom
	cd ${DESTDIR} && lb build

container: build
	mkdir -p ${CPATH}/gcodis
	grep -q "^lxc.rootfs" ${CPATH}/gcodis/config 2>/dev/null || echo "lxc.rootfs = ${CPATH}/gcodis/rootfs" >> ${CPATH}/gcodis/config

	# Network configuration
	grep "^## Network" ./lxc/config || printf "## Network\nlxc.network.type         = veth\nlxc.network.flags               =up\nlxc.network.hwaddr         =${MACADDR}\n#.lxc.network.link         = vmbr\nlxc.network.link                = lxcbr0\nlxc.network.name              = eth0" >> ./lxc/config

	# Copy configuration
	cat ./lxc/config >> ${CPATH}/gcodis/config

	#Copying chroot to rootfs
	cp -vr ${DESTDIR}/chroot/ ${CPATH}/gcodis
	mv ${CPATH}/gcodis/chroot ${CPATH}/gcodis/rootfs
	rm ${CPATH}/gcodis/rootfs/etc/inittab && cp ./lxc/inittab ${CPATH}/gcodis/rootfs/etc/
	mkdir -p ${CPATH}/gcodis/rootfs/selinux
	echo 0 > ${CPATH}/gcodis/rootfs/selinux/enforce
	echo "root:root" | chroot ${CPATH}/gcodis/rootfs/ chpasswd
	
clean:
	cd ${DESTDIR} && lb clean

.PHONY: all describe build_environment prepare_configure make_config add_repos add_packages hooks custom build clean
