FROM telegraf:1.32

RUN mkdir -p /firecamp/

COPY input_cas_jolokia.conf /firecamp/
COPY input_elastic.conf /firecamp/
COPY input_mongo.conf /firecamp/
COPY input_mysql.conf /firecamp/
COPY input_pg.conf /firecamp/
COPY input_redis.conf /firecamp/
COPY input_zk.conf /firecamp/
COPY output_cloudwatch.conf /firecamp/
COPY output_opensearch.conf /firecamp/
COPY telegraf.conf /firecamp/

COPY firecamp-telegraf-cassandra-dashboard.ndjson /firecamp/

COPY firecamp-getserviceconf /
COPY entrypoint.sh /


CMD ["telegraf", "--config", "/firecamp/telegraf.conf"]
