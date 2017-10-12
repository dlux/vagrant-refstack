Refstack Server
================

[![Build Status](https://api.travis-ci.org/dlux/vagrant-refstack.svg?branch=master)](https://api.travis-ci.org/dlux/vagrant-refstack)

This vagrant project is to install refstack server for development purposes.
For additional options such as deploying RefStack on a docker containers,
see [RefStack documentation][1].

**Requirements:**

  * [Vagrant][2]
  * [VirtualBox][3]

**Steps for initialization:**

    $ git clone https://github.com/dlux/vagrant-refstack.git
    $ cd vagrant-refstack
    $ ./recreate.sh

Refstack source code repositories are shared between host and guest computers.
This feature allows to use the advantages of a local IDE and verify those
changes in an isolated virtual environment.

**Steps to recreate:**

    $ ./recreate.sh

*Firewalld*

Given that synchonization uses NFS is possible to have some issues with
firewall. As a solution, it's necessary to add some rules to be setup in
firewalld servicei:

    # firewall-cmd --permanent --add-service rpc-bind
    # firewall-cmd --permanent --add-service nfs

This can be verified by running `# firewall-cmd --list-all`

[1]: https://docs.openstack.org/refstack/latest/README.html
[2]: https://www.vagrantup.com/downloads.html
[3]: https://www.virtualbox.org/wiki/Downloads
