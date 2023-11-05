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
# rpc_url example: 
# https://polygonzkevm-mainnet.g.alchemy.com/v2/{ALCHEMY_API_KEY}
if grep -q "$map_key" "$file"; then
    sed -i '' "s/$map_key/$map_key\n$new_optimizer_runs\n$new_solc_version/" "$file"
    echo "Apply optimizer_runs and solc_version successful."
else
    echo "Search string '\[profile.default\]' not found in the file."
fi

forge script src/script/MainnetDeployPart1.s.sol:MainnetDeployScriptPart1 --rpc-url $rpc_url --broadcast --use $solc_version --optimizer-runs $optimizer_runs -vvvv >> log
# forge script src/script/MainnetDeployPart2.s.sol:MainnetDeployScriptPart2 --rpc-url $rpc_url --broadcast --use $solc_version --optimizer-runs $optimizer_runs -vvvv >> log

start=false
while read line; do

    if [ "$line" = "{" ]; then
        start=true
    fi 
    if [ "$start" = true ]; then
        echo "$line" >> config.json
    fi
    if [ "$line" = "}" ]; then
        echo "}" >> config.json
        break
    fi
    
done < log