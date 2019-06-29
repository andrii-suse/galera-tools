set -e
set -o pipefail

cluster=$1
table=$2

ftable=$table
schema=${table%.*}
table=${table#$schema.}

trap "exit" INT

[ -d $cluster ] || ( echo "Cannot find cluster $cluster"; exit 1 ) >&2

[ -d $cluster/ranges/$ftable ] || ( echo "Cannot find ranges folder {$cluster/ranges/$ftable}"; exit 1 ) >&2
mkdir -p $cluster/rangesdiff
mkdir $cluster/rangesdiff/$ftable || ( echo "Cannot create folder {$cluster/rangesdiff/$ftable}"; exit 1 ) >&2

srcdir=$(pwd)/$cluster/ranges/$ftable
# first create folder for each range
( cd $cluster/rangesdiff/$ftable && (cd $srcdir && find . -type d) | xargs mkdir -p )

mismatches=0

diffranges() {
    local srcdir=$1
    local dir=$2
    local lastrun=$3

    if [ ! -f "$srcdir/count.sh" ]; then
        for D in $(find "$dir" -maxdepth 1 -mindepth 1 -type d -name "range*" | sort); do
            [ -d "$srcdir/$(basename $D)" ] || ( echo "Cannot find folder {$srcdir/$(basename $D)} nor file {$srcdir/count.sh}"; exit 1 ) >&2
            diffranges "$srcdir/$(basename $D)" "$D" $lastrun
        done
    else
        uniq=$($srcdir/count.sh | tee $dir/.out | sed 's/.*://' | sort | uniq | wc -l)
        if [ "$uniq" != 1 ]; then
            : $((mismatches++))
            [ $last_run == 1 ] || echo "? $dir"
            if [ $lastrun == 1 ]; then
                $srcdir/pk.sh > /dev/null
                local nodecnt=0
                for node in $(cat $cluster/nodes.lst); do
                    cp $cluster/$node/last_sql_success.out $dir/pk$node
                    let nodecnt=nodecnt+1
                done
                pks=$(sort $dir/pk* | uniq -c | grep -v "\b$nodecnt " | sed 's/\r$//g' | awk '{printf("%s,",$2)}' | sed 's/,\s*$//' )
                [ ${#pks} -lt 1000 ] || ( echo "Too many differences detected"; exit 1 ) >&2
                sql="$(cat $srcdir/pk.sql) in ($pks)"
                echo $cluster/sql.sh "'$sql'"
                rm $dir/pk*
            fi
            return
        fi

        uniq=$($srcdir/crc32.sh | tee $dir/.out | sed 's/.*://' | sort | uniq | wc -l)
        if [ "$uniq" != 1 ]; then
            : $((mismatches++))
            [ $last_run == 1 ] || echo " ?$dir"
            if [ $lastrun == 1 ]; then
                $srcdir/row.sh > /dev/null
                local nodecnt=0
                for node in $(cat $cluster/nodes.lst); do
                    cp $cluster/$node/last_sql_success.out $dir/row$node
                    let nodecnt=nodecnt+1
                done
                pks=$(sort $dir/row* | uniq -c | grep -v "\b$nodecnt " | sed 's/\r$//g' | awk '{print $2}' | uniq )
                [ ${#pks} -lt 1000 ] || ( echo "Too many differences detected"; exit 1 ) >&2
                sql="$(cat $srcdir/row.sql)"
                for pk in ${pks} ; do
                    echo $cluster/sql.sh "'$sql=$pk'"
                done
                rm $dir/row*
            fi
            return
        fi

        echo ==$dir
        rm -rf "$dir"
    fi
}

iterations=${RANGES_DIFF_ITERATIONS:-3}
while [  $iterations -gt 0 ]; do
    last_run=0
    [ $iterations -ne 1 ] || last_run=1
   
    diffranges "$cluster/ranges/$ftable" "$cluster/rangesdiff/$ftable" $last_run
    [ $mismatches != 0 ] || break
    let iterations=iterations-1 || :
    [ $last_run == 1 ] || echo Identified suspicious ranges: $mismatches, remaining iterations: $iterations
    [ $last_run == 1 ] || mismatches=0
done

if [ $mismatches != 0 ]; then
    echo $(basename $0): found ranges with mismatches: $mismatches
else
    echo $(basename $0): no mismatches were identified
fi
