# Proxmox USPS Shutdown
A script for managing graceful shutdowns of virtual machines in Proxmox during power failures using NUT (Network UPS Tools) and UPS (Uninterruptible Power Supply). Features configurable wait times and force shutdown options.


## Steps to Install

The basic steps to install are:

1. Install and configure NUT to work with your UPS.
2. Install and configure proxmox-shutdown.sh.
3. Configure the NUT upsmon to call proxmox-shutdown.sh.

## Install and Configure NUT

Use `apt install nut` to install NUT, then use the NUT [user documentation](https://networkupstools.org/docs/user-manual.chunked/index.html) to configure it for your UPS.

## Install and Configure proxmox-shutdown.sh. 

Download and install proxmox-shutdown.sh. This will put it in `/usr/local/sbin`, but you can place it anywhere.

```
curl -o /usr/local/sbin/proxmox-shutdown.sh https://raw.githubusercontent.com/jordanmack/proxmox-ups-shutdown/refs/heads/main/proxmox-shutdown.sh
chmod +x /usr/local/sbin/proxmox-shutdown.sh
```

Configure proxmox-shutdown.sh.

`nano /usr/local/sbin/proxmox-shutdown.sh`

In particular, you will probably need to update the following:

- POWER_FAILURE_WAIT_TIME - The amount of time to wait for power to come back on before shutting down.
- UPS_IDENTIFIER - NUT UPS identifier to query for status using upsc.
- DEFAULT_ACTION - Default action for all VMs. Normally set to "shutdown".
- VM_ACTIONS - Specify which VMs should hibernate instead of shutdown.

## Configure the NUT upsmon to call proxmox-shutdown.sh.

By default, the `upsmon` will shutdown your system and it won't do anything to make sure your VMs shut down properly. You must configure it not to shutdown and to call proxmox-shutdown.sh instead.

```
nano /etc/nut/upsmon.conf
```

In particular, you must do the following:

Add the following lines to call `proxmox-shutdown.sh` when on battery:

```
NOTIFYFLAG ONBATT EXEC
NOTIFYCMD /usr/local/sbin/proxmox-shutdown.sh
```

Comment out the following lines to ensure the script handles the shutdown, not `upsmon`:

```
SHUTDOWNCMD "/sbin/shutdown -h +0"
FINALDELAY 5
```

Below are the resulting effective configurations that I use, omitting the commented out lines. Please do not copy and paste these configurations without understanding what they do. Instead, refer to the NUT [user documentation](https://networkupstools.org/docs/user-manual.chunked/index.html).

```

=== /etc/nut/nut.conf ===
MODE=standalone

=== /etc/nut/ups.conf ===
maxretry = 3
[myups]
    driver = usbhid-ups
    port = auto
    desc = "APC Back-UPS"

=== /etc/nut/upsd.conf ===

=== /etc/nut/upsd.users ===
[admin]
    password = replacewithsecurepassword
    actions = SET
    instcmds = ALL
    upsmon master

=== /etc/nut/upsmon.conf ===
MONITOR myups@localhost 1 admin replacewithsecurepassword master
MINSUPPLIES 1
NOTIFYCMD /usr/local/sbin/proxmox-shutdown.sh
POLLFREQ 5
POLLFREQALERT 5
HOSTSYNC 15
DEADTIME 15
POWERDOWNFLAG /etc/killpower
NOTIFYFLAG ONBATT EXEC
RBWARNTIME 43200
NOCOMMWARNTIME 300

=== /etc/nut/upssched.conf ===
CMDSCRIPT /bin/upssched-cmd
```

