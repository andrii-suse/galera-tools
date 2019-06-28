set -- __ranges
echo __clusterdir/sql.sh "'select __pk from __schema.__table where __pk between $1 and ${@:$#}'"
