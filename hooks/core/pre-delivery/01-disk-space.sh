SAFETY_MARGIN=$(( 10 * 1024 * 1024 )) # in bytes

DELIVERED_DIR=`dirname "$DELIVERY_PATH"`

FREE_BYTES=`$EXEC_REMOTE df -k "$DELIVERED_DIR" | awk '/[0-9]%/{print $(NF-2)*1024}'`
NECESSARY_BYTES=$(( `git archive $VERSION | wc -c` + $SAFETY_MARGIN ))

AWK_FORMAT='{x = $0
             split("B KB MB GB TB PB",type)
             for(i=5;y < 1;i--)
                 y = x / (2**(10*i))
             print y type[i+2]
             }'

HUMAN_FREE_BYTES=`echo "$FREE_BYTES" | awk "$AWK_FORMAT"`
HUMAN_NECESSARY_BYTES=`echo "$NECESSARY_BYTES" | awk "$AWK_FORMAT"`

[[ $FREE_BYTES -gt $NECESSARY_BYTES ]] || ( echo "Not enough disk space abvailable on remote ($HUMAN_FREE_BYTES free, $HUMAN_NECESSARY_BYTES needed)" ; exit 1 )

exit 0
