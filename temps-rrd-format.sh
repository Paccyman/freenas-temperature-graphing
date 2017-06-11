#!/usr/local/bin/bash
#####
# This script gathers and outputs the CPU and drive
# temperatures in a format rrdtool can consume.
#
# Author: Seren Thompson
# Date: 2017-04-24
# Website: https://github.com/seren/freenas-temperature-graphing
#####

# # display expanded values
# set -o xtrace
# quit on errors
set -o errexit
# error on unset variables
set -o nounset


# Helpful usage message
func_usage () {
  echo ' This script gathers and outputs the CPU and drive
temperatures in a format rrdtool can consume.

Usage $0 [-v] [-d] [-h]

-v | --verbose  Enables verbose output
-d | --debug    Outputs each line of the script as it executes (turns on xtrace)
-h | --help     Displays this message

Options for ESXi:
--platform "esxi"                  Indicates that we will use ESXi tools to retrieve CPU temps
--ipmitool_username <USERNAME>     Required: Username to use when connecting to BMC
--ipmitool_address  <BMC_ADDRESS>  Required: BMC ip address to connect to

'
}


# Process command line args
origargs="$@"
args=''
help=
verbose=
debug=
PLATFORM=default
while [ $# -gt 0 ]; do
  case $1 in
    -h|--help)  help=1;                     shift 1 ;;
    -v|--verbose) verbose=1;                shift 1 ;;
    -d|--debug) debug=1;                    shift 1 ;;
    --platform) PLATFORM=$2;                shift 2 ;;
    --ipmitool_username) USERNAME=$2;       shift 2 ;;
    --ipmitool_address) BMC_ADDRESS=$2;     shift 2 ;;
    -*)         echo "$0: Unrecognized option: $1 (try --help)" >&2; exit 1 ;;
    *)          shift 1; break ;;
  esac
done

if [ -n "$debug" ]; then
  set -o xtrace
  verbose=1
fi

[ -n "$verbose" ] && set -o xtrace

[ -n "$help" ] && func_usage && exit 0

case "${PLATFORM}" in
  esxi)
    [ -n "$verbose" ] && echo "Platform is set to '${PLATFORM}'. Username is '${USERNAME} and ip is '${BMC_ADDRESS}'"
    [ -z "$USERNAME" ] && echo "You need to to provide --ipmitool_username with an argument" && exit 1
    [ -z "$BMC_ADDRESS" ] && echo "You need to to provide --ipmitool_address with an argument" && exit 1
    args="${args} --platform ${PLATFORM} --ipmitool_username ${USERNAME} --ipmitool_address ${BMC_ADDRESS}"
    ;;
esac

# Check we're root
if [ "$(id -u)" != "0" ]; then
  echo "Error: this script needs to be run as root (for smartctl). Try 'sudo $0 $1'"
  exit 1
fi

sep=':'

# Get CPU ids
numcpus=$(/sbin/sysctl -n hw.ncpu)
# Get drive device names
drivedevs=
for i in $(/sbin/sysctl -n kern.disks | awk '{for (i=NF; i!=0 ; i--) if(match($i, '/da/')) print $i }' ); do
  drivedevs="${drivedevs} ${i}"
done
[ -n "$verbose" ] && echo "numcpus: ${numcpus}"
[ -n "$verbose" ] && echo "drivedevs: ${drivedevs}"

# Get CPU temperatures
data=
for (( i=0; i < ${numcpus}; i++ )); do
  case "${PLATFORM}" in
    esxi)
      [ -n "$verbose" ] && echo "Platform is set to '${PLATFORM}'. Attempting to retrieve CPU$((i+1)) temperatures using ipmitool with username '${USERNAME} and ip ${BMC_ADDRESS}..."
      t=`ipmitool -I lanplus -H ${BMC_ADDRESS} -U ${USERNAME} -f /root/.ipmi sdr elist | sed -Ene 's/^CPU[^ ]+ +Temp +\| +([^.]+).*/\1/p' | sed -n "$((i+1))p"`
      ;;
    *)
      t=`/sbin/sysctl -n dev.cpu.$i.temperature`
  esac
  data=${data}${sep}${t%.*}  # Append the temperature to the data string, removing anything after the decimal
done


# Get drive temperatures
for i in ${drivedevs}; do
  DevTemp=`/usr/local/sbin/smartctl -a /dev/$i | grep '194 *Temperature_Celsius' | awk '{print $10}'`;
  if ! [[ "$DevTemp" == "" ]]; then
    data="${data}${sep}${DevTemp}"
  fi
done
[ -n "$verbose" ] && echo "Raw data: ${data}"

# Strip any leading, trailing, or duplicate colons
[ -n "$verbose" ] && echo "Cleaned up data:"
echo "${data}" | sed 's/:::*/:/;s/^://;s/:$//'

[ -n "$verbose" ] && echo "Done gathering temp data returning"
