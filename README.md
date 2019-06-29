# mariadb-cluster-tools
Execute commands on all cluster nodes (currently only access over ssh is implemented, more ways may follow).
Split table into logical partitions (Range) and then compare data between nodes in each Range.
### Synopsis
#### Automatically detect cluster nodes
At the moment the tool assumes you can access cluster nodes using ssh.
Clone repository and initialize scripts to access cluster
```
git clone https://github.com/andrii-suse/mariadb-cluster-tools
cd mariadb-cluster-tools
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

### Ranges
Ranges can be used to help verifying table's differences across nodes or in other operations, e.g. put a load on nodes.
The table is split into logical partitions according to InnoDB statistics. Each partition may be split once again until partition's range is small enough.
Following environment variables may be used to control the process (with default values):
```
RANGES_COUNT=8
RANGES_MAX_ROWS_PER_RANGE=100000
```
Logical partitions are folders inside cluster directory, which was previously created e.g. with `_template/plant_ssh_cluster.sh`. (But the approach may be used in other environments like any replication topology or local cluster).
This is example output for creating table and its logical partitions in ssh cluster.
```
$> _template/plant_ssh_cluster.sh mynode3
Examining cluster config...
Name: mycluster1
plant_ssh_cluster.sh: success
$> mycluster1/0/sql.sh 'create table test.x select seq as c1 from test.seq_1_to_1000000'
$> mycluster1/sql.sh 'select count(*) from test.x'
mynode1 :1000000
mynode2 :1000000
mynode3 :1000000
mynode4 :1000000
$> _template/plant_ranges.sh mycluster1 test.x
Examining config of cluster {mycluster1}...
Cannot identify primary key for table test.x
$> mycluster1/0/sql.sh 'alter table test.x add primary key(c1)'
$> _template/plant_ranges.sh mycluster1 test.x
Examining config of cluster {mycluster1}...
plant_ranges.sh: success
$> ll mycluster1/ranges/test.x/range05.624996_749995/
drwxr-xr-x 10 a users 4096 Jun 29 10:26 range00.00001_125000
drwxr-xr-x 10 a users 4096 Jun 29 10:26 range01.125000_249999
drwxr-xr-x 10 a users 4096 Jun 29 10:26 range02.249999_374998
drwxr-xr-x 10 a users 4096 Jun 29 10:26 range03.374998_499997
drwxr-xr-x 10 a users 4096 Jun 29 10:27 range04.499997_624996
drwxr-xr-x 10 a users 4096 Jun 29 10:27 range05.624996_749995
drwxr-xr-x 10 a users 4096 Jun 29 10:27 range06.749995_874994
drwxr-xr-x 10 a users 4096 Jun 29 10:27 range07.874994_1000000
```
Last command shows logical partitions, each of them has nested partitions split according to InnoDB stats.
Inside each leaf partition scripts are generated to calculate row count in the partition as well as checksum of rows.
```
$> ll mycluster1/ranges/test.x/range05.624996_749995/range01.640620_656244/
total 24
-rwxr-xr-x 1 a users 401 Jun 29 10:27 count.sh
-rwxr-xr-x 1 a users 169 Jun 29 10:27 crc32.sh
-rwxr-xr-x 1 a users 113 Jun 29 10:27 pk.sh
-rwxr-xr-x 1 a users  31 Jun 29 10:27 pk.sql
-rwxr-xr-x 1 a users 186 Jun 29 10:27 row.sh
-rwxr-xr-x 1 a users  31 Jun 29 10:27 row.sql
$> mycluster1/ranges/test.x/range05.624996_749995/range01.640620_656244/count.sh 
mynode1 :1954 1954 1954 1954 1954 1954 1954 1954 15625
mynode2 :1954 1954 1954 1954 1954 1954 1954 1954 15625
mynode3 :1954 1954 1954 1954 1954 1954 1954 1954 15625
mynode4 :1954 1954 1954 1954 1954 1954 1954 1954 15625
```
Last output shows that each leaf partition has 15625 rows (which are equally spit into sub-partitions 1954 rows each).
```
$> mycluster1/ranges/test.x/range05.624996_749995/range01.640620_656244/crc32.sh 
mynode1 :6211E324
mynode2 :6211E324
mynode3 :6211E324
mynode4 :6211E324
```
Each node has identical checksum for the rows of the partition.

Of course using this information is tricky in live cluster, because difference in output doesn't prove any data inconsistency. But it should be good start to detect potential data difference, e.g. by investigating how outputs change over time.

Now we delete some random rows in the partition and check how nodes are affected:
```
$> mycluster1/sql.sh 'delete from test.x where c1 between 640620 and 656244 and rand()<0.1 limit 10'
$> mycluster1/ranges/test.x/range05.624996_749995/range01.640620_656244/count.sh 
mynode1 :1914 1954 1954 1954 1954 1954 1954 1954 15585
mynode2 :1914 1954 1954 1954 1954 1954 1954 1954 15585
mynode3 :1914 1954 1954 1954 1954 1954 1954 1954 15585
mynode4 :1914 1954 1954 1954 1954 1954 1954 1954 15585
$> mycluster1/ranges/test.x/range05.624996_749995/range01.640620_656244/crc32.sh 
mynode1 :52236369
mynode2 :52236369
mynode3 :52236369
mynode4 :52236369
```

### Ranges Diff
`_template/diff_ranges.sh` is a script which makes the best effort to find differences across specified nodes. (So far only ssh cluster is implemented, more topologies may come).
It is based on Ranges functionality discussed earlier.

#### Ranges Diff Example
Create table and populate data in cluster (we execute queries on each node of cluster just because we can):
```
$> mycluster1/0/sql.sh 'drop table test.x'
$> mycluster1/1/sql.sh 'create table test.x select seq as c1 from test.seq_1_to_1000000'
$> mycluster1/2/sql.sh 'alter table test.x add primary key(c1), add c2 int, add c3 varchar(54), add c4 blob'
$> mycluster1/3/sql.sh 'update test.x set c2=floor(rand()*1000), c3=uuid(), c4=uuid()'
```

Rebuild Ranges because number of columns changed:
```
$> rm -r mycluster1/ranges/test.x
$> _template/plant_ranges.sh mycluster1 test.x
plant_ranges.sh: success
```
Now intentionally make data on each of nodes out of sync with the others:
```
$> # WARNING - never set WSREP_ON=0
$> mycluster1/2/sql.sh 'set WSREP_ON=0; delete from test.x where rand()<0.000001 limit 1'
$> mycluster1/0/sql.sh 'set WSREP_ON=0; update test.x set c4=NULL where rand()<0.0001 limit 1'
$> mycluster1/1/sql.sh 'set WSREP_ON=0; update test.x set c3=uuid() where c1>100000 and rand()<0.00001 limit 1'
$> mycluster1/3/sql.sh 'set WSREP_ON=0; update test.x set c2=1001 where rand()<0.00001 limit 1'
```
Run diff_ranges.sh script. `==` in output means that partition looks in sync. `? ` means row count is not the same across nodes for corresponding range, so checksum wasn't calculated. ` ?` means that row count is correct for the range, but checksum is different. 3 iterations are performed and then helper SQL is printed to identify problem rows:
```
$> _template/diff_ranges.sh mycluster1 test.x
 ?mycluster1/rangesdiff/test.x/range00.00001_125000/range00.00001_15625
