secondsOfInterval=""
latencyThreshold=""
firebaseProject=""
firebaseToken=""
slackHookURL=""

function createFolders() {
  mkdir files
  mkdir logs
}

function printStartupMessage() {
  echo "Service running every $secondsOfInterval seconds."
  echo "Latency Threshold is set for $latencyThreshold ms."
  echo "Output can be found in logs/complete_log.txt."
}

function printDate() {
  echo ""
  echo "Date: $(date +"%Y-%m-%d %T")" | tee -a logs/complete_log.txt > /dev/null
}

function sendIndex() {
  file=$1
  index=$2
  message="{\"text\":\"WARNING: Unindexed querry on Firebase at $(date +"%Y-%m-%d %T") \\n\\n\\tIndex: $index \\n\\n\\tFile: $file\"}"
  curl --output /dev/null -X POST -H 'Content-type: application/json' --data "$message" "$slackHookURL" 2>/dev/null
  #echo "WARNING: Unindexed querry on Firebase.";
  printf "Index: %12s |   %s\n" $index $file | tee -a logs/complete_log.txt
}

function sendLatency() {
  file=$1
  latency=$2
  latencyThreshold=$3
  message="{\"text\":\"WARNING: High Firebase response latency at $(date +"%Y-%m-%d %T"). \\n\\n\\tAverage Latency: $2 ms \\n\\n\\tFile: $1\"}"
  curl --output /dev/null -X POST -H 'Content-type: application/json' --data "$message" "$slackHookURL" 2>/dev/null
  #echo "WARNING: Firebase response latency is high.";
  printf "Latency: %8s   |    %s\n" $latency $file | tee -a logs/complete_log.txt
}

function processLatencyResults() {
  echo "Latency results:"
  i=1
  while : ; do
    file=$(cat files/parsedLatencyFiles.txt | awk -F '\|' "{print \$$i}" 2>/dev/null);
    latency=$(cat files/parsedLatencyTimes.txt | awk -F '\|' "{print \$$i}" 2>/dev/null);
    [ $i -lt 11 ] && [ "$latency" != "" ] && [ "$(echo "$latency > $latencyThreshold" | bc -l )" == 1 ] || break
    sendLatency $file $latency $latencyThreshold;
    i=$((i+1))
  done
}

function processUnindexedQueries() {
  echo "Unindexed queries results:"
  i=2
  while : ; do
    file=$(cat files/parsedUnindexedFiles.txt | awk -F '\|' "{print \$$i}" 2>/dev/null);
    index=$(cat files/parsedUnindexedIndex.txt | awk -F '\|' "{print \$$i}" 2>/dev/null);
    [ $i -lt 20 ] && [ "$index" != "" ] || break
    sendIndex $file $index;
    i=$((i+1))
  done
}


function parseUnindexedFiles() {
  cat $1 | grep 'Unindexed Queries' -A 24 | grep 'Path' -A 24 | awk '{if((NR % 2)) print}' | awk -F │ '{print $2}' | paste -s -d \| 2>/dev/null
}
function parseUnindexedIndex() {
  cat $1 | grep 'Unindexed Queries' -A 24 | grep 'Path' -A 24 | awk '{if((NR % 2)) print}' | awk -F │ '{print $3}' |  paste -s -d \| 2>/dev/null
}
function extractUnindexedQueries() {
  parseUnindexedFiles logs/log.txt > files/parsedUnindexedFiles.txt
  parseUnindexedIndex logs/log.txt > files/parsedUnindexedIndex.txt
}


function parseLatencyFiles() {
  cat $1 | grep 'Read Speed' -A 24 | grep 'Path' -A 24 | tail -n 20 |awk '{if((NR % 2)) print}' | awk -F │ '{print $2}' | paste -s -d \| 2>/dev/null
}
function parseLatencyTime() {
  cat $1 | grep 'Read Speed' -A 24 | grep 'Path' -A 24 | tail -n 20 |awk '{if((NR % 2)) print}' | awk -F │ '{print $4}' | sed 's/,//' | awk -F ' ' '{print $1}' | paste -s -d \| 2>/dev/null
}
function extractLatency() {
  parseLatencyFiles logs/log.txt > files/parsedLatencyFiles.txt
  parseLatencyTime logs/log.txt > files/parsedLatencyTimes.txt
}


function runFirebaseProfile() {
  echo "Starting data firebase profiling."
  seconds=$1
  { sleep $seconds; yes; } | firebase database:profile --project $firebaseProject --token $firebaseToken > logs/log.txt;
}


printStartupMessage
createFolders
while :
do
    printDate
    runFirebaseProfile $secondsOfInterval

    extractLatency
    extractUnindexedQueries

    processLatencyResults
    processUnindexedQueries
done
