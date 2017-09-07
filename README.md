# vagrant-lxd

This is a [Vagrant][] plugin that adds the ability to manage containers
with [LXD][].

[Vagrant]: https://www.vagrantup.com/
[LXD]: https://linuxcontainers.org/lxd/

## Features

The following features are currently supported:

 - Basic VM management (create, suspend, destroy, etc.)
 - Automatic network configuration
 - Synced folders
 - Existing amd64 Vagrant boxes

The following features are not expected to work yet:

 - Snapshots
 - Forwarded ports
 - Static IP addresses
 - IPv6
 - Non-amd64 Vagrant boxes

The plugin requires LXD 2.0 and Vagrant 1.8.7 or newer.

## Installation

Installing the plugin from this repository is a three-step process.

 1. Use Bundler to install development dependencies:
    
        $ bundle install
    
 2. Build the gem:
    
        $ bundle exec rake build
    
 3. Install it as a Vagrant plugin:
    
        $ vagrant plugin install pkg/vagrant-lxd-<version>.gem

## Usage

### Quick Start

This plugin understands the `lxc` box format, so VM images from [Vagrant
Cloud][cloud] should work without modification:

    $ vagrant init --minimal debian/stretch64
    $ vagrant up --provider lxd

[cloud]: https://app.vagrantup.com/boxes/search?provider=lxc

### Shared Folders

In order to use shared folders, you must first add your user ID to the
host machine's subuid(5) and subgid(5) files:

    # echo root:$(id -u):1 >> /etc/subuid
    # echo root:$(id -g):1 >> /etc/subgid

For more information about these commands, and user/group ID mapping in
general, we recommend [this article][1].

[1]: https://insights.ubuntu.com/2017/06/15/custom-user-mappings-in-lxd-containers/

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
