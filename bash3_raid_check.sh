#!/bin/bash
#===============================================================================
#
#          FILE: raid_check.sh
#
#         USAGE: ./raid_check.sh
#
#   DESCRIPTION:
#
#       OPTIONS: RAID_STATUS CTRL_STATUS GET_TMP_REPORT
#  REQUIREMENTS: hpacucli MegaCli StorMan mpt-status sas2ircu
#          BUGS: ---
#         NOTES: ---
#        AUTHOR: Ivan Polonevich (ivan.polonevich@gmail.com),
#  ORGANIZATION: CTCO
#       CREATED: 02/05/2015 10:28
#      REVISION: 003
#===============================================================================

#set -x # uncomment for debug

set -o nounset
shopt -s expand_aliases
trap "exit 1" TERM
cd `dirname $0`

if [ $# -ne 1 ]
then
  echo "Usage: $0 RAID_STATUS or CTRL_STATUS or GET_TMP_REPORT"
  exit
fi

pidscr=$$
PARAM="$1"

OK="0"
NOT_OK="1"
lst_bin_to_check=(lspci grep mv awk date ls mktemp cat wc cut sort head pgrep)
OS=$(uname)

checkb() {
  local bin=$1
  [[ -f $(which ${bin}) ]] >/dev/null 2>&1 || \
    { echo "Please install ${bin}"; exit $NOT_OK ;};
}

case "$OS" in
  SunOS )
    alias awk=gawk
    alias sed=gsed
    alias grep=ggrep
    alias lspci='sudo scanpci'
    export PATH=$PATH:/opt/hp/sbin/
    ;;
  Darwin )
    alias lspci='ioreg'
    ;;
  Linux )
    for inp in "${lst_bin_to_check[@]}";do
      checkb "$inp";
      alias $inp=$(type -p ${inp})
    done
    ;;
esac

hp_smart_array=$(lspci | grep "Smart Array")
[[ -f /proc/mdstat ]] && mdraid=$( grep ^md /proc/mdstat) || mdraid=""
accraid=$(lspci | grep "Adaptec AAC-RAID")
megaraid=$(lspci | grep "MegaRAID")
mpt=$(lspci | grep -Ei "raid|SCSI" | grep "MPT" | \
    grep -v "Symbios Loggic SAS2004")
mptsas=$(lspci | grep -Ei "raid|SCSI" | grep "Symbios Logic SAS2004")
manufacture=(hp_smart_array mdraid accraid megaraid mpt mptsas)

