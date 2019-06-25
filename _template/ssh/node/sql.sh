#!/bin/bash
ssh -tq __host mysql __connect -BN -e "'$@'" information_schema > __workdir/last_sql.out
res=$?
if [[ $res -ne 0 ]]; then
    ( exit $res )
else
    mv __workdir/last_sql.out __workdir/last_sql_success.out
    # ssh injects \r into output, so remove it
    ( 
        head -n 10 __workdir/last_sql_success.out | sed 's/\r//'
        [[ $(head -n 11 __workdir/last_sql_success.out | wc -l) -lt 11 ]] || echo "..."
    )
fi
