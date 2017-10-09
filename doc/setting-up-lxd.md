# Setting up LXD

LXD needs to be configured a particular way before Vagrant can use it.

Specifically, the following settings need to be applied:

 1. LXD must allow HTTPS API access from your machine.
 2. LXD must have a working network bridge.
 3. Your user must be in the "lxd" group.
 4. Your user must have a client certificate registered with LXD.

## Xenial

To install LXD and configure it as described above on Ubuntu 16.04, you
can use the following commands:

```sh
# install lxd
sudo apt install -y lxd

# enable https api access
sudo lxd init --auto --network-address=127.0.0.1 --network-port=8443

# set up a network bridge (press enter to accept the default values)
sudo dpkg-reconfigure -p medium lxd

# add your user to the lxd group
sudo usermod -a lxd -G $(whoami)
```

Once LXD is configured, you should register a client certificate for
Vagrant to use when authenticating to the API (this command will
automatically generate the certificate for you):

```sh
# apply new group membership
newgrp lxd

# create and add a client certificate
lxc config trust add /home/ubuntu/.config/lxc/client.crt
```

At this point everything should be set up for the plugin to work
correctly.

## Other Platforms

The Linux Containers website has a [detailed guide][getting-started-cli]
to installing LXD on other platforms. The steps to configure LXD for
Vagrant will be similar to those above, but some commands will differ.

If you're using the plugin on another platform, please feel free to
propose an addition to this document or add instructions to the
project's [wiki][] for others to follow.

[getting-started-cli]: https://linuxcontainers.org/lxd/getting-started-cli/
[wiki]: https://gitlab.com/catalyst-it/vagrant-lxd/wikis
