#!/bin/bash
#
# RabbitMQ server monitor for file descriptor and sockets usage and limits.
#
# Author: Mike Dorman <mdorman@godaddy.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3
STATE_DEPENDENT=4
STATE=$STATE_OK

usage ()
{
    echo "Usage: $0 [OPTIONS]"
    echo "  -h            Get help"
    echo "  --total       WARN:CRIT thresholds for absolute value of total used file descriptors (maximum values)"
    echo "  --totalpct    WARN:CRIT thresholds for percentage value of total used file descriptors (maximum values)"
    echo "  --sockets     WARN:CRIT thresholds for absolute value of used socket descriptors (maximum values)"
    echo "  --socketspct  WARN:CRIT thresholds for percentage value of used socket descriptors (maximum values)"
    echo "  --limit       WARN:CRIT thresholds for absolute limit value of total file descriptors (minimum values)"
}

TEMP=`getopt -o h --long total:,totalpct:,sockets:,socketspct:,limit: -n $0 -- "$@"`
[ $? -ne 0 ] && usage && exit $STATE_UNKNOWN
eval set -- "$TEMP"

while true; do
    case "$1" in
        -h)
            usage ; shift ; exit $STATE_UNKNOWN ;;
        --total)
            TOTAL_WARN=`echo $2: | cut -d: -f 1`
            TOTAL_CRIT=`echo $2: | cut -d: -f 2`
            shift 2 ;;
        --totalpct)
            TOTALPCT_WARN=`echo $2: | cut -d: -f 1`
            TOTALPCT_CRIT=`echo $2: | cut -d: -f 2`
            shift 2 ;;
        --sockets)
            SOCKETS_WARN=`echo $2: | cut -d: -f 1`
            SOCKETS_CRIT=`echo $2: | cut -d: -f 2`
            shift 2 ;;
        --socketspct)
            SOCKETSPCT_WARN=`echo $2: | cut -d: -f 1`
            SOCKETSPCT_CRIT=`echo $2: | cut -d: -f 2`
            shift 2 ;;
        --limit)
            LIMIT_WARN=`echo $2: | cut -d: -f 1`
            LIMIT_CRIT=`echo $2: | cut -d: -f 2`
            shift 2 ;;
        --)
            shift ; break ;;
    esac
done

limits=`sudo /sbin/rabbitmqctl status | grep file_descriptors -A 4`
[ $? -ne 0 ] && echo "rabbitmqctl status command failed" && exit $STATE_UNKNOWN

total_limit=`echo ${limits} | grep total_limit | sed -r 's/^.+total_limit,([[:digit:]]+).*$/\1/'`
total_used=`echo ${limits} | grep total_used | sed -r 's/^.+total_used,([[:digit:]]+).*$/\1/'`

sockets_limit=`echo ${limits} | grep sockets_limit | sed -r 's/^.+sockets_limit,([[:digit:]]+).*$/\1/'`
sockets_used=`echo ${limits} | grep sockets_used | sed -r 's/^.+sockets_used,([[:digit:]]+).*$/\1/'`

total_pct=`echo \( $total_used/$total_limit \) \* 100 | bc -l | awk '{printf "%3.2f", $0}'`
sockets_pct=`echo \( $sockets_used/$sockets_limit \) \* 100 | bc -l | awk '{printf "%3.2f", $0}'`

# Check all critical thresholds first
[ -n "$TOTAL_CRIT" ] && [ $total_used -gt $TOTAL_CRIT ] && \
    STATE=$STATE_CRITICAL && \
    MESSAGE="${MESSAGE}CRITICAL: total used > $TOTAL_CRIT; "

[ -n "$TOTALPCT_CRIT" ] && [ `echo $total_pct \> $TOTALPCT_CRIT | bc -l` == 1 ] && \
    STATE=$STATE_CRITICAL && \
    MESSAGE="${MESSAGE}CRITICAL: total % used > $TOTALPCT_CRIT%; "

[ -n "$SOCKETS_CRIT" ] && [ $sockets_used -gt $SOCKETS_CRIT ] && \
    STATE=$STATE_CRITICAL && \
    MESSAGE="${MESSAGE}CRITICAL: sockets used > $SOCKETS_CRIT; "

[ -n "$SOCKETSPCT_CRIT" ] && [ `echo $sockets_pct \> $SOCKETSPCT_CRIT | bc -l` -eq 1 ] && \
    STATE=$STATE_CRITICAL && \
    MESSAGE="${MESSAGE}CRITICAL: sockets % used > $SOCKETSPCT_CRIT%; "

[ -n "$LIMIT_CRIT" ] && [ $total_limit -lt $LIMIT_CRIT ] && \
    STATE=$STATE_CRITICAL && \
    MESSAGE="${MESSAGE}CRITICAL: total limit < $LIMIT_CRIT; "

# Check warning thresholds if critical was not already tripped
if [ $STATE -eq $STATE_OK ]; then
    [ -n "$TOTAL_WARN" ] && [ $total_used -gt $TOTAL_WARN ] && \
        STATE=$STATE_WARNING && \
        MESSAGE="${MESSAGE}WARNING: total used > $TOTAL_WARN; "

    [ -n "$TOTALPCT_WARN" ] && [ `echo $total_pct \> $TOTALPCT_WARN | bc -l` == 1 ] && \
        STATE=$STATE_WARNING && \
        MESSAGE="${MESSAGE}WARNING: total % used > $TOTALPCT_WARN%; "

    [ -n "$SOCKETS_WARN" ] && [ $sockets_used -gt $SOCKETS_WARN ] && \
        STATE=$STATE_WARNING && \
        MESSAGE="${MESSAGE}WARNING: sockets used > $SOCKETS_WARN; "

    [ -n "$SOCKETSPCT_WARN" ] && [ `echo $sockets_pct \> $SOCKETSPCT_WARN | bc -l` -eq 1 ] && \
        STATE=$STATE_WARNING && \
        MESSAGE="${MESSAGE}WARNING: sockets % used > $SOCKETSPCT_WARN%; "

    [ -n "$LIMIT_WARN" ] && [ $total_limit -lt $LIMIT_WARN ] && \
        STATE=$STATE_WARNING && \
        MESSAGE="${MESSAGE}WARNING: total limit < $LIMIT_WARN; "
fi

echo -n "${MESSAGE}"
echo -n "Total file descriptors: ${total_used}/${total_limit} (${total_pct}%), "
echo "Sockets: ${sockets_used}/${sockets_limit}, (${sockets_pct}%)"

exit $STATE