==mycluster1/rangesdiff/test.x/range00.00001_125000/range01.15625_31249
==mycluster1/rangesdiff/test.x/range00.00001_125000/range02.31249_46873
? mycluster1/rangesdiff/test.x/range00.00001_125000/range03.46873_62497
==mycluster1/rangesdiff/test.x/range00.00001_125000/range04.62497_78121
==mycluster1/rangesdiff/test.x/range00.00001_125000/range05.78121_93745
==mycluster1/rangesdiff/test.x/range00.00001_125000/range06.93745_109369
==mycluster1/rangesdiff/test.x/range00.00001_125000/range07.109369_125000
==mycluster1/rangesdiff/test.x/range01.125000_249999/range00.125000_140624
==mycluster1/rangesdiff/test.x/range01.125000_249999/range01.140624_156248
==mycluster1/rangesdiff/test.x/range01.125000_249999/range02.156248_171872
==mycluster1/rangesdiff/test.x/range01.125000_249999/range03.171872_187496
 ?mycluster1/rangesdiff/test.x/range01.125000_249999/range04.187496_203120
==mycluster1/rangesdiff/test.x/range01.125000_249999/range05.203120_218744
==mycluster1/rangesdiff/test.x/range01.125000_249999/range06.218744_234368
==mycluster1/rangesdiff/test.x/range01.125000_249999/range07.234368_249999
 ?mycluster1/rangesdiff/test.x/range02.249999_374998/range00.249999_265623
