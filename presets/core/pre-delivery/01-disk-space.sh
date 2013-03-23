SAFETY_MARGIN=$(( 10 * 1024 * 1024 )) # in bytes

FREE_BYTES=`run_remote "df -k \"$REMOTE_PATH\"" | awk '/[0-9]%/{printf "%d", $(NF-2)*1024}'`

NECESSARY_BYTES=$(( `git archive --format=tar $VERSION | wc -c` + $SAFETY_MARGIN ))
#TODO: ajouter la taille du diff entre le .git de la remote (donc toute la remote sauf le delivered) et le .git a livrer ?

AWK_FORMAT='{x = $0
             split("B KB MB GB TB PB", type)
             for(i=5;y < 1;i--)
                 y = x / (2**(10*i))
             print y " " type[i+2]
             }'

HUMAN_FREE_BYTES=`echo "$FREE_BYTES" | awk "$AWK_FORMAT"`
HUMAN_NECESSARY_BYTES=`echo "$NECESSARY_BYTES" | awk "$AWK_FORMAT"`

echo "Delivery will require $HUMAN_NECESSARY_BYTES on remote, $HUMAN_FREE_BYTES available"

if [[ $FREE_BYTES -gt $NECESSARY_BYTES ]]; then
	exit 0
else
	echo "Not enough disk space abvailable on remote"
	exit 1
fi
