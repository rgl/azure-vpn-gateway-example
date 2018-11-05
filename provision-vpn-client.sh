#!/bin/bash
set -eux

result="$(az network vnet-gateway vpn-client generate \
    --resource-group rgl-vpn-gateway-example \
    --name gateway \
    --processor-architecture amd64 \
    --output table)"
client_url="$(echo $result | grep https:// | sed -E 's,.*(https://.+),\1,g')"
wget -qO shared/vpn-client.zip "$client_url"
unzip -t shared/vpn-client.zip
