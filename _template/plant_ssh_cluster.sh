set -e
connect=$1

if [[ $connect == *@* ]] ; then
  nodehost=${connect#*@}
  user=${connect%@*}
else
  nodehost=$connect
fi

if [[ $nodehost == *:* ]] ; then
  port=${nodehost#*:}
fi

sql() {
    if [ -z "$port" ]; then
        ssh -tq ${connect%:*} mysql -BN -e "'$@'" information_schema | sed 's/\r//'
    else
        ssh -tq ${connect%:*} mysql -BN -e "'$@'" -h127.0.0.1 -P $port information_schema | sed 's/\r//'
    fi
}

echo Examining cluster config...

cluster_name=$(sql 'show variables like "wsrep_cluster_name"')
[[ $cluster_name =~ wsrep_cluster_name(.*) ]] || { >&2 echo "Couldn't read cluster_name" ; exit 1; }
cluster_name=$(echo ${BASH_REMATCH[1]})

echo Name: $cluster_name

cluster_address=$(sql 'show variables like "wsrep_cluster_address"')
[[ $cluster_address =~ .*gcomm://(.+) ]] || { >&2 echo "Couldn't read cluster_address" ; exit 1; }
cluster_nodes=${BASH_REMATCH[1]}

[[ ! -z "$cluster_nodes" ]] || { >&2 echo "Couldn't parse cluster_address" ; exit 1; }

ips=$(sql 'show status like "wsrep_incoming_addresses"')
[[ $ips =~ wsrep_incoming_addresses(.+) ]] || { >&2 echo "Couldn't read incoming_addresses" ; exit 1; }
ips=$(echo ${BASH_REMATCH[1]})

[[ ! -z "$ips" ]] || { >&2 echo "Couldn't parse incoming_addresses" ; exit 1; }

IFS=',' read -ra node_host <<< "$cluster_nodes"
IFS=',' read -ra node_ip <<< "$ips"

echo Trying to match node addresses to hostnames from known_hosts...
echo $ips

mkdir $cluster_name || (echo "Error creating directory {$cluster_name}: $?";  exit 1) >&2

i=0
: > "$cluster_name/nodes.lst"

# try to match ip and hostname in cluster
for ipport in "${node_ip[@]}"; do
    port=${ipport#*:}
    ip=${ipport%:*}
    for node in ${node_host[@]}; do
        match=$(grep -o "$node.*,$ip" ~/.ssh/known_hosts | head -n 1) || :
        if [ ! -z "$match" ] ; then
            break
        fi
    done
    [ ! -z "$match" ] || for node in ${node_host[@]}; do
        match=$(grep -o "${node%%.*}.*,$ip" ~/.ssh/known_hosts | head -n 1) || :
        if [ ! -z "$match" ] ; then
            break
        fi
    done
    if [ ! -z "$match" ]; then
        match=${match%,*}
        echo "Mapped $ip to $match"
        node=$match
    else
        node=${ipport#:3306}
        echo "Can't identify hostname for {$ipport} from wsrep_cluster_address, will use ip address instead {$node}"
    fi

    echo $node >> "$cluster_name/nodes.lst"
    mkdir $cluster_name/$node
    for filename in _template/ssh/node/* ; do
      xtra=""
      [ "${port:-3306}" == 3306 ] || xtra="-h 127.0.0.1 -P $port"
      __host=${node%:*}
      [ -z "$user" ] || __host=$user@$__host
      m4 -D__workdir=$(pwd)/$cluster_name/$node -D__host=$__host -D__connect="$xtra" \
        $filename > $cluster_name/$node/$(basename $filename)
      chmod +x $cluster_name/$node/$(basename $filename)  
    done
    ln -s $(pwd)/$cluster_name/$node $(pwd)/$cluster_name/$i

    : $((i++))
done

for filename in _template/ssh/node/* ; do
  m4 -D__clusterdir=$(pwd)/$cluster_name -D__script=$(basename $filename) _template/ssh/foreach.m4 > $cluster_name/$(basename $filename)
  chmod +x $cluster_name/$(basename $filename)
done

echo success
