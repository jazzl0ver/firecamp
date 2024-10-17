#!/bin/bash
set -e

# check required parameters
# MONITOR_SERVICE_NAME is the stateful service to monitor.
# SERVICE_NAME is the telegraf service that monitors the stateful service.
if [ -z "$REGION" -o -z "$CLUSTER" -o -z "$SERVICE_NAME" -o -z "$MONITOR_SERVICE_NAME" -o -z "$MONITOR_SERVICE_TYPE" -o -z "$MONITOR_SERVICE_MEMBERS" -o -z "$OUTPUT" ]; then
  echo "error: some of the following are not specified: REGION ($REGION), CLUSTER ($CLUSTER), SERVICE_NAME ($SERVICE_NAME), MONITOR_SERVICE_NAME ($MONITOR_SERVICE_NAME), MONITOR_SERVICE_TYPE ($MONITOR_SERVICE_TYPE), MONITOR_SERVICE_MEMBERS ($MONITOR_SERVICE_MEMBERS), OUTPUT ($OUTPUT)"
  exit 1
fi

if [ "$OUTPUT" = "opensearch" ]; then
    if [ -z "$OUTPUT_SERVERS" -o -z "$OUTPUT_AUTH_USER" -o -z "$OUTPUT_AUTH_PASS" ]; then
	echo "error: some of the following are not specified: OUTPUT_SERVERS ($OUTPUT_SERVERS), OUTPUT_AUTH_USER ($OUTPUT_AUTH_USER), OUTPUT_AUTH_PASS ($OUTPUT_AUTH_PASS)"
	exit 1
    fi
fi

# telegraf config file directory
configDir="/firecamp"
if [ -n "$TEST_CONFIG_DIR" ]; then
  configDir=$TEST_CONFIG_DIR
fi

# set telegraf configs
export TEL_HOSTNAME=$SERVICE_NAME
export INTERVAL="60s"
if [ -n "$COLLECT_INTERVAL" ]; then
  export INTERVAL=$COLLECT_INTERVAL
fi

# the default servers string to replace for the input conf
FIRECAMP_SERVICE_SERVERS="firecamp-service-servers"
FIRECAMP_OUTPUT_SERVERS="firecamp-output-servers"
FIRECAMP_CASSANDRA_DASHBOARD_TITLE="cluster-monitor-service-name"
FIRECAMP_CASSANDRA_DASHBOARD_INDEX_PATTERN="telegraf-cluster-monitor-service-name"

# get service members array
OIFS=$IFS
IFS=','
read -a members <<< "${MONITOR_SERVICE_MEMBERS}"
IFS=$OIFS


# add redis input plugin
if [ "$MONITOR_SERVICE_TYPE" = "redis" ]; then
  if [ "$CONTAINER_PLATFORM" = "ecs" -o "$CONTAINER_PLATFORM" = "swarm" ]; then
    # load redis service configs to get the redis auth pass
    /firecamp-getserviceconf -cluster=$CLUSTER -service-name=$MONITOR_SERVICE_NAME -outputfile=/redisservice.conf
  fi
  # for k8s, the redis config should be mounted
  . /redisservice.conf

  servers=""
  i=0
  for m in "${members[@]}"; do
    if [ "$i" = "0" ]; then
      if [ "$ENABLE_AUTH" = "true" -a -n "$AUTH_PASS" ]; then
        servers="\"tcp:\/\/:$AUTH_PASS@$m\""
      else
        servers="\"tcp:\/\/:$m\""
      fi
    else
      if [ "$ENABLE_AUTH" = "true" -a -n "$AUTH_PASS" ]; then
        servers+=",\"tcp:\/\/:$AUTH_PASS@$m\""
      else
        servers+=",\"tcp:\/\/:$m\""
      fi
    fi
    i=$(( $i + 1 ))
  done

  # update the servers in input conf
  sed -i "s/\"$FIRECAMP_SERVICE_SERVERS\"/$servers/g" $configDir/input_redis.conf

  # add service input plugin to telegraf.conf
  cat $configDir/input_redis.conf >> $configDir/telegraf.conf
fi

