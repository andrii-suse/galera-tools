# galera-tools
Execute commands on all cluster nodes (currently only access over ssh is implemented, more ways may follow).
### Synopsys 
#### Automatically detect cluster nodes
At the moment the tool assumes you can access cluster nodes using ssh.
Clone repository and initialize scripts to access cluster
```
git clone https://github.com/andrii-suse/galera-tools
cd galera-tools
_template/plant_ssh_cluster.sh root@node1
```
Output like below is expected, where:
- `mycluster` is read from Galera variable `wsrep_cluster_name`;
- `10.10.0.2:3306,10.10.0.3:3306,10.10.0.4:3306,10.10.0.5:3306` is read from `wsrep_incoming_addresses`; 
- `mynode1`,`mynode2`,`mynode3` and `mynode4` are read from `~/.ssh/known_hosts`.

```
Examining cluster config...
Name: mycluster
Trying to match node addresses to hostnames from known_hosts...
10.10.0.2:3306,10.10.0.3:3306,10.10.0.4:3306,10.10.0.5:3306
Mapped 10.10.0.2 to mynode1
Mapped 10.10.0.3 to mynode2
Mapped 10.10.0.4 to mynode3
Mapped 10.10.0.5 to mynode4
success
```
On success directory `mycluster` has been created, which provides set of scripts to be executed on cluster, e.g.:
```
> mycluster/service_status.sh 
mynode1 :active
mynode2 :active
mynode3 :active
mynode4 :active
> mycluster/cluster_size.sh 
mynode1 :wsrep_cluster_size 4
mynode2 :wsrep_cluster_size 4
mynode3 :wsrep_cluster_size 4
mynode4 :wsrep_cluster_size 4
> mycluster/sql.sh 'show variables like "innodb_buffer_pool_size"'
mynode1 :innodb_buffer_pool_size 12884901888
mynode2 :innodb_buffer_pool_size 127926272
mynode3 :innodb_buffer_pool_size 127926272
mynode4 :innodb_buffer_pool_size 127926272
```

#### Explicitly provide list of nodes
It is not always possible to use `wsrep_incoming_addresses` to access cluster, e.g. when it runs in protected network. For such cases the script expects more than one parameter and will not attempt to verify consistency of hostname / IP configuration during scripts generation, e.g.
```
_template/plant_ssh_cluster.sh node1 node2 node3 node4
Examining cluster config...
Name: mycluster
success
```
Then again - a folder for the cluster will be created with scripts usable as in example above. 
