#!/bin/bash
rc=0
for eid in $(cat __clusterdir/nodes.lst) ; do
  echo -n $eid :
  out=$(__clusterdir/$eid/__script "$@")
  rc1=$?
  [ $rc != 0 ] || rc=$rc1
  echo $out
done
(exit $rc)
