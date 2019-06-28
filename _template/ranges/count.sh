set -- __ranges

sql="select "

for range in "$@"; do
    low=$high
    high=$range
    [ -z "$low" ] || sql=$sql" sum(__pk between $low and $high), "
done

echo __clusterdir/sql.sh "'"$sql" count(__pk) from __schema.__table where __pk between $1 and ${@:$#}'"
