#!/bin/bash

log_file="/var/log/syslog" # Specify the path to your syslog file
p2p_count=0
torrent_count=0
declare -A torrent_client_ports=( ["BitTorrent"]="6881 6882 6883 6884 6885 6886 6887 6888 6889 6890" ["uTorrent"]="49152 49153 49154 49155 49156 49157 49158 49159 49160 49161" ["Deluge"]="53160 53161 53162 53163 53164 53165 53166 53167 53168 53169" )
trackers_url="https://raw.githubusercontent.com/ngosang/trackerslist/master/trackers_all.txt"
declare -a offending_ips=()
declare -a offending_macs=()

# Download the list of known torrent trackers
wget -q -O - "$trackers_url" | grep -v "^#" > trackers.txt

# Loop through each line in the syslog file that contains "Fortigate"
while read -r line
do
  if [[ "$line" == *"Fortigate"* ]]; then
    # Extract the relevant fields from the log line
    date=$(echo "$line" | cut -d " " -f 1)
    time=$(echo "$line" | cut -d " " -f 2)
    source_ip=$(echo "$line" | awk '{print $4}' | cut -d "=" -f 2)
    destination_ip=$(echo "$line" | awk '{print $6}' | cut -d "=" -f 2)
    protocol=$(echo "$line" | awk '{print $8}' | cut -d "=" -f 2)
    action=$(echo "$line" | awk '{print $9}' | cut -d "=" -f 2)
    # Parse the MAC address from the log line
    mac=$(echo "$line" | grep -oE "srcmac=[^ ]+" | cut -d "=" -f 2)

    # Check for P2P traffic
    if [[ "$protocol" == "TCP" && "$action" == "allow" ]]; then
      if [[ "$destination_ip" =~ ^(.*):6881$ ]]; then
        # P2P traffic detected
        p2p_count=$((p2p_count+1))
        echo "P2P traffic detected from $source_ip ($mac) to $destination_ip at $date $time"
      fi
    fi

    # Check for torrent traffic
    if [[ "$protocol" == "TCP" && "$action" == "allow" ]]; then
      for client in "${!torrent_client_ports[@]}"; do
        for port in ${torrent_client_ports["$client"]}; do
          if [[ "$destination_ip" =~ ^(.*):$port$ ]]; then
            # Torrent traffic detected
            torrent_count=$((torrent_count+1))
            echo "Torrent traffic detected from $source_ip ($mac) to $destination_ip using $client client at $date $time"
            # Add offending IP and MAC to arrays
            offending_ips+=("$source_ip")
            offending_macs+=("$mac")
          fi
        done
      done
      while read -r tracker; do
        if [[ "$destination_ip" == "$tracker" ]]; then
          # Known torrent tracker site detected
          echo "Known torrent tracker site $tracker detected from $source_ip ($mac) at $date $time"
   fi
    done < "trackers.txt"
  fi
fi
fi
done < "$log_file"

#Output the total counts of P2P and torrent traffic detected
echo "Total P2P traffic detected: $p2p_count"
echo "Total torrent traffic detected: $torrent_count"

#Output the list of offending IP and MAC addresses
if [ ${#offending_ips[@]} -gt 0 ]; then
echo "The following IP and MAC addresses were detected using torrent traffic:"
for (( i=0; i<${#offending_ips[@]}; i++ )); do
echo "${offending_ips[$i]} (${offending_macs[$i]})"
done
fi

#Remove the list of known torrent trackers
rm trackers.txt
