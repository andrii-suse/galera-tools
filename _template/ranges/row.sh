set -- __ranges

high=${@:$#}

echo __clusterdir/sql.sh "'select __pk, conv(bit_xor(cast(crc32(concat("__columns")) as unsigned)), 10, 16) from __schema.__table where __pk between $1 and $high group by __pk '"