# add zookeeper input plugin
if [ "$MONITOR_SERVICE_TYPE" = "zookeeper" ]; then
  servers=""
  i=0
  for m in "${members[@]}"; do
    if [ "$i" = "0" ]; then
      servers="\"$m\""
    else
      servers+=",\"$m\""
    fi
    i=$(( $i + 1 ))
  done

  # update the servers in input conf
  sed -i "s/\"$FIRECAMP_SERVICE_SERVERS\"/$servers/g" $configDir/input_zk.conf

  # add service input plugin to telegraf.conf
  cat $configDir/input_zk.conf >> $configDir/telegraf.conf

  cat $configDir/input_zk.conf
fi

# add cassandra input plugin
if [ "$MONITOR_SERVICE_TYPE" = "cassandra" ]; then
  if [ -z "$MONITOR_SERVICE_JMX_USER" -o -z "$MONITOR_SERVICE_JMX_PASSWD" ]; then
    echo "error: some of the following are not specified: MONITOR_SERVICE_JMX_USER ($MONITOR_SERVICE_JMX_USER), MONITOR_SERVICE_JMX_PASSWD ($MONITOR_SERVICE_JMX_PASSWD)"
    exit 1
  fi

  jolokiaPort="8778"
  servers=""
  i=0
  for m in "${members[@]}"; do
    if [ "$i" = "0" ]; then
      servers="\"http\:\/\/$m:$jolokiaPort\/jolokia\""
    else
      servers+=",\"http\:\/\/$m:$jolokiaPort\/jolokia\""
    fi
    i=$(( $i + 1 ))
  done

  casfile="$configDir/input_cas_jolokia.conf"
  if [ -n "$MONITOR_METRICS" ]; then
    # add custom metrics
    echo "$MONITOR_METRICS" >> $casfile
  fi

  # update the servers in input conf
  sed -i "s/\"$FIRECAMP_SERVICE_SERVERS\"/$servers/g" $casfile

  # cassandra has a few system keyspaces, such as system, system_auth, system_schema. The system
  # keyspace and system_schema keyspace have many tables. Lots of metrics will get published.
  # TODO monitor table metrics for the user keyspaces.
  # TODO check and add the user keyspaces automatically.

  # add service input plugin to telegraf.conf
  cat $casfile >> $configDir/telegraf.conf

#  cat $casfile
fi

# add output plugin
# Note: CloudWatch does not support delete metric, has to wait till it is automatically removed.
# CloudWatch metrics retention limits:
# - Data points with a period of 60 seconds (1 minute) are available for 15 days".
# - After 15 days this data is aggregated and is retrievable only with a resolution of 5 minutes. After 63 days, 1 hours.
# https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/cloudwatch_concepts.html
if [ "$OUTPUT" = "opensearch" ]; then
    # get output servers array
    OIFS=$IFS
    IFS=','
    read -a members <<< "${OUTPUT_SERVERS}"
    IFS=$OIFS
    servers=""
    i=0
    for m in "${members[@]}"; do
	if [ "$i" = "0" ]; then
	    servers="\"$m\""
	else
	    servers+=",\"$m\""
	fi
	i=$(( $i + 1 ))
    done
    outputfile="$configDir/output_opensearch.conf"

    # update the servers in output conf
    sed -i "s|\"$FIRECAMP_OUTPUT_SERVERS\"|$servers|g" $outputfile

    cat $configDir/output_opensearch.conf >> $configDir/telegraf.conf

    # Generate Opensearch dashboard
    if [ "$MONITOR_SERVICE_TYPE" = "cassandra" ]; then
	dashboard=$configDir/firecamp-telegraf-cassandra-dashboard.ndjson
	sed -i "s|$FIRECAMP_CASSANDRA_DASHBOARD_TITLE|$CLUSTER-$MONITOR_SERVICE_NAME|g" $dashboard
	sed -i "s|$FIRECAMP_CASSANDRA_DASHBOARD_INDEX_PATTERN|telegraf-$CLUSTER-$MONITOR_SERVICE_NAME|g" $dashboard
    fi
else
    cat $configDir/output_cloudwatch.conf >> $configDir/telegraf.conf
fi

cat $configDir/telegraf.conf

echo "$@"
exec "$@"
