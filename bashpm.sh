#!/bin/sh

usage="$(basename "$0") [-h] -- A basic bash based package manager

where:
    -h    show this help text
    -i    installs a package
    -r    removes a package
    -u    updates a package
    -v    shows the version $(basename "$0")"

isroot() {
	if [[ $EUID -ne 0 ]]; then
		echo "This script must be run as root" 
		exit 1
	fi
}

isinstalled() {
	pkg=$1
	PACKAGE_COUNT=$(cat /etc/bashpm/packages.json | jq -r "length")
	for run in {0...$PACKAGE_COUNT}
	do
		PACKAGE=$(cat /etc/bashpm/packages.json | jq -r ".[$run]")
		PKG_NAME=$(echo $PACKAGE | jq -r ".name")
		if [[ $pkg = $PKG_NAME ]]; then
			echo "true"
			return 1
		fi
	done
}

getpackage() {
	pkg=$1
	PACKAGE_COUNT=$(cat /etc/bashpm/packages.json | jq -r "length")
	for run in {0...$PACKAGE_COUNT}
	do
		PACKAGE=$(cat /etc/bashpm/packages.json | jq -r ".[$run]")
		PKG_NAME=$(echo $PACKAGE | jq -r ".name")
		if [[ $pkg = $PKG_NAME ]]; then
			echo $PACKAGE
			return 1
		fi
	done
}

getsource() {
	src=$1
	SOURCE_COUNT=$(cat /etc/bashpm/sources.json | jq -r "length")
	for run in {0...$SOURCE_COUNT}
	do
		SOURCE=$(cat /etc/bashpm/sources.json | jq -r ".[$run]")
		SOURCE_NAME=$(echo $SOURCE | jq -r ".name")
		if [[ $src = $SOURCE_NAME ]]; then
			echo $SOURCE
			return 1
		fi
	done
}

while getopts ':hvr:i:u:' option; do
	case "$option" in
		h) echo "$usage"
			exit
			;;
		v)
			echo "$(basename "$0") 0.1.0"
			exit
			;;
		r)
			isroot
			lockfile -r 0 /tmp/bashpm.lock || exit 1
			if [[ $(isinstalled $OPTARG) = "true" ]]; then
				PACKAGE=$(getpackage $OPTARG)
				VERSION=$(echo $PACKAGE | jq -r ".version")
				ARCH=$(echo $PACKAGE | jq -r ".arch")
				SOURCE=$(getsource $(echo $PACKAGE | jq -r ".source"))
				cat /etc/bashpm/packages.json | jq -r "del(.[] | select(.name == $OPTARG))" >> /etc/bashpm/packages.json
				FILES=$(tar --list /var/cache/bashpm/$OPTARG-$VERSION-$ARCH.tar.gz)
				while read -r file
				do
					TYPE=$(stat /$file -c "%F")
					if [ $TYPE = "regular file" ]; then
						if [ ! -f /$file ]; then
							rm /$file
						fi
					fi
				done <<< $FILES
				rm /var/cache/bashpm/$OPTARG-$VERSION-$ARCH.tar.gz
				rm -f /tmp/bashpm.lock
			else
				echo "Package $OPTARG is not installed"
				rm -f /tmp/bashpm.lock
				exit 1
			fi
			exit
			;;
		i)
			isroot
			lockfile -r 0 /tmp/bashpm.lock || exit 1
			if [[ $(isinstalled $OPTARG) = "true" ]]; then
				echo "Package is already installed."
				rm -f /tmp/bashpm.lock
				exit 1
			else
				SOURCE_COUNT=$(cat /etc/bashpm/sources.json | jq -r "length")
				for run in {0...$SOURCE_COUNT}
				do
					SOURCE=$(cat /etc/bashpm/sources.json | jq -r ".[$run]")
					SOURCE_URL=$( echo $SOURCE | jq -r ".url")
					PACKAGES=$(curl $SOURCE_URL/packages.json)
					PACKAGE_COUNT=$(echo $PACKAGES | jq -r "length")
					for pkgrun in {0...$PACKAGE_COUNT}
					do
						PACKAGE=$(echo $PACKAGES | jq -r ".[$pkgrun]")
						PKG_NAME=$(echo $PACKAGE | jq -r ".name")
						if [[ $PKG_NAME = $OPTARG ]]; then
							VERSION=$(echo $PACKAGE | jq -r ".version")
							ARCH=$(echo $PACKAGE | jq -r ".arch")
							cat /etc/bashpm/packages.json | jq -r "+[$PACKAGE]" >> /etc/bashpm/packages.json
							wget -O /var/cache/bashpm/$OPTARG-$VERSION-$ARCH.tar.gz $SOURCE_URL/packages/$OPTARG-$VERSION-$ARCH.tar.gz
							tar -C / -x /var/cache/bashpm/$OPTARG-$VERSION-$ARCH.tar.gz
							rm -f /tmp/bashpm.lock
							exit
						fi
					done
				done
				echo "Package does not exist."
				rm -f /tmp/bashpm.lock
				exit 1
			fi
			exit
			;;
		u)
			$(basename "$0") -r $OPTARG
			$(basename "$0") -i $OPTARG
			exit
			;;
		:) printf "missing argument for -%s\n" "$OPTARG" >&2
			echo "$usage" >&2
			exit 1
			;;
		\?) printf "illegal option: -%s\n" "$OPTARG" >&2
			echo "$usage" >&2
			exit 1
			;;
	esac
done
shift $((OPTIND - 1))