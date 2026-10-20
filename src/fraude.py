import os
from pyspark.sql import SparkSession
from pyspark.sql import functions as F

spark = (
    SparkSession.builder
    .remote(os.environ["SPARK_REMOTE"])
    .getOrCreate()
)

try:
    # Gera dados fictícios no Spark remoto.
    transacoes = (
        spark.range(100_000)
        .withColumnRenamed("id", "transacao_id")
        .withColumn(
            "cliente_id",
            (F.col("transacao_id") % 1000).cast("int"),
        )
        .withColumn(
            "valor",
            F.round(F.rand(seed=42) * 10000 + 10, 2),
        )
    )

    features = transacoes.groupBy("cliente_id").agg(
        F.count("*").alias("quantidade_transacoes"),
        F.round(F.sum("valor"), 2).alias("valor_total"),
        F.round(F.avg("valor"), 2).alias("valor_medio"),
    )

    print("TOP 10 CLIENTES POR VALOR TOTAL")
    features.orderBy(F.desc("valor_total")).show(10, truncate=False)

finally:
    spark.stop()