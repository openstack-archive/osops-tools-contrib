# Display all floating IPs of allocated istances with HEAT from Output
heat stack-list | awk '{ print $4 }' | tail -n+3 | xargs -L1 heat output-show -a | grep '"addr"'