initvars() {
  raid_status=$OK;
  ctrl_status=$OK;
}
check_status() {
  local ST=$1
  local ST_OK=$2
  [[ "$ST" != "$ST_OK" ]] && echo $NOT_OK || echo $OK;
}
create_tmp() {
  local -a tmp_vars=($@)
  local STATUS_FILE=${tmp_vars[0]}
  if [ -f "$STATUS_FILE" ]; then
    local COMMAND_ST=${tmp_vars[@]:1:${#tmp_vars[*]}}
    local TIME_FILE=$(ls -l --time-style="+%s" "$STATUS_FILE"| awk '{print $6}')
    local TIME_NOW=$(date "+%s")
    local TIME_DIF="$TIME_NOW - $TIME_FILE"
    echo  $TIME_DIF | bc

    ( { [[ ! $(pgrep -fx "$COMMAND_ST") ]] && \
      local TMPFILE=$(mktemp ${STATUS_FILE}.XXXXX); \
      eval $COMMAND_ST > $TMPFILE; \
      mv -f $TMPFILE $STATUS_FILE;} > /dev/null 2>&1 &);

  else
    touch $STATUS_FILE
    echo $?
  fi
}
check_manufacture() {
  local -a list_controllers=()
  for controller in "${manufacture[@]}"; do
    [[ -n $(eval echo \${$controller}) ]] && list_controllers+=($controller)
  done
  [[ 0 -eq ${#list_controllers[*]} ]] && \
    echo "Cann't find any controllers" >&2 || echo ${list_controllers[@]}
}

get_var_hp_smart_array() {
  local types=$1
  local -a raid_vars=()
  local -a ctrl_vars=()
  checkb "hpacucli"
  raid_vars[0]="/tmp/hpraid.tmp"
  if [[ -f "${raid_vars[0]}" ]]; then
    raid_vars[1]=$(grep -v "Note:" "${raid_vars[0]}" | \
      grep -iE \
      "fail|error|offline|rebuild|ignoring|degraded|skipping|nok|predictive" | \
      wc -l);
  else
    raid_vars[1]=$(create_tmp "${raid_vars[0]}")
  fi
  raid_vars[2]="0"
  raid_vars[3]="INFOMGR_BYPASS_NONSA=1 hpacucli ctrl all show config"

  ctrl_vars[0]="/tmp/hpctrl.tmp"
  if [[ -f "${ctrl_vars[0]}" ]]; then
    ctrl_vars[1]=$(grep "Controller Status:" "${ctrl_vars[0]}" | \
    grep -iv "ok" |wc -l);
  else
    ctrl_vars[1]=$(create_tmp "${ctrl_vars[0]}")
  fi
  ctrl_vars[2]="0"
  ctrl_vars[3]="INFOMGR_BYPASS_NONSA=1 hpacucli ctrl all show status"
  eval echo \${${types}_vars[@]}
}
get_var_mdraid() {
  local types=$1
  local -a raid_vars=()
  local -a ctrl_vars=()
  tmp_t=($(cat /proc/mdstat | grep md |  awk '{print $1}'))
  raid_vars[0]="/tmp/mdraid.tmp"
  if [[ -f "${raid_vars[0]}" ]]; then
    raid_vars[1]=$(cat "${raid_vars[0]}" | grep -iE "degraded" | wc -l)
  else
    raid_vars[1]=$(create_tmp "${raid_vars[0]}")
  fi
  raid_vars[2]="0"
  raid_vars[3]="mdadm --detail $(ls /dev/md* | grep md| grep -v :)"

  ctrl_vars[0]="${raid_vars[0]}"
  if [[ -f "${ctrl_vars[0]}" ]]; then
    ctrl_vars[1]="0"
  else
    ctrl_vars[1]=$(create_tmp "${ctrl_vars[0]}")
  fi
  ctrl_vars[2]="0"
  ctrl_vars[3]="${raid_vars[3]}"
  eval echo \${${types}_vars[@]}
}
get_var_accraid() {
  local types=$1
  local -a raid_vars=()
  local -a ctrl_vars=()
  checkb "/usr/StorMan/arcconf"
  raid_vars[0]="/tmp/aacraid.tmp"
  if [[ -f "${raid_vars[0]}" ]]; then
    raid_vars[1]=$(grep "Status of logical device" "${raid_vars[0]}" | \
    cut -d : -f 2| grep -cvi "Optimal")
  else
    raid_vars[1]=$(create_tmp "${raid_vars[0]}")
  fi
  raid_vars[2]="0"
  raid_vars[3]="/usr/StorMan/arcconf getconfig 1"

  ctrl_vars[0]="${raid_vars[0]}"
  if [[ -f "${ctrl_vars[0]}" ]]; then
    ctrl_vars[1]=$(grep "Controller Status" "${ctrl_vars[0]}" | \
    cut -d : -f 2| grep -civ "Optimal")
  else
    ctrl_vars[1]=$(create_tmp "${ctrl_vars[0]}")
  fi
  ctrl_vars[2]="0"
  ctrl_vars[3]="${raid_vars[3]}"
  eval echo \${${types}_vars[@]}
}
get_var_megaraid() {
  local types=$1
  local -a raid_vars=()
  local -a ctrl_vars=()
  checkb "/opt/MegaRAID/MegaCli/MegaCli64"
  raid_vars[0]="/tmp/megaraid.tmp"
  if [[ -f "${raid_vars[0]}" ]]; then
    raid_vars[1]=$(grep -Ei 'State|Permission' "${raid_vars[0]}" | \
    cut -d : -f2 | cut -d" " -f2| uniq| grep -civ "Optimal")
  else
    raid_vars[1]=$(create_tmp "${raid_vars[0]}")
  fi
  raid_vars[2]="0"
  raid_vars[3]="/opt/MegaRAID/MegaCli/MegaCli64 -LDInfo -Lall -aALL"

  ctrl_vars[0]="/tmp/megactrl.tmp"
  if [[ -f "${ctrl_vars[0]}" ]]; then
    ctrl_vars[1]=$(grep -i "Status" "${ctrl_vars[0]}" | \
    cut -d : -f 2 | grep -Eiv "normal|ok|Not" | cut -d" " -f2 | wc -l)
  else
    ctrl_vars[1]=$(create_tmp "${ctrl_vars[0]}")
  fi
  ctrl_vars[2]="0"
  ctrl_vars[3]="/opt/MegaRAID/MegaCli/MegaCli64 -EncInfo -aAll"
  eval echo \${${types}_vars[@]}
}
get_var_mpt() {
  local types=$1
  local -a raid_vars=()
  local -a ctrl_vars=()
  checkb "/usr/sbin/mpt-status"
  raid_vars[0]="/tmp/mptraid.tmp"
  if [[ -f "${raid_vars[0]}" ]]; then
    raid_vars[1]=$(grep -i "vol_id" "${raid_vars[0]}" | \
    cut -d" " -f 2 | grep -civ "OPTIMAL")
  else
    raid_vars[1]=$(create_tmp "${raid_vars[0]}")
  fi
  raid_vars[2]="0"
  raid_vars[3]="/usr/sbin/mpt-status -ns"

  ctrl_vars[0]="${raid_vars[0]}"
  if [[ -f "${ctrl_vars[0]}" ]]; then
    ctrl_vars[1]=$(grep -i "scsi_id" "${ctrl_vars[0]}" | grep -cv "100%")
  else
    ctrl_vars[1]=$(create_tmp "${ctrl_vars[0]}")
  fi
  ctrl_vars[2]="0"
  ctrl_vars[3]="${raid_vars[3]}"
  eval echo \${${types}_vars[@]}
}
get_var_mptsas() {
  local types=$1
  local -a raid_vars=()
  local -a ctrl_vars=()
  checkb "/usr/sbin/sas2ircu"
  raid_vars[0]="/tmp/mptsasraid.tmp"
  if [[ -f "${raid_vars[0]}" ]]; then
    raid_vars[1]=$(cat "${raid_vars[0]}" | \
    awk '{if ($0 ~ "Volume state") print $4}'| grep -icv "Optimal")
  else
    raid_vars[1]=$(create_tmp "${raid_vars[0]}")
  fi
  raid_vars[2]="0"
  raid_vars[3]="/usr/sbin/sas2ircu 0 STATUS"

  ctrl_vars[0]="/tmp/mptsasctrl.tmp"
  if [[ -f "${ctrl_vars[0]}" ]]; then
    ctrl_vars[1]=$(cat "${ctrl_vars[0]}" | \
    awk '{if ($0 ~ "Volume status") print $4}'| grep -icv "Enabled")
  else
    ctrl_vars[1]=$(create_tmp "${ctrl_vars[0]}")
  fi
  ctrl_vars[2]="0"
  ctrl_vars[3]="/usr/sbin/sas2ircu 0 DISPLAY"
  eval echo \${${types}_vars[@]}
}
tmp() {
  local -a ST=(raid ctrl)
  local -a listctrl=($(check_manufacture))
  [[ 0 -eq ${#listctrl[*]} ]] &&  kill -s TRAP $$; exit 1;
  local -a vars_to_check=()
  local -a timetpm=()
  for n in "${ST[@]}";do
    for manuf in "${listctrl[@]}";do
      vars_to_check=($(get_var_${manuf} "$n"))
      count_el_array=${#vars_to_check[*]}
      timetmp+=($(create_tmp "${vars_to_check[0]}" \
                "${vars_to_check[@]:3:${count_el_array}}"))
    done
  done
  for timein in "${!timetmp[@]}";do
    echo "${timetmp[$timein]}";
  done | sort -nr | head -1
}
get_status() {
  local ST=$1
  local STS="0"
  local -a listctrl=($(check_manufacture))
  [[ 0 -eq ${#listctrl[*]} ]] && kill -s TRAP $$; exit 1;
  local -a vars_to_check=()
  for manf in "${listctrl[@]}";do
    vars_to_check=($(get_var_${manf} "$ST"))
    STS=$(($STS + $(check_status "${vars_to_check[1]}" "${vars_to_check[2]}")))
  done
  echo $STS
}

case "$PARAM" in
  GET_TMP_REPORT )
    initvars
    echo $(tmp)
    ;;

  RAID_STATUS )
    initvars
    echo $(get_status raid)
    ;;

  CTRL_STATUS )
    initvars
    echo $(get_status ctrl)
    ;;

  *)
    echo "Unknown argument: $PARAM "
    exit 1
    ;;
esac

exit 0
