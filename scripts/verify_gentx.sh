#!/bin/bash
FLIX_HOME="/tmp/omniflixhub$(date +%s)"
RANDOM_KEY="random-validator-key"
CHAIN_ID=omniflixhub-1
VERSION=v0.4.0


GENTX_SUBMISSION_START=$(date -u -d '2022-02-19T00:00:00.000Z' +'%s')
GENTX_SUBMISSION_DEADLINE=$(date -u -d '2022-02-21T11:00:00.000Z' +'%s')

now=$(date -u +'%s')

declare -i maxbond=10000000
maxcommission="0.1"
mincommission="0.05"
if [ $now -lt $GENTX_SUBMISSION_START ]; then
    echo 'Gentx submission not started yet'
    exit 1
fi

if [ $now -gt $GENTX_SUBMISSION_DEADLINE ]; then
    echo 'Gentx submission is closed'
    exit 1
fi
GENTX_FILE=$(find ./$CHAIN_ID/gentxs -iname "*.json")
FILES_COUNT=$(find ./$CHAIN_ID/gentxs -iname "*.json" | wc -l)
LEN_GENTX=$(echo ${#GENTX_FILE})

if [ $FILES_COUNT -gt 1 ]; then
    echo 'Invalid! found more than 1 json file'
    exit 1
fi

if [ $LEN_GENTX -eq 0 ]; then
    echo "gentx file not found."
    exit 1
else
    set -e

    echo "GentxFile::::"
    echo $GENTX_FILE

    denom=$(jq -r '.body.messages[0].value.denom' $GENTX_FILE)
    if [ $denom != "uflix" ]; then
        echo "invalid denom"
        exit 1
    fi

    amount=$(jq -r '.body.messages[0].value.amount' $GENTX_FILE)

    if [ $amount -gt $maxbond ]; then
        echo "bonded amount is too high: $amt > $maxbond"
        exit 1
    fi

    commission=$(jq -r '.body.messages[0].commission.rate' $GENTX_FILE)
    out=$(echo "$commission > $maxcommission" | bc -q)
    if [ $out = 1 ]; then
        echo "commission is high: $commission > $maxcommission"
        exit 1
    fi
    out2=$(echo "$commission < $mincommission" | bc -q)
    if [ $out2 = 1  ]; then
        echo "commission is low: $commission < $mincommission"
        exit 1
    fi
    echo "...........Init omniflixhub.............."

    wget -q https://github.com/OmniFlix/omniflixhub/releases/download/$VERSION/omniflixhubd -O omniflixhubd
    chmod +x omniflixhubd
    
    ./omniflixhubd keys add $RANDOM_KEY --home $FLIX_HOME --keyring-backend test

    ./omniflixhubd init --chain-id $CHAIN_ID validator --home $FLIX_HOME

    echo "..........Updating genesis......."
    sed -i "s/\"stake\"/\"uflix\"/g" $FLIX_HOME/config/genesis.json

    GENACC=$(jq -r '.body.messages[0].delegator_address' $GENTX_FILE)

    echo $GENACC

    ./omniflixhubd add-genesis-account $RANDOM_KEY 10000000uflix --home $FLIX_HOME --keyring-backend test
    ./omniflixhubd add-genesis-account $GENACC 10000000uflix --home $FLIX_HOME

    ./omniflixhubd gentx $RANDOM_KEY 5000000uflix --home $FLIX_HOME \
         --keyring-backend test --chain-id $CHAIN_ID
    cp $GENTX_FILE $FLIX_HOME/config/gentx/

    echo "..........Collecting gentxs......."
    ./omniflixhubd collect-gentxs --home $FLIX_HOME
    sed -i '/persistent_peers =/c\persistent_peers = ""' $FLIX_HOME/config/config.toml

    ./omniflixhubd validate-genesis --home $FLIX_HOME

    echo "..........Starting node......."
    ./omniflixhubd start --home $FLIX_HOME &

    sleep 5s

    echo "...checking network status.."

    ./omniflixhubd status --node http://localhost:26657 | jq

    echo "...Cleaning ..."
    killall omniflixhubd >/dev/null 2>&1
    rm -rf $FLIX_HOME >/dev/null 2>&1
fi
