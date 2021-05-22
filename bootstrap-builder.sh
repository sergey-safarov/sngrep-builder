#!/bin/bash

set -o errexit -o nounset -o pipefail

# Uncomment for debug output
#set -x

get_dist() {
  grep -oP  "(?<=^ID=).*" /etc/os-release | sed -e 's/"//g'
}

get_dist_version() {
  grep -oP  "(?<=^VERSION_ID=).*" /etc/os-release | sed -e 's/"//g'
}

install_env() {
  local dist=$1
  local dist_version=$2
  case ${dist} in
    rhel)
      adduser builder
      subscription-manager register --username="${rhel_username}" --password="${rhel_password}"
      subscription-manager attach
      if [[ "${dist_version}" =~ "7" ]]; then
        yum install -y yum-utils git rpm-build
        yum-config-manager --enablerepo=rhel-7-server-optional-rpms
      else
        dnf install -y 'dnf-command(builddep)' git rpm-build
        dnf config-manager --set-enabled codeready-builder-for-rhel-${dist_version}-x86_64-rpms
      fi
      ;;
    centos)
      adduser builder
      yum install -y dnf
      dnf install -y 'dnf-command(builddep)' git rpm-build
      if [ "${dist_version}" -eq 8 ]; then
        dnf config-manager --set-enabled powertools
      fi
      ;;
    fedora)
      adduser builder
      dnf install -y 'dnf-command(builddep)' git rpm-build
      ;;
    debian)
      adduser builder
      apt-get update
      apt-get install -y build-essential devscripts git
      ;;
    alpine)
      adduser builder
      addgroup builder abuild
      apk --no-cache upgrade
      apk --no-cache add alpine-sdk sudo git
      echo "%abuilder ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/abuild
      su - builder -c "git config --global user.name 'Your Full Name'"
      su - builder -c "git config --global user.email 'your@email.address'"
      su - builder -c "abuild-keygen -a -i"
      ;;
    opensuse-leap)
      useradd builder
      zypper -n install curl git rpm-build
      ;;
    opensuse-tumbleweed)
      useradd builder
      zypper -n install curl shadow git rpm-build
      ;;
  esac
}

install_deps() {
  local dist=$1
  local dist_version=$2
  case ${dist} in
    rhel)
      curl -s -S -O https://raw.githubusercontent.com/irontec/sngrep/master/pkg/rpm/SPECS/sngrep.spec
      if [[ "${dist_version}" =~ "7" ]]; then
        yum-builddep -y sngrep.spec
      else
        dnf builddep -y sngrep.spec
      fi
      rm -f sngrep.spec
      ;;
    centos)
      curl -s -S -O https://raw.githubusercontent.com/irontec/sngrep/master/pkg/rpm/SPECS/sngrep.spec
      dnf builddep -y sngrep.spec
      rm -f sngrep.spec
      ;;
    fedora)
      dnf builddep -y https://raw.githubusercontent.com/irontec/sngrep/master/pkg/rpm/SPECS/sngrep.spec
      ;;
    debian)
      git clone https://github.com/irontec/sngrep.git
      cd sngrep
      ln -s pkg/debian/ .
      dpkg-source -b .
      cd ..
      rm -Rf sngrep
      mk-build-deps -i --tool="apt-get --no-install-recommends -y" sngrep_*.dsc
      rm -f /sngrep*
      ;;
    alpine)
      local TMPDIR=$(mktemp -d)
      curl -s -S -o ${TMPDIR}/APKBUILD https://raw.githubusercontent.com/alpinelinux/aports/master/community/sngrep/APKBUILD
      chown -R builder ${TMPDIR}
      su - builder -c "cd ${TMPDIR}; abuild deps"
      rm -Rf ${TMPDIR}
      ;;
    opensuse-leap)
      curl -s -S -O https://raw.githubusercontent.com/irontec/sngrep/master/pkg/rpm/SPECS/sngrep.spec
      zypper -n install $(rpmspec -P sngrep.spec | grep BuildRequires | sed -r -e 's/BuildRequires:\s+//' -e 's/,//g' | xargs)
      rm -f sngrep.spec
      ;;
    opensuse-tumbleweed)
      curl -s -S -O https://raw.githubusercontent.com/irontec/sngrep/master/pkg/rpm/SPECS/sngrep.spec
      zypper -n install $(rpmspec -P sngrep.spec | grep BuildRequires | sed -r -e 's/BuildRequires:\s+//' -e 's/,//g' | xargs)
      rm -f sngrep.spec
      ;;
  esac
}

cleanup() {
  local dist=$1
  local dist_version=$2
  case ${dist} in
    rhel)
      yum clean all
      dnf clean all
      subscription-manager remove --all
      subscription-manager unregister
      ;;
    centos)
      yum clean all
      dnf clean all
      ;;
    fedora)
      dnf clean all
      ;;
    debian)
      apt-get clean
      ;;
    opensuse-leap)
      zypper clean --all
      ;;
    opensuse-tumbleweed)
      zypper clean --all
      ;;
  esac
}

echo "Preparing sngrep builder using '${base_image}:${image_tag}' image"; \
dist=$(get_dist)
dist_version=$(get_dist_version)

install_env ${dist} ${dist_version}
install_deps ${dist} ${dist_version}
cleanup ${dist} ${dist_version}

