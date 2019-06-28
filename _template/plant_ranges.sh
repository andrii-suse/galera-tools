set -e
set -o pipefail

RANGES_COUNT=${RANGES_COUNT:-32}
RANGES_MAX_ROWS_PER_RANGE=${RANGES_MAX_ROWS_PER_RANGE:-10000}

cluster=$1
table=$2

ftable=$table
schema=${table%.*}
table=${table#$schema.}

[ -d $cluster ] || ( echo "Cannot find cluster $cluster"; exit 1 ) >&2
echo Examining config of cluster {$cluster}...

pk=$($cluster/0/sql.sh 'select column_name from information_schema.KEY_COLUMN_USAGE where table_name="'$table'" and table_schema="'$schema'" and constraint_name="primary"') || :
[ ! -z "$pk" ] || ( echo "Cannot identify primary key for table $ftable"; exit 1 ) >&2

minmax=$($cluster/0/sql.sh "select min($pk), max($pk) from $ftable") || :
set -- $minmax
min=$1
max=$2
{ [ ! -z "$minmax" ] && [ "$max" -gt "$min" ]; } || ( echo "Cannot identify values range for table $ftable (from {$minmax} and {$min} {$max})"; exit 1 ) >&2

columns=$($cluster/0/sql.sh '
select group_concat(
  concat(
    if(is_nullable="YES",
        concat(
          "ifnull(",
            if(data_type like "%text" or data_type like "%lob",
              concat("crc32(",column_name,")"),
              column_name
            ),
          ",",char(34),column_name,"NULL",char(34),
          ")"
        ),
        if(data_type like "%text" or data_type like "%lob",
          concat("crc32(",column_name,")"),
          column_name
        )
    )
  )
) as c
from COLUMNS where table_name="'$table'" and table_schema="'$schema'"')

[ "${#columns}" -gt 6 ] || ( echo "Cannot construct expression for calculating row checksums"; exit 1 ) >&2

mkdir -p $cluster/ranges
mkdir $cluster/ranges/$ftable || ( echo "Cannot create folder {$cluster/ranges/$ftable}"; exit 1 ) >&2

ranges() {
    local low=$1
    local high=$2
    local dir=$3
    local step=$(((high-low)/RANGES_COUNT))
    [ "$step" -gt 0 ] || ( echo "Internal error - step=0"; exit 1 ) >&2

    local expected_rows=$($cluster/0/sql.sh "explain select count(*) from $ftable where $pk between $low and $high" | awk '{ print $9 }')
    echo $low $high $expected_rows
    [ $expected_rows -eq $expected_rows ] 2>/dev/null || ( echo "Cannot estimate number of rows in range $low and $high, got: {$expected_rows}"; exit 1 ) >&2

    local l=$low
    local i
    local ranges=$l
    local flat=1
    [ $expected_rows -le $RANGES_MAX_ROWS_PER_RANGE ] || flat=0
    for (( i=1; i<RANGES_COUNT; i++ )); do
        local h=$((l+step))
        [ $i != $((RANGES_COUNT-1)) ] || h=$high
        if [ $flat == 1 ]; then
            ranges="$ranges $h"
        else
            local nextdir="$dir/range$(printf "%02d" $i).$(printf "%05d" $l)_$h"
            mkdir $nextdir || ( echo "Cannot create directory {$nextdir}"; exit 1 ) >&2
            ranges $l $h $nextdir
        fi
        l=$h
    done
    if [ $flat == 1 ]; then
        for f in _template/ranges/* ; do
            m4 -D__table="$table" -D__schema="$schema" -D__pk="$pk" -D__clusterdir="$(pwd)/$cluster" -D__ranges="$ranges" -D__columns="${columns@Q}" $f | bash -e > "$dir/$(basename $f)"
            chmod +x "$dir/$(basename $f)"
        done
    fi
}

ranges $min $max "$cluster/ranges/$ftable"

echo $(basename $0): success 
