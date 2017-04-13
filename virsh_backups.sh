#!/bin/bash

folder="/var/lib/libvirt/images/xml/current" && if [[ ! -d "$folder" ]]; then mkdir $folder; fi
archive="/var/lib/libvirt/images/xml/archives" && if [[ ! -d "$archive" ]]; then mkdir $archive; fi
VMs=(`virsh list --all | awk '{ print $2 }' | sed -r 's/^Name$//g' | sed '/^$/d' | tr '\n' ' '`)

for guest in "${VMs[@]}"; do
  if [[ ! -e "$folder/$guest.xml" ]]; then
    virsh dumpxml $guest > $folder/$guest.xml
  else
    existing=$(md5sum $folder/$guest.xml | awk '{ print $1 }')
    if [[ `virsh dumpxml $guest | md5sum | cut -b-32` != "$existing" ]]; then
      migrate=`ls -l $folder/$guest.xml | awk '{ print $9"_"$6$7$8 }' | sed 's/://g'`
      mv $folder/$guest.xml $archive/$migrate && virsh dumpxml $guest > $folder/$guest.xml
    fi
  fi
done