==mycluster1/rangesdiff/test.x/range02.249999_374998/range01.265623_281247
==mycluster1/rangesdiff/test.x/range02.249999_374998/range02.281247_296871
==mycluster1/rangesdiff/test.x/range02.249999_374998/range03.296871_312495
==mycluster1/rangesdiff/test.x/range02.249999_374998/range04.312495_328119
==mycluster1/rangesdiff/test.x/range02.249999_374998/range05.328119_343743
==mycluster1/rangesdiff/test.x/range02.249999_374998/range06.343743_359367
==mycluster1/rangesdiff/test.x/range02.249999_374998/range07.359367_374998
==mycluster1/rangesdiff/test.x/range03.374998_499997/range00.374998_390622
==mycluster1/rangesdiff/test.x/range03.374998_499997/range01.390622_406246
==mycluster1/rangesdiff/test.x/range03.374998_499997/range02.406246_421870
==mycluster1/rangesdiff/test.x/range03.374998_499997/range03.421870_437494
==mycluster1/rangesdiff/test.x/range03.374998_499997/range04.437494_453118
==mycluster1/rangesdiff/test.x/range03.374998_499997/range05.453118_468742
==mycluster1/rangesdiff/test.x/range03.374998_499997/range06.468742_484366
==mycluster1/rangesdiff/test.x/range03.374998_499997/range07.484366_499997
==mycluster1/rangesdiff/test.x/range04.499997_624996/range00.499997_515621
==mycluster1/rangesdiff/test.x/range04.499997_624996/range01.515621_531245
==mycluster1/rangesdiff/test.x/range04.499997_624996/range02.531245_546869
==mycluster1/rangesdiff/test.x/range04.499997_624996/range03.546869_562493
==mycluster1/rangesdiff/test.x/range04.499997_624996/range04.562493_578117
==mycluster1/rangesdiff/test.x/range04.499997_624996/range05.578117_593741
==mycluster1/rangesdiff/test.x/range04.499997_624996/range06.593741_609365
==mycluster1/rangesdiff/test.x/range04.499997_624996/range07.609365_624996
==mycluster1/rangesdiff/test.x/range05.624996_749995/range00.624996_640620
==mycluster1/rangesdiff/test.x/range05.624996_749995/range01.640620_656244
==mycluster1/rangesdiff/test.x/range05.624996_749995/range02.656244_671868
==mycluster1/rangesdiff/test.x/range05.624996_749995/range03.671868_687492
==mycluster1/rangesdiff/test.x/range05.624996_749995/range04.687492_703116
==mycluster1/rangesdiff/test.x/range05.624996_749995/range05.703116_718740
==mycluster1/rangesdiff/test.x/range05.624996_749995/range06.718740_734364
==mycluster1/rangesdiff/test.x/range05.624996_749995/range07.734364_749995
==mycluster1/rangesdiff/test.x/range06.749995_874994/range00.749995_765619
==mycluster1/rangesdiff/test.x/range06.749995_874994/range01.765619_781243
==mycluster1/rangesdiff/test.x/range06.749995_874994/range02.781243_796867
==mycluster1/rangesdiff/test.x/range06.749995_874994/range03.796867_812491
==mycluster1/rangesdiff/test.x/range06.749995_874994/range04.812491_828115
==mycluster1/rangesdiff/test.x/range06.749995_874994/range05.828115_843739
==mycluster1/rangesdiff/test.x/range06.749995_874994/range06.843739_859363
==mycluster1/rangesdiff/test.x/range06.749995_874994/range07.859363_874994
==mycluster1/rangesdiff/test.x/range07.874994_1000000/range00.874994_890619
==mycluster1/rangesdiff/test.x/range07.874994_1000000/range01.890619_906244
==mycluster1/rangesdiff/test.x/range07.874994_1000000/range02.906244_921869
==mycluster1/rangesdiff/test.x/range07.874994_1000000/range03.921869_937494
==mycluster1/rangesdiff/test.x/range07.874994_1000000/range04.937494_953119
==mycluster1/rangesdiff/test.x/range07.874994_1000000/range05.953119_968744
==mycluster1/rangesdiff/test.x/range07.874994_1000000/range06.968744_984369
==mycluster1/rangesdiff/test.x/range07.874994_1000000/range07.984369_1000000
Identified suspicious ranges: 4, remaining iterations: 2
 ?mycluster1/rangesdiff/test.x/range00.00001_125000/range00.00001_15625
