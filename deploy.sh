#!/bin/bash

vagrant plugin uninstall vagrant-lxd
rm vagrant-lxd-0.2.2.gem
gem build vagrant-lxd.gemspec
vagrant plugin install vagrant-lxd-0.2.2.gem

#echo
#echo "---------------------------------------------------"
#vagrant up --provider=lxd

#echo
#echo "---------------------------------------------------"
#vagrant destroy -f