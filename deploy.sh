#!/bin/sh

read -p "Please enter Solidity compile version:" solc_version
read -p "Please enter Solidity optimizer runs:" optimizer_runs
read -p "Please enter deploy rpc url:" rpc_url

file="foundry.toml"       
map_key="\[profile.default\]"  
new_solc_version="solc_version = '$solc_version'" 
new_optimizer_runs="optimizer_runs = $optimizer_runs"

# search for optimizer_runs and delete it
if grep -q "optimizer_runs" "$file"; then
    sed -i '' '/optimizer_runs/d' "$file"
else
    echo "Search string 'optimizer_runs' not found in the file."
fi

# search for solc_version and delete it
if grep -q "solc_version" "$file"; then
    sed -i '' '/solc_version/d' "$file"
else
    echo "Search string 'solc_version' not found in the file."
fi

# Apply new optimizer_runs and solc_version
if grep -q "$map_key" "$file"; then
    sed -i '' "s/$map_key/$map_key\n$new_optimizer_runs\n$new_solc_version/" "$file"
    echo "Apply optimizer_runs and solc_version successful."
else
    echo "Search string '\[profile.default\]' not found in the file."
fi

forge script src/script/MainnetDeploy.s.sol:MainnetDeployScript --rpc-url $rpc_url --broadcast --use $solc_version --optimizer-runs $optimizer_runs -vvvv >> log

i=1
start=0
while read line; do
    if [ "$line" = "{" ]; then
        start=$(( start + 1 ))
    fi
    if [ "$start" -eq 1 ]; then
        echo "$line" >> config.json
    fi
    if [ "$line" = "}" ]; then
        echo "}" >> config.json
        break
    fi
    i=$(( i + 1 ))
done < log