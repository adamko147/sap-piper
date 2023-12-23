#!/usr/bin/env bash

set -e

if [[ "$PIPER_kubeConfig" != "" ]]; then
    echo "kubeconfig $PIPER_kubeConfig from env PIPER_kubeConfig"
    export KUBECONFIG="$PIPER_kubeConfig"
fi

VALUES="cluster.yaml"

ZONES=$(kubectl get nodes -o jsonpath='{.items[*].metadata.labels.topology\.kubernetes\.io/zone}')
ZONES=$(for i in ${ZONES[@]}; do echo $i; done | sort -u)

EGRESS_IPS=()

for zone in $ZONES; do
    echo -n "getting egress ip for zone $zone... "
    OVERRIDES="{\"apiVersion\": \"v1\", \"metadata\": {\"labels\": {\"sidecar.istio.io/inject\": \"false\"}},\"spec\": {\"nodeSelector\": {\"topology.kubernetes.io/zone\": \"$zone\"}}}"
    kubectl delete pod "busybox-$zone" --ignore-not-found &> /dev/null
    addr=$(kubectl run --tty -it "busybox-$zone" --image=curlimages/curl --restart=Never --overrides="$OVERRIDES" --command -- curl http://ifconfig.me/ip 2> /dev/null)
    echo "$addr"
    EGRESS_IPS+=($addr)
    kubectl delete pod "busybox-$zone" --ignore-not-found &> /dev/null
done

EGRESS_IPS=($(echo ${EGRESS_IPS[*]} | tr ' ' '\n' | sort -u))
EGRESS_IPS=$(echo -n ${EGRESS_IPS[*]} | tr ' ' ',')

if ! which yq &> /dev/null ; then
    YQ=$(mktemp)
    PLATFORM=$(uname -o | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m | sed 's/aarch64/arm64/' | sed 's/x86_64/amd64/')
    echo "downloading yq_${PLATFORM}_${ARCH} to $YQ..."
    curl -L -s --output $YQ https://github.com/mikefarah/yq/releases/latest/download/yq_${PLATFORM}_${ARCH}
    chmod +x $YQ
else
    YQ=yq
fi

echo -n "getting kyma domain... "
DOMAIN=$($YQ -r '. as $root | $root.current-context as $cc | $root.contexts[] | select(.name==$cc) | .context.cluster as $cluster | $root.clusters[] | select(.name==$cluster) | .cluster.server | sub("^http(s)://", "") | sub("^api\.", "")' $KUBECONFIG)
echo $DOMAIN

cat <<EOF > $VALUES
kymaDomain: "$DOMAIN"
kymaEgressIps: "$EGRESS_IPS"
EOF
echo
echo "Saved to $VALUES"
echo
cat $VALUES
echo
echo "PWD: $(pwd)"
echo "ls -la"
ls -la
