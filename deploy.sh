#!/bin/bash

vagrant plugin uninstall vagrant-lxd
rm vagrant-lxd-0.2.3.gem
gem build vagrant-lxd.gemspec
vagrant plugin install vagrant-lxd-0.2.4.gem

#echo
#echo "---------------------------------------------------"
#vagrant up --provider=lxd

#echo
#echo "---------------------------------------------------"
#vagrant destroy -f