#!/bin/bash
# DATE: 2017.03.13
# AUTHOR: jw
# VERSION: 2
# USAGE: Easy button solution for migration KVM guests to a new host
# NOTES:
#   - ./vm_relocate [$new_host_server] should be executed on $old_host_server
#   - make sure you carry your key when SSHing to $old_host_server (ssh -A $old_host_server)
#   - aforementioned public key must be in authorized_users for root on $new_host_server
#   - VMs array will not populate with shut off machines, to change this, specify --all flag
#   - /var/lib/libvirt/images/xmls/ path must exist on $new_host_server for XML transfer
#   - /tmp/xml directory is purposely left behind in case something goes awry
#   - /var/lib/libvirt/images/ path must exist on $new_host_server
#   - once complete, you will need to virsh define the XMLs on $new_host_server, then virsh start $guest
#

LOG(){
  echo "$(date +%Y%m%d%H%M%S) $1 $2" >> /var/log/vm_relocate.log
}

if [ "$#" -ne 1 ]; then
  echo "Usage: ./$0 [\$new_host_server]" && exit 2
else
  newhome=$1
  folder="/tmp/xml" && if [[ ! -d "$folder" ]]; then mkdir $folder; fi
  VMs=(`virsh list | awk '{ print $2 }' | grep -Ev '^(Name|)$' | tr '\n' ' '`)
fi

if [[ ${#VMs[@]} -eq 0 ]]; then
  message="No virtual guests on this host! Aborting"
  LOG "[FATAL ]" "$message"; echo $message; exit 2
else
  for guest in "${VMs[@]}"; do
    message="Dumping $guest to $folder"
    LOG "[INFO  ]" "$message"; echo $message
    xml="$folder/$guest.xml"; virsh dumpxml $guest > $xml

    if [ -e $xml ]; then
      message="Moving $xml to $newhome"
      LOG "[INFO  ]" "$message"; echo $message
      scp $xml root@$newhome:/var/lib/libvirt/images/xmls/
    else
      message="$guest XML file does not exist, skipping guest"
      LOG "[DEBUG ]" "$message"; continue
    fi

    message="Discovering qcow file path for $guest"
    LOG "[INFO  ]" "$message"; echo $message
    qcow=$(grep -E 'source file=.+qcow2' $xml | grep -Eoi "file='.+.qcow2'" | cut -d'=' -f2 | tr -d \'\")

    if [ -e $qcow ]; then
      message="$guest disk is located at $qcow"
      LOG "[INFO  ]" "$message" && echo $message
      LOG "[DEBUG ]" "$(ls -alh $qcow)"; moveit=1
    else
      message="$guest qcow path was not successfully extracted!"
      LOG "[ERROR ]" "$message"; echo $message; moveit=0
    fi

    message="Shutting down $guest"
    LOG "[INFO  ]" "$message" && echo $message
    virsh shutdown $guest

    count=0
    while [ $(virsh list --all | grep $guest | grep -Eo 'shut off$' | wc -l) -ne 1 ]; do
      message="Waiting for $guest to reach shut off state"
      LOG "[INFO  ]" $message; echo $message; count=$(($count + 1)); sleep 10
      if [ $count -eq 30 ]; then
        message="$guest did not shutdown within 5 minutes, skipping..."
        LOG "[ERROR ]" "$message"; moveit=0; break
      else
        LOG "[WARN  ]" "$guest has been shutting down for $(($count*10)) seconds"
      fi
    done

    if [ $moveit -eq 1 ]; then
      message="Moving $guest to $newhome"
      LOG "[INFO  ]" "$message" && echo $message
      scp $qcow root@$newhome:/var/lib/libvirt/images/

      message="Undefining $guest!!"
      LOG "[INFO  ]" "$message" && echo $message
      virsh undefine $guest
    else
      message="$guest never reached shut off state"
      LOG "[DEBUG ]" "$message" && echo $message
      message="Proceeding to next virtual guest"
      LOG "[DEBUG ]" "$message" && echo $message
    fi
  done
fi
