#!/bin/bash -u

if [ "$EUID" -ne 0 ]; then
  echo 'This script must be run as root.' >&2
  exit 1
fi

if command -v puppet >/dev/null 2>&1; then
  echo 'Puppet is already installed, nothing to do'
  exit 0
fi

# need lsb_release to get RHEL version
if ! command -v lsb_release >/dev/null 2>&1; then
  echo 'lsb_release not available, installing redhat-lsb-core...'
  yum install -y redhat-lsb-core
fi

echo 'Installing Puppet...'

# enable repo
rhel=`lsb_release -r | awk -F '[\t|.]' '{print $2}'`
rpm -ivh https://yum.puppetlabs.com/puppetlabs-release-pc1-el-$rhel.noarch.rpm

# install puppet
yum install -y puppet

# csr_attributes file will be used to embed facts into the agent's certificate
# not validating args is bad practice, but this script should only be called from the vagrantfile
echo 'writing csr_attributes.yaml'
cat > /etc/puppetlabs/puppet/csr_attributes.yaml << EOF
---
extension_requests:
  pp_role: $1
  pp_environment: $2
EOF

echo 'Puppet has been installed.'

if [ $1 = 'puppetmaster' ]; then
  # librarian-puppet will be used to install modules from control repo for initial manifest run
  yum install -y ruby git
  gem install librarian-puppet --no-ri --no-rdoc

  # clone control repo to get Puppetfile and puppetmaster manifest
  git clone -b $2 https://github.com/erumble/control-repo.git /tmp/puppet/control-repo

  # bootstrap the puppet master
  pushd /tmp/puppet/control-repo
  librarian-puppet install --path /tmp/puppet/modules
  puppet apply --test --modulepath=/tmp/puppet/modules/:/tmp/puppet/control-repo/site/ -e "include roles::${1}"
  r10k deploy environment -pv
  popd

  # clean up after ourselves
  rm -rf /tmp/puppet
fi

# use init syntax to be backwards compatible with CentOS <= 6
service puppet start

