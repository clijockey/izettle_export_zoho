#!/usr/bin/env bash

# use set -e instead of #!/bin/bash -e in case we're
# called with `bash ~/bin/scriptname`
set -e # bail out early if any command fails
set -u # fail if we hit unset variables
set -o pipefail # fail if any component of any pipe fails


############
## Functions

penceToPound(){
    local convert
    convert=$(bc <<< "scale=2; ${1}/100")
    echo "${convert}"
    # return ${convert}
}

echo "Payment Number,Customer Name,Date,Mode,Exchange Rate,Amount,Description,Bank Charges,Invoice Number,Invoice Amount,Withholding Tax Amount"

# startDate="2018-05-01"
# endDate="2018-05-31"
currentDate=$(date -j -f "%Y-%m-%d" "${1}" "+%s")
endDate=$(date -j -f "%Y-%m-%d" "${2}" "+%s")
offset=86400

# Get the token and use vars set in env
token=$(curl --silent -d "grant_type=password&client_id=${IZETTLE_CLIENT_ID}&client_secret=${IZETTLE_CLIENT_SECRET}&username=${IZETTLE_USERNAME}&password=${IZETTLE_PASSWORD}" -H 'Content-Type: application/x-www-form-urlencoded' "https://oauth.izettle.net/token" | jq -r .access_token)

while [ "${currentDate}" -le "${endDate}" ] 
# while [ "$dateTs" -le "$eDateTs" ]
do
    date=$(date -j -f "%s" ${currentDate} "+%Y-%m-%d")
    currentDate=$((${currentDate}+${offset}))
    dateNext=$(date -j -f "%s" ${currentDate} "+%Y-%m-%d")
   
    amountPreliminary=$(curl --silent "https://finance.izettle.com/organizations/34a5f270-7ec4-11e7-8545-112b899ccf62/accounts/PRELIMINARY/transactions?includeTransactionType=CARD_PAYMENT_FEE&start=${date}&end=${dateNext}" -H "Authorization: Bearer ${token}" | jq -r -c '.data[].amount')

    amountLiquid=$(curl --silent "https://finance.izettle.com/organizations/34a5f270-7ec4-11e7-8545-112b899ccf62/accounts/LIQUID/transactions?includeTransactionType=CARD_PAYMENT_FEE&start=${date}&end=${dateNext}" -H "Authorization: Bearer ${token}" | jq -r -c '.data[].amount')

    totalPrelim=0
    totalLiquid=0
    for p in ${amountPreliminary}
    do
        totalPrelim=$(expr "${totalPrelim}" + "${p}")
    done || exit 1

    for l in ${amountLiquid}
    do
        totalLiquid=$(expr "${totalLiquid}" + "${l}")
    done || exit 1

    fee=$(penceToPound `expr "${totalPrelim}" + "${totalLiquid}"`)


    ## Purchase Transactions

    purchases=$(curl --silent "https://purchase.izettle.com/purchases/v2?startDate=${date}&endDate=${dateNext}" -H "Authorization: Bearer ${token}" | jq -r -c '.purchases[]' | sed -e 's/ /_/g')

    # echo $purchases

    totalCardPayment=0
    totalCashPayment=0
    for purchase in ${purchases}
    do
        payments=$(echo "${purchase}" | jq -r -c '.payments[]')
        # echo $payments
        for payment in ${payments}
        do

            type=$(echo "${payment}" | jq -r '.type')
            if [[ "${type}" == "IZETTLE_CARD" ]];
                then
                    cardAmount=$(echo "${payment}" | jq -r '.amount')
                    totalCardPayment=$(expr ${totalCardPayment} + "${cardAmount}")
                     # DONT UNDERSTAND WHY NEED TO PUT BELOW IN - FAILS IF NOT IN PLACE!!
                    printf ""
            elif [[ "${type}" == "IZETTLE_CASH" ]];
                then
                    cashAmount=$(echo "${payment}" | jq -r '.amount')
                    totalCashPayment=$(expr ${totalCashPayment} + "${cashAmount}")
                    # DONT UNDERSTAND WHY NEED TO PUT BELOW IN - FAILS IF NOT IN PLACE!!
                    printf ""
            fi
        done || exit 1
    done || exit 1


    # totalPayments=$(penceToPound `expr ${totalCardPayment} + ${totalCashPayment}`)
    totalCardPayment=$(penceToPound "${totalCardPayment}")
    totalCashPayment=$(penceToPound "${totalCashPayment}")
    paymentNumber=${date//-}

    # echo "Payment Number,Customer Name,Date,Mode,Exchange Rate,Amount,Description,Bank Charges,Invoice Number,Invoice Amount,Withholding Tax Amount"
    echo "${paymentNumber}1,No35,${date},Cash,,${totalCashPayment},Cash Payment,,,,"
    echo "${paymentNumber}2,No35,${date},iZettle,,${totalCardPayment},Tide,${fee//-},,,"

done || exit 1