? mycluster1/rangesdiff/test.x/range00.00001_125000/range03.46873_62497
 ?mycluster1/rangesdiff/test.x/range01.125000_249999/range04.187496_203120
 ?mycluster1/rangesdiff/test.x/range02.249999_374998/range00.249999_265623
Identified suspicious ranges: 4, remaining iterations: 1
mycluster1/sql.sh 'select c1,ifnull(c2,"c2NULL"),ifnull(c3,"c3NULL"),ifnull(crc32(c4),"c4NULL") from test.x where c1=6473'
mycluster1/sql.sh 'select c1 from test.x where c1 in (47545)'
mycluster1/sql.sh 'select c1,ifnull(c2,"c2NULL"),ifnull(c3,"c3NULL"),ifnull(crc32(c4),"c4NULL") from test.x where c1=194063'
mycluster1/sql.sh 'select c1,ifnull(c2,"c2NULL"),ifnull(c3,"c3NULL"),ifnull(crc32(c4),"c4NULL") from test.x where c1=259041'
diff_ranges.sh: found ranges with mismatches: 4
```
So four ranges have problems, let's execute the printed commands and confirm difference:
```
$> mycluster1/sql.sh 'select c1,ifnull(c2,"c2NULL"),ifnull(c3,"c3NULL"),ifnull(crc32(c4),"c4NULL") from test.x where c1=6473'
mynode1 :6473 983 2ab75fd8-9a56-11e9-8b8a-e4b97a6bc8c5 c4NULL
mynode2 :6473 983 2ab75fd8-9a56-11e9-8b8a-e4b97a6bc8c5 1916486655
mynode3 :6473 983 2ab75fd8-9a56-11e9-8b8a-e4b97a6bc8c5 1916486655
mynode4 :6473 983 2ab75fd8-9a56-11e9-8b8a-e4b97a6bc8c5 1916486655
$> mycluster1/sql.sh 'select c1 from test.x where c1 in (47545)'
mynode1 :47545
mynode2 :47545
mynode3 :
mynode4 :47545
$> mycluster1/sql.sh 'select c1,ifnull(c2,"c2NULL"),ifnull(c3,"c3NULL"),ifnull(crc32(c4),"c4NULL") from test.x where c1=194063'
mynode1 :194063 605 2c7eef03-9a56-11e9-8b8a-e4b97a6bc8c5 1061910511
mynode2 :194063 605 72201b19-9a56-11e9-8902-e4b97a6bc8c5 1061910511
mynode3 :194063 605 2c7eef03-9a56-11e9-8b8a-e4b97a6bc8c5 1061910511
mynode4 :194063 605 2c7eef03-9a56-11e9-8b8a-e4b97a6bc8c5 1061910511
$> mycluster1/sql.sh 'select c1,ifnull(c2,"c2NULL"),ifnull(c3,"c3NULL"),ifnull(crc32(c4),"c4NULL") from test.x where c1=259041'
mynode1 :259041 784 2d2d7add-9a56-11e9-8b8a-e4b97a6bc8c5 1781520011
mynode2 :259041 784 2d2d7add-9a56-11e9-8b8a-e4b97a6bc8c5 1781520011
mynode3 :259041 784 2d2d7add-9a56-11e9-8b8a-e4b97a6bc8c5 1781520011
mynode4 :259041 1001 2d2d7add-9a56-11e9-8b8a-e4b97a6bc8c5 1781520011
```
