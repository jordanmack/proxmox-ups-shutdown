#!/bin/bash

# ==============================
# NUT Shutdown Script for Proxmox
# ==============================
# This script is designed to be used with Proxmox and NUT (Network UPS Tools).
# It will wait for a power failure, then gracefully shut down all running VMs
# before shutting down the host machine. VMs can be configured to hibernate
# instead of shutting down by adding their VMID to the VM_ACTIONS array.

# ==============================
# Configuration
# ==============================
DRY_RUN=false  # If set to true, the script will not shut down the host machine.
SIMULATE_FAILURE=false  # If set to true, the script will simulate a power failure and ignore UPS status.
POWER_FAILURE_WAIT_TIME=300  # Delay time in second for power restoration before taking action.
VM_ACTION_DELAY=5  # Delay time in seconds between processing each VM action.
VM_SHUTDOWN_TIMEOUT=30  # Timeout period in seconds before force shutdown of VMs that did not shut down gracefully.
DEFAULT_ACTION="shutdown"  # Set to "shutdown" or "hibernate" to define the default action for all VMs. (Does not apply to CTs.)
UPS_IDENTIFIER="myups@localhost" # NUT UPS identifier to query for status using upsc.

# Specific VM overrides. Add VMID and action to the array to override the default action.
declare -A VM_ACTIONS
VM_ACTIONS[105]="hibernate"
VM_ACTIONS[109]="hibernate"
VM_ACTIONS[114]="hibernate"

# ==============================
# Functions
# ==============================

log_message() {
    echo "NUT: $1" | tee >(logger -t NUT)
}

# ==============================
# Main Script
# ==============================

# Wait for power failure to be detected.
log_message "Power failure detected. Waiting $POWER_FAILURE_WAIT_TIME seconds for restoration before taking action."
sleep $POWER_FAILURE_WAIT_TIME

# Check if power has returned.
UPS_STATUS=$(upsc $UPS_IDENTIFIER ups.status 2>/dev/null || echo "UNKNOWN")
BATTERY_LEVEL=$(upsc $UPS_IDENTIFIER battery.charge 2>/dev/null || echo "0")

if [[ "$SIMULATE_FAILURE" == true ]]; then
	log_message "Simulating power failure. Proceeding with shutdown."
elif [[ "$UPS_STATUS" =~ OL ]]; then
	if [[ "$UPS_STATUS" =~ BOOST && "$BATTERY_LEVEL" -le 20 ]]; then
		log_message "UPS is in BOOST mode with low battery ($BATTERY_LEVEL%). Proceeding with shutdown."
	else
		log_message "Power restored. UPS is online with status: $UPS_STATUS, Battery level: $BATTERY_LEVEL%."
		exit 0
	fi
else
	log_message "UPS status: $UPS_STATUS. Battery level: $BATTERY_LEVEL%. Power NOT restored. Initiating shutdown."
fi

# ==============================
# Process All Running VMs
# ==============================

# Get a list of all running CTs.
RUNNING_CTS=$(pct list | awk 'NR>1 && $2 == "running" {print $1}' | xargs -r)

# Cycle through each running CT.
for CTID in $RUNNING_CTS; do
	log_message "Executing shutdown for CT $CTID."
	pct shutdown $CTID
	sleep $VM_ACTION_DELAY
done

# Get a list of all running VMs.
RUNNING_VMS=$(qm list | awk '$3 == "running" {print $1}' | xargs -r)
VM_COUNT=$(qm list | awk '$3 == "running" {print $1}' | xargs -r | wc -w)

# Cycle through each running VM.
for VMID in $RUNNING_VMS; do
	# Determine the action for this VM.
	ACTION="${VM_ACTIONS[$VMID]:-$DEFAULT_ACTION}"

	# Log and execute the action.
	log_message "Executing $ACTION for VM $VMID."

	if [[ "$ACTION" == "hibernate" ]]; then
		qm suspend $VMID --todisk 1
	else
		qm shutdown $VMID --skiplock 1
	fi

	# Wait for the specified delay time before processing the next VM.
	sleep $VM_ACTION_DELAY
done

# ==============================
# Check for Running VMs Before Host Shutdown
# ==============================

# Wait for VMs to shut down gracefully, then force stop any remaining VMs.
log_message "Waiting for VMs to shut down. Checking again in $VM_SHUTDOWN_TIMEOUT seconds."
sleep $VM_SHUTDOWN_TIMEOUT

# Force shutdown remaining CTs.
RUNNING_CTS=$(pct list | awk 'NR>1 && $2 == "running" {print $1}' | xargs -r)
for CTID in $RUNNING_CTS; do
	if [[ $(pct status "$CTID") =~ running ]]; then
		log_message "CT $CTID did not shut down cleanly. Forcing stop."
		pct stop $CTID --skiplock 1
		sleep $VM_ACTION_DELAY
	fi
done

# Force shutdown remaining VMs.
RUNNING_VMS=$(qm list | awk '$3 == "running" {print $1}' | xargs -r)
for VMID in $RUNNING_VMS; do
	if [[ $(qm status "$VMID") =~ running ]]; then
		log_message "VM $VMID did not shut down cleanly. Forcing stop."
		qm stop $VMID --skiplock 1
		sleep $VM_ACTION_DELAY
	fi
done

# ==============================
# Shutdown the Host Machine
# ==============================

log_message "All VMs have been shut down. Proceeding with host shutdown."
sleep 5

if [[ "$DRY_RUN" == true ]]; then
	log_message "Dry run enabled. Shutdown skipped."
else
	shutdown -h now "Power failure detected. System shutting down."
fi
