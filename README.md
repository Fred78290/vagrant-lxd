# vagrant-lxd

This is a [Vagrant][] plugin that adds the ability to manage containers
with [LXD][].

[Vagrant]: https://www.vagrantup.com/
[LXD]: https://linuxcontainers.org/lxd/

## Features

The following features are currently supported:

 - VM management (create, suspend, destroy, etc.)
 - IPv4 networking
 - Synced folders
 - Snapshots

The following features are not expected to work yet:

 - Forwarded ports
 - Static IP addresses
 - IPv6 networking

The plugin requires LXD 2.0 and Vagrant 1.8.7 or newer.

## Installation

### From Rubygems

You can install the latest version of the plugin directly from
rubygems.org with the `vagrant plugin` command:

    $ vagrant plugin install vagrant-lxd

### From Git

Installing from this repository is a three-step process.

 1. Use Bundler to install development dependencies:
    
        $ bundle install
    
 2. Build the gem:
    
        $ bundle exec rake build
    
 3. Install it as a Vagrant plugin:
    
        $ vagrant plugin install pkg/vagrant-lxd-<version>.gem

## Usage

### Quick Start

First, make sure that you've [configured LXD correctly][setting-up-lxd]
for use with Vagrant.

Once LXD is set up, you can use `vagrant up --provider lxd` to create
container-backed machines. This plugin reuses the `lxc` box format, so
VM images from [Vagrant Cloud][cloud] should work without modification:

    $ vagrant init --minimal debian/stretch64
    $ vagrant up --provider lxd

[setting-up-lxd]: doc/setting-up-lxd.md
[cloud]: https://app.vagrantup.com/boxes/search?provider=lxc

#### Configuration

Below is an example Vagrantfile showing all of the provider's
configurable values, along with their defaults. The `debian/stretch64`
box is available on the Vagrant Cloud, so you should be able to copy
this file and adjust it as you see fit.

``` ruby
Vagrant.configure('2') do |config|
  config.vm.box = 'debian/stretch64'

  config.vm.provider 'lxd' do |lxd|
    lxd.api_endpoint = 'https://127.0.0.1:8443'
    lxd.timeout = 10
    lxd.name = nil
    lxd.nesting = false
    lxd.privileged = false
    lxd.ephemeral = false
    lxd.profiles = []
  end
end
```

### Shared Folders

In order to use shared folders, you must first add your user ID to the
host machine's subuid(5) and subgid(5) files:

    $ echo root:$(id -u):1 | sudo tee -a /etc/subuid
    $ echo root:$(id -g):1 | sudo tee -a /etc/subgid

For more information about these commands, and user/group ID mapping in
general, we recommend [this article][1].

[1]: https://insights.ubuntu.com/2017/06/15/custom-user-mappings-in-lxd-containers/

### Shared LXD Containers

It's possible to share a single LXD container between multiple Vagrant
VMs by "attaching" them to the container by name.

For example, to associate the "default" VM with a preexisting LXD
container called "my-container", use the `vagrant lxd attach` command:

    $ lxc list -cn # list available containers
    +--------------+
    |     NAME     |
    +--------------+
    | my-container |
    +--------------+
    
    $ vagrant lxd detach default # detach from current container, if necessary
    ==> default: Machine is not attached to a container, skipping...
    
    $ vagrant lxd attach default my-container
    ==> default: Attaching to container 'my-container'...

### Nested Containers

In order to run Linux containers on an LXD-backed machine, it must be
created with the `nesting` and `privileged` properties set to `true`.
These correspond to the `security.nesting` and `security.privileged`
configuration items for LXD, respectively. Refer to LXD's [container
configuration documentation][docs] for details.

    config.vm.provider 'lxd' do |lxd|
      lxd.nesting = true
      lxd.privileged = true
    end

[docs]: https://lxd.readthedocs.io/en/latest/containers/

## Hacking

To run Vagrant with the plugin automatically loaded, you can use the
`bundle exec` command:

    $ bundle exec vagrant <command>

## Contributing

 1. Fork it from <https://gitlab.com/catalyst-it/vagrant-lxd>
 2. Create a feature branch (`git checkout -b my-new-feature`)
 3. Commit your changes (`git commit -am 'Add some feature'`)
 4. Push to the branch (`git push origin my-new-feature`)
 5. Create a Merge Request at <https://gitlab.com/catalyst-it/vagrant-lxd/merge_requests>
